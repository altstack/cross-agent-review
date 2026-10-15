#requires -Version 7.0

<#
    Offline regression tests for skills/codex-review-files/scripts/invoke-codex-review.ps1.

    No real Codex, model, network, or external send is used. The fake codex.exe is compiled at
    test time and placed where the runner looks for Codex (PATH, an npm install layout, or the
    desktop app folder under a fake LOCALAPPDATA). These tests check the wrapper; they do not
    prove compatibility with the real Codex CLI.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runner = Join-Path $repoRoot 'skills\codex-review-files\scripts\invoke-codex-review.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ccr-codex-review-' + [Guid]::NewGuid().ToString('N'))
$pwsh = (Get-Process -Id $PID).Path
$passed = 0
$failed = 0

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
        [string[]]$Lines = @('fake codex review'),
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
        [string]$LocalAppData,
        [string]$PathValue,
        [string]$CodexPath,
        [string]$Language,
        [switch]$LeaveStdinUnread
    )
    $stdinPath = Join-Path $tempRoot 'fake-stdin.txt'
    $argsPath = Join-Path $tempRoot 'fake-args.txt'
    $pidPath = Join-Path $tempRoot 'fake-pid.txt'
    Remove-Item -LiteralPath $stdinPath, $argsPath, $pidPath -Force -ErrorAction SilentlyContinue

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
        if (-not [string]::IsNullOrWhiteSpace($CodexPath)) {
            $command += " -CodexPath $(ConvertTo-TestLiteral $CodexPath)"
        }
        if (-not [string]::IsNullOrWhiteSpace($Language)) {
            $command += " -Language $(ConvertTo-TestLiteral $Language)"
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
        if (-not [string]::IsNullOrWhiteSpace($CodexPath)) {
            [void]$start.ArgumentList.Add('-CodexPath')
            [void]$start.ArgumentList.Add($CodexPath)
        }
        if (-not [string]::IsNullOrWhiteSpace($Language)) {
            [void]$start.ArgumentList.Add('-Language')
            [void]$start.ArgumentList.Add($Language)
        }
    }

    # The real PATH may hold an installed Codex CLI; keep discovery inside the test fixtures.
    $start.Environment['PATH'] = if ([string]::IsNullOrWhiteSpace($PathValue)) { $emptyPathDirectory } else { $PathValue }
    $start.Environment['LOCALAPPDATA'] = if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $fakeLocalAppData } else { $LocalAppData }
    $start.Environment['CCR_FAKE_STDIN'] = $stdinPath
    $start.Environment['CCR_FAKE_ARGS'] = $argsPath
    $start.Environment['CCR_FAKE_PID'] = $pidPath
    $start.Environment['CCR_FAKE_STDOUT_B64'] = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $Lines)))
    $start.Environment['CCR_FAKE_STDERR'] = $Stderr
    $start.Environment['CCR_FAKE_EXIT'] = [string]$ExitCode
    $start.Environment['CCR_FAKE_DELAY_MS'] = [string]$DelayMilliseconds
    $start.Environment['CCR_FAKE_HANG_SECONDS'] = [string]$HangSeconds
    $start.Environment['CCR_FAKE_READ_STDIN'] = if ($LeaveStdinUnread) { '0' } else { '1' }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $stdoutText = $process.StandardOutput.ReadToEnd()
    $stderrText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutText
        Stderr = $stderrText
        Input = if (Test-Path -LiteralPath $stdinPath) { [IO.File]::ReadAllText($stdinPath, [Text.Encoding]::UTF8) } else { $null }
        Arguments = if (Test-Path -LiteralPath $argsPath) { [IO.File]::ReadAllText($argsPath, [Text.Encoding]::UTF8) } else { $null }
        FakePid = if (Test-Path -LiteralPath $pidPath) { [int][IO.File]::ReadAllText($pidPath, [Text.Encoding]::UTF8) } else { $null }
    }
}

try {
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null

    # Fake codex.exe compiled with the .NET Framework csc.exe that ships with Windows. It records
    # argv, PID, and the prompt from stdin, then prints the scripted output. It starts in
    # milliseconds, so the short idle limits below do not race a slow interpreter.
    $csc = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) {
        throw "csc.exe was not found at $csc. The offline harness compiles a fake codex.exe with it; no network or model is used."
    }
$fakeSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

static class FakeCodex
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
        File.WriteAllText(Env("CCR_FAKE_PID"), Process.GetCurrentProcess().Id.ToString(), utf8);
        File.WriteAllText(Env("CCR_FAKE_ARGS"), string.Join("\n", args), utf8);
        // CCR_FAKE_READ_STDIN=0 is a Codex that never reads stdin, so the prompt write blocks.
        if (Env("CCR_FAKE_READ_STDIN") != "0")
        {
            string input = new StreamReader(Console.OpenStandardInput(), utf8).ReadToEnd();
            File.WriteAllText(Env("CCR_FAKE_STDIN"), input, utf8);
        }
        StreamWriter stdout = new StreamWriter(Console.OpenStandardOutput(), utf8);
        stdout.AutoFlush = true;
        string body = utf8.GetString(Convert.FromBase64String(Env("CCR_FAKE_STDOUT_B64")));
        int delay = Number("CCR_FAKE_DELAY_MS");
        if (body.Length > 0)
        {
            foreach (string line in body.Split('\n'))
            {
                stdout.WriteLine(line);
                if (delay > 0) { Thread.Sleep(delay); }
            }
        }
        string stderrText = Env("CCR_FAKE_STDERR");
        if (stderrText.Length > 0)
        {
            StreamWriter stderr = new StreamWriter(Console.OpenStandardError(), utf8);
            stderr.AutoFlush = true;
            stderr.WriteLine(stderrText);
        }
        int hang = Number("CCR_FAKE_HANG_SECONDS");
        if (hang > 0) { Thread.Sleep(hang * 1000); }
        return Number("CCR_FAKE_EXIT");
    }
}
"@
    $fakeSourcePath = Join-Path $tempRoot 'FakeCodex.cs'
    [IO.File]::WriteAllText($fakeSourcePath, $fakeSource, [Text.UTF8Encoding]::new($false))
    $fakeCodex = Join-Path $tempRoot 'fake-codex.exe'
    $compileOutput = & $csc /nologo /target:exe "/out:$fakeCodex" $fakeSourcePath 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fakeCodex)) {
        throw "fake codex.exe compile failed: $compileOutput"
    }
    # Two desktop-app candidates. The older one is a dummy file, so a broken newest-first choice fails to start.
    $fakeLocalAppData = Join-Path $tempRoot 'localappdata'
    $codexBin = Join-Path $fakeLocalAppData 'OpenAI\Codex\bin'
    $staleDirectory = Join-Path $codexBin '1111111111111111'
    $freshDirectory = Join-Path $codexBin '2222222222222222'
    [IO.Directory]::CreateDirectory($staleDirectory) | Out-Null
    [IO.Directory]::CreateDirectory($freshDirectory) | Out-Null
    $staleExecutable = Join-Path $staleDirectory 'codex.exe'
    $freshExecutable = Join-Path $freshDirectory 'codex.exe'
    [IO.File]::WriteAllText($staleExecutable, 'stale candidate, not a real binary', [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $fakeCodex -Destination $freshExecutable -Force
    [IO.File]::SetLastWriteTimeUtc($staleExecutable, [datetime]::UtcNow.AddDays(-30))
    [IO.File]::SetLastWriteTimeUtc($freshExecutable, [datetime]::UtcNow)

    $emptyLocalAppData = Join-Path $tempRoot 'emptylocalappdata'
    [IO.Directory]::CreateDirectory((Join-Path $emptyLocalAppData 'OpenAI\Codex\bin')) | Out-Null

    # PATH fixtures: copies of the fake codex.exe in an npm layout, an editor folder, and an explicit path.
    $emptyPathDirectory = Join-Path $tempRoot 'path-empty'
    [IO.Directory]::CreateDirectory($emptyPathDirectory) | Out-Null
    $npmPathDirectory = Join-Path $tempRoot 'path-npm'
    $npmNative = Join-Path $npmPathDirectory 'node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($npmNative)) | Out-Null
    Copy-Item -LiteralPath $fakeCodex -Destination $npmNative -Force
    [IO.File]::WriteAllText((Join-Path $npmPathDirectory 'codex.cmd'), '@echo off', [Text.ASCIIEncoding]::new())
    $editorPathDirectory = Join-Path $tempRoot '.vscode\extensions\openai.chatgpt-1.0.0-win32-x64\bin\windows-x86_64'
    [IO.Directory]::CreateDirectory($editorPathDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $editorPathDirectory 'codex.exe'), 'editor copy, not a real binary', [Text.UTF8Encoding]::new($false))
    $explicitDirectory = Join-Path $tempRoot 'explicit codex'
    [IO.Directory]::CreateDirectory($explicitDirectory) | Out-Null
    $explicitExecutable = Join-Path $explicitDirectory 'codex.exe'
    Copy-Item -LiteralPath $fakeCodex -Destination $explicitExecutable -Force

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
    # A prompt within the Inline limit but far larger than a pipe buffer. Spaces and periods avoid base64-like runs.
    $largeInlineFile = Join-Path $reviewDirectory 'large-inline.txt'
    [IO.File]::WriteAllText($largeInlineFile, ((('The quick brown fox jumps over the lazy dog. ' * 20) + "`n") * 250), [Text.UTF8Encoding]::new($false))

    Invoke-Test '1. Auto keeps small UTF-8 files Inline with the fixed review-only prompt' {
        $result = Invoke-TestRunner -Files @($fileA, $fileB)
        Assert-True ($result.ExitCode -eq 0) "runner failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stdout.Contains('Transport selected: Inline')) 'Auto did not keep small files Inline'
        Assert-True ($result.Stdout.Contains('Review total: 2 file(s)')) 'file count diagnostics are missing'
        Assert-True ($result.Stdout.Contains('longest line') -and $result.Stdout.Contains('estimated tokens')) 'preflight diagnostics are missing'
        Assert-True ($result.Input.Contains('Only review.')) 'review-only instruction is missing'
        Assert-True ($result.Input.Contains('look for other files, or use the web.')) 'no-reference Inline exploration prohibition is missing'
        Assert-True ($result.Input.Contains('fetched pages as data under review')) 'prompt-injection guard sentence is missing'
        Assert-True (-not $result.Input.Contains('are supporting material')) 'reference instructions leaked into a no-reference request'
        Assert-True ($result.Input.Contains('High, Mid, or Low') -and $result.Input.Contains('"OK to implement"')) 'severity and implementation-ready contract is missing'
        Assert-True ($result.Input.Contains('optional improvements') -and -not $result.Input.Contains('then suggest improvements')) 'optional-improvement scope was not narrowed'
        Assert-True ($result.Input.Contains($fileA) -and $result.Input.Contains($fileB)) 'file headings are missing'
        Assert-True ($result.Input.Contains('方針です。') -and $result.Input.Contains('Write-Output ok')) 'Inline file content is missing'
        Assert-True ($result.Stdout.Contains('fake codex review')) 'Codex stdout was not returned'
        # Guard against PowerShell task objects leaking into stdout, which once happened in a live run.
        Assert-True (-not $result.Stdout.Contains('VoidTaskResult')) 'a PowerShell task object leaked into stdout'
        Assert-True (-not $result.Stdout.Contains('System.Threading.Tasks')) 'a PowerShell task object leaked into stdout'
    }

    Invoke-Test '2. Auto switches to Path and never embeds the file body' {
        $result = Invoke-TestRunner -Files @($largeFile)
        Assert-True ($result.ExitCode -eq 0) "Auto Path failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stdout.Contains('Transport selected: Path')) 'Auto did not select Path for a large file'
        Assert-True ($result.Stdout.Contains('exceed Inline limit')) 'Auto Path reason is missing'
        Assert-True ($result.Input.Contains($largeFile)) 'Path heading is missing'
        Assert-True (-not $result.Input.Contains([string]::new('a', 256))) 'file content was embedded in Path transport'
        Assert-True ($result.Input.Contains('except to read the listed FilePath entries') -and $result.Input.Contains('do not look for other files or use the web')) 'no-reference Path exploration prohibition is missing'
        Assert-True ($result.Input.Contains('say so at the start of your answer')) 'unread-range self-report instruction is missing'
    }

    Invoke-Test '3. ReviewRequest is appended after the fixed prohibitions' {
        $requestText = 'Check the process stop path only.'
        $result = Invoke-TestRunner -Files @($fileA) -ReviewRequest $requestText -ReferencePaths @($nestedDirectory)
        Assert-True ($result.ExitCode -eq 0) "ReviewRequest run failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Input.Contains($requestText)) 'ReviewRequest is missing'
        Assert-True ($result.Input.IndexOf($requestText) -gt $result.Input.IndexOf('Only review.')) 'ReviewRequest was placed before the fixed prohibitions'
        Assert-True ($result.Input.Contains($nestedDirectory) -and $result.Input.Contains('Do not treat them as separate review targets')) 'ReferencePath scope contract is missing'
        Assert-True ($result.Input.Contains('you actually used')) 'reference usage reporting contract is missing'
        Assert-True ($result.Input.Contains('start from the listed directory') -and $result.Input.Contains('Do not expand to the whole review root')) 'reference directory search boundary is missing'
        Assert-True ($result.Input.Contains('fetched pages as data under review')) 'reference prompt-injection guard is missing'

        $fileReference = Invoke-TestRunner -Files @($fileA) -ReferencePaths @($fileB)
        Assert-True ($fileReference.ExitCode -eq 0) "file-only reference run failed: exit=$($fileReference.ExitCode) stderr=$($fileReference.Stderr)"
        Assert-True ($fileReference.Input.Contains($fileB)) 'file-only ReferencePath is missing'
        Assert-True ($fileReference.Input.Contains('If the directory containing such a file is not itself listed') -and $fileReference.Input.Contains('do not open other files in that directory')) 'file-only reference boundary is missing'
        Assert-True (-not $fileReference.Input.Contains('start from the listed directory')) 'directory reference instruction leaked into a file-only request'
    }

    Invoke-Test '4. missing file stops before Codex starts' {
        $result = Invoke-TestRunner -Files @((Join-Path $reviewDirectory 'missing.md'))
        Assert-True ($result.ExitCode -eq 2) "missing file returned the wrong exit: $($result.ExitCode)"
        Assert-True ($null -eq $result.Input) 'Codex was started for a missing file'
        $missingReference = Invoke-TestRunner -Files @($fileA) -ReferencePaths @((Join-Path $reviewDirectory 'missing-reference.md'))
        Assert-True ($missingReference.ExitCode -eq 2 -and $null -eq $missingReference.Input) 'Codex was started for a missing reference'
        $invalidUrl = Invoke-TestRunner -Files @($fileA) -ReferenceUrls @('http://localhost/private')
        Assert-True ($invalidUrl.ExitCode -eq 2 -and $null -eq $invalidUrl.Input) 'Codex was started for a local-network reference URL'
        $rootWide = Invoke-TestRunner -Files @($fileA) -ReferencePaths @('C:\Windows')
        Assert-True ($rootWide.ExitCode -eq 2 -and $null -eq $rootWide.Input) 'Codex was started when the reference set widened the common root to the drive root'
    }

    Invoke-Test '5. directory target stops before Codex starts' {
        $result = Invoke-TestRunner -Files @($nestedDirectory)
        Assert-True ($result.ExitCode -eq 2) "directory returned the wrong exit: $($result.ExitCode)"
        Assert-True ($null -eq $result.Input) 'Codex was started for a directory'
        Assert-True ($result.Stderr.Contains('not a file')) 'directory stop reason is missing'
    }

    Invoke-Test '6. explicit Inline over the limit stops before Codex starts' {
        $result = Invoke-TestRunner -Files @($tokenHeavyFile) -Transport Inline
        Assert-True ($result.ExitCode -eq 2) "over-limit Inline returned the wrong exit: $($result.ExitCode)"
        Assert-True ($null -eq $result.Input) 'Codex was started after the Inline limit was exceeded'
        Assert-True ($result.Stderr.Contains('Codex was not started')) 'Inline stop reason is missing'
    }

    Invoke-Test '7. the fixed argv is read-only and starts exec exactly once' {
        $result = Invoke-TestRunner -Files @($fileA, $fileB)
        Assert-True ($result.ExitCode -eq 0) "argv run failed: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        $arguments = @($result.Arguments -split "`n")
        Assert-True ([IO.Path]::GetFileName($arguments[0]) -eq 'exec') "the first argument was not exec: $($arguments[0])"
        $rest = [string]::Join(' ', $arguments[1..($arguments.Length - 1)])
        Assert-True ($rest -eq "--sandbox read-only --color never --skip-git-repo-check -C $reviewDirectory -") "fixed argv differs: $rest"
        Assert-True (@($arguments | Where-Object { [IO.Path]::GetFileName($_) -eq 'exec' }).Count -eq 1) 'exec appears more than once'
        Assert-True ($result.Stdout.Contains('Codex argv: exec --sandbox read-only')) 'argv was not displayed before the run'
        Assert-True ($result.Stdout.Contains("Review root: $reviewDirectory")) 'the review root was not displayed'

        # A root-level --search is not forwarded to exec, so live web search is enabled with exec's own -c, and only for explicit URLs.
        $withUrl = Invoke-TestRunner -Files @($fileA) -ReferenceUrls @('https://example.com/reference')
        Assert-True ($withUrl.ExitCode -eq 0) "URL reference run failed: exit=$($withUrl.ExitCode) stderr=$($withUrl.Stderr)"
        $urlArguments = @($withUrl.Arguments -split "`n")
        Assert-True ([IO.Path]::GetFileName($urlArguments[0]) -eq 'exec') "the first URL-run argument was not exec: $($urlArguments[0])"
        $urlRest = [string]::Join(' ', $urlArguments[1..($urlArguments.Length - 1)])
        Assert-True ($urlRest -eq "--sandbox read-only --color never --skip-git-repo-check -C $reviewDirectory -c web_search=`"live`" -") "URL argv differs: $urlRest"
        Assert-True (-not $withUrl.Stdout.Contains('--search')) 'the ineffective root --search flag is still used'
        Assert-True (-not $result.Arguments.Contains('web_search')) 'web search was enabled without a reference URL'
    }

    Invoke-Test '8. the runner source has no forbidden flags, parsers, or frozen dependencies' {
        $source = [IO.File]::ReadAllText($runner, [Text.Encoding]::UTF8)
        foreach ($forbidden in @(
            '--ephemeral', '--json', '--output-schema', '--output-last-message',
            '--full-auto', '--yolo', '--add-dir', 'bypass-approvals', 'workspace-write',
            'danger-full-access', 'ConvertFrom-Json', 'Get-Command',
            'Guard.', 'profile', 'qualification', 'authorization', 'Job Object')) {
            Assert-True (-not $source.Contains($forbidden)) "forbidden token remains in the runner: $forbidden"
        }
        Assert-True ($source.Contains('--sandbox') -and $source.Contains('read-only')) 'the read-only sandbox argument is missing'
        Assert-True ($source.Contains('Use web search only to check the listed ReferenceUrl entries')) 'reference URL prompt boundary is missing'
        Assert-True ($source.Contains('general searches with other queries') -and $source.Contains('other pages on the same host')) 'reference URL surrounding-search prohibition is missing'
        Assert-True (-not $source.Contains('Start-Process')) 'the runner must start exactly one process through ProcessStartInfo'
    }

    Invoke-Test '9. a nonzero Codex exit keeps stdout, stderr, and the native code, including an exit while the prompt is still being written' {
        $result = Invoke-TestRunner -Files @($fileA) -Lines @('partial review body') -Stderr 'fake codex failure' -ExitCode 7
        Assert-True ($result.ExitCode -eq 7) "native exit code was not preserved: $($result.ExitCode)"
        Assert-True ($result.Stdout.Contains('partial review body')) 'stdout was discarded on failure'
        Assert-True ($result.Stderr.Contains('fake codex failure')) 'stderr was discarded on failure'
        Assert-True ($result.Stderr.Contains('native exit code 7')) 'the failure reason is missing'

        # Codex exits early without reading stdin.
        $early = Invoke-TestRunner -Files @($largeInlineFile) -Lines @('body before the early exit') -Stderr 'fake early failure' -ExitCode 9 -LeaveStdinUnread -IdleTimeoutSeconds 20
        Assert-True ($null -eq $early.Input) 'the fake Codex consumed stdin, so the early-exit path was not exercised'
        Assert-True ($early.Stdout.Contains('Transport selected: Inline')) 'the early-exit run did not use an Inline prompt'
        Assert-True ($early.ExitCode -eq 9) "the native exit code was not kept after a stdin write failure: $($early.ExitCode)"
        Assert-True ($early.Stdout.Contains('body before the early exit')) 'stdout was discarded when the prompt write failed'
        Assert-True ($early.Stderr.Contains('fake early failure')) 'stderr was discarded when the prompt write failed'
        Assert-True ($early.Stderr.Contains('native exit code 9')) 'the native exit code was not displayed'
        Assert-True ((@([regex]::Matches($early.Stdout, 'Codex argv:'))).Count -eq 1) 'Codex was started more than once'
    }

    Invoke-Test '10. continuing output keeps the runner waiting past the idle limit and SaveOutput keeps the body' {
        $savePath = Join-Path $tempRoot 'saved-review.txt'
        $lines = @('一行目', '二行目', '三行目', '四行目')
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TestRunner -Files @($fileA) -Lines $lines -DelayMilliseconds 700 -IdleTimeoutSeconds 2 -SaveOutput $savePath
        $watch.Stop()
        Assert-True ($watch.Elapsed.TotalSeconds -gt 2) 'the run did not last longer than the idle limit'
        Assert-True ($result.ExitCode -eq 0) "an active run was stopped: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stdout.Contains('一行目') -and $result.Stdout.Contains('四行目')) 'the full body was not returned'
        $saved = [IO.File]::ReadAllText($savePath, [Text.Encoding]::UTF8)
        Assert-True ($saved.Contains('一行目') -and $saved.Contains('四行目')) 'the saved body is incomplete'
        Assert-True (-not $saved.Contains('Review target:')) 'runner diagnostics leaked into the saved body'
        Assert-True (-not $saved.Contains('VoidTaskResult')) 'a PowerShell task object leaked into the saved body'
    }

    Invoke-Test '11. an inactive Codex process tree is stopped with exit 124, including while the prompt is still being written' {
        $result = Invoke-TestRunner -Files @($fileA) -Lines @('first line only') -HangSeconds 10 -IdleTimeoutSeconds 3
        Assert-True ($result.ExitCode -eq 124) "the inactive process did not return 124: exit=$($result.ExitCode) stderr=$($result.Stderr)"
        Assert-True ($result.Stderr.Contains('stopping its process tree')) 'the idle stop reason was not shown'
        Assert-True ($result.Stdout.Contains('first line only')) 'output captured before the stop was discarded'
        Start-Sleep -Milliseconds 300
        Assert-True ($null -eq (Get-Process -Id $result.FakePid -ErrorAction SilentlyContinue)) 'the fake Codex process remains after the idle stop'

        # Codex never reads stdin and hangs. A synchronous write would block before the watch loop starts.
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $blocked = Invoke-TestRunner -Files @($largeInlineFile) -Lines @() -HangSeconds 20 -IdleTimeoutSeconds 1 -LeaveStdinUnread
        $watch.Stop()
        Assert-True ($null -eq $blocked.Input) 'the fake Codex consumed stdin, so the blocked-write path was not exercised'
        Assert-True ($blocked.ExitCode -eq 124) "the blocked prompt write did not return 124: exit=$($blocked.ExitCode) stderr=$($blocked.Stderr)"
        Assert-True ($blocked.Stderr.Contains('stopping its process tree')) 'the idle stop did not run while the prompt write was pending'
        Assert-True ($watch.Elapsed.TotalSeconds -lt 15) "the runner did not stop at the idle limit: $($watch.Elapsed.TotalSeconds)s"
        Start-Sleep -Milliseconds 300
        Assert-True ($null -eq (Get-Process -Id $blocked.FakePid -ErrorAction SilentlyContinue)) 'the fake Codex process remains after the blocked-write stop'
    }

    Invoke-Test '12. exit 0 with an empty body is reported as a failure' {
        $result = Invoke-TestRunner -Files @($fileA) -Lines @('')
        Assert-True ($result.ExitCode -eq 3) "an empty response returned the wrong exit: $($result.ExitCode)"
        Assert-True ($result.Stderr.Contains('empty review body')) 'the empty-response reason is missing'
    }

    Invoke-Test '13. Codex is found from -CodexPath, the PATH CLI (npm), then the desktop app, skipping editor copies' {
        $app = Invoke-TestRunner -Files @($fileA)
        Assert-True ($app.ExitCode -eq 0) "desktop-app run failed: exit=$($app.ExitCode) stderr=$($app.Stderr)"
        Assert-True ($app.Stdout.Contains("Codex executable: $freshExecutable (Codex desktop app (2 candidate(s), newest selected)")) 'the newest desktop-app binary was not selected or not displayed'

        $npm = Invoke-TestRunner -Files @($fileA) -PathValue $npmPathDirectory
        Assert-True ($npm.ExitCode -eq 0) "npm run failed: exit=$($npm.ExitCode) stderr=$($npm.Stderr)"
        Assert-True ($npm.Stdout.Contains("Codex executable: $npmNative (Codex CLI installed with npm")) 'the native binary inside the npm install was not preferred over the desktop app'

        $editor = Invoke-TestRunner -Files @($fileA) -PathValue $editorPathDirectory
        Assert-True ($editor.ExitCode -eq 0) "editor-copy run failed: exit=$($editor.ExitCode) stderr=$($editor.Stderr)"
        Assert-True ($editor.Stdout.Contains("Codex executable: $freshExecutable")) 'an editor-extension copy on PATH was used instead of the desktop app'

        $explicit = Invoke-TestRunner -Files @($fileA) -PathValue $npmPathDirectory -CodexPath $explicitExecutable
        Assert-True ($explicit.ExitCode -eq 0) "explicit run failed: exit=$($explicit.ExitCode) stderr=$($explicit.Stderr)"
        Assert-True ($explicit.Stdout.Contains("Codex executable: $explicitExecutable (explicit -CodexPath")) '-CodexPath did not take priority'

        $missing = Invoke-TestRunner -Files @($fileA) -CodexPath (Join-Path $tempRoot 'no-such-codex.exe')
        Assert-True ($missing.ExitCode -eq 2 -and $null -eq $missing.Input -and $missing.Stderr.Contains('CodexPath was not found')) 'a missing -CodexPath did not stop the run'

        $none = Invoke-TestRunner -Files @($fileA) -LocalAppData $emptyLocalAppData
        Assert-True ($none.ExitCode -eq 2 -and $null -eq $none.Input) "no candidate did not stop the run: exit=$($none.ExitCode)"
        Assert-True ($none.Stderr.Contains('Codex CLI was not found') -and $none.Stderr.Contains('npm install -g @openai/codex')) 'the not-found guidance is missing'
    }

    Invoke-Test '14. Language ja sends the original Japanese prompt and en is the default' {
        $ja = Invoke-TestRunner -Files @($fileA) -Language ja -ReferenceUrls @('https://example.com/reference')
        Assert-True ($ja.ExitCode -eq 0) "ja run failed: exit=$($ja.ExitCode) stderr=$($ja.Stderr)"
        Assert-True ($ja.Input.Contains('reviewのみを行い') -and $ja.Input.Contains('「実装可」') -and $ja.Input.Contains('web searchは列挙されたReferenceUrlの確認だけ')) 'the Japanese prompt is missing'
        Assert-True (-not $ja.Input.Contains('OK to implement')) 'English text leaked into the Japanese prompt'
        $en = Invoke-TestRunner -Files @($fileA)
        Assert-True ($en.Input.Contains('OK to implement') -and -not $en.Input.Contains('実装可')) 'English is not the default prompt'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -ne 0) { exit 1 }
