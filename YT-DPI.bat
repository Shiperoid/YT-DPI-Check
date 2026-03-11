<# :
@echo off
title YT-DPI v2.0
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0' -Encoding UTF8) -join [Environment]::NewLine)"
exit /b
#>

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::CursorVisible = $false
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# --- ОТКЛЮЧЕНИЕ ВЫДЕЛЕНИЯ МЫШЬЮ (ЗАЩИТА ОТ ЗАВИСАНИЙ) ---
$code = @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    const uint ENABLE_QUICK_EDIT = 0x0040;
    const int STD_INPUT_HANDLE = -10;
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")]
    static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public static void DisableQuickEdit() {
        IntPtr consoleHandle = GetStdHandle(STD_INPUT_HANDLE);
        uint consoleMode;
        if (GetConsoleMode(consoleHandle, out consoleMode)) {
            consoleMode &= ~ENABLE_QUICK_EDIT;
            SetConsoleMode(consoleHandle, consoleMode);
        }
    }
}
"@
Add-Type -TypeDefinition $code
[ConsoleHelper]::DisableQuickEdit()

# --- Сетка координат ---
$X = @{ Dom=2; IP=48; HTTP=68; T12=78; T13=88; Lat=98; Ver=108 }

$BaseTargets = @(
    "google.com", "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
        "i.ytimg.com", "i9.ytimg.com", "s.ytimg.com", "yt3.ggpht.com", "yt4.ggpht.com",
        "googleusercontent.com", "yt3.googleusercontent.com", "googlevideo.com",
        "manifest.googlevideo.com", "redirector.googlevideo.com", "googleapis.com",
        "youtubei.googleapis.com", "youtubeembeddedplayer.googleapis.com", "youtubekids.com",
        "signaler-pa.youtube.com"
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

# --- УЛУЧШЕННАЯ ПРОВЕРКА СЕТИ ---
function Get-NetworkInfo {
    $info = @{ ConfigDNS="UNK"; RealDNS="CHECKING..."; DoH="OFF"; ISP="UNK"; LOC="UNK"; CDN="manifest.googlevideo.com" }
    
    # 1. Локальный DNS (совместимо с Win 7)
    try {
        $wmi = Get-WmiObject Win32_NetworkAdapterConfiguration | Where { $_.IPEnabled -and $_.DNSServerSearchOrder } | Select -First 1
        if ($wmi) { $info.ConfigDNS = $wmi.DNSServerSearchOrder[0] }
    } catch {}

    # 2. Проверка DoH (Win 11 системный или через прокси-процессы)
    try {
        $doh = netsh dns show encryption 2>$null | Out-String
        if ($doh -match "Yes|Да") { $info.DoH = "SYS-DoH" }
        elseif (Get-Process | Where { $_.Name -match "dnscrypt|cloudflared|goodcheck|stubby" }) { $info.DoH = "PROXY-DoH" }
    } catch {}

    # 3. Честный DNS и GEO (аналог dnscheck.tools через API)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy() # Ускоряет запуск (пропуск авто-прокси)
        
        # Получаем ISP и внешний IP
        $geo = $wc.DownloadString("http://ip-api.com/json/?fields=status,countryCode,city,isp,query") | ConvertFrom-Json
        if ($geo.status -eq "success") {
            $info.ISP = ($geo.isp -replace '(?i)\s*(LLC|Inc|Ltd|JSC|PJSC|OOO|ZAO)', '').Trim()
            $info.LOC = "$($geo.city), $($geo.countryCode)"
            
            # Самое важное: Узнаем IP сервера, который реально сделал запрос (Real DNS)
            $dnsCheck = $wc.DownloadString("http://edns.ip-api.com/json") | ConvertFrom-Json
            $info.RealDNS = if ($dnsCheck.dns.ip) { $dnsCheck.dns.ip } else { $geo.query }
        }
    } catch { $info.RealDNS = "OFFLINE/DNS_ERR" }

    return $info
}

function Show-HelpMenu {
    [Console]::Clear()
    Out-Str 2 2 "=== YT-DPI : MINI GUIDE ===" "Cyan"

    Out-Str 2 4 "[ STATUS CODES ]" "Yellow"
    Out-Str 4 5 "OK   - Connection successful. No interference." "Green"
    Out-Str 4 6 "RST  - Connection Reset. DPI injected a TCP RST." "Red"
    Out-Str 4 7 "DRP  - Connection Dropped (Blackholed during handshake)." "Red"
    Out-Str 4 8 "N/A  - Not Available (e.g., Windows 7/10 lacking TLS 1.3)." "DarkGray"
    Out-Str 4 9 "FAIL - Connection timed out or general socket error." "Red"

    Out-Str 2 11 "[ RESULT ]" "Yellow"
    Out-Str 4 12 "AVAILABLE  - TLS passed. YouTube should work fine." "Green"
    Out-Str 4 13 "DPI BLOCK  - HTTP works, but TLS is blocked/dropped (Typical DPI)." "Yellow"
    Out-Str 4 14 "IP  BLOCK  - Both HTTP and TLS are unreachable (Hard IP ban)." "Red"
    
    Out-Str 2 16 "[ COLUMNS ]" "Yellow"
    Out-Str 4 17 "HTTP    - Port 80 (Cleartext HTTP). Used as a baseline for IP reachability." "White"
    Out-Str 4 18 "TLS 1.2 - Port 443. The most common secure protocol for YouTube." "White"
    Out-Str 4 19 "TLS 1.3 - Port 443. Modern protocol (harder for DPI to parse)." "White"
    Out-Str 4 20 "LAT     - Latency (Ping) to the server during TCP handshake." "White"

    Out-Str 2 23 "PRESS ANY KEY TO RETURN TO SCANNER..." "Cyan"
    Clear-KeyBuffer
    $null = [Console]::ReadKey($true)
    Clear-KeyBuffer
}

function Draw-UI ($NetInfo, $Targets, $ClearScreen = $true) {
    $LinesNeeded = $Targets.Count + 19
    if ($ClearScreen) {
        # Расширяем консоль до 145 символов
        cmd /c "mode con: cols=145 lines=$LinesNeeded"
        [Console]::Clear()
    }
    
    Out-Str 1 1 '██╗   ██╗████████╗    ██████╗ ██████╗ ██╗  _    _____    ____' 'Green'
    Out-Str 1 2 '╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║ | |  / /__ \  / __ \' 'Green'
    Out-Str 1 3 ' ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║ | | / /__/ / / / / /' 'Green'
    Out-Str 1 4 '  ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║ | |/ // __/_/ /_/ /' 'Green'
    Out-Str 1 5 '   ██╝      ██╝       ██████╝ ██╝     ██╝ |___//____(_)____/' 'Green'





# ИНФОРМАЦИОННЫЙ БЛОК (Координаты 65)
    $dohCol = if ($NetInfo.DoH -ne "OFF") { "Green" } else { "Gray" }
    Out-Str 65 1 "> SYSTEM STATUS: [ ONLINE ]" "Green"
    Out-Str 65 2 ("> OS DNS:       " + $NetInfo.ConfigDNS).PadRight(40) "Cyan"
    Out-Str 65 3 ("> UPSTREAM DNS: " + $NetInfo.RealDNS).PadRight(40) "Yellow" # Честный DNS
    Out-Str 65 4 ("> DoH/ENCRYPT:  " + $NetInfo.DoH).PadRight(40) $dohCol
    Out-Str 65 5 ("> DETECTED CDN: " + $NetInfo.CDN).PadRight(40) "Magenta"
    Out-Str 65 6 ("> ISP / LOC:    $($NetInfo.ISP) ($($NetInfo.LOC))").PadRight(60) "DarkGray"


    
    $ispStr = "> ISP / LOC:     $($NetInfo.ISP) ($($NetInfo.LOC))"
    Out-Str 65 6 ($ispStr.PadRight(58)) "Gray"
    
    # Отрисовка телеметрии вместе с интерфейсом (защита от моргания)
    # СТАТИСТИКА (Сдвинута вправо на 115, чтобы не мешать DNS)
    $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
    Out-Str 115 1 "[ RAM: ${ram}MB ]" "DarkGray"
    Out-Str 115 2 "[ CLEAN:   $($Stats.Clean) ]" "Green"
    Out-Str 115 3 "[ BLOCKED: $($Stats.Blocked) ]" "Yellow"
    Out-Str 115 4 "[ ERRORS:  $($Stats.Err) ]" "Red"
    
    Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($jobsCount.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray" 
    Out-Str 95 2 ("[ BLOCKS: $($Stats.Blocked.ToString().PadRight(2)) | RST: $($Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
    Out-Str 95 3 ("[ CLEAN:  $($Stats.Clean.ToString().PadRight(2)) | ERR: $($Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"

    # Компактный вывод провайдера и города
    $ispStr = "> ISP / LOC:     $($NetInfo.ISP) ($($NetInfo.LOC))"
    Out-Str 65 6 ($ispStr.PadRight(58)) "Magenta"

    $y = 8; $l = "═" * 141
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
        Out-Str $X.Dom (11+$i) ($Targets[$i].PadRight(38)) "Gray"
        if ($ClearScreen) { 
            Out-Str $X.IP   (11+$i) ("---.---.---.---".PadRight(16)) "DarkGray"
            Out-Str $X.HTTP (11+$i) ("--".PadRight(6)) "DarkGray"
            Out-Str $X.T12  (11+$i) ("--".PadRight(8)) "DarkGray"
            Out-Str $X.T13  (11+$i) ("--".PadRight(8)) "DarkGray"
            Out-Str $X.Lat  (11+$i) ("----".PadRight(6)) "DarkGray"
            Out-Str $X.Ver  (11+$i) ("IDLE".PadRight(30)) "DarkGray"
        }
    }
    Out-Str 0 (11+$Targets.Count+1) $l "DarkCyan"
}

$Worker = {
    param($Target)
    $res = [PSCustomObject]@{ IP="FAILED"; HTTP="FAIL"; T12="FAIL"; T13="FAIL"; Lat="0ms"; Verdict="DNS_ERR"; Color="Red" }
    
    # 0. DNS (Если нет интернета или VPN переключается - упадет только тут)
    try {
        $dns = [System.Net.Dns]::GetHostAddresses($Target)
        if (!$dns) { return $res }
        $res.IP = $dns[0].IPAddressToString
    } catch {
        $res.Verdict = "DNS ERROR / NO NETWORK"
        return $res
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    

        # 1. HTTP (Независимый блок + замер пинга)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($res.IP, 80, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(1000)) {
            $tcp.EndConnect($asyn)
            $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
            if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }
            
            $stream = $tcp.GetStream()
            $stream.ReadTimeout = 1000
            $stream.WriteTimeout = 1000
            $msg = "HEAD / HTTP/1.1`r`nHost: $($Target)`r`nUser-Agent: curl/7.88.1`r`nConnection: close`r`n`r`n"
            $buf = [System.Text.Encoding]::ASCII.GetBytes($msg)
            $stream.Write($buf, 0, $buf.Length)
            $readBuf = New-Object byte[] 64
            if ($stream.Read($readBuf, 0, 64) -gt 0) { $res.HTTP = "OK" }
        } else {
            $res.HTTP = "DROP"
        }
        $tcp.Close()
    } catch { $res.HTTP = "ERR" }

    # 2. TLS 1.2 (Независимый блок + замер пинга)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($res.IP, 443, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(1500)) {
            $tcp.EndConnect($asyn)
            $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
            if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            $authAsync = $ssl.BeginAuthenticateAsClient($Target, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false, $null, $null)
            if ($authAsync.AsyncWaitHandle.WaitOne(1500)) {
                $ssl.EndAuthenticateAsClient($authAsync)
                $res.T12 = "OK"
            } else { $res.T12 = "DRP" }
            $ssl.Close()
        } else { $res.T12 = "DRP" }
        $tcp.Close()
    } catch { 
        $errMsg = "$($_.Exception.Message) $($_.Exception.InnerException.Message)"
        if ($errMsg -match "reset|сброшено|forcibly closed|разорвал") { 
            $res.T12 = "RST" 
        } else { 
            $res.T12 = "OK" 
        }
    }

    # 3. TLS 1.3 (Независимый блок)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($res.IP, 443, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(1500)) {
            $tcp.EndConnect($asyn)
            $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
            if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
            $authAsync = $ssl.BeginAuthenticateAsClient($Target, $null, 12288, $false, $null, $null)
            if ($authAsync.AsyncWaitHandle.WaitOne(1500)) {
                $ssl.EndAuthenticateAsClient($authAsync)
                $res.T13 = "OK"
            } else { $res.T13 = "DRP" }
            $ssl.Close()
        } else { $res.T13 = "DRP" }
        $tcp.Close()
    } catch { 
        $errMsg = "$($_.Exception.Message) $($_.Exception.InnerException.Message)"
        if ($errMsg -match "not supported|algorithm|поддерживается|алгоритм|не удается") { 
            $res.T13 = "N/A" 
        } elseif ($errMsg -match "reset|сброшено|forcibly closed|разорвал") { 
            $res.T13 = "RST" 
        } else { 
            $res.T13 = "OK" 
        }
    }

    # Итоговый RESULT
    if ($res.T12 -eq "OK" -or $res.T13 -eq "OK") {
        $res.Verdict = "AVAILABLE"; $res.Color = "Green"
    } elseif ($Target -match "^r\d+.*\.googlevideo\.com" -and $res.T12 -eq "DRP") {
        # Исключение для CDN: если сервер Google молча отбрасывает пакеты (Drop),
        # скорее всего это защита GGC от чужих IP-адресов (когда включен VPN).
        $res.Verdict = "CDN GEO-DROP (VPN?)"; $res.Color = "DarkGray"
    } elseif ($res.HTTP -eq "OK") {
        $res.Verdict = "DPI BLOCK"; $res.Color = "Yellow"
    } elseif ($res.HTTP -eq "ERR" -and $res.T12 -eq "RST" -and $res.T13 -eq "RST") {
        $res.Verdict = "ROUTING ERROR"; $res.Color = "Red"
    } else {
        $res.Verdict = "IP BLOCK"; $res.Color = "Red"
    }

    
    return $res
}

$Pool = [runspacefactory]::CreateRunspacePool(1, 20); $Pool.Open()
$f = 0
$FirstRun = $true
$UI_Y = 30 
$Stats = @{ Clean = 0; Blocked = 0; Rst = 0; Err = 0 }

while ($true) {
    if ($FirstRun) {
    # Сначала рисуем пустой интерфейс
    $EmptyInfo = @{ ConfigDNS="..."; RealDNS="..."; ISP="..."; LOC="..."; CDN="..." }
    Draw-UI $EmptyInfo $BaseTargets $true
    
    # Теперь спокойно (но быстро) собираем инфу
    $NetInfo = Get-NetworkInfo
    $Targets = @($BaseTargets + $NetInfo.CDN | Select-Object -Unique)
    
    # Перерисовываем уже с данными
    Draw-UI $NetInfo $Targets $true
    $FirstRun = $false
    }

    $f++
    if ($f % 5 -eq 0) { 
        $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
        $jobsCount = if ($null -ne $ActiveJobs) { $ActiveJobs.Count } else { 0 }
        $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
        $ramStr = "${ram}MB".PadRight(5) # Жестко фиксируем ширину под 3 цифры + MB
        Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($ActiveJobs.Count.ToString().PadRight(1)) ]".PadRight(28)) "DarkGray"  
        Out-Str 95 2 ("[ BLOCKS: $($Stats.Blocked.ToString().PadRight(2)) | RST: $($Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
        Out-Str 95 3 ("[ CLEAN:  $($Stats.Clean.ToString().PadRight(2)) | ERR: $($Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
    }

    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true).Key
        
        # Жесткий и моментальный выход из программы
        if ($k -eq "Q" -or $k -eq "Escape") { [Environment]::Exit(0) }
        
        if ($k -eq "H") {
            Show-HelpMenu
            Draw-UI $NetInfo $Targets $true
            Out-Str 2 $UI_Y ("[ READY ] [ENTER] START | [H] HELP | [Q] QUIT".PadRight(118)) "Black" "White"
            continue
        }
        
        if ($k -eq "Enter") {
            $Stats.Clean = 0; $Stats.Blocked = 0; $Stats.Rst = 0; $Stats.Err = 0
            Out-Str 2 $UI_Y ("[ WAIT ] REFRESHING NETWORK STATE...".PadRight(118)) "Black" "Cyan"
            $NetInfo = Get-NetworkInfo
            
            $NewTargets = @($BaseTargets + $NetInfo.CDN | Select-Object -Unique)
            $NeedClear = ($NewTargets.Count -ne $Targets.Count)
            $Targets = $NewTargets
            
            Draw-UI $NetInfo $Targets $NeedClear
            $UI_Y = 11 + $Targets.Count + 3
            
            Out-Str 2 $UI_Y ("[ BUSY ] SCANNING IN PROGRESS... PRESS [Q] TO ABORT".PadRight(118)) "Black" "Yellow"
            
            for($i=0; $i -lt $Targets.Count; $i++) { 
                Out-Str $X.Ver (11+$i) ("PREPARING...".PadRight(30)) "DarkGray"
            }
            
            $ActiveJobs = [System.Collections.ArrayList]::new()
            for($i=0; $i -lt $Targets.Count; $i++) {
                $ps = [PowerShell]::Create().AddScript($Worker).AddArgument($Targets[$i])
                $ps.RunspacePool = $Pool
                [void]$ActiveJobs.Add([PSCustomObject]@{ P=$ps; H=$ps.BeginInvoke(); Row=11+$i })
            }

            $Aborted = $false
            
            while ($ActiveJobs.Count -gt 0) {
                $f++

                # --- ЖИВАЯ ТЕЛЕМЕТРИЯ ВО ВРЕМЯ СКАНА ---
                if ($f % 5 -eq 0) { 
                    $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
                    $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
                    $ramStr = "${ram}MB".PadRight(5) # Жестко фиксируем ширину под 3 цифры + MB
                    Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($ActiveJobs.Count.ToString().PadRight(1)) ]".PadRight(28)) "DarkGray"  
                    Out-Str 95 2 ("[ BLOCKS: $($Stats.Blocked.ToString().PadRight(2)) | RST: $($Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
                    Out-Str 95 3 ("[ CLEAN:  $($Stats.Clean.ToString().PadRight(2)) | ERR: $($Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
                }
                # ---------------------------------------

                while ([Console]::KeyAvailable) {
                    $inkey = [Console]::ReadKey($true).Key
                    if ($inkey -eq "Q" -or $inkey -eq "Escape") { $Aborted = $true }
                }
                if ($Aborted) { break }

                $Completed = @()
                foreach($j in $ActiveJobs) {
                    if ($j.H.IsCompleted) {
                        $Completed += $j
                    } else {
                        Out-Str $X.Ver $j.Row ("SCANNING " + (Get-ScanAnim $f $j.Row)).PadRight(30) "Cyan"
                        
                        if ($f % 3 -eq 0) {
                            $rnd1 = Get-Random -Min 10 -Max 255
                            $rnd2 = Get-Random -Min 10 -Max 255
                            $rnd3 = Get-Random -Min 10 -Max 255
                            $rnd4 = Get-Random -Min 10 -Max 255
                            $fakeIP = "$rnd1.$rnd2.$rnd3.$rnd4"
                            Out-Str $X.IP $j.Row ($fakeIP.PadRight(16)) "DarkGray"
                            
                            $fakeLat = "$((Get-Random -Min 5 -Max 99))ms"
                            Out-Str $X.Lat $j.Row ($fakeLat.PadRight(6)) "DarkGray"
                        }
                    }
                }

                foreach($j in $Completed) {
                    $rawOutput = $j.P.EndInvoke($j.H)
                    $res = $rawOutput | Where-Object { $_ -is [PSCustomObject] -and $_.IP } | Select-Object -Last 1
                    
                    if (!$res) {
                        $res = [PSCustomObject]@{ IP="ERROR"; HTTP="--"; T12="--"; T13="--"; Lat="--"; Verdict="THREAD_CRASH"; Color="Red" }
                    }

                    $ipStr  = [string]$res.IP
                    $htStr  = [string]$res.HTTP
                    $t12Str = [string]$res.T12
                    $t13Str = [string]$res.T13
                    $latStr = [string]$res.Lat
                    $verStr = [string]$res.Verdict

                    # --- Подсчет статистики ---
                    if ($verStr -match "AVAILABLE") { $Stats.Clean++ }
                    elseif ($verStr -match "BLOCK") { $Stats.Blocked++ }
                    elseif ($verStr -match "ERR" -or $verStr -match "CRASH") { $Stats.Err++ }
                    
                    if ($t12Str -eq "RST" -or $t13Str -eq "RST") { $Stats.Rst++ }
                    # --------------------------


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
                # Мгновенно обновляем интерфейс
                Out-Str 2 $UI_Y ("[ ABORTED ] SCAN STOPPED. [ENTER] RESTART | [H] HELP | [Q] QUIT".PadRight(118)) "Black" "Red"
                
                # АСИНХРОННАЯ остановка. Мы НЕ вызываем Dispose(), чтобы не заблокировать UI!
                # Потоки сами тихо умрут в фоне через пару секунд по таймауту сети.
                foreach($j in $ActiveJobs) { 
                    try { 
                        $null = $j.P.BeginStop($null, $null)
                    } catch {} 
                }
            } else {
                Out-Str 2 $UI_Y ("[ SUCCESS ] SCAN FINISHED. [ENTER] RESTART | [H] HELP | [Q] QUIT".PadRight(118)) "Black" "Green"
            }
            Clear-KeyBuffer
        }
    }
    [System.Threading.Thread]::Sleep(100)
}