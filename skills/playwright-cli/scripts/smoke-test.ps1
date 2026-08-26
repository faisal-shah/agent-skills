<#
.SYNOPSIS
    Exercise a complete playwright-cli browser lifecycle without network I/O.
#>
[CmdletBinding()]
param(
    [string]$Browser = $(if ($env:OS -eq "Windows_NT") { "msedge" } else { "chromium" })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$env:NO_UPDATE_NOTIFIER = "1"

if (-not (Get-Command playwright-cli -ErrorAction SilentlyContinue)) {
    throw "playwright-cli is not installed or is not on PATH."
}

if ($env:OS -eq "Windows_NT") {
    & (Join-Path $PSScriptRoot "repair-windows-playwright-cli.ps1")
}

$sessionName = "skill-smoke-$PID"
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempDirectory = [IO.Path]::GetFullPath((Join-Path $tempBase "playwright-cli-$([guid]::NewGuid().ToString('N'))"))
if (-not $tempDirectory.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create a smoke-test directory outside the system temporary directory."
}

New-Item -ItemType Directory -Path $tempDirectory | Out-Null
Push-Location $tempDirectory
try {
    & playwright-cli "-s=$sessionName" open about:blank "--browser=$Browser"
    if ($LASTEXITCODE -ne 0) { throw "playwright-cli open failed." }

    & playwright-cli "-s=$sessionName" run-code "async page => { await page.setContent('<!doctype html><title>playwright-cli smoke test</title><h1>ready</h1>'); }"
    if ($LASTEXITCODE -ne 0) { throw "playwright-cli run-code failed." }

    $titleMatches = & playwright-cli --raw "-s=$sessionName" eval "document.title === 'playwright-cli smoke test'"
    if ($LASTEXITCODE -ne 0 -or $titleMatches.Trim() -ne "true") {
        throw "playwright-cli returned an unexpected title comparison: '$titleMatches'."
    }

    $screenshot = Join-Path $tempDirectory "smoke.png"
    & playwright-cli "-s=$sessionName" screenshot "--filename=$screenshot"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $screenshot) -or (Get-Item -LiteralPath $screenshot).Length -eq 0) {
        throw "playwright-cli did not create a non-empty screenshot."
    }
} finally {
    & playwright-cli "-s=$sessionName" close 2>$null
    Pop-Location
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

Write-Output "playwright-cli browser lifecycle smoke test passed with $Browser."
