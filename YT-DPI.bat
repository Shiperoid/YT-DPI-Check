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


# --- ГЛОБАЛЬНЫЕ НАСТРОЙКИ ПРОКСИ ---
$global:ProxyConfig = @{
    Enabled = $false
    Type    = "HTTP"   # HTTP / HTTPS (оба работают через CONNECT)
    Host    = ""
    Port    = 0
    User    = ""
    Pass    = ""
}


# --- Сетка координат ---
$X = @{ Dom=2; IP=41; HTTP=59; T12=67; T13=77; Lat=87; Ver=95 }

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

function Get-NetworkInfo {
    #Отключение эсперементального flushdns
    #cmd.exe /c "ipconfig /flushdns >nul 2>&1"
    
    $dns = "UNKNOWN"
    try {
        $wmi = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
        if ($wmi) { $dns = $wmi.DNSServerSearchOrder[0] }
    } catch {}

    $rnd = [guid]::NewGuid().ToString().Substring(0,8)
    $cdn = "manifest.googlevideo.com"
    try {
        $req = [System.Net.WebRequest]::Create("http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd")
        $req.CachePolicy = New-Object System.Net.Cache.HttpRequestCachePolicy([System.Net.Cache.HttpRequestCacheLevel]::NoCacheNoStore)
        $req.KeepAlive = $false
        $req.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
        $req.Timeout = 1500
        $resp = $req.GetResponse()
        $stream = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $raw = $stream.ReadToEnd()
        $resp.Close()
        if ($raw -match "=>\s+([\w-]+)") { $cdn = "r1.$($matches[1]).googlevideo.com" }
    } catch {}

    $isp = "UNKNOWN"
    $loc = "UNKNOWN"
    
    # Делаем максимум 2 быстрые попытки (на случай, если VPN меняет маршрут)
    for ($i = 1; $i -le 2; $i++) {
        try {
            $reqGeo = [System.Net.WebRequest]::Create("http://ip-api.com/json/?fields=status,countryCode,city,isp")
            $reqGeo.CachePolicy = New-Object System.Net.Cache.HttpRequestCachePolicy([System.Net.Cache.HttpRequestCacheLevel]::NoCacheNoStore)
            $reqGeo.KeepAlive = $false
            $reqGeo.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
            $reqGeo.UserAgent = "curl/7.88.1" # Маскировка (без неё ip-api банит)
            $reqGeo.Timeout = 1500
            $respGeo = $reqGeo.GetResponse()
            $streamGeo = New-Object System.IO.StreamReader($respGeo.GetResponseStream())
            $rawGeo = $streamGeo.ReadToEnd()
            $respGeo.Close()

            $geo = $rawGeo | ConvertFrom-Json
            if ($geo.status -eq "success") {
                $isp = $geo.isp -replace '(?i)\s*(LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC)', ''
                if ($isp.Length -gt 25) { $isp = $isp.Substring(0, 22) + '...' }
                $loc = "$($geo.city), $($geo.countryCode)"
                break # Если успешно — сразу выходим из цикла
            }
        } catch {
            # Если это первая попытка и интернета нет (VPN переключается), ждем 1 сек
            if ($i -eq 1) { [System.Threading.Thread]::Sleep(1000) }
        }
    }

    return @{ DNS = $dns; CDN = $cdn; ISP = $isp; LOC = $loc }
}

function Connect-ThroughProxy {
    param($TargetHost, $TargetPort, $ProxyConfig)
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        # Подключаемся к прокси-серверу
        $asyn = $tcp.BeginConnect($ProxyConfig.Host, $ProxyConfig.Port, $null, $null)
        if (-not $asyn.AsyncWaitHandle.WaitOne(2000)) { throw "Timeout connecting to proxy" }
        $tcp.EndConnect($asyn)

        $stream = $tcp.GetStream()
        $stream.ReadTimeout = 2000
        $stream.WriteTimeout = 2000

        # Формируем CONNECT-запрос
        $connectStr = "CONNECT $TargetHost`:$TargetPort HTTP/1.1`r`nHost: $TargetHost`:$TargetPort`r`n"
        if ($ProxyConfig.User -and $ProxyConfig.Pass) {
            $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)"))
            $connectStr += "Proxy-Authorization: Basic $auth`r`n"
        }
        $connectStr += "Proxy-Connection: Keep-Alive`r`n`r`n"

        $buf = [Text.Encoding]::ASCII.GetBytes($connectStr)
        $stream.Write($buf, 0, $buf.Length)

        # Читаем ответ прокси
        $respBuf = New-Object byte[] 256
        $bytesRead = $stream.Read($respBuf, 0, 256)
        $respStr = [Text.Encoding]::ASCII.GetString($respBuf, 0, $bytesRead)

        if ($respStr -match "HTTP/1.[01] 200") {
            return $tcp, $stream   # успешно, возвращаем открытый поток
        } else {
            throw "Proxy refused: $respStr"
        }
    } catch {
        $tcp.Close()
        throw
    }
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


function Show-ProxyMenu {
    [Console]::CursorVisible = $true
    [Console]::Clear()

    Write-Host "=== НАСТРОЙКИ ПРОКСИ ===" -ForegroundColor Cyan
    Write-Host "Текущие настройки:"
    if ($global:ProxyConfig.Enabled) {
        Write-Host "  Включен: Да" -ForegroundColor Green
        Write-Host "  Тип: $($global:ProxyConfig.Type)" -ForegroundColor Yellow
        Write-Host "  Хост: $($global:ProxyConfig.Host)" -ForegroundColor Yellow
        Write-Host "  Порт: $($global:ProxyConfig.Port)" -ForegroundColor Yellow
        if ($global:ProxyConfig.User) { Write-Host "  Логин: $($global:ProxyConfig.User)" -ForegroundColor Yellow }
    } else {
        Write-Host "  Включен: Нет" -ForegroundColor Red
    }

    Write-Host "`nВведите новые настройки (или оставьте пустым для отмены):"

    $type = Read-Host "Тип прокси (HTTP/HTTPS)"
    if ($type -eq "") { 
        [Console]::CursorVisible = $false
        return 
    }
    $hostAddr = Read-Host "Адрес прокси"
    if ($hostAddr -eq "") { 
        [Console]::CursorVisible = $false
        return 
    }
    $port = Read-Host "Порт"
    if ($port -eq "" -or -not ($port -as [int])) { 
        Write-Host "Неверный порт, отмена." -ForegroundColor Red
        [Console]::CursorVisible = $false
        return
    }
    $user = Read-Host "Логин (если нужен, иначе Enter)"
    $pass = Read-Host "Пароль (если нужен, иначе Enter)"

    $global:ProxyConfig.Enabled = $true
    $global:ProxyConfig.Type = $type.ToUpper()
    $global:ProxyConfig.Host = $hostAddr
    $global:ProxyConfig.Port = [int]$port
    $global:ProxyConfig.User = $user
    $global:ProxyConfig.Pass = $pass

    Write-Host "`nНастройки сохранены. Нажмите любую клавишу для возврата..." -ForegroundColor Green
    $null = [Console]::ReadKey($true)
    [Console]::CursorVisible = $false

    # Перерисовываем главный экран
    Draw-UI $NetInfo $Targets $true
    Out-Str 2 $UI_Y ("[ READY ] [ENTER] START | [H] HELP | [P] PROXY | [Q] QUIT".PadRight(118)) "Black" "White"
}


function Draw-UI ($NetInfo, $Targets, $ClearScreen = $true) {
    $LinesNeeded = $Targets.Count + 19
    if ($LinesNeeded -lt 30) { $LinesNeeded = 30 }
    
    if ($ClearScreen) {
        cmd /c "mode con: cols=125 lines=$LinesNeeded"
        [Console]::Clear()
    }
    
    Out-Str 1 1 '██╗   ██╗████████╗    ██████╗ ██████╗ ██╗  _    _____    ____' 'Green'
    Out-Str 1 2 '╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║ | |  / /__ \  / __ \' 'Green'
    Out-Str 1 3 ' ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║ | | / /__/ / / / / /' 'Green'
    Out-Str 1 4 '  ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║ | |/ // __/_/ /_/ /' 'Green'
    Out-Str 1 5 '   ██╝      ██╝       ██████╝ ██╝     ██╝ |___//____(_)____/' 'Green'

    Out-Str 65 1 "> SYSTEM STATUS: [ ONLINE ]" "Green"
    Out-Str 65 2 ("> ACTIVE DNS:    " + $NetInfo.DNS).PadRight(50) "Cyan"
    Out-Str 65 3 "> ENGINE:        Barebuh 0.6" "Red"
    Out-Str 65 4 ("> DETECTED CDN:  " + $NetInfo.CDN).PadRight(50) "Yellow"
    Out-Str 65 5 "> AUTHOR:        https://github.com/Shiperoid/" "Gray"
    # Отрисовка телеметрии вместе с интерфейсом (защита от моргания)
    $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
    $ramStr = "${ram}MB".PadRight(5)
    $jobsCount = if ($null -ne $ActiveJobs) { $ActiveJobs.Count } else { 0 }
    
    Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($jobsCount.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray" 
    Out-Str 95 2 ("[ BLOCKS: $($Stats.Blocked.ToString().PadRight(2)) | RST: $($Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
    Out-Str 95 3 ("[ CLEAN:  $($Stats.Clean.ToString().PadRight(2)) | ERR: $($Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"

    # Компактный вывод провайдера и города
    $ispStr = "> ISP / LOC:     $($NetInfo.ISP) ($($NetInfo.LOC))"
    Out-Str 65 6 ($ispStr.PadRight(58)) "Magenta"

    $proxyStatus = if ($global:ProxyConfig.Enabled) { 
        "PROXY: $($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)" 
    } else { 
        "PROXY: OFF" 
    }
    Out-Str 65 7 ($proxyStatus.PadRight(58)) "DarkYellow"


    $y = 8; $l = "=" * 121
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
    
     # --- ПРОВЕРКА ТИПА ПРОКСИ ---
    if ($global:ProxyConfig.Enabled -and $global:ProxyConfig.Type -notin @("HTTP","HTTPS")) {
        $res.Verdict = "UNSUPPORTED PROXY TYPE"
        return $res
    }

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
    # 1. HTTP c прокси
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = $null
        if ($global:ProxyConfig.Enabled -and $global:ProxyConfig.Type -in @("HTTP","HTTPS")) {
            # Подключение через прокси
            $proxyResult = Connect-ThroughProxy -TargetHost $Target -TargetPort 80 -ProxyConfig $global:ProxyConfig
            $tcp = $proxyResult[0]
            $stream = $proxyResult[1]
            $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
            if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }
            
            # Отправляем HTTP-запрос через уже открытый туннель
            $msg = "HEAD / HTTP/1.1`r`nHost: $($Target)`r`nUser-Agent: curl/7.88.1`r`nConnection: close`r`n`r`n"
            $buf = [System.Text.Encoding]::ASCII.GetBytes($msg)
            $stream.Write($buf, 0, $buf.Length)
            $readBuf = New-Object byte[] 64
            if ($stream.Read($readBuf, 0, 64) -gt 0) { $res.HTTP = "OK" } else { $res.HTTP = "ERR" }
            $tcp.Close()
        } else {
            # Прямое подключение (как было)
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
        }
    } catch { 
        $res.HTTP = "ERR" 
    }

    # 2. TLS 1.2 (Независимый блок + замер пинга)
    # 2. TLS 1.2 с прокси
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        if ($global:ProxyConfig.Enabled -and $global:ProxyConfig.Type -in @("HTTP","HTTPS")) {
            # Через прокси
            $proxyResult = Connect-ThroughProxy -TargetHost $Target -TargetPort 443 -ProxyConfig $global:ProxyConfig
            $tcp = $proxyResult[0]
            $stream = $proxyResult[1]
            $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
            if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

            $ssl = New-Object System.Net.Security.SslStream($stream, $false)
            $authAsync = $ssl.BeginAuthenticateAsClient($Target, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false, $null, $null)
            if ($authAsync.AsyncWaitHandle.WaitOne(1500)) {
                $ssl.EndAuthenticateAsClient($authAsync)
                $res.T12 = "OK"
            } else { $res.T12 = "DRP" }
            $ssl.Close()
            $tcp.Close()
        } else {
            # Прямое подключение (оригинальный код)
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
        }
    } catch { 
        $errMsg = "$($_.Exception.Message) $($_.Exception.InnerException.Message)"
        if ($errMsg -match "reset|сброшено|forcibly closed|разорвал") { 
            $res.T12 = "RST" 
        } else { 
            $res.T12 = "OK" 
        }
    }

    # 3. TLS 1.3 (с поддержкой прокси)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        if ($global:ProxyConfig.Enabled -and $global:ProxyConfig.Type -in @("HTTP","HTTPS")) {
            # Подключение через прокси
            $proxyResult = Connect-ThroughProxy -TargetHost $Target -TargetPort 443 -ProxyConfig $global:ProxyConfig
            $tcp = $proxyResult[0]
            $stream = $proxyResult[1]
            $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
            if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

            $ssl = New-Object System.Net.Security.SslStream($stream, $false)
            $authAsync = $ssl.BeginAuthenticateAsClient($Target, $null, 12288, $false, $null, $null)
            if ($authAsync.AsyncWaitHandle.WaitOne(1500)) {
                $ssl.EndAuthenticateAsClient($authAsync)
                $res.T13 = "OK"
            } else {
                $res.T13 = "DRP"
            }
            $ssl.Close()
            $tcp.Close()
        } else {
            # Прямое подключение (оригинальный код)
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
        }
    } catch { 
        $errMsg = "$($_.Exception.Message) $($_.Exception.InnerException.Message)"
        if ($errMsg -match "not supported|algorithm|поддерживается|алгоритм|не удается") { 
            $res.T13 = "N/A" 
        } elseif ($errMsg -match "reset|сброшено|forcibly closed|разорвал") { 
            $res.T13 = "RST" 
        } else { 
            $res.T13 = "ERR"   # Изменено с "OK" на "ERR" для единообразия
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
        $NetInfo = Get-NetworkInfo
        $Targets = @($BaseTargets + $NetInfo.CDN | Select-Object -Unique)
        Draw-UI $NetInfo $Targets $true
        $UI_Y = 11 + $Targets.Count + 3
        Out-Str 2 $UI_Y ("[ READY ] [ENTER] START | [H] HELP | [Q] QUIT".PadRight(118)) "Black" "White"
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
        
        if ($k -eq "P") {
            Show-ProxyMenu
            # После меню перерисовываем главный экран
            Draw-UI $NetInfo $Targets $true
            Out-Str 2 $UI_Y ("[ READY ] [ENTER] START | [H] HELP | [P] PROXY | [Q] QUIT".PadRight(118)) "Black" "White"
            continue
        }


        if ($k -eq "H") {
            Show-HelpMenu
            Draw-UI $NetInfo $Targets $true
            Out-Str 2 $UI_Y ("[ READY ] [ENTER] START | [H] HELP | [P] PROXY | [Q] QUIT".PadRight(118)) "Black" "White"
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