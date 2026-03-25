<#
.SYNOPSIS
    Install or uninstall the netlist-to-schematic agent skill.

.DESCRIPTION
    Copies SKILL.md and scripts/ into the target skills directory.
    Defaults to both ~/.copilot/skills and ~/.codex/skills if no path is
    provided.

.EXAMPLE
    .\install.ps1                               # install to default Copilot and Codex dirs
    .\install.ps1 -Copilot                      # install to Copilot only
    .\install.ps1 -Codex                        # install to Codex only
    .\install.ps1 -SkillsDir C:\my\skills       # install to custom path
    .\install.ps1 -Uninstall                    # uninstall from default dirs
#>
param(
    [string]$SkillsDir,
    [switch]$Copilot,
    [switch]$Codex,
    [switch]$All,
    [switch]$Uninstall,
    [switch]$Help
)

$SkillName = "netlist-to-schematic"

function Show-Usage {
    Write-Host "Usage: .\install.ps1 [-Uninstall] [-Copilot|-Codex|-All] [-SkillsDir <path>]"
    Write-Host ""
    Write-Host "  Install:    .\install.ps1                          # defaults to ~/.copilot/skills and ~/.codex/skills"
    Write-Host "  Install:    .\install.ps1 -Copilot"
    Write-Host "  Install:    .\install.ps1 -Codex"
    Write-Host "  Install:    .\install.ps1 -SkillsDir C:\my\skills"
    Write-Host "  Uninstall:  .\install.ps1 -Uninstall               # removes from both default user dirs"
    Write-Host ""
    Write-Host "Creates <skills-directory>\$SkillName\ with SKILL.md and scripts/."
    exit 1
}

if ($Help) { Show-Usage }

if ($SkillsDir -and ($Copilot -or $Codex -or $All)) {
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
    }

    if (-not $Copilot -and -not $Codex) {
        $Copilot = $true
        $Codex = $true
    }

    if ($Copilot) {
        $TargetRoots += (Join-Path (Join-Path $HOME ".copilot") "skills")
    }
    if ($Codex) {
        $TargetRoots += (Join-Path (Join-Path $HOME ".codex") "skills")
    }
}

foreach ($TargetRoot in $TargetRoots) {
    $Target = Join-Path $TargetRoot $SkillName

    if ($Uninstall) {
        if (Test-Path $Target) {
            Remove-Item -Recurse -Force $Target
            Write-Host "Removed $Target"
        } else {
            Write-Host "Nothing to remove: $Target does not exist"
        }
    } else {
        $ScriptsDir = Join-Path $Target "scripts"
        New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
        Copy-Item (Join-Path $ScriptRoot "SKILL.md") -Destination $Target -Force
        Copy-Item (Join-Path (Join-Path $ScriptRoot "scripts") "*.py") -Destination $ScriptsDir -Force
        Write-Host "Installed $SkillName to $Target"
    }
}
