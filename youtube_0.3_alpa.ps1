# Environment Setup
$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Define available protocols (TLS 1.3 is available only on Win 10 21H1+ / Win 11)
$IsWin7 = ([Environment]::OSVersion.Version.Major -eq 6 -and [Environment]::OSVersion.Version.Minor -eq 1)
if ($IsWin7) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
} else {
    # For Win 10/11 try TLS 1.2 + 1.3 (12288 is the enum value for Tls13)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
}

# --- Function to dynamically find the nearest CDN node ---
function Get-LocalCDN {
    $cdnHost = "redirector.googlevideo.com"
    try {
        # Resolve CNAME/IP for the nearest node
        $addresses = [System.Net.Dns]::GetHostAddresses($cdnHost)
        $hostName = [System.Net.Dns]::GetHostEntry($addresses[0]).HostName
        return $hostName
    } catch {
        return "rr1---sn-uxax-5u6e.googlevideo.com" # Fallback if DNS is hijacked/poisoned
    }
}

# --- Core testing function ---
function Test-NetworkDPI {
    param([string]$Target)
    $timeout = 2500
    $res = @{ Domain=$Target.PadRight(38); IP="?"; TCP="FAIL"; TLS="FAIL"; UDP="FAIL"; Latency=0; Verdict="BLOCKED" }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcp = New-Object System.Net.Sockets.TcpClient
    
    try {
        # 0. DNS Resolution
        $ips = [System.Net.Dns]::GetHostAddresses($Target)
        $res.IP = $ips[0].IPAddressToString.PadRight(15)

        # 1. TCP Check (Port 443)
        $ar = $tcp.BeginConnect($Target, 443, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne($timeout)) {
            $tcp.EndConnect($ar)
            $res.TCP = "OK  "
            $res.Latency = $sw.ElapsedMilliseconds
        } else {
            $res.Verdict = "IP BLOCK"
            return $res
        }

        # 2. TLS Handshake (SNI) - Testing for DPI/TSPU blocking
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
        $arSsl = $ssl.BeginAuthenticateAsClient($Target, $null, $GlobalProtocol, $false, $null, $null)
        if ($arSsl.AsyncWaitHandle.WaitOne($timeout)) {
            $ssl.EndAuthenticateAsClient($arSsl)
            $res.TLS = "OK  "
        } else {
            $res.TLS = "DROP" # Packet sent, but no response (common DPI behavior)
            $res.Verdict = "DPI BLOCK (SNI)"
            return $res
        }

        # 3. UDP Check (QUIC/HTTP3)
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Connect($Target, 443)
        $udp.Send([byte[]](1..10), 10) | Out-Null
        $res.UDP = "SENT" # UDP is stateless; if no ICMP unreachable was received, we assume SENT
        $udp.Close()

        $res.Verdict = "AVAILABLE"
    } catch {
        # Handle cases where the exception message might be too short for Substring
        $errMsg = $_.Exception.Message
        $res.Verdict = "ERROR: $(if ($errMsg.Length -gt 10) { $errMsg.Substring(0,10) } else { $errMsg })"
    } finally {
        if ($ssl) { $ssl.Dispose() }
        if ($tcp) { $tcp.Dispose() }
    }
    return $res
}

# --- Execution ---
Clear-Host
Write-Host "--- SCANNING NETWORK FOR YOUTUBE BLOCKING (WIN 7/10/11) ---"
Write-Host "Resolving local Google Global Cache node..."
$localCDN = Get-LocalCDN
Write-Host "Detected your CDN: $localCDN" -ForegroundColor Cyan

$targets = @(
    "google.com",                  # Control check for Google access
    "www.youtube.com",             # Main website entry
    "m.youtube.com",               # Mobile interface
    "i.ytimg.com",                 # Thumbnails and static images
    "yt3.ggpht.com",               # User avatars
    "manifest.googlevideo.com",    # Video stream metadata
    $localCDN                      # Your local video server (CDN)
)

Write-Host ""
Write-Host "DOMAIN                                 IP              TCP   TLS   UDP    LAT   RESULT"
Write-Host "--------------------------------------------------------------------------------------------"

foreach ($t in $targets) {
    $report = Test-NetworkDPI $t
    
    $color = "Red"
    if ($report.Verdict -eq "AVAILABLE") { $color = "Green" }
    elseif ($report.Verdict -match "DPI") { $color = "Yellow" }
    elseif ($report.Verdict -eq "IP BLOCK") { $color = "DarkRed" }

    # Single-line console output
    Write-Host "$($report.Domain)" -NoNewline
    Write-Host "$($report.IP) " -NoNewline -ForegroundColor Gray
    Write-Host "$($report.TCP)  " -NoNewline
    Write-Host "$($report.TLS)  " -NoNewline
    Write-Host "$($report.UDP)   " -NoNewline -ForegroundColor Gray
    Write-Host "$($report.Latency.ToString().PadLeft(4))ms " -NoNewline -ForegroundColor Cyan
    Write-Host " [$($report.Verdict)]" -ForegroundColor $color
}

Write-Host "--------------------------------------------------------------------------------------------"
Read-Host "`nThe diagnosis is complete. Press Enter..."