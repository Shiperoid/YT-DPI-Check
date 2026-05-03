# Loads YT-DPI.Core.dll and smoke-calls TLS + traceroute entrypoints (replaces Add-Type of inline C#).
param(
    [Parameter(Mandatory)][string]$DllPath,
    [string]$RepoRoot = $null
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DllPath)) { throw "DLL missing: $DllPath" }

Add-Type -Path $DllPath -ErrorAction Stop
$ed = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
Write-Host "release-gate-dll-smoke: Add-Type OK | PS $($PSVersionTable.PSVersion) $ed | $DllPath"

$r = [YtDpi.TlsScanner]::TestT13('127.0.0.1', 'localhost', '', 0, '', '', 800)
Write-Host "release-gate-dll-smoke: TlsScanner.TestT13 -> $r"

$hops = [YtDpi.AdvancedTraceroute]::Trace('127.0.0.1', 4, 600, [YtDpi.TraceMethod]::Udp, $null)
$c = if ($null -eq $hops) { 0 } else { @($hops).Count }
Write-Host "release-gate-dll-smoke: AdvancedTraceroute.Trace hop count -> $c"

$hp = [YtDpi.HttpPortProbe]::QuickDirect('127.0.0.1', 79, 200)
Write-Host "release-gate-dll-smoke: HttpPortProbe.QuickDirect Ok=$($hp.Ok) LatMs=$($hp.LatencyMs)"

$h12 = [YtDpi.Tls12Scripting]::HandshakeDirectDetailed('127.0.0.1', 443, 'localhost', 500)
Write-Host "release-gate-dll-smoke: Tls12Scripting.HandshakeDirectDetailed -> $($h12.Cell) timedOut=$($h12.HandshakeTimedOut)"

try {
    [void][YtDpi.TcpTimeouts]::ConnectToIpPort('127.0.0.1', 65321, 200)
    Write-Host 'release-gate-dll-smoke: TcpTimeouts.ConnectToIpPort unexpectedly succeeded'
    exit 2
} catch {
    Write-Host "release-gate-dll-smoke: TcpTimeouts.ConnectToIpPort threw (expected): $($_.Exception.GetType().Name)"
}

if ($RepoRoot) {
    $smoke = Join-Path $PSScriptRoot 'smoke-yt-dpi-engines.ps1'
    if (-not (Test-Path -LiteralPath $smoke)) { throw "Smoke script missing: $smoke" }
    Write-Host 'release-gate-dll-smoke: running smoke-yt-dpi-engines...'
    & $smoke -RepoRoot $RepoRoot
    if (-not $?) { throw 'smoke-yt-dpi-engines failed' }
}

Write-Host 'release-gate-dll-smoke: ALL OK'
