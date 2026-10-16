#requires -Version 7.0

<#
    Offline tests for install.ps1. They use a temporary home folder and never touch your profile.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer = Join-Path $repoRoot 'install.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('car-install-' + [Guid]::NewGuid().ToString('N'))
$pwsh = (Get-Process -Id $PID).Path
$passed = 0
$failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
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

function Invoke-Installer {
    param([string]$HomePath, [string[]]$Arguments = @(), [string]$Script = $installer)
    $output = & $pwsh -NoProfile -File $Script -HomePath $HomePath @Arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = [string]::Join("`n", @($output)) }
}

function New-TestHome {
    param([string]$Name, [string[]]$AgentFolders)
    $homePath = Join-Path $tempRoot $Name
    foreach ($folder in $AgentFolders) { [void][IO.Directory]::CreateDirectory((Join-Path $homePath $folder)) }
    return $homePath
}

try {
    [void][IO.Directory]::CreateDirectory($tempRoot)

    Invoke-Test '1. each detected agent gets the two skills that call the other agents, never itself' {
        $homePath = New-TestHome 'all' @('.claude', '.codex', '.grok')
        $result = Invoke-Installer $homePath
        Assert-True ($result.ExitCode -eq 0) "installer failed: $($result.Output)"
        $expected = @(
            '.claude\skills\codex-review-files\scripts\invoke-codex-review.ps1',
            '.claude\skills\grok-review-files\scripts\invoke-grok-review.ps1',
            '.agents\skills\claude-review-files\scripts\invoke-claude-review.ps1',
            '.agents\skills\grok-review-files\agents\openai.yaml',
            '.grok\skills\claude-review-files\SKILL.md',
            '.grok\skills\codex-review-files\SKILL.md')
        foreach ($relative in $expected) {
            Assert-True (Test-Path -LiteralPath (Join-Path $homePath $relative)) "missing after install: $relative"
        }
        foreach ($relative in @('.claude\skills\claude-review-files', '.agents\skills\codex-review-files', '.grok\skills\grok-review-files')) {
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $homePath $relative))) "an agent received its own skill: $relative"
        }
    }

    Invoke-Test '2. agents without a home folder are skipped unless named with -Agent' {
        $homePath = New-TestHome 'claude-only' @('.claude')
        $result = Invoke-Installer $homePath
        Assert-True ($result.Output.Contains('Skip Codex') -and $result.Output.Contains('Skip Grok')) "missing agents were not reported: $($result.Output)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $homePath '.agents'))) 'Codex skills were installed without a ~/.codex folder'
        $named = Invoke-Installer $homePath @('-Agent', 'Grok')
        Assert-True (Test-Path -LiteralPath (Join-Path $homePath '.grok\skills\claude-review-files\SKILL.md')) "-Agent Grok did not install: $($named.Output)"
    }

    Invoke-Test '3. existing skill folders are kept without -Force and replaced with -Force' {
        $homePath = New-TestHome 'force' @('.claude')
        [void](Invoke-Installer $homePath)
        $marker = Join-Path $homePath '.claude\skills\codex-review-files\local-note.txt'
        [IO.File]::WriteAllText($marker, 'user edit', [Text.UTF8Encoding]::new($false))
        $keep = Invoke-Installer $homePath
        Assert-True ($keep.Output.Contains('Keep Claude') -and (Test-Path -LiteralPath $marker)) 'an existing skill folder was replaced without -Force'
        $force = Invoke-Installer $homePath @('-Force')
        Assert-True ($force.Output.Contains('Installed Claude') -and -not (Test-Path -LiteralPath $marker)) '-Force did not replace the skill folder'
    }

    Invoke-Test '4. -WhatIf changes nothing and -Uninstall removes only these skills' {
        $homePath = New-TestHome 'uninstall' @('.claude', '.codex', '.grok')
        [void](Invoke-Installer $homePath @('-WhatIf'))
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $homePath '.claude\skills'))) '-WhatIf installed skills'
        [void](Invoke-Installer $homePath)
        $other = Join-Path $homePath '.claude\skills\someone-else'
        [void][IO.Directory]::CreateDirectory($other)
        $result = Invoke-Installer $homePath @('-Uninstall')
        Assert-True ($result.ExitCode -eq 0) "uninstall failed: $($result.Output)"
        foreach ($relative in @('.claude\skills\codex-review-files', '.claude\skills\grok-review-files', '.agents\skills\claude-review-files', '.agents\skills\grok-review-files', '.grok\skills\claude-review-files', '.grok\skills\codex-review-files')) {
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $homePath $relative))) "not removed: $relative"
        }
        Assert-True (Test-Path -LiteralPath $other) 'an unrelated skill folder was removed'
    }

    Invoke-Test '5. a missing skill source stops -Force before anything installed is removed' {
        $partialRepo = Join-Path $tempRoot 'partial repo'
        [void][IO.Directory]::CreateDirectory((Join-Path $partialRepo 'plugins\review-with-grok\skills'))
        Copy-Item -LiteralPath $installer -Destination (Join-Path $partialRepo 'install.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'plugins\review-with-grok\skills\grok-review-files') -Destination (Join-Path $partialRepo 'plugins\review-with-grok\skills\grok-review-files') -Recurse
        $homePath = New-TestHome 'partial' @('.claude')
        [void](Invoke-Installer $homePath)
        $marker = Join-Path $homePath '.claude\skills\codex-review-files\local-note.txt'
        [IO.File]::WriteAllText($marker, 'installed copy', [Text.UTF8Encoding]::new($false))
        $result = Invoke-Installer $homePath @('-Force') -Script (Join-Path $partialRepo 'install.ps1')
        Assert-True ($result.ExitCode -ne 0 -and $result.Output.Contains('Skill source folder was not found')) "a missing source did not stop the installer: $($result.Output)"
        Assert-True (Test-Path -LiteralPath $marker) 'the installed skill was removed although its source was missing'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $homePath '.claude\skills') -Directory | Where-Object Name -like '*.installing-*').Count -eq 0) 'a staging folder was left behind'
    }

    Invoke-Test '6. -Uninstall removes Codex skills even when ~/.codex is gone' {
        $homePath = New-TestHome 'codex-gone' @('.codex')
        [void](Invoke-Installer $homePath)
        Assert-True (Test-Path -LiteralPath (Join-Path $homePath '.agents\skills\claude-review-files')) 'Codex skills were not installed'
        Remove-Item -LiteralPath (Join-Path $homePath '.codex') -Recurse -Force
        $result = Invoke-Installer $homePath @('-Uninstall')
        Assert-True ($result.ExitCode -eq 0 -and -not $result.Output.Contains('Skip Codex')) "uninstall skipped Codex: $($result.Output)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $homePath '.agents\skills\claude-review-files'))) 'Codex skills were left after uninstall'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -ne 0) { exit 1 }
