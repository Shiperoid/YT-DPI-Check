<# :
@echo off
title YT-DPI v2.0 test build
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0' -Encoding UTF8) -join [Environment]::NewLine)"
exit /b
#>

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::CursorVisible = $false
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# --- Сетка координат ---
$X = @{ Dom=2; IP=36; HTTP=54; T12=62; T13=72; Lat=82; Ver=90 }

$BaseTargets = @(
    "google.com", "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
    "i.ytimg.com", "yt3.ggpht.com", "googlevideo.com", "manifest.googlevideo.com",
    "googleapis.com", "youtubei.googleapis.com", "yt3.googleusercontent.com"
)

function Out-Str($x, $y, $str, $color="White", $bg="Black") {
    try {
        [Console]::SetCursorPosition($x, $y)
        [Console]::ForegroundColor = $color
        [Console]::BackgroundColor = $bg
        [Console]::Write($str)
        [Console]::BackgroundColor = "Black"
    } catch {}
}

function Get-ScanAnim($f, $row) {
    $frames = "[=   ]", "[ =  ]", "[  = ]", "[   =]", "[  = ]", "[ =  ]"
    return $frames[($f + $row) % $frames.Length]
}

function Clear-KeyBuffer {
    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
}

function Get-NetworkInfo {
    $dns = "UNKNOWN"
    $wmi = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.DNSServerSearchOrder -ne $null }
    if ($wmi) { $dns = $wmi.DNSServerSearchOrder[0] }

    $cdn = "manifest.googlevideo.com"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
        $raw = $wc.DownloadString("http://redirector.googlevideo.com/report_mapping?di=no")
        if ($raw -match "=>\s+([\w-]+)") { $cdn = "r1.$($matches[1]).googlevideo.com" }
    } catch {}

    return @{ DNS = $dns; CDN = $cdn }
}

function Show-HelpMenu {
    [Console]::Clear()
    Out-Str 2 2 "=== YT-DPI ANALYZER : MINI GUIDE ===" "Cyan"
    
    Out-Str 2 4 "[ STATUS CODES ]" "Yellow"
    Out-Str 4 5 "OK   - Connection successful. No interference." "Green"
    Out-Str 4 6 "RST  - Connection Reset. DPI dropped the packet." "Red"
    Out-Str 4 7 "N/A  - Not Available (e.g., Windows 7/10 does not support TLS 1.3)." "DarkGray"
    Out-Str 4 8 "FAIL - Connection timed out or general socket error." "Red"

    Out-Str 2 10 "[ VERDICTS ]" "Yellow"
    Out-Str 4 11 "AVAILABLE (CLEAN)  - TLS passed. YouTube should work fine." "Green"
    Out-Str 4 12 "DPI BLOCK DETECTED - HTTP works, but TLS is blocked by provider (Typical DPI)." "Yellow"
    Out-Str 4 13 "FULL IP BLOCK      - Both HTTP and TLS are unreachable (Hard IP ban)." "Red"
    
    Out-Str 2 15 "[ COLUMNS ]" "Yellow"
    Out-Str 4 16 "HTTP    - Port 80 (Cleartext HTTP). Used as a baseline for IP reachability." "White"
    Out-Str 4 17 "TLS 1.2 - Port 443. The most common secure protocol for YouTube." "White"
    Out-Str 4 18 "TLS 1.3 - Port 443. Modern protocol (harder for DPI to parse)." "White"
    Out-Str 4 19 "LAT     - Latency (Ping) to the server during TLS handshake." "White"

    Out-Str 2 22 "PRESS ANY KEY TO RETURN TO SCANNER..." "Cyan"
    Clear-KeyBuffer
    $null = [Console]::ReadKey($true)
    Clear-KeyBuffer
}

function Draw-UI ($NetInfo, $Targets) {
    $LinesNeeded = $Targets.Count + 18
    if ($LinesNeeded -lt 30) { $LinesNeeded = 30 }
    cmd /c "mode con: cols=125 lines=$LinesNeeded"
    [Console]::Clear()
    
    Out-Str 1 1 '██╗   ██╗████████╗    ██████╗ ██████╗ ██╗  _    _____    ____' 'Green'
    Out-Str 1 2 '╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║ | |  / /__ \  / __ \' 'Green'
    Out-Str 1 3 ' ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║ | | / /__/ / / / / /' 'Green'
    Out-Str 1 4 '  ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║ | |/ // __/_/ /_/ /' 'Green'
    Out-Str 1 5 '   ██╝      ██╝       ██████╝ ██╝     ██╝ |___//____(_)____/' 'Green'

    Out-Str 65 1 "> SYSTEM STATUS: [ ONLINE ]" "Green"
    Out-Str 65 2 ("> ACTIVE DNS:    " + $NetInfo.DNS).PadRight(50) "Cyan"
    Out-Str 65 3 ("> DETECTED CDN:  " + $NetInfo.CDN).PadRight(50) "Yellow"
    Out-Str 65 4 "> ENGINE:        dpi-ebatel 2.0" "Red"
    Out-Str 65 5 "> AUTHOR:        https://github.com/Shiperoid/" "Gray"

    $y = 7; $l = "=" * 121
    Out-Str 0 $y $l "DarkCyan"
    Out-Str $X.Dom ($y+1) "TARGET DOMAIN" "White"
    Out-Str $X.IP  ($y+1) "IP ADDRESS" "White"
    Out-Str $X.HTTP ($y+1) "HTTP" "White"
    Out-Str $X.T12 ($y+1) "TLS 1.2" "White"
    Out-Str $X.T13 ($y+1) "TLS 1.3" "White"
    Out-Str $X.Lat ($y+1) "LAT" "White"
    Out-Str $X.Ver ($y+1) "RESULT" "White"
    Out-Str 0 ($y+2) $l "DarkCyan"

    for($i=0; $i -lt $Targets.Count; $i++) {
        Out-Str $X.Dom (10+$i) ($Targets[$i].PadRight(32)) "Gray"
        Out-Str $X.Ver (10+$i) ("IDLE".PadRight(30)) "DarkGray"
    }
    Out-Str 0 (10+$Targets.Count+1) $l "DarkCyan"
}

$Worker = {
    param($Target)
    $res = [PSCustomObject]@{ IP="FAILED"; HTTP="FAIL"; T12="FAIL"; T13="FAIL"; Lat="0ms"; Verdict="DNS_ERR"; Color="Red" }
    try {
        $dns = [System.Net.Dns]::GetHostAddresses($Target)
        if (!$dns) { return $res }
        $res.IP = $dns[0].IPAddressToString
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        # 1. HTTP
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($res.IP, 80, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(800)) {
            $tcp.EndConnect($asyn)
            $stream = $tcp.GetStream()
            $stream.ReadTimeout = 1000
            $stream.WriteTimeout = 1000
            $msg = "HEAD / HTTP/1.1`r`nHost: $($Target)`r`nUser-Agent: curl/7.88.1`r`nConnection: close`r`n`r`n"
            $buf = [System.Text.Encoding]::ASCII.GetBytes($msg)
            try {
                $stream.Write($buf, 0, $buf.Length)
                $readBuf = New-Object byte[] 64
                if ($stream.Read($readBuf, 0, 64) -gt 0) { $res.HTTP = "OK" }
            } catch {}
        }
        $tcp.Close()

        # 2. TLS 1.2
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($res.IP, 443, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(1200)) {
            $tcp.EndConnect($asyn)
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            $res.Lat = "$($sw.ElapsedMilliseconds)ms"
            try {
                $ssl.AuthenticateAsClient($Target, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
                if ($ssl.IsAuthenticated) { $res.T12 = "OK" }
            } catch { $res.T12 = "RST" }
            $ssl.Close()
        }
        $tcp.Close()

        # 3. TLS 1.3
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($res.IP, 443, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(1200)) {
            $tcp.EndConnect($asyn)
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            try {
                $ssl.AuthenticateAsClient($Target, $null, 12288, $false)
                if ($ssl.IsAuthenticated) { $res.T13 = "OK" }
            } catch { 
                $errMsg = "$($_.Exception.Message) $($_.Exception.InnerException.Message)"
                if ($errMsg -match "not supported|algorithm|поддерживается|алгоритм|не удается") { 
                    $res.T13 = "N/A" 
                } else { $res.T13 = "RST" }
            }
            $ssl.Close()
        }
        $tcp.Close()

        if ($res.T12 -eq "OK" -or $res.T13 -eq "OK") {
            $res.Verdict = "AVAILABLE (CLEAN)"; $res.Color = "Green"
        } elseif ($res.HTTP -eq "OK") {
            $res.Verdict = "DPI BLOCK DETECTED"; $res.Color = "Yellow"
        } else {
            $res.Verdict = "FULL IP BLOCK"; $res.Color = "Red"
        }
    } catch { $res.Verdict = "ERR: SOCKET" }
    
    return $res
}

$Pool = [runspacefactory]::CreateRunspacePool(1, 20); $Pool.Open()
$f = 0
$FirstRun = $true
$UI_Y = 30 

while ($true) {
    if ($FirstRun) {
        $NetInfo = Get-NetworkInfo
        $Targets = $BaseTargets + $NetInfo.CDN | Select-Object -Unique
        Draw-UI $NetInfo $Targets
        $UI_Y = 10 + $Targets.Count + 3
        Out-Str 2 $UI_Y (" [ READY ] [ENTER] START | [H] HELP | [Q] QUIT ".PadRight(120)) "Black" "White"
        $FirstRun = $false
    }

    $f++
    if ($f % 5 -eq 0) { Out-Str 120 1 ("|/-\"[$f/5 % 4]) "Cyan" }

    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true).Key
        if ($k -eq "Q" -or $k -eq "Escape") { break }
        
        if ($k -eq "H") {
            Show-HelpMenu
            Draw-UI $NetInfo $Targets
            Out-Str 2 $UI_Y (" [ READY ] [ENTER] START | [H] HELP | [Q] QUIT ".PadRight(120)) "Black" "White"
            continue
        }
        
        if ($k -eq "Enter") {
            Out-Str 2 $UI_Y (" [ WAIT ] REFRESHING NETWORK STATE (DNS/CDN)... ".PadRight(120)) "Black" "Cyan"
            $NetInfo = Get-NetworkInfo
            $Targets = $BaseTargets + $NetInfo.CDN | Select-Object -Unique
            Draw-UI $NetInfo $Targets
            $UI_Y = 10 + $Targets.Count + 3
            
            Out-Str 2 $UI_Y (" [ BUSY ] SCANNING IN PROGRESS... PRESS [Q] TO ABORT ".PadRight(120)) "Black" "Yellow"
            
            for($i=0; $i -lt $Targets.Count; $i++) { 
                Out-Str $X.IP (10+$i) (" " * 85) 
                Out-Str $X.Ver (10+$i) ("PREPARING...".PadRight(30)) "DarkGray"
            }
            
            $ActiveJobs = [System.Collections.ArrayList]::new()
            for($i=0; $i -lt $Targets.Count; $i++) {
                $ps = [PowerShell]::Create().AddScript($Worker).AddArgument($Targets[$i])
                $ps.RunspacePool = $Pool
                [void]$ActiveJobs.Add([PSCustomObject]@{ P=$ps; H=$ps.BeginInvoke(); Row=10+$i })
            }

            $Aborted = $false
            
            while ($ActiveJobs.Count -gt 0) {
                $f++
                if ([Console]::KeyAvailable) {
                    $inkey = [Console]::ReadKey($true).Key
                    if ($inkey -eq "Q" -or $inkey -eq "Escape") { $Aborted = $true; break }
                }

                $Completed = @()
                foreach($j in $ActiveJobs) {
                    if ($j.H.IsCompleted) {
                        $Completed += $j
                    } else {
                        Out-Str $X.Ver $j.Row ("SCANNING " + (Get-ScanAnim $f $j.Row)).PadRight(30) "Cyan"
                    }
                }

                foreach($j in $Completed) {
                    # Жесткий фильтр: забираем только нужный объект, отсекая мусор
                    $rawOutput = $j.P.EndInvoke($j.H)
                    $res = $rawOutput | Where-Object { $_ -is [PSCustomObject] -and $_.IP } | Select-Object -Last 1
                    
                    # Защита от краша потока
                    if (!$res) {
                        $res = [PSCustomObject]@{ IP="ERROR"; HTTP="--"; T12="--"; T13="--"; Lat="--"; Verdict="THREAD_CRASH"; Color="Red" }
                    }

                    # Принудительно кастуем в строку перед вызовом PadRight
                    $ipStr  = [string]$res.IP
                    $htStr  = [string]$res.HTTP
                    $t12Str = [string]$res.T12
                    $t13Str = [string]$res.T13
                    $latStr = [string]$res.Lat
                    $verStr = [string]$res.Verdict

                    Out-Str $X.IP   $j.Row ($ipStr.PadRight(16)) "DarkGray"
                    
                    $hCol = if($htStr -eq "OK") {"Green"} else {"Red"}
                    Out-Str $X.HTTP $j.Row ($htStr.PadRight(6)) $hCol
                    
                    $t12Col = if($t12Str -eq "OK") {"Green"} else {"Red"}
                    Out-Str $X.T12  $j.Row ($t12Str.PadRight(8)) $t12Col
                    
                    $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A") {"Gray"} else {"Red"}
                    Out-Str $X.T13  $j.Row ($t13Str.PadRight(8)) $t13Col
                    
                    Out-Str $X.Lat  $j.Row ($latStr.PadRight(6)) "Cyan"
                    Out-Str $X.Ver  $j.Row ($verStr.PadRight(30)) $res.Color
                    
                    $j.P.Dispose()
                    $ActiveJobs.Remove($j)
                }
                [System.Threading.Thread]::Sleep(50)
            }
            
            if ($Aborted) {
                foreach($j in $ActiveJobs) { $j.P.Dispose() }
                Out-Str 2 $UI_Y (" [ ABORTED ] SCAN STOPPED. [ENTER] RESTART | [H] HELP | [Q] QUIT ".PadRight(120)) "Black" "Red"
            } else {
                Out-Str 2 $UI_Y (" [ SUCCESS ] SCAN FINISHED. [ENTER] RESTART | [H] HELP | [Q] QUIT ".PadRight(120)) "Black" "Green"
            }
            Clear-KeyBuffer
        }
    }
    [System.Threading.Thread]::Sleep(100)
}
$Pool.Close(); $Pool.Dispose()