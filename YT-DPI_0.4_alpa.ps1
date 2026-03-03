# --- Environment Setup ---
$ErrorActionPreference = "SilentlyContinue"
# Ignore SSL certificate errors (useful when testing DPI that intercepts traffic)
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Define available protocols (TLS 1.3 is 12288)
# Wrapped in try-catch to support older .NET versions without crashing
try {
    # Try to enable TLS 1.2 + 1.3
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12 -bor 12288
} catch {
    # Fallback to TLS 1.2 only
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
}

# --- Dynamic CDN Discovery ---
function Get-LocalCDN {
    $cdnHost = "redirector.googlevideo.com"
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($cdnHost)
        return [System.Net.Dns]::GetHostEntry($addresses[0]).HostName
    } catch {
        return "rr1---sn-uxax-5u6e.googlevideo.com" # Fallback if DNS is poisoned
    }
}

# --- Core Testing Function ---
function Test-NetworkDPI {
    param(
        [string]$Target,
        [int]$MaxRetries = 2,      # Number of attempts for TLS/TCP
        [int]$TimeoutMs = 2500     # Timeout for each step
    )
    
    # Pre-resolve DNS to avoid repetitive lookups
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($Target)
        $targetIP = $ips[0].IPAddressToString
    } catch {
        return @{ Domain=$Target; IP="DNS FAIL"; TCP="FAIL"; TLS="FAIL"; UDP="FAIL"; Latency=0; Verdict="DNS ERROR" }
    }

    $res = @{ 
        Domain  = $Target; 
        IP      = $targetIP; 
        TCP     = "FAIL"; 
        TLS     = "FAIL"; 
        UDP     = "SENT"; 
        Latency = 0; 
        Verdict = "UNKNOWN" 
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # --- Retry Loop ---
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ssl = $null

        try {
            # 1. TCP Connection Check
            $ar = $tcp.BeginConnect($targetIP, 443, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                $tcp.EndConnect($ar)
                $res.TCP = "OK"
                if ($res.Latency -eq 0) { $res.Latency = $sw.ElapsedMilliseconds }
            } else {
                $res.Verdict = "IP BLOCK" # If TCP fails, it's likely an IP-level block
                break # No point in retrying TLS if TCP is blocked
            }

            # 2. TLS Handshake (The SNI Test)
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            # Use the Domain Name for SNI, but connect to the pre-resolved IP
            $arSsl = $ssl.BeginAuthenticateAsClient($Target, $null, $GlobalProtocol, $false, $null, $null)
            
            if ($arSsl.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                $ssl.EndAuthenticateAsClient($arSsl)
                $res.TLS = "OK"
                $res.Verdict = "AVAILABLE"
                return $res # Success! Exit function immediately
            } else {
                $res.TLS = "DROP"
                $res.Verdict = "DPI BLOCK (SNI)"
                # Continue to next retry attempt, maybe it was a fluke
            }
        } catch {
            $res.Verdict = "ERROR: $($_.Exception.Message.Trim().Substring(0, [Math]::Min(15, $_.Exception.Message.Length)))"
        } finally {
            # Strict cleanup to prevent socket exhaustion
            if ($ssl) { $ssl.Close(); $ssl.Dispose() }
            if ($tcp) { $tcp.Close(); $tcp.Dispose() }
        }

        if ($attempt -lt $MaxRetries) { 
            Start-Sleep -Milliseconds 500 # Wait before next attempt
        }
    }

    return $res
}

# --- Execution ---
Clear-Host
Write-Host "--- YT-DPI_0.4_alpa YOUTUBE CHECK UTILITY ---" -ForegroundColor White
$localCDN = Get-LocalCDN
Write-Host "Detected CDN: $localCDN" -ForegroundColor Cyan

$targets = @(
    "google.com", 
    "www.youtube.com", 
    "i.ytimg.com", 
    "yt3.ggpht.com", 
    "manifest.googlevideo.com", 
    $localCDN
)

# Header using Format Operator
$headerTemplate = "{0,-35} {1,-15} {2,-5} {3,-5} {4,-6} {5,6}   {6}"
Write-Host ""
Write-Host ($headerTemplate -f "DOMAIN", "IP", "TCP", "TLS", "UDP", "LAT", "RESULT")
Write-Host ("-" * 95)

foreach ($t in $targets) {
    $report = Test-NetworkDPI $t
    
    # Determine color logic
    $color = "Red"
    if ($report.Verdict -eq "AVAILABLE") { $color = "Green" }
    elseif ($report.Verdict -match "DPI") { $color = "Yellow" }
    elseif ($report.Verdict -match "DNS") { $color = "Magenta" }

    # Output formatted line
    $line = $headerTemplate -f `
        $report.Domain, 
        $report.IP, 
        $report.TCP, 
        $report.TLS, 
        $report.UDP, 
        ("$($report.Latency)ms"), 
        $report.Verdict

    Write-Host $line -ForegroundColor $color
}

Write-Host ("-" * 95)
Write-Host "Analysis finished. Check 'DPI BLOCK' or 'IP BLOCK' results."
Read-Host "Press Enter to exit"