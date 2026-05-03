# Copies YT-DPI.ps1, YT-DPI.bat, and both Core TFMs into artifacts/yt-dpi-core-ps for release-style layout.
param(
    [string]$RepoRoot = (Split-Path -LiteralPath $PSScriptRoot -Parent),
    [string]$Configuration = 'Release'
)
$ErrorActionPreference = 'Stop'
$core = Join-Path $RepoRoot 'src\YT-DPI.Core\YT-DPI.Core.csproj'
if (-not (Test-Path -LiteralPath $core)) { throw "Missing $core" }

Write-Host "dotnet build $core -c $Configuration"
dotnet build $core -c $Configuration
if (-not $?) { throw 'dotnet build failed' }

$outRoot = Join-Path $RepoRoot 'artifacts\yt-dpi-core-ps'
$null = New-Item -ItemType Directory -Path $outRoot -Force

$tfms = @('net472', 'net8.0')
foreach ($tf in $tfms) {
    $srcDll = Join-Path $RepoRoot "src\YT-DPI.Core\bin\$Configuration\$tf\YT-DPI.Core.dll"
    if (-not (Test-Path -LiteralPath $srcDll)) { throw "Missing build output: $srcDll" }
    $destDir = Join-Path $outRoot (Join-Path 'lib' $tf)
    $null = New-Item -ItemType Directory -Path $destDir -Force
    Copy-Item -LiteralPath $srcDll -Destination (Join-Path $destDir 'YT-DPI.Core.dll') -Force
}

foreach ($f in @('YT-DPI.ps1', 'YT-DPI.bat')) {
    $p = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing $p" }
    Copy-Item -LiteralPath $p -Destination (Join-Path $outRoot $f) -Force
}

Write-Host "Bundle ready: $outRoot (lib\net472, lib\net8.0 + scripts)"
