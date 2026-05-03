# Release gate: extract $tlsCode / $traceCode from YT-DPI.ps1; compile + smoke under multiple hosts (PS 5.1 x64/WOW64, pwsh).
param(
    [string]$RepoRoot = (Split-Path -LiteralPath $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'

function Write-GateHostContext {
    param([string]$Label)
    Write-Host "======== $Label ========"
    try {
        $os = [System.Environment]::OSVersion.VersionString
        $ver = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($ver) { Write-Host "OS: $ver" }
        Write-Host "OSVersion: $os"
    } catch {
        Write-Host "OSVersion: (unavailable)"
    }
    $ed = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
    Write-Host "PSVersion: $($PSVersionTable.PSVersion) | PSEdition: $ed | PID: $PID"
    try {
        $clr = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        Write-Host "Runtime: $clr"
    } catch {
        try {
            Write-Host "CLR: $([System.Environment]::Version)"
        } catch { }
    }
    Write-Host "RepoRoot: $RepoRoot"
    Write-Host "========================"
}

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

function Get-PwshCandidatePaths {
    $seen = @{}
    $list = New-Object System.Collections.Generic.List[string]

    function Add-Exe([string]$p) {
        if (-not $p) { return }
        try { $full = [System.IO.Path]::GetFullPath($p) } catch { return }
        if (-not (Test-Path -LiteralPath $full)) { return }
        $key = $full.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        [void]$seen.Add($key, $true)
        [void]$list.Add($full)
    }

    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { Add-Exe $cmd.Source }

    $pf86 = ${env:ProgramFiles(x86)}
    foreach ($base in @($env:ProgramFiles, $pf86)) {
        if (-not $base) { continue }
        $pwRoot = Join-Path $base 'PowerShell'
        if (-not (Test-Path -LiteralPath $pwRoot)) { continue }
        Get-ChildItem -LiteralPath $pwRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Add-Exe (Join-Path $_.FullName 'pwsh.exe')
        }
    }

    Add-Exe (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    Add-Exe (Join-Path $env:ProgramFiles 'PowerShell\7-preview\pwsh.exe')
    if ($pf86) {
        Add-Exe (Join-Path $pf86 'PowerShell\7\pwsh.exe')
    }

    $extra = [System.Environment]::GetEnvironmentVariable('YT_DPI_GATE_EXTRA_PS', 'Process')
    if (-not $extra) { $extra = [System.Environment]::GetEnvironmentVariable('YT_DPI_GATE_EXTRA_PS', 'User') }
    if (-not $extra) { $extra = [System.Environment]::GetEnvironmentVariable('YT_DPI_GATE_EXTRA_PS', 'Machine') }
    if ($extra) {
        foreach ($part in $extra -split '[;|]', [System.StringSplitOptions]::RemoveEmptyEntries) {
            Add-Exe $part.Trim()
        }
    }

    return ,$list.ToArray()
}

function Invoke-GateHost {
    param(
        [string]$Exe,
        [string]$Label,
        [string]$TlsFile,
        [string]$TraceFile,
        [string]$Helper,
        [string]$RepoRootArg
    )
    Write-Host "---- $Label ----"
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Helper,
        '-TlsPath', $TlsFile, '-TracePath', $TraceFile
    )
    if ($RepoRootArg) {
        $args += @('-RepoRoot', $RepoRootArg)
    }
    $p = Start-Process -FilePath $Exe -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "$Label failed (exit $($p.ExitCode))" }
}

Write-GateHostContext 'release-gate (orchestrator)'

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

# AST + patterns on current host (before any Add-Type in this session)
$smoke = Join-Path $PSScriptRoot 'smoke-yt-dpi-engines.ps1'
if (Test-Path -LiteralPath $smoke) {
    Write-Host "---- smoke-yt-dpi-engines (current host, before Add-Type) ----"
    & $smoke -RepoRoot $RepoRoot
    if (-not $?) { throw "smoke-yt-dpi-engines failed" }
}

# Same process: Add-Type + smoke (same parser/runtime as orchestrator)
Write-Host "---- Add-Type + smoke (current session) ----"
& $helper -TlsPath $tlsFile -TracePath $traceFile -RepoRoot $RepoRoot

$winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $winPs) {
    Invoke-GateHost -Exe $winPs -Label 'Windows PowerShell 5.1 x64 (System32)' `
        -TlsFile $tlsFile -TraceFile $traceFile -Helper $helper -RepoRootArg $RepoRoot
} else {
    Write-Warning 'powershell.exe not found under System32; skipped.'
}

$wowPs = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $wowPs) {
    try {
        Invoke-GateHost -Exe $wowPs -Label 'Windows PowerShell 5.1 WOW64 (32-bit)' `
            -TlsFile $tlsFile -TraceFile $traceFile -Helper $helper -RepoRootArg $RepoRoot
    } catch {
        Write-Warning "WOW64 PowerShell gate skipped or failed: $_"
    }
} else {
    Write-Host "---- WOW64 powershell.exe not present (e.g. ARM64 host); skip ----"
}

$pwshList = Get-PwshCandidatePaths
if ($pwshList.Count -eq 0) {
    Write-Warning 'No pwsh.exe candidates found; install PowerShell 7+ or set YT_DPI_GATE_EXTRA_PS.'
} else {
    $n = 0
    foreach ($exe in $pwshList) {
        $n++
        Invoke-GateHost -Exe $exe -Label "pwsh candidate $n / $($pwshList.Count): $exe" `
            -TlsFile $tlsFile -TraceFile $traceFile -Helper $helper -RepoRootArg $RepoRoot
    }
}

Write-Host 'RELEASE GATE: ALL OK'
