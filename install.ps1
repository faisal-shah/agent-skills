<#
.SYNOPSIS
    Install or uninstall agent skills.

.DESCRIPTION
    Iterates skills/*/install.ps1 and runs each with the provided arguments.
    Defaults to both ~/.copilot/skills and ~/.codex/skills if no path is
    provided.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Copilot

.EXAMPLE
    .\install.ps1 -Codex

.EXAMPLE
    .\install.ps1 -Claude

.EXAMPLE
    .\install.ps1 -Uninstall
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

function Show-Usage {
    Write-Output "Usage: .\install.ps1 [-Uninstall] [-Copilot|-Codex|-Claude|-All] [-SkillsDir <path>]"
    Write-Output ""
    Write-Output "  Install all:       .\install.ps1"
    Write-Output "  Copilot only:      .\install.ps1 -Copilot"
    Write-Output "  Codex only:        .\install.ps1 -Codex"
    Write-Output "  Claude Code only:  .\install.ps1 -Claude"
    Write-Output "  Custom skills dir: .\install.ps1 -SkillsDir C:\my\skills"
    Write-Output "  Uninstall all:     .\install.ps1 -Uninstall"
    Write-Output ""
    Write-Output "Installs skills: circuit-sim, commit, elmer-fem, expo-firebase-stack,"
    Write-Output "                 mermaid, memory, netlist-to-schematic, playwright-cli,"
    Write-Output "                 robust-doc, shellcheck, technical-report, uv"
    exit 1
}

if ($Help) { Show-Usage }

if ($SkillsDir -and ($Copilot -or $Codex -or $Claude -or $All)) {
    Write-Error "Use either -SkillsDir or agent switches, not both."
    exit 1
}

$ScriptRoot = $PSScriptRoot
$SawTargetFlag = $Copilot -or $Codex -or $Claude -or $All

$Passthru = @{}
if ($Uninstall)  { $Passthru["Uninstall"] = $true }
if ($SkillsDir)  { $Passthru["SkillsDir"] = $SkillsDir }
if ($Copilot)    { $Passthru["Copilot"] = $true }
if ($Codex)      { $Passthru["Codex"] = $true }
if ($Claude)     { $Passthru["Claude"] = $true }
if ($All)        { $Passthru["All"] = $true }

Get-ChildItem -Path (Join-Path $ScriptRoot "skills") -Directory | ForEach-Object {
    # A skill can opt OUT of the bulk install with a .no-default-install marker;
    # it is then installable only via its own skills/<name>/install.ps1. Used for
    # project-specific skills (e.g. sabeel-color-scheme).
    if (Test-Path (Join-Path $_.FullName ".no-default-install")) {
        return
    }
    $installer = Join-Path $_.FullName "install.ps1"
    if (Test-Path $installer) {
        & $installer @Passthru
        if (-not $?) {
            throw "Skill installer failed: $installer"
        }
    }
}

if (-not $SkillsDir -and -not $Uninstall) {
    $installCopilotInstr = $Copilot -or $All -or (-not $SawTargetFlag)
    $installCodexInstr   = $Codex   -or $All -or (-not $SawTargetFlag)
    # Never by default: ~/.claude/CLAUDE.md is hand-edited far more often than the
    # other two, so it is only written when -Claude or -All is asked for.
    $installClaudeInstr  = $Claude  -or $All

    if ($installCopilotInstr) {
        $copilotDir = Join-Path $HOME ".copilot"
        New-Item -ItemType Directory -Force -Path $copilotDir | Out-Null
        Copy-Item (Join-Path $ScriptRoot "copilot-instructions.md") `
                  (Join-Path $copilotDir "copilot-instructions.md") -Force
        Write-Output "Installed copilot-instructions.md to $copilotDir"
    }
    if ($installCodexInstr) {
        $codexDir = Join-Path $HOME ".codex"
        New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
        Copy-Item (Join-Path $ScriptRoot "codex-instructions.md") `
                  (Join-Path $codexDir "instructions.md") -Force
        Write-Output "Installed codex-instructions.md to $codexDir"
    }
    if ($installClaudeInstr) {
        $claudeDir = Join-Path $HOME ".claude"
        New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
        $claudeSource = Join-Path $ScriptRoot "claude-instructions.md"
        $claudeTarget = Join-Path $claudeDir "CLAUDE.md"
        if ((Test-Path $claudeTarget) -and
            (Get-FileHash $claudeTarget).Hash -ne (Get-FileHash $claudeSource).Hash) {
            Copy-Item $claudeTarget "$claudeTarget.bak" -Force
            Write-Output "Backed up existing $claudeTarget to $claudeTarget.bak"
        }
        Copy-Item $claudeSource $claudeTarget -Force
        Write-Output "Installed claude-instructions.md to $claudeTarget"
    }
}
