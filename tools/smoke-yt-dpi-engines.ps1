# Smoke: AST parse YT-DPI.ps1 + patterns used by scan jobs list and NetInfo runspace (PS 5.1 / 7+).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ytDpi = Join-Path $root 'YT-DPI.ps1'
if (-not (Test-Path -LiteralPath $ytDpi)) {
    throw "YT-DPI.ps1 not found (tried $ytDpi)"
}

Write-Host "Host: $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"
Write-Host "File: $ytDpi"

$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ytDpi, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) {
    $errs | ForEach-Object { Write-Error $_.Message }
    exit 1
}
Write-Host 'AST parse: OK'

# List[object] + Add + foreach + indexer (scan worker list)
$jobs = [System.Collections.Generic.List[object]]::new()
[void]$jobs.Add([PSCustomObject]@{ N = 1 })
[void]$jobs.Add([PSCustomObject]@{ N = 2 })
$sum = 0
foreach ($j in $jobs) { $sum += $j.N }
if ($sum -ne 3) { throw "List foreach failed: sum=$sum" }
if ($jobs[1].N -ne 2) { throw "List indexer failed" }
Write-Host 'List job pattern: OK'

# Runspace BeginInvoke / EndInvoke (NetInfo background)
$rs = [runspacefactory]::CreateRunspace()
$rs.Open()
$ps = [powershell]::Create()
$ps.Runspace = $rs
$null = $ps.AddScript({
    param($x)
    return @{ Echo = $x }
}).AddArgument(42)
$h = $ps.BeginInvoke()
$deadline = [datetime]::UtcNow.AddSeconds(30)
while (-not $h.IsCompleted) {
    if ([datetime]::UtcNow -gt $deadline) { throw 'BeginInvoke timeout' }
    Start-Sleep -Milliseconds 30
}
$raw = $ps.EndInvoke($h)
try { $ps.Dispose() } catch {}
try { $rs.Close(); $rs.Dispose() } catch {}
$arr = @($raw)
$one = if ($arr.Count) { $arr[-1] } else { $null }
if ($one.Echo -ne 42) { throw "Runspace result wrong: $($one | ConvertTo-Json -Compress)" }
Write-Host 'Runspace async pattern: OK'

Write-Host 'SMOKE ALL OK'
