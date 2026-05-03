# Legacy: compiles TLS + traceroute C# from external text files via Add-Type (pre-DLL gate).
# Current release gate uses release-gate-dll-smoke.ps1 + YT-DPI.Core.dll; keep this script for manual checks.
param(
    [Parameter(Mandatory)][string]$TlsPath,
    [Parameter(Mandatory)][string]$TracePath,
    [string]$RepoRoot = $null
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TlsPath)) { throw "TLS file missing: $TlsPath" }
if (-not (Test-Path -LiteralPath $TracePath)) { throw "Trace file missing: $TracePath" }
$tls = [System.IO.File]::ReadAllText($TlsPath, [System.Text.Encoding]::UTF8)
$tr = [System.IO.File]::ReadAllText($TracePath, [System.Text.Encoding]::UTF8)
Add-Type -TypeDefinition $tls -ErrorAction Stop
Add-Type -TypeDefinition $tr -ErrorAction Stop
$ed = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
Write-Host "release-gate-addtype: Add-Type OK | PS $($PSVersionTable.PSVersion) $ed"

if ($RepoRoot) {
    $smoke = Join-Path $PSScriptRoot 'smoke-yt-dpi-engines.ps1'
    if (-not (Test-Path -LiteralPath $smoke)) { throw "Smoke script missing: $smoke" }
    Write-Host "release-gate-addtype: running smoke in same process..."
    & $smoke -RepoRoot $RepoRoot
    if (-not $?) { throw 'smoke-yt-dpi-engines failed after Add-Type' }
}

Write-Host "release-gate-addtype: ALL OK"
