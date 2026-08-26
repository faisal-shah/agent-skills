<#
.SYNOPSIS
    Install or uninstall the playwright-cli agent skill.

.DESCRIPTION
    Copies SKILL.md, references/, and scripts/ into the target skills directory.
    Defaults to both ~/.copilot/skills and ~/.codex/skills if no path is
    provided. On Windows, a default-directory install also applies the
    idempotent no-popup repair to an existing global @playwright/cli package.

.EXAMPLE
    .\install.ps1                               # install to default Copilot and Codex dirs
    .\install.ps1 -Copilot                      # install to Copilot only
    .\install.ps1 -Codex                        # install to Codex only
    .\install.ps1 -Claude                       # install to Claude Code only
    .\install.ps1 -SkillsDir C:\my\skills       # install to custom path
    .\install.ps1 -Uninstall                    # uninstall from default dirs
#>
param(
    [string]$SkillsDir,
    [switch]$Copilot,
    [switch]$Codex,
    [switch]$Claude,
    [switch]$All,
    [switch]$Uninstall,
    [switch]$Help
)

$SkillName = "playwright-cli"

function Show-Usage {
    Write-Output "Usage: .\install.ps1 [-Uninstall] [-Copilot|-Codex|-Claude|-All] [-SkillsDir <path>]"
    Write-Output ""
    Write-Output "  Install:    .\install.ps1                          # defaults to ~/.copilot/skills and ~/.codex/skills"
    Write-Output "  Install:    .\install.ps1 -Copilot"
    Write-Output "  Install:    .\install.ps1 -Codex"
    Write-Output "  Install:    .\install.ps1 -Claude                    # ~/.claude/skills"
    Write-Output "  Install:    .\install.ps1 -SkillsDir C:\my\skills"
    Write-Output "  Uninstall:  .\install.ps1 -Uninstall               # removes from both default user dirs"
    Write-Output ""
    Write-Output "Creates <skills-directory>\$SkillName\ with SKILL.md, references/, and scripts/."
    exit 1
}

if ($Help) { Show-Usage }

if ($SkillsDir -and ($Copilot -or $Codex -or $Claude -or $All)) {
    Write-Error "Use either -SkillsDir or agent switches, not both."
    exit 1
}

$ScriptRoot = $PSScriptRoot
$TargetRoots = @()

if ($SkillsDir) {
    $TargetRoots = @($SkillsDir)
} else {
    if ($All) {
        $Copilot = $true
        $Codex = $true
        $Claude = $true
    }

    if (-not $Copilot -and -not $Codex -and -not $Claude) {
        $Copilot = $true
        $Codex = $true
    }

    if ($Copilot) {
        $TargetRoots += (Join-Path (Join-Path $HOME ".copilot") "skills")
    }
    if ($Codex) {
        $TargetRoots += (Join-Path (Join-Path $HOME ".codex") "skills")
    }
    if ($Claude) {
        $TargetRoots += (Join-Path (Join-Path $HOME ".claude") "skills")
    }
}

foreach ($TargetRoot in $TargetRoots) {
    $Target = Join-Path $TargetRoot $SkillName

    if ($Uninstall) {
        if (Test-Path $Target) {
            Remove-Item -Recurse -Force $Target
            Write-Output "Removed $Target"
        } else {
            Write-Output "Nothing to remove: $Target does not exist"
        }
    } else {
        $RefsDir = Join-Path $Target "references"
        $ScriptsDir = Join-Path $Target "scripts"
        New-Item -ItemType Directory -Force -Path $RefsDir | Out-Null
        New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
        Copy-Item (Join-Path $ScriptRoot "SKILL.md") -Destination $Target -Force
        Copy-Item (Join-Path (Join-Path $ScriptRoot "references") "*.md") -Destination $RefsDir -Force
        Copy-Item (Join-Path (Join-Path $ScriptRoot "scripts") "*") -Destination $ScriptsDir -Force
        Write-Output "Installed $SkillName to $Target"
    }
}

if (-not $Uninstall -and -not $SkillsDir -and $env:OS -eq "Windows_NT") {
    & (Join-Path $ScriptRoot "scripts\repair-windows-playwright-cli.ps1") -AllowMissing
}
