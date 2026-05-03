# Compiles TLS + traceroute C# snippets (same as YT-DPI.ps1 embedded types). Used by release-gate.ps1 in a fresh process.
param(
    [Parameter(Mandatory)][string]$TlsPath,
    [Parameter(Mandatory)][string]$TracePath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TlsPath)) { throw "TLS file missing: $TlsPath" }
if (-not (Test-Path -LiteralPath $TracePath)) { throw "Trace file missing: $TracePath" }
$tls = [System.IO.File]::ReadAllText($TlsPath, [System.Text.Encoding]::UTF8)
$tr = [System.IO.File]::ReadAllText($TracePath, [System.Text.Encoding]::UTF8)
Add-Type -TypeDefinition $tls -ErrorAction Stop
Add-Type -TypeDefinition $tr -ErrorAction Stop
$ed = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
Write-Host "release-gate-addtype: OK | PS $($PSVersionTable.PSVersion) $ed"
