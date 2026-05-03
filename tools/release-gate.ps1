# Release gate: extract $tlsCode / $traceCode from YT-DPI.ps1 and compile under Windows PowerShell 5.1 and pwsh (if present).
param(
    [string]$RepoRoot = (Split-Path -LiteralPath $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'

function Get-YtDpiHereStringContent {
    param(
        [string[]]$Lines,
        [string]$StartLineExact
    )
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -eq $StartLineExact) {
            $sb = New-Object System.Text.StringBuilder
            for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j] -eq '"@') {
                    return $sb.ToString()
                }
                [void]$sb.AppendLine($Lines[$j])
            }
            throw "Here-string starting at line $($i+1) ($StartLineExact) not closed with ""@."
        }
    }
    throw "Marker not found: $StartLineExact"
}

$ytDpi = Join-Path $RepoRoot 'YT-DPI.ps1'
if (-not (Test-Path -LiteralPath $ytDpi)) { throw "YT-DPI.ps1 not found: $ytDpi" }

$lines = Get-Content -LiteralPath $ytDpi
$tlsCode = Get-YtDpiHereStringContent -Lines $lines -StartLineExact '$tlsCode = @"'
$traceCode = Get-YtDpiHereStringContent -Lines $lines -StartLineExact '$traceCode = @"'

$dir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'yt-dpi-release-gate')
$null = New-Item -ItemType Directory -Path $dir -Force
$tlsFile = Join-Path $dir 'tls_gate.cs.txt'
$traceFile = Join-Path $dir 'trace_gate.cs.txt'
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tlsFile, $tlsCode, $utf8)
[System.IO.File]::WriteAllText($traceFile, $traceCode, $utf8)

$helper = Join-Path $PSScriptRoot 'release-gate-addtype.ps1'
if (-not (Test-Path -LiteralPath $helper)) { throw "Missing $helper" }

function Invoke-GateHost {
    param([string]$Exe, [string]$Label)
    Write-Host "---- $Label ----"
    $p = Start-Process -FilePath $Exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $helper,
        '-TlsPath', $tlsFile, '-TracePath', $traceFile
    ) -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "$Label failed (exit $($p.ExitCode))" }
}

# AST + patterns (existing smoke)
$smoke = Join-Path $PSScriptRoot 'smoke-yt-dpi-engines.ps1'
if (Test-Path -LiteralPath $smoke) {
    Write-Host "---- smoke-yt-dpi-engines (current host) ----"
    & $smoke
    if (-not $?) { throw "smoke-yt-dpi-engines failed" }
}

# Same-process compile (catches regressions when gate is run in a clean shell)
Write-Host "---- Add-Type current session ----"
& $helper -TlsPath $tlsFile -TracePath $traceFile

$winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $winPs) {
    Invoke-GateHost -Exe $winPs -Label 'Windows PowerShell 5.1 (System32)'
}
else {
    Write-Warning 'powershell.exe not found under System32; skipped.'
}

$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($pwshCmd) {
    Invoke-GateHost -Exe $pwshCmd.Source -Label 'PowerShell Core (pwsh)'
}
else {
    Write-Warning 'pwsh not in PATH; skipped (install PowerShell 7+ for full gate).'
}

Write-Host 'RELEASE GATE: ALL OK'
