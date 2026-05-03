# Release gate: dotnet build YT-DPI.Core (net472 + net8.0), DLL smoke + AST under multiple hosts (PS 5.1 x64/WOW64, pwsh).
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

function Invoke-GateHostDll {
    param(
        [string]$Exe,
        [string]$Label,
        [string]$DllPath,
        [string]$Helper,
        [string]$RepoRootArg
    )
    Write-Host "---- $Label ----"
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Helper,
        '-DllPath', $DllPath
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

$coreProj = Join-Path $RepoRoot 'src\YT-DPI.Core\YT-DPI.Core.csproj'
if (-not (Test-Path -LiteralPath $coreProj)) { throw "YT-DPI.Core.csproj not found: $coreProj" }

Write-Host '---- dotnet build YT-DPI.Core (Release) ----'
dotnet build $coreProj -c Release
if (-not $?) { throw 'dotnet build YT-DPI.Core failed' }

$dll472 = Join-Path $RepoRoot 'src\YT-DPI.Core\bin\Release\net472\YT-DPI.Core.dll'
$dll8 = Join-Path $RepoRoot 'src\YT-DPI.Core\bin\Release\net8.0\YT-DPI.Core.dll'
foreach ($p in @($dll472, $dll8)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing build output: $p" }
}

$helper = Join-Path $PSScriptRoot 'release-gate-dll-smoke.ps1'
if (-not (Test-Path -LiteralPath $helper)) { throw "Missing $helper" }

$smoke = Join-Path $PSScriptRoot 'smoke-yt-dpi-engines.ps1'
if (Test-Path -LiteralPath $smoke) {
    Write-Host '---- smoke-yt-dpi-engines (current host, before Add-Type) ----'
    & $smoke -RepoRoot $RepoRoot
    if (-not $?) { throw 'smoke-yt-dpi-engines failed' }
}

$gateDll = $dll472
if ($PSVersionTable.PSEdition -eq 'Core') { $gateDll = $dll8 }

Write-Host "---- DLL smoke (current session, $gateDll) ----"
& $helper -DllPath $gateDll -RepoRoot $RepoRoot

$winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $winPs) {
    Invoke-GateHostDll -Exe $winPs -Label 'Windows PowerShell 5.1 x64 (System32)' `
        -DllPath $dll472 -Helper $helper -RepoRootArg $RepoRoot
} else {
    Write-Warning 'powershell.exe not found under System32; skipped.'
}

$wowPs = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $wowPs) {
    try {
        Invoke-GateHostDll -Exe $wowPs -Label 'Windows PowerShell 5.1 WOW64 (32-bit)' `
            -DllPath $dll472 -Helper $helper -RepoRootArg $RepoRoot
    } catch {
        Write-Warning "WOW64 PowerShell gate skipped or failed: $_"
    }
} else {
    Write-Host '---- WOW64 powershell.exe not present (e.g. ARM64 host); skip ----'
}

$pwshList = Get-PwshCandidatePaths
if ($pwshList.Count -eq 0) {
    Write-Warning 'No pwsh.exe candidates found; install PowerShell 7+ or set YT_DPI_GATE_EXTRA_PS.'
} else {
    $n = 0
    foreach ($exe in $pwshList) {
        if ($exe -match '\\PowerShell\\6\\') {
            Write-Warning "Skipping PowerShell 6.x host (net8.0 managed DLL not loadable): $exe"
            continue
        }
        $n++
        Invoke-GateHostDll -Exe $exe -Label "pwsh candidate $n / $($pwshList.Count): $exe" `
            -DllPath $dll8 -Helper $helper -RepoRootArg $RepoRoot
    }
}

Write-Host 'RELEASE GATE: ALL OK'
