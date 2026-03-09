<#
.SYNOPSIS
    Install or uninstall the memory agent skill.

.DESCRIPTION
    Copies SKILL.md into the target skills directory.
    Defaults to ~/.copilot/skills if no path is provided.

.EXAMPLE
    .\install.ps1                              # install to default
    .\install.ps1 -SkillsDir C:\my\skills      # install to custom path
    .\install.ps1 -Uninstall                    # uninstall from default
#>
param(
    [string]$SkillsDir,
    [switch]$Uninstall,
    [switch]$Help
)

$SkillName = "memory"

function Show-Usage {
    Write-Host "Usage: .\install.ps1 [-Uninstall] [-SkillsDir <path>]"
    Write-Host ""
    Write-Host "  Install:    .\install.ps1                          # defaults to ~/.copilot/skills"
    Write-Host "  Install:    .\install.ps1 -SkillsDir C:\my\skills"
    Write-Host "  Uninstall:  .\install.ps1 -Uninstall"
    Write-Host ""
    Write-Host "Creates <skills-directory>\$SkillName\ with SKILL.md."
    exit 1
}

if ($Help) { Show-Usage }

if (-not $SkillsDir) {
    $SkillsDir = Join-Path $HOME ".copilot" "skills"
}

$Target = Join-Path $SkillsDir $SkillName
$ScriptRoot = $PSScriptRoot

if ($Uninstall) {
    if (Test-Path $Target) {
        Remove-Item -Recurse -Force $Target
        Write-Host "Removed $Target"
    } else {
        Write-Host "Nothing to remove: $Target does not exist"
    }
    exit 0
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item (Join-Path $ScriptRoot "SKILL.md") -Destination $Target -Force
Write-Host "Installed $SkillName to $Target"
