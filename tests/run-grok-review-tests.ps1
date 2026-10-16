#requires -Version 7.0

<#
    Offline regression tests for skills/grok-review-files/scripts/invoke-grok-review.ps1.

    No real Grok, model, network, or external send is used. The fake grok.exe is compiled at test
    time with the .NET Framework csc.exe that ships with Windows and placed at GROK_HOME\bin\grok.exe.
    These tests check the wrapper; they do not prove compatibility with the real Grok Build CLI.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runner = Join-Path $repoRoot 'skills\grok-review-files\scripts\invoke-grok-review.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('gkr-grok-review-' + [Guid]::NewGuid().ToString('N'))
$pwsh = (Get-Process -Id $PID).Path
$passed = 0
$failed = 0
$defaultLines = @(
    '{"type":"thought","data":"reading the file"}',
    '{"type":"text","data":"fake "}',
    '{"type":"text","data":"grok review"}',
    '{"type":"end","stopReason":"EndTurn","sessionId":"s1","requestId":"r1"}'
)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function ConvertTo-TestLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:passed++
        Write-Output "PASS: $Name"
    }
    catch {
        $script:failed++
        Write-Output "FAIL: $Name - $($_.Exception.Message)"
    }
}

function Invoke-TestRunner {
    param(
        [string[]]$Files,
        [string[]]$Lines = $defaultLines,
        [string]$Stderr = '',
        [int]$ExitCode = 0,
        [int]$DelayMilliseconds = 0,
        [int]$HangSeconds = 0,
        [int]$IdleTimeoutSeconds = 10,
        [string]$Transport,
        [string]$ReviewRequest,
        [string[]]$ReferencePaths = @(),
        [string[]]$ReferenceUrls = @(),
        [string]$SaveOutput,
        [string]$GrokHome,
        [string]$Language,
        [string]$Model,
        [string]$Effort
    )
    $promptCopyPath = Join-Path $tempRoot 'fake-prompt.txt'
    $argsPath = Join-Path $tempRoot 'fake-args.txt'
    $pidPath = Join-Path $tempRoot 'fake-pid.txt'
    Remove-Item -LiteralPath $promptCopyPath, $argsPath, $pidPath -Force -ErrorAction SilentlyContinue

    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $pwsh
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $tempRoot
    [void]$start.ArgumentList.Add('-NoProfile')

    # `pwsh -File` returns the runner's exit code as is but cannot bind several values to [string[]].
    # Use an encoded command only for several files; cases that check exit codes use -File.
    if ($Files.Count -gt 1) {
        $fileExpression = [string]::Join(',', @($Files | ForEach-Object { ConvertTo-TestLiteral $_ }))
        $command = "& $(ConvertTo-TestLiteral $runner) -FilePath @($fileExpression) -IdleTimeoutSeconds $IdleTimeoutSeconds"
        if (-not [string]::IsNullOrWhiteSpace($Transport)) {
            $command += " -Transport $(ConvertTo-TestLiteral $Transport)"
        }
        if (-not [string]::IsNullOrWhiteSpace($ReviewRequest)) {
            $command += " -ReviewRequest $(ConvertTo-TestLiteral $ReviewRequest)"
        }
        if ($ReferencePaths.Count -gt 0) {
            $referenceExpression = [string]::Join(',', @($ReferencePaths | ForEach-Object { ConvertTo-TestLiteral $_ }))
            $command += " -ReferencePath @($referenceExpression)"
        }
        if ($ReferenceUrls.Count -gt 0) {
            $urlExpression = [string]::Join(',', @($ReferenceUrls | ForEach-Object { ConvertTo-TestLiteral $_ }))
            $command += " -ReferenceUrl @($urlExpression)"
        }
        if (-not [string]::IsNullOrWhiteSpace($SaveOutput)) {
            $command += " -SaveOutput $(ConvertTo-TestLiteral $SaveOutput)"
        }
        if (-not [string]::IsNullOrWhiteSpace($Language)) {
            $command += " -Language $(ConvertTo-TestLiteral $Language)"
        }
        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            $command += " -Model $(ConvertTo-TestLiteral $Model)"
        }
        if (-not [string]::IsNullOrWhiteSpace($Effort)) {
            $command += " -Effort $(ConvertTo-TestLiteral $Effort)"
        }
        [void]$start.ArgumentList.Add('-EncodedCommand')
        [void]$start.ArgumentList.Add([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
    }
    else {
        [void]$start.ArgumentList.Add('-File')
        [void]$start.ArgumentList.Add($runner)
        [void]$start.ArgumentList.Add('-FilePath')
        [void]$start.ArgumentList.Add($Files[0])
        [void]$start.ArgumentList.Add('-IdleTimeoutSeconds')
        [void]$start.ArgumentList.Add([string]$IdleTimeoutSeconds)
        if (-not [string]::IsNullOrWhiteSpace($Transport)) {
            [void]$start.ArgumentList.Add('-Transport')
            [void]$start.ArgumentList.Add($Transport)
        }
        if (-not [string]::IsNullOrWhiteSpace($ReviewRequest)) {
            [void]$start.ArgumentList.Add('-ReviewRequest')
            [void]$start.ArgumentList.Add($ReviewRequest)
        }
        foreach ($reference in $ReferencePaths) {
            [void]$start.ArgumentList.Add('-ReferencePath')
            [void]$start.ArgumentList.Add($reference)
        }
        foreach ($url in $ReferenceUrls) {
            [void]$start.ArgumentList.Add('-ReferenceUrl')
            [void]$start.ArgumentList.Add($url)
        }
        if (-not [string]::IsNullOrWhiteSpace($SaveOutput)) {
            [void]$start.ArgumentList.Add('-SaveOutput')
            [void]$start.ArgumentList.Add($SaveOutput)
        }
        if (-not [string]::IsNullOrWhiteSpace($Language)) {
            [void]$start.ArgumentList.Add('-Language')
            [void]$start.ArgumentList.Add($Language)
        }
        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            [void]$start.ArgumentList.Add('-Model')
            [void]$start.ArgumentList.Add($Model)
        }
        if (-not [string]::IsNullOrWhiteSpace($Effort)) {
            [void]$start.ArgumentList.Add('-Effort')
            [void]$start.ArgumentList.Add($Effort)
        }
    }

    $start.Environment['GROK_HOME'] = if ([string]::IsNullOrWhiteSpace($GrokHome)) { $fakeGrokHome } else { $GrokHome }
    $start.Environment['GROK_FAKE_PROMPT'] = $promptCopyPath
    $start.Environment['GROK_FAKE_ARGS'] = $argsPath
    $start.Environment['GROK_FAKE_PID'] = $pidPath
    $start.Environment['GROK_FAKE_STDOUT_B64'] = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $Lines)))
    $start.Environment['GROK_FAKE_STDERR'] = $Stderr
    $start.Environment['GROK_FAKE_EXIT'] = [string]$ExitCode
    $start.Environment['GROK_FAKE_DELAY_MS'] = [string]$DelayMilliseconds
    $start.Environment['GROK_FAKE_HANG_SECONDS'] = [string]$HangSeconds

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $stdoutText = $process.StandardOutput.ReadToEnd()
    $stderrText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $arguments = if (Test-Path -LiteralPath $argsPath) { [IO.File]::ReadAllText($argsPath, [Text.Encoding]::UTF8) } else { $null }
    [string[]]$argumentList = @(if ($null -ne $arguments) { $arguments -split "`n" })
    $promptIndex = [Array]::IndexOf($argumentList, '--prompt-file')
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutText
        Stderr = $stderrText
        Input = if (Test-Path -LiteralPath $promptCopyPath) { [IO.File]::ReadAllText($promptCopyPath, [Text.Encoding]::UTF8) } else { $null }
        Arguments = $arguments
        ArgumentList = $argumentList
        PromptFile = if ($promptIndex -ge 0) { $argumentList[$promptIndex + 1] } else { $null }
        FakePid = if (Test-Path -LiteralPath $pidPath) { [int][IO.File]::ReadAllText($pidPath, [Text.Encoding]::UTF8) } else { $null }
    }
}

try {
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null

    $csc = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) {
        throw "csc.exe was not found at $csc. The offline harness compiles a fake grok.exe with it; no network or model is used."
    }

    # Fake grok.exe: records argv and the prompt file, then prints the scripted stream.
$fakeSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

static class FakeGrok
{
    static string Env(string name)
    {
        return Environment.GetEnvironmentVariable(name) ?? string.Empty;
    }

    static int Number(string name)
    {
        int value;
        return int.TryParse(Env(name), out value) ? value : 0;
    }

    static int Main(string[] args)
    {
        UTF8Encoding utf8 = new UTF8Encoding(false);
        File.WriteAllText(Env("GROK_FAKE_ARGS"), string.Join("\n", args), utf8);
        File.WriteAllText(Env("GROK_FAKE_PID"), Process.GetCurrentProcess().Id.ToString(), utf8);
        for (int i = 0; i + 1 < args.Length; i++)
        {
            if (args[i] == "--prompt-file")
            {
                File.WriteAllText(Env("GROK_FAKE_PROMPT"), File.ReadAllText(args[i + 1], utf8), utf8);
            }
        }
        StreamWriter stdout = new StreamWriter(Console.OpenStandardOutput(), utf8);
        stdout.AutoFlush = true;
        string body = utf8.GetString(Convert.FromBase64String(Env("GROK_FAKE_STDOUT_B64")));
        int delay = Number("GROK_FAKE_DELAY_MS");
        if (body.Length > 0)
        {
            foreach (string line in body.Split('\n'))
            {
                stdout.WriteLine(line);
                if (delay > 0) { Thread.Sleep(delay); }
            }
        }
        string stderrText = Env("GROK_FAKE_STDERR");
        if (stderrText.Length > 0)
        {
            StreamWriter stderr = new StreamWriter(Console.OpenStandardError(), utf8);
            stderr.AutoFlush = true;
            stderr.WriteLine(stderrText);
        }
        int hang = Number("GROK_FAKE_HANG_SECONDS");
        if (hang > 0) { Thread.Sleep(hang * 1000); }
        return Number("GROK_FAKE_EXIT");
    }
}
'@
    $fakeSourcePath = Join-Path $tempRoot 'FakeGrok.cs'
    [IO.File]::WriteAllText($fakeSourcePath, $fakeSource, [Text.UTF8Encoding]::new($false))
    $fakeGrokHome = Join-Path $tempRoot 'grok home'
    $fakeBin = Join-Path $fakeGrokHome 'bin'
    [IO.Directory]::CreateDirectory($fakeBin) | Out-Null
    $fakeExecutable = Join-Path $fakeBin 'grok.exe'
    $compileOutput = & $csc /nologo /target:exe "/out:$fakeExecutable" $fakeSourcePath 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fakeExecutable)) {
        throw "fake grok.exe compile failed: $compileOutput"
    }
    $emptyGrokHome = Join-Path $tempRoot 'empty grok home'
    [IO.Directory]::CreateDirectory($emptyGrokHome) | Out-Null

    $reviewDirectory = Join-Path $tempRoot 'review root'
    $nestedDirectory = Join-Path $reviewDirectory 'nested'
    [IO.Directory]::CreateDirectory($nestedDirectory) | Out-Null
    $fileA = Join-Path $reviewDirectory '計画.md'
    $fileB = Join-Path $nestedDirectory 'code.ps1'
    [IO.File]::WriteAllText($fileA, "方針です。`n二行目です。", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($fileB, 'Write-Output ok', [Text.UTF8Encoding]::new($false))
    $largeFile = Join-Path $reviewDirectory '大きい file.html'
    [IO.File]::WriteAllText($largeFile, (([string]::new('a', 1024) + "`n") * 1100), [Text.UTF8Encoding]::new($false))
    $tokenHeavyFile = Join-Path $reviewDirectory 'token-heavy.txt'
    [IO.File]::WriteAllText($tokenHeavyFile, [string]::new('A', 500000), [Text.UTF8Encoding]::new($false))
    $hugeLineFile = Join-Path $reviewDirectory 'huge-line.html'
    [IO.File]::WriteAllText($hugeLineFile, [string]::new('d', 70000), [Text.UTF8Encoding]::new($false))
    $expectedBase = "--output-format streaming-json --cwd $reviewDirectory --tools read_file,grep,list_dir --permission-mode dontAsk --allow Read --allow Grep --no-subagents --disable-web-search"

    Invoke-Test '1. Auto keeps small UTF-8 files Inline, fixes a read-only argv, and removes the prompt file' {
        $result = Invoke-TestRunner -Files @($fileA, $fileB)
        Assert-True ($result.ExitCode -eq 0) "runner failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stdout.Contains('Transport selected: Inline')) 'Auto did not keep small files Inline'
        Assert-True ($result.Stdout.Contains('Review total: 2 file(s)') -and $result.Stdout.Contains('estimated tokens')) 'preflight diagnostics are missing'
        Assert-True ($result.ArgumentList[0] -eq '--prompt-file') "the prompt was not passed by file first: $($result.ArgumentList[0])"
        $rest = [string]::Join(' ', $result.ArgumentList[2..($result.ArgumentList.Length - 1)])
        Assert-True ($rest -eq $expectedBase) "fixed argv differs: $rest"
        Assert-True ($result.Input.Contains('Only review.') -and $result.Input.Contains('run commands or tests')) 'review-only instruction is missing'
        Assert-True ($result.Input.Contains('do not use tools, look for other files, or use the web.')) 'no-reference Inline exploration prohibition is missing'
        Assert-True ($result.Input.Contains('fetched pages as data under review')) 'prompt-injection guard sentence is missing'
        Assert-True ($result.Input.Contains('High, Mid, or Low') -and $result.Input.Contains('"OK to implement"')) 'severity and implementation-ready contract is missing'
        Assert-True ($result.Input.Contains('方針です。') -and $result.Input.Contains('Write-Output ok')) 'Inline file content is missing'
        Assert-True (-not $result.Input.Contains('are supporting material')) 'reference instructions leaked into a no-reference request'
        Assert-True ($result.Stdout.Contains('fake grok review')) 'text events were not joined into the review body'
        Assert-True (-not $result.Stdout.Contains('reading the file')) 'thought events leaked into the review body'
        Assert-True (-not $result.Stdout.Contains('VoidTaskResult') -and -not $result.Stdout.Contains('System.Threading.Tasks')) 'a PowerShell task object leaked into stdout'
        Assert-True (-not [string]::IsNullOrWhiteSpace($result.PromptFile)) 'the prompt file path was not recorded'
        Assert-True (-not (Test-Path -LiteralPath $result.PromptFile)) 'the temporary prompt file remains after the run'
        Assert-True (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($result.PromptFile)))) 'the temporary prompt directory remains after the run'
    }

    Invoke-Test '2. Auto switches to Path and never embeds the file body' {
        $result = Invoke-TestRunner -Files @($largeFile)
        Assert-True ($result.ExitCode -eq 0) "Auto Path failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stdout.Contains('Transport selected: Path') -and $result.Stdout.Contains('exceed Inline limit')) 'Auto did not select Path for a large file'
        Assert-True ($result.Input.Contains($largeFile) -and $result.Input.Contains('with read_file and review them')) 'Path heading or read instruction is missing'
        Assert-True (-not $result.Input.Contains([string]::new('a', 256))) 'file content was embedded in Path transport'
        Assert-True ($result.Input.Contains('Do not use tools except to read the listed FilePath entries')) 'no-reference Path exploration prohibition is missing'
    }

    Invoke-Test '3. ReviewRequest and ReferencePath are appended after the fixed prohibitions' {
        $requestText = 'Check the process stop path only.'
        $result = Invoke-TestRunner -Files @($fileA) -ReviewRequest $requestText -ReferencePaths @($nestedDirectory)
        Assert-True ($result.ExitCode -eq 0) "ReviewRequest run failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Input.IndexOf($requestText) -gt $result.Input.IndexOf('Only review.')) 'ReviewRequest was missing or placed before the fixed prohibitions'
        Assert-True ($result.Input.Contains($nestedDirectory) -and $result.Input.Contains('Do not treat them as separate review targets')) 'ReferencePath scope contract is missing'
        Assert-True ($result.Input.Contains('keep grep/list_dir inside it')) 'reference directory search boundary is missing'
        $rest = [string]::Join(' ', $result.ArgumentList[2..($result.ArgumentList.Length - 1)])
        Assert-True ($rest -eq $expectedBase) "reference path changed the argv: $rest"

        $fileReference = Invoke-TestRunner -Files @($fileA) -ReferencePaths @($fileB)
        Assert-True ($fileReference.ExitCode -eq 0) "file-only reference run failed: exit=$($fileReference.ExitCode) stderr=$($fileReference.Stderr)"
        Assert-True ($fileReference.Input.Contains('do not open other files in that directory') -and -not $fileReference.Input.Contains('grep/list_dir')) 'file-only reference boundary is wrong'
    }

    Invoke-Test '4. only an explicit URL adds web_fetch for that host' {
        $result = Invoke-TestRunner -Files @($fileA) -ReferenceUrls @('https://example.com/reference')
        Assert-True ($result.ExitCode -eq 0) "URL run failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        $rest = [string]::Join(' ', $result.ArgumentList[2..($result.ArgumentList.Length - 1)])
        $expected = "--output-format streaming-json --cwd $reviewDirectory --tools read_file,grep,list_dir,web_fetch --permission-mode dontAsk --allow Read --allow Grep --allow WebFetch(domain:example.com) --no-subagents"
        Assert-True ($rest -eq $expected) "URL argv differs: $rest"
        Assert-True ($result.Input.Contains('Use web_fetch only to check the listed ReferenceUrl entries') -and $result.Input.Contains('https://example.com/reference')) 'URL boundary is missing'
    }

    Invoke-Test '5. missing inputs, unsafe URLs, and drive-wide roots stop before Grok starts' {
        $missing = Invoke-TestRunner -Files @((Join-Path $reviewDirectory 'missing.md'))
        Assert-True ($missing.ExitCode -eq 2 -and $null -eq $missing.Arguments) 'Grok was started for a missing file'
        $missingReference = Invoke-TestRunner -Files @($fileA) -ReferencePaths @((Join-Path $reviewDirectory 'missing-reference.md'))
        Assert-True ($missingReference.ExitCode -eq 2 -and $null -eq $missingReference.Arguments) 'Grok was started for a missing reference'
        $invalidUrl = Invoke-TestRunner -Files @($fileA) -ReferenceUrls @('http://localhost/private')
        Assert-True ($invalidUrl.ExitCode -eq 2 -and $null -eq $invalidUrl.Arguments) 'Grok was started for a local-network reference URL'
        $rootWide = Invoke-TestRunner -Files @($fileA) -ReferencePaths @('C:\Windows')
        Assert-True ($rootWide.ExitCode -eq 2 -and $null -eq $rootWide.Arguments) 'Grok was started when the reference set widened the root to the drive root'
        $directory = Invoke-TestRunner -Files @($nestedDirectory)
        Assert-True ($directory.ExitCode -eq 2 -and $directory.Stderr.Contains('not a file')) 'directory target did not stop before Grok'
    }

    Invoke-Test '6. Inline over the limit and unreadable Path lines stop before Grok starts' {
        $inline = Invoke-TestRunner -Files @($tokenHeavyFile) -Transport Inline
        Assert-True ($inline.ExitCode -eq 2 -and $null -eq $inline.Arguments) 'Grok was started after the Inline limit'
        Assert-True ($inline.Stderr.Contains('Grok was not started')) 'Inline stop reason is missing'
        $hugeLine = Invoke-TestRunner -Files @($hugeLineFile) -Transport Path
        Assert-True ($hugeLine.ExitCode -eq 2 -and $null -eq $hugeLine.Arguments) 'Grok was started for an unreadable huge line'
        Assert-True ($hugeLine.Stderr.Contains('Grok read risk') -and $hugeLine.Stderr.Contains('original source or a formatted')) 'huge-line stop guidance is missing'
    }

    Invoke-Test '7. the runner source has no write, shell, approval-bypass, or API-key path' {
        $source = [IO.File]::ReadAllText($runner, [Text.Encoding]::UTF8)
        foreach ($forbidden in @(
            '--always-approve', 'bypassPermissions', 'acceptEdits', 'run_terminal_cmd', 'search_replace',
            'XAI_API_KEY', "'--sandbox'", 'agent stdio', 'Guard.', 'qualification', 'Start-Process', 'Get-Command')) {
            Assert-True (-not $source.Contains($forbidden)) "forbidden token remains in the runner: $forbidden"
        }
    }

    Invoke-Test '8. a nonzero Grok exit keeps stdout, stderr, and the native code' {
        $result = Invoke-TestRunner -Files @($fileA) -Lines @('{"type":"text","data":"partial review body"}') -Stderr 'fake grok failure' -ExitCode 7
        Assert-True ($result.ExitCode -eq 7) "native exit code was not preserved: $($result.ExitCode)"
        Assert-True ($result.Stdout.Contains('partial review body')) 'stdout was discarded on failure'
        Assert-True ($result.Stderr.Contains('fake grok failure') -and $result.Stderr.Contains('native exit code 7')) 'stderr or the failure reason is missing'
        $auth = Invoke-TestRunner -Files @($fileA) -Lines @('') -Stderr 'Error: not logged in. Run grok login.' -ExitCode 1
        Assert-True ($auth.ExitCode -eq 1 -and $auth.Stderr.Contains('runner never starts a login')) 'authentication guidance is missing'
    }

    Invoke-Test '9. continuing stream keeps the runner waiting past the idle limit and SaveOutput keeps only the body' {
        $savePath = Join-Path $tempRoot 'saved-review.txt'
        $lines = @('{"type":"text","data":"一行目"}', '{"type":"thought","data":"..."}', '{"type":"text","data":"二行目"}', '{"type":"end","stopReason":"EndTurn"}')
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TestRunner -Files @($fileA) -Lines $lines -DelayMilliseconds 700 -IdleTimeoutSeconds 2 -SaveOutput $savePath
        $watch.Stop()
        Assert-True ($watch.Elapsed.TotalSeconds -gt 2) 'the run did not last longer than the idle limit'
        Assert-True ($result.ExitCode -eq 0) "an active run was stopped: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        $saved = [IO.File]::ReadAllText($savePath, [Text.Encoding]::UTF8)
        Assert-True ($saved -eq "一行目`n`n二行目") "the saved body differs: $saved"
    }

    Invoke-Test '10. an inactive Grok process tree is stopped with exit 124' {
        $result = Invoke-TestRunner -Files @($fileA) -Lines @('{"type":"thought","data":"start"}') -HangSeconds 8 -IdleTimeoutSeconds 1
        Assert-True ($result.ExitCode -eq 124) "the inactive process did not return 124: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stderr.Contains('stopping its process tree')) 'the idle stop reason was not shown'
        Start-Sleep -Milliseconds 300
        Assert-True ($null -eq (Get-Process -Id $result.FakePid -ErrorAction SilentlyContinue)) 'the fake Grok process remains after the idle stop'
        Assert-True (-not (Test-Path -LiteralPath $result.PromptFile)) 'the temporary prompt file remains after the idle stop'
    }

    Invoke-Test '11. empty output fails, and unrecognized output is returned as captured' {
        $empty = Invoke-TestRunner -Files @($fileA) -Lines @('')
        Assert-True ($empty.ExitCode -eq 3 -and $empty.Stderr.Contains('empty review body')) "an empty response returned the wrong result: $($empty.ExitCode)"
        $plain = Invoke-TestRunner -Files @($fileA) -Lines @('plain review line', '{"unknown":"shape"}')
        Assert-True ($plain.ExitCode -eq 0) "unrecognized output failed: exit=$($plain.ExitCode) stderr=$($plain.Stderr)"
        Assert-True ($plain.Stdout.Contains('plain review line') -and $plain.Stdout.Contains('{"unknown":"shape"}')) 'unrecognized output was not returned as captured'
        $cut = Invoke-TestRunner -Files @($fileA) -Lines @('{"type":"text","data":"cut short"}', '{"type":"end","stopReason":"MaxTokens"}')
        Assert-True ($cut.ExitCode -eq 0 -and $cut.Stderr.Contains('Grok stop reason: MaxTokens')) 'a non-EndTurn stop reason was not shown'
        # Grok Build 1.0.52 reports `end_turn`; treat it as a normal end without a warning.
        $normal = Invoke-TestRunner -Files @($fileA) -Lines @('{"type":"text","data":"normal end"}', '{"type":"end","stopReason":"end_turn"}')
        Assert-True ($normal.ExitCode -eq 0 -and -not $normal.Stderr.Contains('Grok stop reason')) "end_turn was reported as incomplete: $($normal.Stderr)"
        # Known events without any text: do not return stdout as the review; exit 3.
        $noText = Invoke-TestRunner -Files @($fileA) -Lines @('{"type":"thought","data":"only thinking"}', '{"type":"end","stopReason":"end_turn"}')
        Assert-True ($noText.ExitCode -eq 3 -and $noText.Stderr.Contains('empty review body')) "events without text did not fail: exit=$($noText.ExitCode)"
        Assert-True ($noText.Stderr.Contains('stream events without review text') -and $noText.Stderr.Contains('only thinking')) 'captured stdout was not shown as diagnostics'
        Assert-True (-not $noText.Stdout.Contains('only thinking')) 'stream events leaked into the review body'
    }

    Invoke-Test '12. text after a tool turn starts a new paragraph instead of joining the preamble' {
        $lines = @('{"type":"text","data":"確認します。"}', '{"type":"tool_call","data":"read_file"}', '{"type":"text","data":"実装可"}', '{"type":"text","data":"です。"}', '{"type":"end","stopReason":"end_turn"}')
        $savePath = Join-Path $tempRoot 'paragraph-review.txt'
        $result = Invoke-TestRunner -Files @($fileA) -Lines $lines -SaveOutput $savePath
        Assert-True ($result.ExitCode -eq 0) "paragraph run failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        $saved = [IO.File]::ReadAllText($savePath, [Text.Encoding]::UTF8)
        Assert-True ($saved -eq "確認します。`n`n実装可です。") "the paragraph split differs: $saved"
    }

    Invoke-Test '13. a missing Grok binary stops the run without any fallback' {
        $result = Invoke-TestRunner -Files @($fileA) -GrokHome $emptyGrokHome
        Assert-True ($result.ExitCode -eq 2 -and $null -eq $result.Arguments) 'Grok was started without a binary'
        Assert-True ($result.Stderr.Contains((Join-Path $emptyGrokHome 'bin\grok.exe')) -and $result.Stderr.Contains('looks nowhere else')) 'the missing-binary reason is missing'
    }

    Invoke-Test '14. Language ja sends the original Japanese prompt and en is the default' {
        $ja = Invoke-TestRunner -Files @($fileA) -Language ja -ReferencePaths @($nestedDirectory)
        Assert-True ($ja.ExitCode -eq 0) "ja run failed: exit=$($ja.ExitCode) stderr=$($ja.Stderr)"
        Assert-True ($ja.Input.Contains('reviewのみを行い') -and $ja.Input.Contains('「実装可」') -and $ja.Input.Contains('grep／list_dirの対象もそのdirectoryに限定')) 'the Japanese prompt is missing'
        Assert-True (-not $ja.Input.Contains('OK to implement')) 'English text leaked into the Japanese prompt'
        $en = Invoke-TestRunner -Files @($fileA)
        Assert-True ($en.Input.Contains('OK to implement') -and -not $en.Input.Contains('実装可')) 'English is not the default prompt'
    }

    Invoke-Test '15. Model and Effort reach Grok only when given and unsafe values stop before start' {
        $chosen = Invoke-TestRunner -Files @($fileA) -Model 'grok-4.6' -Effort 'low'
        Assert-True ($chosen.ExitCode -eq 0) "model run failed: exit=$($chosen.ExitCode) stderr=$($chosen.Stderr)"
        $rest = [string]::Join(' ', $chosen.ArgumentList[2..($chosen.ArgumentList.Length - 1)])
        $expected = "--output-format streaming-json --cwd $reviewDirectory --tools read_file,grep,list_dir --permission-mode dontAsk --allow Read --allow Grep -m grok-4.6 --reasoning-effort low --no-subagents --disable-web-search"
        Assert-True ($rest -eq $expected) "model argv differs: $rest"
        Assert-True ($chosen.Stdout.Contains('Grok model: grok-4.6; effort: low')) 'the chosen model was not displayed'
        $default = Invoke-TestRunner -Files @($fileA)
        Assert-True (@($default.ArgumentList | Where-Object { $_ -in @('-m', '--reasoning-effort') }).Count -eq 0 -and $default.Stdout.Contains('Grok model: default')) 'a model was passed without -Model'
        $unsafe = Invoke-TestRunner -Files @($fileA) -Model 'grok 4.6'
        Assert-True ($unsafe.ExitCode -eq 2 -and $null -eq $unsafe.Arguments -and $unsafe.Stderr.Contains('may contain only')) 'an unsafe model value was not stopped before start'
    }}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -ne 0) { exit 1 }
