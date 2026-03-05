<# :
@echo off
:: -----------------------------------------------------------------------------
:: BOOTSTRAPPER SECTION
:: Sets up the console window size immediately to prevent buffer scrolling issues.
:: Launches PowerShell with Bypass execution policy.
:: -----------------------------------------------------------------------------
mode con: cols=110 lines=35
title YT-DPI ANALYZER [FORENSIC SUITE]
color 0F
cls
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0' -Encoding UTF8) -join [Environment]::NewLine)"
exit /b
#>

#region [ MODULE 1: KERNEL & SYSTEM INTERFACE ]
# -----------------------------------------------------------------------------
# Handles Windows API calls, Console Modes, and Certificate Policies.
# -----------------------------------------------------------------------------

$ErrorActionPreference = "SilentlyContinue"

# 1.1 Console Buffer Setup (Prevents scrolling/jitter)
$RawUI = $Host.UI.RawUI
$ConsoleSize = $RawUI.WindowSize
$ConsoleSize.Height = 35
$ConsoleSize.Width = 110
$RawUI.BufferSize = $ConsoleSize

# 1.2 "Anti-Freeze" - Disable QuickEdit Mode via Kernel32
# This prevents the script from pausing when the user clicks the console window.
$Kernel32Def = @"
using System;
using System.Runtime.InteropServices;
public class ConsoleUtils {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
}
"@

try {
    Add-Type -TypeDefinition $Kernel32Def -Language CSharp
    
    $STD_INPUT_HANDLE = -10
    $ENABLE_QUICK_EDIT = 0x0040
    $ENABLE_INSERT_MODE = 0x0020
    $ENABLE_EXTENDED_FLAGS = 0x0080 # Critical for Windows 7

    $Handle = [ConsoleUtils]::GetStdHandle($STD_INPUT_HANDLE)
    $CurrentMode = 0
    [ConsoleUtils]::GetConsoleMode($Handle, [ref]$CurrentMode)
    
    # Disable QuickEdit and Insert Mode, Force Extended Flags
    $NewMode = ($CurrentMode -band (-not ($ENABLE_QUICK_EDIT -bor $ENABLE_INSERT_MODE))) -bor $ENABLE_EXTENDED_FLAGS
    [ConsoleUtils]::SetConsoleMode($Handle, $NewMode)
} catch {
    # Fail silently if API calls are blocked, script will still work
}

# 1.3 Certificate Policy Override (Windows 7 Fix)
# Forces .NET to accept all SSL certificates, avoiding root CA issues on old OS.
if ("TrustAllCertsPolicy" -as [type]) {} else {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
#endregion


#region [ MODULE 2: UI ENGINE ]
# -----------------------------------------------------------------------------
# Handles direct buffer manipulation for flicker-free rendering.
# -----------------------------------------------------------------------------

# Hide cursor for a cleaner look
try { [Console]::CursorVisible = $false } catch {}

function Write-At {
    <#
    .SYNOPSIS
        Writes text to specific coordinates without clearing the screen.
    #>
    param(
        [int]$x, 
        [int]$y, 
        [string]$text, 
        [ConsoleColor]$color="Gray"
    )
    try {
        $Pos = $RawUI.CursorPosition
        $Pos.X = $x
        $Pos.Y = $y
        $RawUI.CursorPosition = $Pos
        Write-Host $text -NoNewline -ForegroundColor $color
    } catch {}
}

function Draw-Interface {
    <#
    .SYNOPSIS
        Draws the static frame, headers, and footer.
    #>
    Clear-Host
    # Header
    Write-At 2 1 "YT-DPI CHECK TOOL" "Cyan"
    Write-At 35 1 ":: FORENSIC TCP/TLS ANALYZER ::" "DarkGray"
    Write-At 90 1 "v1.6 (Refactored)" "DarkGreen"
    Write-At 0 2 ("=" * 109) "DarkGray"
    
    # Columns
    Write-At 2 4 "TARGET DOMAIN" "White"
    Write-At 42 4 "IP ADDRESS" "White"
    Write-At 60 4 "TCP" "White"
    Write-At 68 4 "TLS" "White"
    Write-At 78 4 "LATENCY" "White"
    Write-At 90 4 "VERDICT" "White"
    
    Write-At 0 5 ("-" * 109) "DarkGray"
    
    # Footer
    $y = 30
    Write-At 0 $y ("=" * 109) "DarkGray"
    Write-At 2 ($y+1) "[ENTER]" "Green"
    Write-At 10 ($y+1) "RE-RUN ANALYSIS" "Gray"
    Write-At 2 ($y+2) "[Q/ESC]" "Red"
    Write-At 10 ($y+2) "EXIT TOOL" "Gray"
    
# ASCII Logo
    $y = 23 
    
    # x=32
    Write-At 32 ($y+0) "██╗   ██╗████████╗" "Red"
    Write-At 32 ($y+1) "╚██╗ ██╔╝╚══██╔══╝" "Red"
    Write-At 32 ($y+2) " ╚████╔╝    ██║   " "Red"
    Write-At 32 ($y+3) "  ╚██╔╝     ██║   " "Red"
    Write-At 32 ($y+4) "   ██║      ██║   " "Red"
    Write-At 32 ($y+5) "   ╚═╝      ╚═╝   " "Red"

    Write-At 50 ($y+0) "██████╗ ██████╗ ██╗" "Green"
    Write-At 50 ($y+1) "██╔══██╗██╔══██╗██║" "Green"
    Write-At 50 ($y+2) "██║  ██║██████╔╝██║" "Green"
    Write-At 50 ($y+3) "██║  ██║██╔═══╝ ██║" "Green"
    Write-At 50 ($y+4) "██████╔╝██║     ██║" "Green"
    Write-At 50 ($y+5) "╚═════╝ ╚═╝     ╚═╝" "Cyan"

    Write-At 31 ($y+6) "https://github.com/Shiperoid/YT-DPI-Check"  "DarkGray"
    Write-At 72 ($y+4) "DEEP PACKET" "DarkGray"
    Write-At 72 ($y+5) "INSPECTION"  "DarkGray"
}
#endregion


#region [ MODULE 3: NETWORK LOGIC (WORKER THREAD) ]
# -----------------------------------------------------------------------------
# The isolated script block that runs inside the RunspacePool.
# Contains Retries, Jitter, and TLS Handshake logic.
# -----------------------------------------------------------------------------
$NetworkWorker = {
    param($Target)
    
    # 3.1 Jitter (Anti-Flood)
    # Random delay to prevent simultaneous packet bursting
    Start-Sleep -Milliseconds (Get-Random -Min 100 -Max 600)

    # 3.2 TLS Configuration (Inside Thread)
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    try {
        # Bitwise OR 12288 forces TLS 1.3 draft/support on compatible .NET versions
        $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12 -bor 12288
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    } catch {
        $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    # 3.3 Result Object Initialization
    $Result = New-Object PSObject -Property @{
        Domain  = $Target
        IP      = "Resolving..."
        TCP     = ".."
        TLS     = ".."
        Lat     = "..."
        Verdict = "WAIT"
        Color   = "Gray"
    }

    try {
        # 3.4 DNS Resolution
        $IPAddresses = [System.Net.Dns]::GetHostAddresses($Target)
        $TargetIP = $IPAddresses[0].IPAddressToString
        $Result.IP = $TargetIP
        
        # 3.5 Connection Loop (Retry Mechanism)
        $MaxRetries = 2
        $IsSuccess = $false

        for ($Attempt = 1; $Attempt -le $MaxRetries; $Attempt++) {
            
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $TcpClient = New-Object System.Net.Sockets.TcpClient
            
            try {
                # A. TCP Connect
                $AsyncConnect = $TcpClient.BeginConnect($TargetIP, 443, $null, $null)
                
                if ($AsyncConnect.AsyncWaitHandle.WaitOne(2500)) {
                    $TcpClient.EndConnect($AsyncConnect)
                    $Result.TCP = "OK"
                    
                    # Capture latency only on first successful TCP
                    if ($Result.Lat -eq "...") { $Result.Lat = "$($Stopwatch.ElapsedMilliseconds)ms" }
                    
                    # B. SSL/TLS Handshake
                    try {
                        $SslStream = New-Object System.Net.Security.SslStream($TcpClient.GetStream(), $false)
                        $AsyncSsl = $SslStream.BeginAuthenticateAsClient($Target, $null, $GlobalProtocol, $false, $null, $null)
                        
                        if ($AsyncSsl.AsyncWaitHandle.WaitOne(500)) {
                            $SslStream.EndAuthenticateAsClient($AsyncSsl)
                            $Result.TLS = "OK"
                            $Result.Verdict = "AVAILABLE"
                            $Result.Color = "Green"
                            $IsSuccess = $true
                        } else {
                            # TLS Timeout
                            if ($Attempt -lt $MaxRetries) { throw "RetryTimeout" }
                            $Result.TLS = "TO"
                            $Result.Verdict = "DPI BLOCK"
                            $Result.Color = "Yellow"
                        }
                    } catch {
                        # Handle Exceptions
                        if ($_.Exception.InnerException -match "reset" -or $_.Exception.Message -match "reset") {
                            $Result.TLS = "RS"
                            $Result.Verdict = "DPI RESET"
                            $Result.Color = "Red"
                            $IsSuccess = $true # Reset is a definitive answer
                        } elseif ($_.ToString() -match "RetryTimeout") {
                            # Silent catch to trigger retry loop
                        } else {
                            # Soft SSL Error (e.g. cipher mismatch on old Win7) -> Treat as Available
                            $Result.TLS = "OK"
                            $Result.Verdict = "AVAILABLE"
                            $Result.Color = "Green"
                            $IsSuccess = $true
                        }
                    }
                } else {
                    # TCP Timeout
                    if ($Attempt -lt $MaxRetries) { throw "TcpTimeout" }
                    $Result.Verdict = "IP BLOCK"
                    $Result.Color = "DarkRed"
                    $Result.TCP = "FL"
                }
            } catch {
                # General Connection Failure
                if ($Attempt -ge $MaxRetries) {
                     $Result.Verdict = "CONN FAIL"
                     $Result.Color = "Red"
                }
            } finally {
                if ($TcpClient) { $TcpClient.Close() }
            }

            if ($IsSuccess) { break }
            # Wait before retry
            Start-Sleep -Milliseconds 500
        }
        
    } catch {
        $Result.Verdict = "DNS ERROR"
        $Result.Color = "DarkRed"
    }
    
    return $Result
}
#endregion


#region [ MODULE 4: MAIN CONTROLLER ]
# -----------------------------------------------------------------------------
# Orchestrates the UI, Thread Pool, and User Input.
# -----------------------------------------------------------------------------

function Get-LocalCDN {
    Write-At 2 3 "Detecting Local CDN Node..." "Yellow"
    $Url = "http://redirector.googlevideo.com/report_mapping?di=no"
    try {
        $Wc = New-Object System.Net.WebClient
        $Wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
        $Raw = $Wc.DownloadString($Url)
        if ($Raw -match "=>\s+([\w-]+)") { return "r1.$($matches[1]).googlevideo.com" }
    } catch {}
    return "manifest.googlevideo.com"
}

# 4.1 Target Definition
$BaseTargets = @(
    "google.com", "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
    "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com", 
    "googlevideo.com", "manifest.googlevideo.com", "redirector.googlevideo.com",
    "youtubei.googleapis.com", "youtubekids.com"
)

# 4.2 Initialize Runspaces
$RunspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$RunspacePool.Open()

# 4.3 Initial Rendering
Draw-Interface
$LocalCDN = Get-LocalCDN
Write-At 2 3 ("Detected CDN: " + $LocalCDN.PadRight(50)) "Cyan"

$Targets = $BaseTargets + $LocalCDN | Select-Object -Unique

# Pre-fill table rows
$RowStart = 6
for ($i=0; $i -lt $Targets.Count; $i++) {
    Write-At 2 ($RowStart+$i) $Targets[$i] "DarkGray"
    Write-At 42 ($RowStart+$i) "..." "DarkGray"
    Write-At 90 ($RowStart+$i) "IDLE" "DarkGray"
}

# 4.4 Main Event Loop
while ($true) {
    if ($RawUI.KeyAvailable) {
        $Key = $RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Exit Condition (Q or ESC)
        if ($Key.VirtualKeyCode -eq 81 -or $Key.VirtualKeyCode -eq 27) { break }
        
        # Start Condition (Enter)
        if ($Key.VirtualKeyCode -eq 13) {
            
            Write-At 25 32 " STATUS: INITIALIZING SCAN... " "Black" "White"
            
            # Dispatch Jobs
            $Jobs = @()
            foreach ($Target in $Targets) {
                $PowerShell = [PowerShell]::Create().AddScript($NetworkWorker).AddArgument($Target)
                $PowerShell.RunspacePool = $RunspacePool
                
                $JobObject = New-Object PSObject -Property @{ 
                    Pipe   = $PowerShell 
                    Handle = $PowerShell.BeginInvoke() 
                    Done   = $false 
                }
                $Jobs += $JobObject
            }
            
            Write-At 25 32 " STATUS: SCANNING...          " "Black" "Yellow"
            
            # Monitoring Loop
            $Scanning = $true
            while ($Scanning) {
                $Scanning = $false
                $Index = 0
                
                foreach ($Job in $Jobs) {
                    $RowIndex = $RowStart + $Index
                    
                    if ($Job.Handle.IsCompleted) {
                        if (-not $Job.Done) {
                            # Retrieve Result
                            $Result = $Job.Pipe.EndInvoke($Job.Handle)[0]
                            $Job.Done = $true
                            $Job.Pipe.Dispose()
                            
                            # Determine Colors (Win7 Compatible Logic)
                            $ColorTcp = "Red"; if ($Result.TCP -eq "OK") { $ColorTcp = "Green" }
                            $ColorTls = "Red"; if ($Result.TLS -eq "OK") { $ColorTls = "Green" }
                            
                            # Render Row
                            Write-At 2  $RowIndex ($Result.Domain.PadRight(38)) "Gray"
                            Write-At 42 $RowIndex ($Result.IP.PadRight(16)) "DarkGray"
                            Write-At 60 $RowIndex ($Result.TCP.PadRight(4)) $ColorTcp
                            Write-At 68 $RowIndex ($Result.TLS.PadRight(4)) $ColorTls
                            Write-At 78 $RowIndex ($Result.Lat.PadRight(8)) "White"
                            Write-At 90 $RowIndex ($Result.Verdict.PadRight(15)) $Result.Color
                        }
                    } else {
                        $Scanning = $true
                        Write-At 90 $RowIndex "SCANNING..." "Cyan"
                    }
                    $Index++
                }
                Start-Sleep -Milliseconds 100
            }
            Write-At 25 32 " STATUS: ANALYSIS COMPLETED   " "Black" "Green"
        }
    }
    Start-Sleep -Milliseconds 50
}

# 4.5 Cleanup
$RunspacePool.Close()
$RunspacePool.Dispose()
try { [Console]::CursorVisible = $true } catch {}
Clear-Host
#endregion