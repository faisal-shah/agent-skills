<#
.SYNOPSIS
    Install or uninstall agent skills and profiles.

.DESCRIPTION
    Iterates skills/*/install.ps1 and runs each with the provided arguments.
    Defaults to both ~/.copilot/skills and ~/.codex/skills if no path is
    provided. Also installs the build123d profile unless -NoProfiles is used.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Copilot

.EXAMPLE
    .\install.ps1 -Codex

.EXAMPLE
    .\install.ps1 -Claude

.EXAMPLE
    .\install.ps1 -InstallPowerShellAliases

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
    [switch]$NoProfiles,
    [switch]$InstallPowerShellAliases,
    [switch]$SmokeTestBuild123d,
    [switch]$Help
)

function Show-Usage {
    Write-Output "Usage: .\install.ps1 [-Uninstall] [-Copilot|-Codex|-Claude|-All] [-SkillsDir <path>] [options]"
    Write-Output ""
    Write-Output "  Install all:       .\install.ps1"
    Write-Output "  Copilot only:      .\install.ps1 -Copilot"
    Write-Output "  Codex only:        .\install.ps1 -Codex"
    Write-Output "  Claude Code only:  .\install.ps1 -Claude"
    Write-Output "  Custom skills dir: .\install.ps1 -SkillsDir C:\my\skills"
    Write-Output "  Uninstall all:     .\install.ps1 -Uninstall"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -NoProfiles                 Skip build123d profile files"
    Write-Output "  -InstallPowerShellAliases    Install codex-build123d and copilot-build123d helpers"
    Write-Output "  -SmokeTestBuild123d          Run build123d-mcp --version through uv"
    Write-Output ""
    Write-Output "Installs skills: circuit-sim, commit, elmer-fem, expo-firebase-stack,"
    Write-Output "                 mermaid, memory, netlist-to-schematic, playwright-cli,"
    Write-Output "                 robust-doc, shellcheck, technical-report, uv"
    Write-Output "Installs profile: build123d"
    exit 1
}

function Test-CommandAvailable {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-AgentTarget {
    if ($Copilot -and -not $Codex -and -not $All) { return "copilot" }
    if ($Codex -and -not $Copilot -and -not $All) { return "codex" }
    return "all"
}

function Invoke-Build123dProfileInstaller {
    param([string]$Target)

    if (-not (Test-CommandAvailable "uv")) {
        throw "uv is required to install the build123d profile."
    }

    $installer = Join-Path $ScriptRoot "scripts\install_build123d_profile.py"
    $uvArgs = @("run", "--upgrade", "--python", "3.12", $installer, "--target", $Target)
    if ($Uninstall) {
        $uvArgs += "--uninstall"
    }

    & uv @uvArgs
    if ($LASTEXITCODE -ne 0) {
        throw "build123d profile installer failed."
    }
}

function Invoke-Build123dSmokeTest {
    if (-not (Test-CommandAvailable "uv")) {
        throw "uv is required to smoke-test build123d-mcp."
    }

    & uv tool run --python 3.12 --from "git+https://github.com/pzfreo/build123d-mcp@main" build123d-mcp --version
    if ($LASTEXITCODE -ne 0) {
        throw "build123d-mcp smoke test failed."
    }
}

function Install-PowerShellLaunchHelper {
    $source = Join-Path $ScriptRoot "profiles\build123d\aliases\agent-modes.ps1"
    $targetDir = Join-Path (Join-Path $HOME ".codex") "powershell"
    $target = Join-Path $targetDir "agent-modes.ps1"

    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item $source $target -Force

    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not $profilePath) { $profilePath = $PROFILE }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null

    $escapedTarget = $target.Replace("'", "''")
    $start = "# >>> agent-skills build123d aliases >>>"
    $end = "# <<< agent-skills build123d aliases <<<"
    $block = @"
$start
. '$escapedTarget'
$end
"@

    $content = ""
    if (Test-Path $profilePath) {
        $content = Get-Content -Raw $profilePath
    }

    $pattern = "(?ms)^# >>> agent-skills build123d aliases >>>.*?^# <<< agent-skills build123d aliases <<<\r?\n?"
    if ($content -match $pattern) {
        $content = [regex]::Replace($content, $pattern, $block + [Environment]::NewLine)
    } else {
        if ($content -and -not $content.EndsWith([Environment]::NewLine)) {
            $content += [Environment]::NewLine
        }
        $content += $block + [Environment]::NewLine
    }

    Set-Content -Path $profilePath -Value $content -Encoding UTF8
    Write-Output "Installed PowerShell launch helpers to $target"
    Write-Output "Updated PowerShell profile $profilePath"
}

function Uninstall-PowerShellLaunchHelper {
    $target = Join-Path (Join-Path (Join-Path $HOME ".codex") "powershell") "agent-modes.ps1"
    if (Test-Path $target) {
        Remove-Item -Force $target
        Write-Output "Removed PowerShell launch helpers from $target"
    }

    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not $profilePath) { $profilePath = $PROFILE }
    if (Test-Path $profilePath) {
        $content = Get-Content -Raw $profilePath
        $pattern = "(?ms)^# >>> agent-skills build123d aliases >>>.*?^# <<< agent-skills build123d aliases <<<\r?\n?"
        $newContent = [regex]::Replace($content, $pattern, "")
        if ($newContent -ne $content) {
            Set-Content -Path $profilePath -Value $newContent -Encoding UTF8
            Write-Output "Removed build123d alias block from $profilePath"
        }
    }
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

# The build123d profile installer has no Claude target; skip it for -Claude alone.
if (-not $SkillsDir -and -not $NoProfiles -and
    ((-not $SawTargetFlag) -or $Copilot -or $Codex -or $All)) {
    Invoke-Build123dProfileInstaller -Target (Get-AgentTarget)
}

if (-not $SkillsDir -and $InstallPowerShellAliases) {
    if ($Uninstall) {
        Uninstall-PowerShellLaunchHelper
    } else {
        Install-PowerShellLaunchHelper
    }
}

if (-not $SkillsDir -and $SmokeTestBuild123d -and -not $Uninstall) {
    Invoke-Build123dSmokeTest
}
