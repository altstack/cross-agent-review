#requires -Version 7.0

<#
    Copy the review skills into each agent's personal skill folder (or remove them).

      Claude Code  ~/.claude/skills   codex-review-files, grok-review-files
      Codex        ~/.agents/skills   claude-review-files, grok-review-files
      Grok Build   ~/.grok/skills     claude-review-files, codex-review-files

    No agent gets the skill that would call itself. Grok also scans ~/.claude/skills, so it can
    see grok-review-files there; that skill tells Grok not to use it.

    By default only agents whose home folder exists (~/.claude, ~/.codex, ~/.grok) are set up.
    Existing skill folders are left alone unless -Force is given. Use -WhatIf to preview.

    Examples (from a PowerShell 7 prompt in this folder):
      .\install.ps1
      .\install.ps1 -Agent Claude,Codex -Force
      .\install.ps1 -Uninstall
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Claude', 'Codex', 'Grok')]
    [string[]]$Agent = @('Claude', 'Codex', 'Grok'),

    [switch]$Force,

    [switch]$Uninstall,

    # Folder that contains .claude, .codex, .agents, and .grok. Defaults to your user profile.
    [string]$HomePath = [Environment]::GetFolderPath('UserProfile')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$targets = [ordered]@{
    Claude = @{ Home = '.claude'; Root = '.claude\skills'; Skills = @('codex-review-files', 'grok-review-files') }
    Codex = @{ Home = '.codex'; Root = '.agents\skills'; Skills = @('claude-review-files', 'grok-review-files') }
    Grok = @{ Home = '.grok'; Root = '.grok\skills'; Skills = @('claude-review-files', 'codex-review-files') }
}
$explicitAgents = $PSBoundParameters.ContainsKey('Agent')
$sourceRoot = Join-Path $PSScriptRoot 'skills'

foreach ($name in $Agent) {
    $target = $targets[$name]
    $agentHome = Join-Path $HomePath $target.Home
    # Uninstall looks only at the skill folders, because Codex keeps its skills outside ~/.codex.
    if (-not $Uninstall -and -not $explicitAgents -and -not [IO.Directory]::Exists($agentHome)) {
        Write-Output "Skip ${name}: $agentHome was not found. Pass -Agent $name to set it up anyway."
        continue
    }
    $skillRoot = Join-Path $HomePath $target.Root
    foreach ($skill in $target.Skills) {
        $destination = Join-Path $skillRoot $skill
        if ($Uninstall) {
            if ([IO.Directory]::Exists($destination)) {
                if ($PSCmdlet.ShouldProcess($destination, 'Remove skill folder')) {
                    Remove-Item -LiteralPath $destination -Recurse -Force -Confirm:$false
                    Write-Output "Removed ${name}: $destination"
                }
            }
            continue
        }
        if ([IO.Directory]::Exists($destination) -and -not $Force) {
            Write-Output "Keep ${name}: $destination already exists. Use -Force to replace it."
            continue
        }
        $source = Join-Path $sourceRoot $skill
        if (-not [IO.Directory]::Exists($source)) {
            throw "Skill source folder was not found: $source. Run install.ps1 from a complete copy of the repository. Nothing was removed."
        }
        if ($PSCmdlet.ShouldProcess($destination, 'Install skill folder')) {
            # Copy next to the destination first, so a failed copy never leaves the old skill deleted.
            [void][IO.Directory]::CreateDirectory($skillRoot)
            $staging = "$destination.installing-$([Guid]::NewGuid().ToString('N'))"
            try {
                Copy-Item -LiteralPath $source -Destination $staging -Recurse -Confirm:$false
                if ([IO.Directory]::Exists($destination)) {
                    Remove-Item -LiteralPath $destination -Recurse -Force -Confirm:$false
                }
                Move-Item -LiteralPath $staging -Destination $destination -Confirm:$false
            }
            finally {
                if ([IO.Directory]::Exists($staging)) {
                    Remove-Item -LiteralPath $staging -Recurse -Force -Confirm:$false
                }
            }
            Write-Output "Installed ${name}: $destination"
        }
    }
}
