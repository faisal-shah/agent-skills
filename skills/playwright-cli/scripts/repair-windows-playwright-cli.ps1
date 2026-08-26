<#
.SYNOPSIS
    Prevent @playwright/cli from opening transient console windows on Windows.

.DESCRIPTION
    Applies narrowly scoped compatibility fixes to the globally installed
    @playwright/cli package:

    1. Disable the update notifier on Node.js 24+, avoiding a known Windows
       libuv assertion while preserving update checks on supported runtimes.
    2. Hide the detached Node daemon and browser process windows.
    3. Run taskkill.exe directly and hidden instead of through cmd.exe.

    The script is idempotent and fails before writing when the installed
    package layout or expected source patterns are unknown. Re-run it after an
    npm upgrade until the upstream package includes equivalent behavior.

.PARAMETER Check
    Verify that the installed CLI is already repaired without changing files.

.PARAMETER AllowMissing
    Return successfully when npm or @playwright/cli is not installed. Intended
    for the skill installer.

.PARAMETER NpmRoot
    Override the global npm package directory. Intended for isolated testing.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$AllowMissing,
    [string]$NpmRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    Write-Output "No playwright-cli console repair is needed on this platform."
    return
}

if (-not $NpmRoot) {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCommand) {
        if ($AllowMissing) {
            Write-Output "npm is not installed; skipped the optional playwright-cli repair."
            return
        }
        throw "npm is required to locate the global @playwright/cli installation."
    }

    $npmOutput = @(& $npmCommand.Source root --global)
    if ($LASTEXITCODE -ne 0 -or $npmOutput.Count -eq 0) {
        throw "Unable to resolve the global npm package directory."
    }
    $NpmRoot = $npmOutput[-1].Trim()
}

$packageRoot = Join-Path $NpmRoot "@playwright\cli"
$packageJsonPath = Join-Path $packageRoot "package.json"
if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
    if ($AllowMissing) {
        Write-Output "@playwright/cli is not installed globally; skipped the optional Windows repair."
        return
    }
    throw "Global @playwright/cli package not found under '$NpmRoot'."
}

$package = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
$playwrightCoreRoots = @(
    (Join-Path $packageRoot "node_modules\playwright-core"),
    (Join-Path $NpmRoot "playwright-core")
)
$playwrightCoreRoot = $playwrightCoreRoots |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1
if (-not $playwrightCoreRoot) {
    throw "Unable to locate playwright-core for @playwright/cli $($package.version)."
}

$sessionPath = Join-Path $playwrightCoreRoot "lib\tools\cli-client\session.js"
$coreBundlePath = Join-Path $playwrightCoreRoot "lib\coreBundle.js"
$cliPath = Join-Path $packageRoot "playwright-cli.js"
foreach ($path in @($cliPath, $sessionPath, $coreBundlePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Unsupported @playwright/cli $($package.version) layout: missing '$path'."
    }
}

$cli = [IO.File]::ReadAllText($cliPath)
$session = [IO.File]::ReadAllText($sessionPath)
$coreBundle = [IO.File]::ReadAllText($coreBundlePath)

$notifierFix = "if (process.platform === 'win32' && Number(process.versions.node.split('.')[0]) >= 24)`n  process.env.NO_UPDATE_NOTIFIER ??= '1';"
$notifierAnchor = '// @ts-check'
$sessionFixedPattern = 'detached:\s*true,\r?\n\s*windowsHide:\s*true,\r?\n\s*stdio:'
$sessionOldPattern = '(?<indent>[ \t]*)detached:\s*true,\r?\n(?<next>[ \t]*)stdio:'
$browserFixedPattern = 'detached:\s*process\.platform\s*!==\s*"win32",\r?\n\s*windowsHide:\s*true,\r?\n\s*env:'
$browserOldPattern = '(?<indent>[ \t]*)detached:\s*process\.platform\s*!==\s*"win32",\r?\n(?<next>[ \t]*)env:'
$taskkillOld = '          const taskkillProcess = childProcess.spawnSync(`taskkill /pid ${spawnedProcess.pid} /T /F`, { shell: true });'
$taskkillNew = '          const taskkillProcess = childProcess.spawnSync("taskkill.exe", ["/pid", String(spawnedProcess.pid), "/T", "/F"], { windowsHide: true });'

$needsNotifierFix = -not $cli.Contains($notifierFix)
$needsSessionFix = -not [regex]::IsMatch($session, $sessionFixedPattern)
$needsBrowserFix = -not [regex]::IsMatch($coreBundle, $browserFixedPattern)
$needsTaskkillFix = -not $coreBundle.Contains($taskkillNew)

if ($Check) {
    if ($needsNotifierFix -or $needsSessionFix -or $needsBrowserFix -or $needsTaskkillFix) {
        throw "@playwright/cli $($package.version) still needs the Windows no-popup repair."
    }
    Write-Output "@playwright/cli $($package.version) Windows no-popup repair is installed."
    return
}

if (-not $needsNotifierFix -and -not $needsSessionFix -and -not $needsBrowserFix -and -not $needsTaskkillFix) {
    Write-Output "@playwright/cli $($package.version) Windows no-popup repair is already installed."
    return
}

if ($needsNotifierFix) {
    $patternMatches = [regex]::Matches($cli, [regex]::Escape($notifierAnchor))
    if ($patternMatches.Count -ne 1) {
        throw "Unsupported CLI entry point in @playwright/cli $($package.version); expected one notifier repair target, found $($patternMatches.Count)."
    }
    $cli = $cli.Replace($notifierAnchor, "$notifierAnchor`n`n$notifierFix")
}

if ($needsSessionFix) {
    $patternMatches = [regex]::Matches($session, $sessionOldPattern)
    if ($patternMatches.Count -ne 1) {
        throw "Unsupported daemon launcher in @playwright/cli $($package.version); expected one repair target, found $($patternMatches.Count)."
    }
    $session = [regex]::Replace(
        $session,
        $sessionOldPattern,
        { param($match) "$($match.Groups['indent'].Value)detached: true,`n$($match.Groups['indent'].Value)windowsHide: true,`n$($match.Groups['next'].Value)stdio:" },
        1
    )
}

if ($needsBrowserFix) {
    $patternMatches = [regex]::Matches($coreBundle, $browserOldPattern)
    if ($patternMatches.Count -ne 1) {
        throw "Unsupported browser launcher in @playwright/cli $($package.version); expected one repair target, found $($patternMatches.Count)."
    }
    $coreBundle = [regex]::Replace(
        $coreBundle,
        $browserOldPattern,
        { param($match) "$($match.Groups['indent'].Value)detached: process.platform !== `"win32`",`n$($match.Groups['indent'].Value)windowsHide: true,`n$($match.Groups['next'].Value)env:" },
        1
    )
}

if ($needsTaskkillFix) {
    $patternMatches = [regex]::Matches($coreBundle, [regex]::Escape($taskkillOld))
    if ($patternMatches.Count -ne 1) {
        throw "Unsupported browser shutdown path in @playwright/cli $($package.version); expected one repair target, found $($patternMatches.Count)."
    }
    $coreBundle = $coreBundle.Replace($taskkillOld, $taskkillNew)
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)
if ($needsNotifierFix) {
    [IO.File]::WriteAllText($cliPath, $cli, $utf8NoBom)
}
if ($needsSessionFix) {
    [IO.File]::WriteAllText($sessionPath, $session, $utf8NoBom)
}
if ($needsBrowserFix -or $needsTaskkillFix) {
    [IO.File]::WriteAllText($coreBundlePath, $coreBundle, $utf8NoBom)
}

& $PSCommandPath -Check -NpmRoot $NpmRoot
Write-Output "Repaired @playwright/cli $($package.version) for hidden Windows process launches."
