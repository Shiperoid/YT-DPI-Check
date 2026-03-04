<# :
@echo off
:: Batch-starter: launches PowerShell without execution policy restrictions
title YT-DPI Check Tool v1.1.0
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content '%~f0') -join [Environment]::NewLine)"
if %errorlevel% neq 0 pause
exit /b
#>

# --- Environment Setup ---
if ($Host.UI.RawUI.BufferSize.Width -lt 115) {
    $size = $Host.UI.RawUI.BufferSize; $size.Width = 115; $Host.UI.RawUI.BufferSize = $size
    $window = $Host.UI.RawUI.WindowSize; $window.Width = 115; $Host.UI.RawUI.WindowSize = $window
}

$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# TLS Setup: Force TLS 1.2 and 1.3
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12 -bor 12288
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
}

function Format-WideString {
    param([string]$str, [int]$len)
    if ($str.Length -gt $len) { return $str.Substring(0, $len - 3) + "..." }
    return $str.PadRight($len)
}

function Get-LocalCDN {
    $url = "http://redirector.googlevideo.com/report_mapping?di=no"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
        $raw = $wc.DownloadString($url)
        if ($raw -match "=>\s+([\w-]+)") { return "r1.$($matches[1]).googlevideo.com" }
    } catch {}
    return "manifest.googlevideo.com"
}

# --- Advanced DPI Test Logic ---
function Test-NetworkDPI {
    param([string]$Target, [int]$MaxRetries = 1)
    
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($Target)
        $targetIP = $ips[0].IPAddressToString
    } catch {
        return @{ Domain=$Target; IP="DNS FAIL"; TCP="--"; TLS="--"; UDP="--"; Latency=0; Verdict="DNS ERROR" }
    }

    $res = @{ Domain=$Target; IP=$targetIP; TCP="FL"; TLS="FL"; UDP="??"; Latency=0; Verdict="UNKNOWN" }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # 1. UDP / QUIC Probe (Basic check for UDP 443 reachability)
    $udpClient = New-Object System.Net.Sockets.UdpClient
    $udpClient.Connect($targetIP, 443)
    try {
        $dummyQUIC = [byte[]](0x01, 0x00, 0x00, 0x00) # Dummy QUIC-like header
        $udpClient.Send($dummyQUIC, $dummyQUIC.Length)
        $res.UDP = "OK" 
    } catch {
        $res.UDP = "BK" # Blocked or Unreachable
    } finally { $udpClient.Close() }

    # 2. TCP & TLS/SNI Handshake
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ssl = $null
        try {
            $ar = $tcp.BeginConnect($targetIP, 443, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(2000)) {
                $tcp.EndConnect($ar)
                $res.TCP = "OK"
                if ($res.Latency -eq 0) { $res.Latency = $sw.ElapsedMilliseconds }

                # Deep TLS Check with SNI
                $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
                $arSsl = $ssl.BeginAuthenticateAsClient($Target, $null, $GlobalProtocol, $false, $null, $null)
                
                if ($arSsl.AsyncWaitHandle.WaitOne(2500)) {
                    $ssl.EndAuthenticateAsClient($arSsl)
                    $res.TLS = "OK"; $res.Verdict = "AVAILABLE"
                    return $res
                } else {
                    # If TCP connected but TLS timed out - 99% SNI Filter (DPI)
                    $res.TLS = "DR"; $res.Verdict = "DPI BLOCK"
                }
            } else { $res.Verdict = "IP BLOCK" }
        } catch {
            # Handling "Connection Reset" or "Remote Certificate Invalid"
            # In many cases with Google, a Reset after ClientHello is also DPI.
            if ($_.Exception.InnerException -match "reset" -or $_.Exception.Message -match "reset") {
                $res.TLS = "RS"; $res.Verdict = "DPI RESET"
            } elseif ($res.TCP -eq "OK") {
                # If TCP is fine but TLS throws a non-timeout error, it might be reachable but refusing SNI
                $res.TLS = "OK"; $res.Verdict = "AVAILABLE" 
            }
        }
        finally { if ($ssl){$ssl.Close()}; if ($tcp){$tcp.Close()} }
    }
    return $res
}

# --- Execution ---
Clear-Host
Write-Host ">>> YT-DPI Check v1.1.0 <<<" -ForegroundColor White
$localCDN = Get-LocalCDN
Write-Host "Detected CDN Node: $localCDN" -ForegroundColor Cyan
Write-Host ("=" * 110)

$header = "{0,-45} {1,-15} {2,-4} {3,-4} {4,-4} {5,-7} {6}"
Write-Host ($header -f "DOMAIN", "IP", "TCP", "TLS", "UDP", "LAT", "RESULT")
Write-Host ("-" * 110)

# Optimized target list (focused on high-load services)
$targets = @(
    "google.com",
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "youtu.be",
    "i.ytimg.com",
    "i9.ytimg.com",
    "s.ytimg.com",
    "yt3.ggpht.com",
    "yt4.ggpht.com",
    "googleusercontent.com",
    "yt3.googleusercontent.com",
    "googlevideo.com",
    "manifest.googlevideo.com",
    "redirector.googlevideo.com",
    "googleapis.com",
    "youtubei.googleapis.com",
    "youtubeembeddedplayer.googleapis.com",
    "youtubekids.com",
    "nhacmp3youtube.com",
    "signaler-pa.youtube.com",
    $localCDN
)

$targets = $targets | Select-Object -Unique
$allResults = @() 

foreach ($t in $targets) {
    $report = Test-NetworkDPI $t
    $allResults += $report
    
    $color = "Red"
    if ($report.Verdict -eq "AVAILABLE") { $color = "Green" }
    elseif ($report.Verdict -match "DPI") { $color = "Yellow" }
    
    $dispDomain = Format-WideString $report.Domain 45
    $dispIP     = Format-WideString $report.IP 15
    $dispLat    = if ($report.Latency -gt 0) { "$($report.Latency)ms" } else { "---" }

    Write-Host ($header -f $dispDomain, $dispIP, $report.TCP, $report.TLS, $report.UDP, $dispLat, $report.Verdict) -ForegroundColor $color
}

Write-Host ("=" * 110)
Write-Host " STATUS LEGEND" -ForegroundColor Cyan
Write-Host "  TCP/TLS/UDP: OK = Pass | FL = Failed | DR = Dropped (DPI) | RS = Reset (DPI) | BK = UDP Blocked"
Write-Host "  RESULT:      AVAILABLE = Normal | DPI BLOCK = SNI Filtering | IP BLOCK = Routing Issue"
Write-Host ("-" * 110)

$dpiDetected = ($allResults | Where-Object { $_.Verdict -match "DPI" }).Count
if ($dpiDetected -gt 0) {
    Write-Host "DIAGNOSIS: DPI/TSPU interference detected on $dpiDetected host(s). Try using ByeDPI/GoodCheck." -ForegroundColor Yellow
} else {
    Write-Host "DIAGNOSIS: No DPI filtering detected. Connectivity is normal." -ForegroundColor Green
}

Write-Host ("=" * 110)
Read-Host "Analysis finished. Press Enter to exit"