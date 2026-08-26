<#
.SYNOPSIS
    Validate a native playwright-cli installation and its agent-safe defaults.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$env:NO_UPDATE_NOTIFIER = "1"

$problems = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()

function Resolve-RequiredCommand {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        $script:problems.Add("$Name is not installed or is not on PATH.")
        return $null
    }
    return $command
}

$nodeCommand = Resolve-RequiredCommand -Name "node"
$null = Resolve-RequiredCommand -Name "npm"
$cliCommand = Resolve-RequiredCommand -Name "playwright-cli"

if ($nodeCommand) {
    $nodeVersion = (& $nodeCommand.Source --version).Trim()
    $nodeMajor = [int]($nodeVersion -replace '^v(\d+).*$', '$1')
    if ($nodeMajor -lt 20) {
        $problems.Add("Node.js $nodeVersion is too old; the current Playwright runtime requires Node.js 20 or newer.")
    } else {
        Write-Output "Node.js: $nodeVersion ($($nodeCommand.Source))"
    }
}

$isWsl = -not ($env:OS -eq "Windows_NT") -and (
    (Test-Path -LiteralPath "/proc/sys/fs/binfmt_misc/WSLInterop") -or
    ($env:WSL_DISTRO_NAME)
)
if ($cliCommand) {
    $cliPath = $cliCommand.Source
    if ($isWsl -and $cliPath -match '^/mnt/[a-z]/') {
        $problems.Add("WSL resolved the Windows playwright-cli shim at '$cliPath'. Install Node.js and @playwright/cli inside WSL and put that bin directory before /mnt paths.")
    } else {
        $cliVersion = (& $cliCommand.Source --version).Trim()
        if ($LASTEXITCODE -ne 0) {
            $problems.Add("playwright-cli --version failed with exit code $LASTEXITCODE.")
        } else {
            Write-Output "playwright-cli: $cliVersion ($cliPath)"
        }
    }
}

if ($env:NODE_TLS_REJECT_UNAUTHORIZED -eq "0") {
    $warnings.Add("NODE_TLS_REJECT_UNAUTHORIZED=0 disables TLS certificate verification. Configure the corporate CA instead.")
}

foreach ($warning in $warnings) {
    Write-Warning $warning
}
if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Error $problem -ErrorAction Continue
    }
    throw "playwright-cli doctor found $($problems.Count) blocking problem(s)."
}

Write-Output "playwright-cli environment checks passed."
