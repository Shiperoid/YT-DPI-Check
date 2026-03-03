# --- Environment Setup ---
$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# TLS Protocol Setup
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12 -bor 12288
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
}

# Helper: Truncate strings to keep table aligned
function Format-WideString {
    param([string]$str, [int]$len)
    if ($str.Length -gt $len) { return $str.Substring(0, $len - 3) + "..." }
    return $str
}

function Get-LocalCDN {
    $cdnHost = "redirector.googlevideo.com"
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($cdnHost)
        return [System.Net.Dns]::GetHostEntry($addresses[0]).HostName
    } catch { return "rr1---sn-uxax-5u6e.googlevideo.com" }
}

function Test-NetworkDPI {
    param([string]$Target, [int]$MaxRetries = 2)
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($Target)
        $targetIP = $ips[0].IPAddressToString
    } catch {
        return @{ Domain=$Target; IP="DNS FAIL"; TCP="--"; TLS="--"; UDP="--"; Latency=0; Verdict="DNS ERROR" }
    }

    $res = @{ Domain=$Target; IP=$targetIP; TCP="FL"; TLS="FL"; UDP="??"; Latency=0; Verdict="UNKNOWN" }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ssl = $null
        try {
            $ar = $tcp.BeginConnect($targetIP, 443, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(2500)) {
                $tcp.EndConnect($ar)
                $res.TCP = "OK"
                if ($res.Latency -eq 0) { $res.Latency = $sw.ElapsedMilliseconds }

                $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
                $arSsl = $ssl.BeginAuthenticateAsClient($Target, $null, $GlobalProtocol, $false, $null, $null)
                if ($arSsl.AsyncWaitHandle.WaitOne(2500)) {
                    $ssl.EndAuthenticateAsClient($arSsl)
                    $res.TLS = "OK"; $res.Verdict = "AVAILABLE"; $res.UDP = "OK"
                    return $res
                } else {
                    $res.TLS = "DR"; $res.Verdict = "DPI BLOCK"
                }
            } else { $res.Verdict = "IP BLOCK"; break }
        } catch { $res.Verdict = "ERR" }
        finally { if ($ssl){$ssl.Close()}; if ($tcp){$tcp.Close()} }
        if ($attempt -lt $MaxRetries) { Start-Sleep -Milliseconds 400 }
    }
    return $res
}

# --- Execution ---
Clear-Host
Write-Host ">>> YT-DPI check v0.6 <<<" -ForegroundColor White
$localCDN = Get-LocalCDN
Write-Host "CDN: $localCDN" -ForegroundColor Cyan
Write-Host ("=" * 79)

$header = "{0,-25} {1,-15} {2,-4} {3,-4} {4,-4} {5,-6} {6}"
Write-Host ($header -f "DOMAIN", "IP", "TCP", "TLS", "UDP", "LAT", "RESULT")
Write-Host ("-" * 79)

$targets = @("google.com", "www.youtube.com", "i.ytimg.com", "yt3.ggpht.com", "manifest.googlevideo.com", $localCDN)
$allResults = @() # Storage for final summary (to avoid re-testing)

foreach ($t in $targets) {
    $report = Test-NetworkDPI $t
    $allResults += $report
    
    $color = "Red"
    if ($report.Verdict -eq "AVAILABLE") { $color = "Green" }
    elseif ($report.Verdict -match "DPI") { $color = "Yellow" }
    
    $dispDomain = Format-WideString $report.Domain 25
    $dispIP     = Format-WideString $report.IP 15
    $dispLat    = if ($report.Latency -gt 0) { "$($report.Latency)ms" } else { "---" }

    Write-Host ($header -f $dispDomain, $dispIP, $report.TCP, $report.TLS, $report.UDP, $dispLat, $report.Verdict) -ForegroundColor $color
}

# --- Legend & Instant Summary ---
Write-Host ("=" * 79)
Write-Host " STATUS LEGEND" -ForegroundColor Cyan
Write-Host ("-" * 79)

# Используем -NoNewline, чтобы раскрасить только ключи (OK, FL, DR...)
Write-Host "  [TCP/TLS]  " -NoNewline -ForegroundColor Gray
Write-Host "OK" -NoNewline -ForegroundColor Green
Write-Host ": Success  | " -NoNewline
Write-Host "FL" -NoNewline -ForegroundColor Red
Write-Host ": Failed  | " -NoNewline
Write-Host "DR" -NoNewline -ForegroundColor Yellow
Write-Host ": Dropped (DPI Filter) | " -NoNewline
Write-Host "--" -NoNewline -ForegroundColor Gray
Write-Host ": Skipped"

Write-Host "  [RESULT]   " -NoNewline -ForegroundColor Gray
Write-Host "DPI BLOCK" -NoNewline -ForegroundColor Yellow
Write-Host ": SNI filter detected  | " -NoNewline
Write-Host "IP BLOCK" -NoNewline -ForegroundColor Red
Write-Host ": Address unreachable"

Write-Host ("-" * 79)

$dpiDetected = ($allResults | Where-Object { $_.Verdict -eq "DPI BLOCK" }).Count
if ($dpiDetected -gt 0) {
    Write-Host "DPI interference detected ($dpiDetected hosts)." -ForegroundColor Yellow
} else {
    Write-Host "No DPI filtering detected. Connectivity is normal." -ForegroundColor Green
}

Write-Host ("=" * 79)
Read-Host "Analysis finished. Press Enter to exit"