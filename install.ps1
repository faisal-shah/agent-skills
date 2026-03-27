<#
.SYNOPSIS
    Install or uninstall all agent skills.

.DESCRIPTION
    Iterates skills/*/install.ps1 and runs each with the provided arguments.
    Defaults to both ~/.copilot/skills and ~/.codex/skills if no path is
    provided.

.EXAMPLE
    .\install.ps1                               # install all to default Copilot and Codex dirs
    .\install.ps1 -Copilot                      # install all to Copilot only
    .\install.ps1 -Codex                        # install all to Codex only
    .\install.ps1 -SkillsDir C:\my\skills       # install all to custom path
    .\install.ps1 -Uninstall                    # uninstall all from default dirs
#>
param(
    [string]$SkillsDir,
    [switch]$Copilot,
    [switch]$Codex,
    [switch]$All,
    [switch]$Uninstall,
    [switch]$Help
)

function Show-Usage {
    Write-Host "Usage: .\install.ps1 [-Uninstall] [-Copilot|-Codex|-All] [-SkillsDir <path>]"
    Write-Host ""
    Write-Host "  Install all:    .\install.ps1                          # defaults to ~/.copilot/skills and ~/.codex/skills"
    Write-Host "  Copilot only:   .\install.ps1 -Copilot"
    Write-Host "  Codex only:     .\install.ps1 -Codex"
    Write-Host "  Custom dir:     .\install.ps1 -SkillsDir C:\my\skills"
    Write-Host "  Uninstall all:  .\install.ps1 -Uninstall"
    Write-Host ""
    Write-Host "Installs: circuit-sim, elmer-fem, netlist-to-schematic, technical-report, memory"
    exit 1
}

if ($Help) { Show-Usage }

# Build pass-through arguments as a hashtable for proper splatting
$Passthru = @{}
if ($Uninstall)  { $Passthru["Uninstall"] = $true }
if ($SkillsDir)  { $Passthru["SkillsDir"] = $SkillsDir }
if ($Copilot)    { $Passthru["Copilot"] = $true }
if ($Codex)      { $Passthru["Codex"] = $true }
if ($All)        { $Passthru["All"] = $true }

$ScriptRoot = $PSScriptRoot

Get-ChildItem -Path (Join-Path $ScriptRoot "skills") -Directory | ForEach-Object {
    $installer = Join-Path $_.FullName "install.ps1"
    if (Test-Path $installer) {
        & $installer @Passthru
    }
}

# Install user-level instructions files (unless using --SkillsDir or --Uninstall)
if (-not $SkillsDir -and -not $Uninstall) {
    $installCopilotInstr = $Copilot -or $All -or (-not $Copilot -and -not $Codex)
    $installCodexInstr   = $Codex   -or $All -or (-not $Copilot -and -not $Codex)

    if ($installCopilotInstr) {
        $copilotDir = Join-Path $HOME ".copilot"
        New-Item -ItemType Directory -Force -Path $copilotDir | Out-Null
        Copy-Item (Join-Path $ScriptRoot "copilot-instructions.md") `
                  (Join-Path $copilotDir "copilot-instructions.md") -Force
        Write-Host "Installed copilot-instructions.md to $copilotDir"
    }
    if ($installCodexInstr) {
        $codexDir = Join-Path $HOME ".codex"
        New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
        Copy-Item (Join-Path $ScriptRoot "codex-instructions.md") `
                  (Join-Path $codexDir "instructions.md") -Force
        Write-Host "Installed codex-instructions.md to $codexDir"
    }
}
