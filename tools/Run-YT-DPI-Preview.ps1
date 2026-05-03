# Run Terminal.Gui preview (YT-DPI.App). Requires .NET 10 SDK.
param(
    [string]$RepoRoot = $null,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$proj = Join-Path $RepoRoot 'src\YT-DPI.App\YT-DPI.App.csproj'
if (-not (Test-Path -LiteralPath $proj)) {
    throw "Project not found: $proj (check RepoRoot)"
}
Write-Host "dotnet run -c $Configuration --project $proj"
dotnet run -c $Configuration --project $proj @args
