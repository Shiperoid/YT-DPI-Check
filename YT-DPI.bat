<# :
@echo off
title YT-DPI v2.0 Proxy
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0' -Encoding UTF8) -join [Environment]::NewLine)"
exit /b
#>

$ErrorActionPreference = "SilentlyContinue"
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

# --- ГЛОБАЛЬНЫЕ НАСТРОЙКИ ---
$global:ProxyConfig = @{ Enabled = $false; Type = "HTTP"; Host = ""; Port = 0; User = ""; Pass = "" }
$script:NetInfo = $null
$script:Targets = $null
$script:ActiveJobs = $null
$script:Stats = @{ Clean = 0; Blocked = 0; Rst = 0; Err = 0 }
$X = @{ Dom=2; IP=41; HTTP=59; T12=67; T13=77; Lat=87; Ver=95 }

# ====================================================================================
# Список целей для теста
# ====================================================================================

$BaseTargets = @(
    # 1. Базовая проверка связи (обычно не блокируется)
    "google.com", 
    
    # 2. Сам сайт и короткие ссылки
    "youtube.com", "youtu.be", 
    
    # 3. Серверы картинок (превью видео, аватарки каналов)
    "i.ytimg.com", "yt3.ggpht.com", 
    
    # 4. Ядро плеера (если они в блоке - видео будет бесконечно грузиться)
    "manifest.googlevideo.com", "redirector.googlevideo.com", 
    
    # 5. API Ютуба (отвечает за работу мобильных приложений, Smart TV и комментарии)
    "youtubei.googleapis.com", 
    
    # 6. Авторизация и служебный трафик
    "signaler-pa.youtube.com"
)



#$BaseTargets = @(
#    "google.com", "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
#    "i.ytimg.com", "i9.ytimg.com", "s.ytimg.com", "yt3.ggpht.com", "yt4.ggpht.com",
#    "googleusercontent.com", "yt3.googleusercontent.com", "googlevideo.com",
#    "manifest.googlevideo.com", "redirector.googlevideo.com", "googleapis.com",
#    "youtubei.googleapis.com", "youtubeembeddedplayer.googleapis.com", "youtubekids.com",
#    "signaler-pa.youtube.com"
#)

# ====================================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ И UI
# ====================================================================================

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
    Out-Str 65 3 "> ENGINE:        Cherkash 1.3" "Red"
    Out-Str 65 4 ("> DETECTED CDN:  " + $NetInfo.CDN).PadRight(50) "Yellow"
    Out-Str 65 5 "> AUTHOR:        https://github.com/Shiperoid/" "Gray"
    
    $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB)
    $ramStr = "${ram}MB".PadRight(5)
    $jobsCount = if ($null -ne $script:ActiveJobs) { $script:ActiveJobs.Count } else { 0 }
    
    Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($jobsCount.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray" 
    Out-Str 95 2 ("[ BLOCKS: $($script:Stats.Blocked.ToString().PadRight(2)) | RST: $($script:Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
    Out-Str 95 3 ("[ CLEAN:  $($script:Stats.Clean.ToString().PadRight(2)) | ERR: $($script:Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"

    $ispStr = "> ISP / LOC:     $($NetInfo.ISP) ($($NetInfo.LOC))"
    Out-Str 65 6 ($ispStr.PadRight(58)) "Magenta"

    $proxyStatus = if ($global:ProxyConfig.Enabled) { "PROXY: $($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)" } else { "PROXY: OFF" }
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

# ====================================================================================
# СЕТЕВЫЕ И ПРОКСИ ФУНКЦИИ (ГЛОБАЛЬНЫЕ)
# ====================================================================================

function Connect-ThroughSocks5($TargetHost, $TargetPort, $ProxyConfig) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $asyn = $tcp.BeginConnect($ProxyConfig.Host, $ProxyConfig.Port, $null, $null)
        if (-not $asyn.AsyncWaitHandle.WaitOne(3000)) { throw "Timeout SOCKS5" }
        $tcp.EndConnect($asyn)
        $stream = $tcp.GetStream(); $stream.ReadTimeout = 3000; $stream.WriteTimeout = 3000

        $methods = @(0x00); if ($ProxyConfig.User -and $ProxyConfig.Pass) { $methods += 0x02 }
        $stream.Write(([byte[]]@(0x05, $methods.Length) + $methods), 0, $methods.Length + 2)
        $resp = New-Object byte[] 2
        if ($stream.Read($resp, 0, 2) -ne 2) { throw "No response" }
        
        if ($resp[1] -eq 0x02) {
            $u = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.User); $p = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.Pass)
            $authReq = [byte[]]@(0x01, $u.Length) + $u + [byte[]]@($p.Length) + $p
            $stream.Write($authReq, 0, $authReq.Length)
            if ($stream.Read($resp, 0, 2) -ne 2 -or $resp[1] -ne 0x00) { throw "Auth failed" }
        }

        $ipObj = $null
        if ([System.Net.IPAddress]::TryParse($TargetHost, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork') {
            $req = [byte[]]@(0x05, 0x01, 0x00, 0x01) + $ipObj.GetAddressBytes()
        } else {
            $h = [Text.Encoding]::UTF8.GetBytes($TargetHost)
            $req = [byte[]]@(0x05, 0x01, 0x00, 0x03, $h.Length) + $h
        }
        $req += [byte[]]@( [math]::Floor($TargetPort / 256), ($TargetPort % 256) )
        $stream.Write($req, 0, $req.Length)

        $buf = New-Object byte[] 255
        if ($stream.Read($buf, 0, 10) -lt 4 -or $buf[1] -ne 0x00) { throw "SOCKS5 routing failed" }
        return @{ Tcp = $tcp; Stream = $stream }
    } catch { $tcp.Close(); throw }
}

function Connect-ThroughProxy($TargetHost, $TargetPort, $ProxyConfig) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $asyn = $tcp.BeginConnect($ProxyConfig.Host, $ProxyConfig.Port, $null, $null)
        if (-not $asyn.AsyncWaitHandle.WaitOne(3000)) { throw "Timeout HTTP Proxy" }
        $tcp.EndConnect($asyn)
        $stream = $tcp.GetStream(); $stream.ReadTimeout = 3000; $stream.WriteTimeout = 3000
        
        $h = if ($TargetHost -match ":") { "[$TargetHost]" } else { $TargetHost }
        $req = "CONNECT $h`:$TargetPort HTTP/1.1`r`nHost: $h`:$TargetPort`r`n"
        if ($ProxyConfig.User -and $ProxyConfig.Pass) {
            $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)"))
            $req += "Proxy-Authorization: Basic $auth`r`n"
        }
        $req += "Proxy-Connection: Keep-Alive`r`n`r`n"
        
        $buf = [Text.Encoding]::ASCII.GetBytes($req)
        $stream.Write($buf, 0, $buf.Length)
        
        $resp = New-Object byte[] 512
        $read = $stream.Read($resp, 0, 512)
        if ([Text.Encoding]::ASCII.GetString($resp, 0, $read) -match "HTTP/1.[01]\s+200") { 
            return @{ Tcp = $tcp; Stream = $stream } 
        } else { throw "Proxy refused" }
    } catch { $tcp.Close(); throw }
}

function Get-NetworkInfo {
    $dns = "UNKNOWN"
    try {
        $wmi = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
        if ($wmi) { $dns = $wmi.DNSServerSearchOrder[0] }
    } catch {}

    function Invoke-SmartGet($HostName, $Path) {
        $url = "http://$HostName$Path"
        if (-not $global:ProxyConfig.Enabled -or $global:ProxyConfig.Type -in @("HTTP", "HTTPS")) {
            try {
                $req = [System.Net.WebRequest]::Create($url)
                $req.Timeout = 2000; $req.UserAgent = "curl/7.88.1"; $req.KeepAlive = $false
                if ($global:ProxyConfig.Enabled) {
                    $wp = New-Object System.Net.WebProxy($global:ProxyConfig.Host, $global:ProxyConfig.Port)
                    if ($global:ProxyConfig.User) { $wp.Credentials = New-Object System.Net.NetworkCredential($global:ProxyConfig.User, $global:ProxyConfig.Pass) }
                    $req.Proxy = $wp
                } else { $req.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy() }
                $resp = $req.GetResponse(); $r = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd(); $resp.Close(); return $r
            } catch { return "" }
        } else {
            try {
                $conn = Connect-ThroughSocks5 $HostName 80 $global:ProxyConfig
                $req = [Text.Encoding]::ASCII.GetBytes("GET $Path HTTP/1.0`r`nHost: $HostName`r`nUser-Agent: curl/7.88.1`r`nConnection: close`r`n`r`n")
                $conn.Stream.Write($req, 0, $req.Length)
                $buf = New-Object byte[] 4096; $respBytes = New-Object System.Collections.Generic.List[byte]
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                while ($sw.ElapsedMilliseconds -lt 2000) {
                    if ($conn.Stream.DataAvailable) {
                        $read = $conn.Stream.Read($buf, 0, 4096)
                        if ($read -gt 0) { for ($i=0; $i -lt $read; $i++) { $respBytes.Add($buf[$i]) } } else { break }
                    } elseif ($respBytes.Count -gt 0) { break }
                    else { [System.Threading.Thread]::Sleep(50) }
                }
                $conn.Tcp.Close()
                $parts = ([Text.Encoding]::UTF8.GetString($respBytes.ToArray())) -split "`r`n`r`n", 2
                if ($parts.Length -eq 2) { return $parts[1] }
            } catch {}
        }
        return ""
    }

    $rnd = [guid]::NewGuid().ToString().Substring(0,8)
    $cdn = "manifest.googlevideo.com"
    if ((Invoke-SmartGet "redirector.googlevideo.com" "/report_mapping?di=no&nocache=$rnd") -match "=>\s+([\w-]+)") { $cdn = "r1.$($matches[1]).googlevideo.com" }

    $isp = "UNKNOWN"; $loc = "UNKNOWN"
    for ($i = 1; $i -le 2; $i++) {
        $rawGeo = Invoke-SmartGet "ip-api.com" "/json/?fields=status,countryCode,city,isp"
        if ($rawGeo -match "(?s)(\{.*\})") {
            try {
                $geo = $matches[1] | ConvertFrom-Json
                if ($geo.status -eq "success") {
                    $isp = $geo.isp -replace '(?i)\s*(LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC)', ''
                    if ($isp.Length -gt 25) { $isp = $isp.Substring(0, 22) + '...' }
                    $loc = "$($geo.city), $($geo.countryCode)"
                    break
                }
            } catch {}
        }
        if ($i -eq 1) { [System.Threading.Thread]::Sleep(500) }
    }
    return @{ DNS = $dns; CDN = $cdn; ISP = $isp; LOC = $loc }
}

function Show-ProxyMenu {
    [Console]::CursorVisible = $true; [Console]::Clear()
    Write-Host "=== НАСТРОЙКИ ПРОКСИ ===" -ForegroundColor Cyan
    
    if ($global:ProxyConfig.Enabled) {
        Write-Host "  [ СТАТУС ]  ВКЛЮЧЕН" -ForegroundColor Green
        Write-Host "  [ ТИП ]     $($global:ProxyConfig.Type)" -ForegroundColor Yellow
        Write-Host "  [ АДРЕС ]   $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)" -ForegroundColor Yellow
        if ($global:ProxyConfig.User) { Write-Host "  [ ЛОГИН ]   $($global:ProxyConfig.User)" -ForegroundColor Yellow }
    } else { 
        Write-Host "  [ СТАТУС ]  ОТКЛЮЧЕН" -ForegroundColor DarkGray 
    }

    Write-Host "`n=== ПОДДЕРЖИВАЕМЫЕ ТИПЫ: HTTP / HTTPS / SOCKS5 ===" -ForegroundColor Cyan
    Write-Host "  1. Автоопределение:     " -NoNewline; Write-Host "127.0.0.1:8080 " -ForegroundColor Gray -NoNewline; Write-Host "(Скрипт сам поймет тип)" -ForegroundColor DarkGray
    Write-Host "  2. Явное указание:      " -NoNewline; Write-Host "socks5://192.168.1.1:1080" -ForegroundColor Gray
    Write-Host "  3. С логином и паролем: " -NoNewline; Write-Host "http://user:pass@10.0.0.1:3128" -ForegroundColor Gray
    Write-Host "  4. Отключить прокси:    " -NoNewline; Write-Host "Введите 0 или OFF" -ForegroundColor Gray
    Write-Host "  5. Отмена:              " -NoNewline; Write-Host "Просто нажмите Enter" -ForegroundColor Gray

    Write-Host "`n> Введите прокси: " -ForegroundColor Yellow -NoNewline
    $inputStr = Read-Host

    if ([string]::IsNullOrWhiteSpace($inputStr)) { 
        [Console]::CursorVisible = $false; return 
    }
    
    if ($inputStr -eq "0" -or $inputStr.ToUpper() -eq "OFF") {
        $global:ProxyConfig.Enabled = $false
        Write-Host "`n[V] Прокси успешно отключен." -ForegroundColor Green
        Start-Sleep -Seconds 1
        [Console]::CursorVisible = $false; return
    }

    # Регулярка для парсинга (протокол, юзер, пароль, хост, порт)
    $pattern = '^(?i)(?:(?<type>http|https|socks5)://)?(?:(?<user>[^:]+):(?<pass>[^@]+)@)?(?<host>[^:/]+|\[[a-f0-9:]+\]):(?<port>\d{1,5})$'
    
    if ($inputStr -match $pattern) {
        $t = $matches['type']
        $h = $matches['host']
        $p = [int]$matches['port']
        $u = $matches['user']
        $pw = $matches['pass']

        if ($p -le 0 -or $p -gt 65535) {
            Write-Host "`n[x] Ошибка: Неверный порт!" -ForegroundColor Red
            Start-Sleep -Seconds 2
            [Console]::CursorVisible = $false; return
        }

        # --- УМНОЕ АВТООПРЕДЕЛЕНИЕ ТИПА ПРОКСИ ЧЕРЕЗ БОЕВОЙ ТЕСТ ---
        if (!$t) {
            Write-Host "`n[*] Тип не указан. Запускаю автоопределение..." -ForegroundColor DarkGray
            
            # Временный конфиг для тестов
            $tempConf = @{ Host=$h; Port=$p; User=$u; Pass=$pw; Type="SOCKS5" }
            $detected = "HTTP" # Значение на случай, если сервер вообще мертв
            
            try {
                Write-Host "  -> Проверка SOCKS5... " -NoNewline -ForegroundColor DarkGray
                $c = Connect-ThroughSocks5 "google.com" 80 $tempConf
                $detected = "SOCKS5"
                $c.Tcp.Close()
                Write-Host "OK!" -ForegroundColor Green
            } catch {
                Write-Host "Нет ($($_.Exception.Message))" -ForegroundColor Red
                
                try {
                    Write-Host "  -> Проверка HTTP...   " -NoNewline -ForegroundColor DarkGray
                    $tempConf.Type = "HTTP"
                    $c = Connect-ThroughProxy "google.com" 80 $tempConf
                    $detected = "HTTP"
                    $c.Tcp.Close()
                    Write-Host "OK!" -ForegroundColor Green
                } catch {
                    Write-Host "Нет ($($_.Exception.Message))" -ForegroundColor Red
                    Write-Host "  [!] Сервер не ответил на тесты. Оставляем HTTP по умолчанию." -ForegroundColor DarkGray
                }
            }
            $t = $detected
            Write-Host "  => Итоговый тип: $t" -ForegroundColor Cyan
        }

        $global:ProxyConfig.Enabled = $true
        $global:ProxyConfig.Type = $t.ToUpper()
        $global:ProxyConfig.Host = $h
        $global:ProxyConfig.Port = $p
        $global:ProxyConfig.User = $u
        $global:ProxyConfig.Pass = $pw

        Write-Host "`n[V] Настройки успешно сохранены!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    } else {
        Write-Host "`n[x] Ошибка: Неверный формат! Попробуйте снова." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }

    [Console]::CursorVisible = $false
}

function Test-ProxyConnection {
    [Console]::Clear()
    Write-Host "=== ТЕСТ ПРОКСИ ===" -ForegroundColor Cyan
    if (-not $global:ProxyConfig.Enabled) { Write-Host "Прокси отключён." -ForegroundColor Red; Start-Sleep 2; return }
    
    Write-Host "Подключение к google.com:80 через $($global:ProxyConfig.Type)..." -ForegroundColor Yellow
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        if ($global:ProxyConfig.Type -eq "SOCKS5") { $c = Connect-ThroughSocks5 "google.com" 80 $global:ProxyConfig }
        else { $c = Connect-ThroughProxy "google.com" 80 $global:ProxyConfig }
        
        Write-Host "Соединение установлено за $($sw.ElapsedMilliseconds)мс!" -ForegroundColor Green
        $req = [Text.Encoding]::ASCII.GetBytes("HEAD / HTTP/1.1`r`nHost: google.com`r`nConnection: close`r`n`r`n")
        $c.Stream.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 64
        if ($c.Stream.Read($buf, 0, 64) -gt 0) { Write-Host "HTTP-запрос успешно прошел!" -ForegroundColor Green }
        $c.Tcp.Close()
    } catch { Write-Host "ОШИБКА: $_" -ForegroundColor Red }
    
    Write-Host "`nНажмите любую клавишу..." -ForegroundColor Cyan; $null = [Console]::ReadKey($true)
}

function Show-HelpMenu {
    [Console]::Clear()
    Out-Str 2 2 "=== YT-DPI : MINI GUIDE ===" "Cyan"
    
    Out-Str 2 4 "[ STATUS CODES ]" "Yellow"
    Out-Str 4 5 "OK   - Connection successful (Cert validation ignored for testing)." "Green"
    Out-Str 4 6 "RST  - Connection Reset. DPI injected a TCP RST packet." "Red"
    Out-Str 4 7 "DRP  - Connection Dropped (Blackholed/Timeout during handshake)." "Red"
    Out-Str 4 8 "N/A  - Not Available (e.g., Windows 7/10 lacking TLS 1.3 support)." "DarkGray"
    Out-Str 4 9 "FAIL - Connection failed or general socket error." "Red"
    
    Out-Str 2 11 "[ RESULT ]" "Yellow"
    Out-Str 4 12 "AVAILABLE     - TLS passed. Domain is fully accessible." "Green"
    Out-Str 4 13 "DPI BLOCK     - HTTP works, but TLS is blocked/dropped (Typical DPI)." "Yellow"
    Out-Str 4 14 "IP  BLOCK     - Both HTTP and TLS are unreachable (Hard block/Dead node)." "Red"
    Out-Str 4 15 "ROUTING ERROR - Network issues, proxy failure, or bad routing." "Red"

    Out-Str 2 17 "[ PROXY MODE ]" "Yellow"
    Out-Str 4 18 "[ *PROXIED* ] - DNS resolution is safely handled by the remote proxy." "Cyan"
    
    Out-Str 2 21 "PRESS ANY KEY TO RETURN TO SCANNER..." "Cyan"
    Clear-KeyBuffer; $null = [Console]::ReadKey($true); Clear-KeyBuffer
}

# ====================================================================================
# РАБОЧИЙ ПОТОК
# ====================================================================================

$Worker = {
    param($Target, $ProxyConfig)
    $res = [PSCustomObject]@{ IP="FAILED"; HTTP="FAIL"; T12="FAIL"; T13="FAIL"; Lat="0ms"; Verdict="DNS_ERR"; Color="Red" }
    
    if (-not $ProxyConfig.Enabled) {
        try {
            $dns = [System.Net.Dns]::GetHostAddresses($Target)
            if (!$dns) { return $res }
            $res.IP = $dns[0].IPAddressToString
        } catch { return $res }
    } else { $res.IP = "[ *PROXIED* ]" }

    function Get-Connection($Port) {
        if ($ProxyConfig.Enabled) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $asyn = $tcp.BeginConnect($ProxyConfig.Host, $ProxyConfig.Port, $null, $null)
            if (-not $asyn.AsyncWaitHandle.WaitOne(2000)) { throw "Proxy Timeout" }
            $tcp.EndConnect($asyn)
            $stream = $tcp.GetStream(); $stream.ReadTimeout = 2000; $stream.WriteTimeout = 2000

            if ($ProxyConfig.Type -eq "SOCKS5") {
                $m = @(0x00); if ($ProxyConfig.User) { $m += 0x02 }
                [void]$stream.Write(([byte[]]@(0x05, $m.Length) + $m), 0, $m.Length + 2)
                $r = New-Object byte[] 2; if ($stream.Read($r, 0, 2) -ne 2) { throw "Err" }
                if ($r[1] -eq 0x02) {
                    $u = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.User); $p = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.Pass)
                    $auth = [byte[]]@(0x01, $u.Length) + $u + [byte[]]@($p.Length) + $p
                    [void]$stream.Write($auth, 0, $auth.Length)
                    if ($stream.Read($r, 0, 2) -ne 2 -or $r[1] -ne 0x00) { throw "Auth Fail" }
                }
                $h = [Text.Encoding]::UTF8.GetBytes($Target)
                $req = [byte[]]@(0x05, 0x01, 0x00, 0x03, $h.Length) + $h + [byte[]]@([math]::Floor($Port/256), ($Port%256))
                [void]$stream.Write($req, 0, $req.Length)
                $buf = New-Object byte[] 255; if ($stream.Read($buf, 0, 10) -lt 4 -or $buf[1] -ne 0x00) { throw "Route Fail" }
                return @{ Tcp = $tcp; Stream = $stream }
            } else {
                $authStr = ""
                if ($ProxyConfig.User) { $authStr = "Proxy-Authorization: Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)")) + "`r`n" }
                $req = [Text.Encoding]::ASCII.GetBytes("CONNECT $Target`:$Port HTTP/1.1`r`nHost: $Target`:$Port`r`n${authStr}Proxy-Connection: Keep-Alive`r`n`r`n")
                [void]$stream.Write($req, 0, $req.Length)
                $buf = New-Object byte[] 256; $read = $stream.Read($buf, 0, 256)
                if ([Text.Encoding]::ASCII.GetString($buf, 0, $read) -match "HTTP/1.[01]\s+200") { return @{ Tcp = $tcp; Stream = $stream } }
                throw "Proxy Refused"
            }
        } else {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $asyn = $tcp.BeginConnect($res.IP, $Port, $null, $null)
            if (-not $asyn.AsyncWaitHandle.WaitOne(1500)) { throw "Timeout" }
            $tcp.EndConnect($asyn)
            $stream = $tcp.GetStream(); $stream.ReadTimeout = 1500; $stream.WriteTimeout = 1500
            return @{ Tcp = $tcp; Stream = $stream }
        }
    }

    #!!! не пихать $certCallback = { param... return $true } внутрь потока, слоамает работу
    # 1. HTTP
    $conn = $null
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $conn = Get-Connection 80
        $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
        if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

        $conn.Stream.ReadTimeout = 2000
        $msg = [System.Text.Encoding]::ASCII.GetBytes("HEAD / HTTP/1.1`r`nHost: $($Target)`r`nUser-Agent: curl/7.88.1`r`nConnection: close`r`n`r`n")
        [void]$conn.Stream.Write($msg, 0, $msg.Length)
        $buf = New-Object byte[] 64
        if ($conn.Stream.Read($buf, 0, 64) -gt 0) { $res.HTTP = "OK" } else { $res.HTTP = "DROP" }
    } catch { 
        $res.HTTP = if ($_.Exception.Message -match "Timeout") { "DROP" } else { "ERR" } 
    } finally {
        if ($null -ne $conn) { try { $conn.Tcp.Close(); $conn.Tcp.Dispose() } catch {} }
    }

    # 2. TLS 1.2
    $conn = $null
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $conn = Get-Connection 443
        $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
        if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

        $ssl = New-Object System.Net.Security.SslStream($conn.Stream, $false)
        $authAsync = $ssl.BeginAuthenticateAsClient($Target, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false, $null, $null)
        
        if ($authAsync.AsyncWaitHandle.WaitOne(3500)) { 
            $ssl.EndAuthenticateAsClient($authAsync); $res.T12 = "OK" 
        } else { $res.T12 = "DRP" }
        $ssl.Close()
    } catch { 
        $err = $_.Exception.Message; if ($_.Exception.InnerException) { $err += " " + $_.Exception.InnerException.Message }
        if ($err -match "certificate|сертификат|подлинности|validation") { $res.T12 = "OK" }
        elseif ($err -match "reset|сброшено|forcibly closed|разорвал") { $res.T12 = "RST" } 
        else { $res.T12 = "DRP" } 
    } finally {
        if ($null -ne $conn) { try { $conn.Tcp.Close(); $conn.Tcp.Dispose() } catch {} }
    }

    # 3. TLS 1.3
    $conn = $null
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $conn = Get-Connection 443
        $lat = $sw.ElapsedMilliseconds; if ($lat -eq 0) { $lat = 1 }
        if ($res.Lat -eq "0ms") { $res.Lat = "${lat}ms" }

        $ssl = New-Object System.Net.Security.SslStream($conn.Stream, $false)
        $authAsync = $ssl.BeginAuthenticateAsClient($Target, $null, 12288, $false, $null, $null)
        
        if ($authAsync.AsyncWaitHandle.WaitOne(3500)) { 
            $ssl.EndAuthenticateAsClient($authAsync); $res.T13 = "OK" 
        } else { $res.T13 = "DRP" }
        $ssl.Close()
    } catch { 
        $err = $_.Exception.Message; if ($_.Exception.InnerException) { $err += " " + $_.Exception.InnerException.Message }
        if ($err -match "certificate|сертификат|подлинности|validation") { $res.T13 = "OK" }
        elseif ($err -match "not supported|algorithm|поддерживается|алгоритм") { $res.T13 = "N/A" } 
        elseif ($err -match "reset|сброшено|forcibly closed|разорвал") { $res.T13 = "RST" } 
        else { $res.T13 = "DRP" }
    } finally {
        if ($null -ne $conn) { try { $conn.Tcp.Close(); $conn.Tcp.Dispose() } catch {} }
    }

    if ($res.T12 -eq "OK" -or $res.T13 -eq "OK") { $res.Verdict = "AVAILABLE"; $res.Color = "Green" } 
    elseif ($res.HTTP -eq "OK") { $res.Verdict = "DPI BLOCK"; $res.Color = "Yellow" } 
    elseif ($res.HTTP -eq "ERR" -and $res.T12 -eq "RST" -and $res.T13 -eq "RST") { $res.Verdict = "ROUTING ERROR"; $res.Color = "Red" } 
    else { $res.Verdict = "IP BLOCK"; $res.Color = "Red" }
    
    return $res
}

# ====================================================================================
# ГЛАВНЫЙ ЦИКЛ ПРОГРАММЫ
# ====================================================================================

$Pool = [runspacefactory]::CreateRunspacePool(1, 20); $Pool.Open()
$f = 0; $FirstRun = $true; $UI_Y = 30 
$NavStr = "[ READY ] [ENTER] START | [H] HELP | [P] PROXY | [S] SAVE | [Q] QUIT".PadRight(121)

while ($true) {
    if ($FirstRun) {
        $script:NetInfo = Get-NetworkInfo
        $script:Targets = @($BaseTargets + $script:NetInfo.CDN | Select-Object -Unique)
        Draw-UI $script:NetInfo $script:Targets $true
        $UI_Y = 11 + $script:Targets.Count + 3
        Out-Str 2 $UI_Y $NavStr "Black" "White"
        $FirstRun = $false
    }

    $f++
    if ($f % 5 -eq 0) { 
        $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB); $ramStr = "${ram}MB".PadRight(5)
        $jobsCount = if ($null -ne $script:ActiveJobs) { $script:ActiveJobs.Count } else { 0 }
        Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($jobsCount.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"  
        Out-Str 95 2 ("[ BLOCKS: $($script:Stats.Blocked.ToString().PadRight(2)) | RST: $($script:Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
        Out-Str 95 3 ("[ CLEAN:  $($script:Stats.Clean.ToString().PadRight(2)) | ERR: $($script:Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
    }

    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true).Key
        
        if ($k -eq "Q" -or $k -eq "Escape") { [Environment]::Exit(0) }
        elseif ($k -eq "H") { Show-HelpMenu; Draw-UI $script:NetInfo $script:Targets $true; Out-Str 2 $UI_Y $NavStr "Black" "White"; continue }
        elseif ($k -eq "P") { Show-ProxyMenu; Draw-UI $script:NetInfo $script:Targets $true; Out-Str 2 $UI_Y $NavStr "Black" "White"; continue }
        elseif ($k -eq "T") { Test-ProxyConnection; Draw-UI $script:NetInfo $script:Targets $true; Out-Str 2 $UI_Y $NavStr "Black" "White"; continue }
        
        elseif ($k -eq "S") { 
            Out-Str 2 $UI_Y ("[ WAIT ] SAVING RESULTS TO FILE...".PadRight(121)) "Black" "Cyan"
            # Используем текущую директорию консоли вместо пустой переменной скрипта
            $logPath = Join-Path -Path (Get-Location).Path -ChildPath "YT-DPI_Report.txt"
            $logContent = "=== YT-DPI REPORT ===`r`n"
            $logContent += "TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
            $logContent += "ISP:  $($script:NetInfo.ISP) ($($script:NetInfo.LOC))`r`n"
            $logContent += "DNS:  $($script:NetInfo.DNS)`r`n"
            $logContent += "PROXY: $(if($global:ProxyConfig.Enabled) {"$($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)"} else {"OFF"})`r`n"
            $logContent += "-" * 90 + "`r`n"
            $logContent += "{0,-38} {1,-16} {2,-6} {3,-8} {4,-8} {5,-6} {6}`r`n" -f "TARGET DOMAIN", "IP ADDRESS", "HTTP", "TLS 1.2", "TLS 1.3", "LAT", "RESULT"
            $logContent += "-" * 90 + "`r`n"
            
            # Читаем данные прямо с экрана (из массива Targets)
            # Чтобы не усложнять, мы просто парсим то, что уже протестировано
            foreach($j in $script:ActiveJobs) {
                if ($j.Done) {
                    $res = $j.P.EndInvoke($j.H) | Where-Object { $_ -is [PSCustomObject] -and $null -ne $_.IP } | Select-Object -Last 1
                    if ($res) {
                        $ip = if($global:ProxyConfig.Enabled) {"[ PROXIED ]"} else {$res.IP}
                        $logContent += "{0,-38} {1,-16} {2,-6} {3,-8} {4,-8} {5,-6} {6}`r`n" -f $script:Targets[$j.Row-11], $ip, $res.HTTP, $res.T12, $res.T13, $res.Lat, $res.Verdict
                    }
                }
            }
            [IO.File]::WriteAllText($logPath, $logContent)
            Out-Str 2 $UI_Y ("[ SUCCESS ] SAVED TO: $logPath".PadRight(121)) "Black" "Green"
            Start-Sleep -Seconds 2
            Out-Str 2 $UI_Y $NavStr "Black" "White"
            continue 
        }

        if ($k -eq "Enter") {
            $script:Stats.Clean = 0; $script:Stats.Blocked = 0; $script:Stats.Rst = 0; $script:Stats.Err = 0
            Out-Str 2 $UI_Y ("[ WAIT ] REFRESHING NETWORK STATE...".PadRight(121)) "Black" "Cyan"
            $script:NetInfo = Get-NetworkInfo
            
            $NewTargets = @($BaseTargets + $script:NetInfo.CDN | Select-Object -Unique)
            $NeedClear = ($NewTargets.Count -ne $script:Targets.Count)
            $script:Targets = $NewTargets
            
            Draw-UI $script:NetInfo $script:Targets $NeedClear
            $UI_Y = 11 + $script:Targets.Count + 3
            Out-Str 2 $UI_Y ("[ BUSY ] SCANNING IN PROGRESS... PRESS [Q] TO ABORT".PadRight(121)) "Black" "Yellow"
            for($i=0; $i -lt $script:Targets.Count; $i++) { Out-Str $X.Ver (11+$i) ("PREPARING...".PadRight(30)) "DarkGray" }
            
            $script:ActiveJobs = @()
            for($i=0; $i -lt $script:Targets.Count; $i++) {
                $ps = [PowerShell]::Create().AddScript($Worker).AddArgument($script:Targets[$i]).AddArgument($global:ProxyConfig)
                $ps.RunspacePool = $Pool
                $script:ActiveJobs += [PSCustomObject]@{ P=$ps; H=$ps.BeginInvoke(); Row=(11+$i); Done=$false }
            }

            $Aborted = $false
            
            while ($true) {
                $f++
                $AllDone = $true 
                
                if ($f % 20 -eq 0) { 
                    $ram = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB); $ramStr = "${ram}MB".PadRight(5)
                    Out-Str 95 1 ("[ RAM: $ramStr | JOBS: $($script:ActiveJobs.Count.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"  
                    Out-Str 95 2 ("[ BLOCKS: $($script:Stats.Blocked.ToString().PadRight(2)) | RST: $($script:Stats.Rst.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
                    Out-Str 95 3 ("[ CLEAN:  $($script:Stats.Clean.ToString().PadRight(2)) | ERR: $($script:Stats.Err.ToString().PadRight(2)) ]".PadRight(28)) "DarkGray"
                }

                while ([Console]::KeyAvailable) { if ([Console]::ReadKey($true).Key -in @("Q","Escape")) { $Aborted = $true } }
                if ($Aborted) { break }

                foreach($j in $script:ActiveJobs) {
                    if ($j.Done) { continue } 
                    
                    $AllDone = $false 

                    if ($j.H.IsCompleted) {
                        $raw = $j.P.EndInvoke($j.H)
                        $res = $null
                        
                        # Более надежный поиск объекта без жесткой привязки к типу
                        if ($raw) { 
                            foreach($item in $raw) { 
                                if ($item -and $null -ne $item.IP -and $null -ne $item.Verdict) { 
                                    $res = $item 
                                } 
                            } 
                        }
                        
                        if (!$res) { $res = [PSCustomObject]@{ IP="ERROR"; HTTP="--"; T12="--"; T13="--"; Lat="--"; Verdict="THREAD_CRASH"; Color="Red" } }

                        $v = [string]$res.Verdict
                        if ($v -match "AVAILABLE") { $script:Stats.Clean++ } elseif ($v -match "BLOCK") { $script:Stats.Blocked++ } elseif ($v -match "ERR" -or $v -match "CRASH") { $script:Stats.Err++ }
                        if ($res.T12 -eq "RST" -or $res.T13 -eq "RST") { $script:Stats.Rst++ }

                        # Безопасное присвоение переменных перед выводом (как в старой версии)
                        $ipStr  = [string]$res.IP
                        $htStr  = [string]$res.HTTP
                        $t12Str = [string]$res.T12
                        $t13Str = [string]$res.T13
                        $latStr = [string]$res.Lat

                        Out-Str $X.IP   $j.Row ($ipStr.PadRight(16)) "DarkGray"
                        
                        $hCol = if($htStr -eq "OK") {"Green"} else {"Red"}
                        Out-Str $X.HTTP $j.Row ($htStr.PadRight(6)) $hCol
                        
                        $t12Col = if($t12Str -eq "OK") {"Green"} else {"Red"}
                        Out-Str $X.T12  $j.Row ($t12Str.PadRight(8)) $t12Col
                        
                        $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A") {"Gray"} else {"Red"}
                        Out-Str $X.T13  $j.Row ($t13Str.PadRight(8)) $t13Col
                        
                        Out-Str $X.Lat  $j.Row ($latStr.PadRight(6)) "Cyan"
                        Out-Str $X.Ver  $j.Row ($v.PadRight(30)) $res.Color
                        
                        $j.Done = $true 
                    } else {
                        Out-Str $X.Ver $j.Row ("SCANNING " + (Get-ScanAnim $f $j.Row)).PadRight(30) "Cyan"
                        if ($f % 4 -eq 0) {
                            # Если прокси включен - пишем статику, если выключен - анимируем цифры
                            if ($global:ProxyConfig.Enabled) {
                                Out-Str $X.IP $j.Row ("[ *PROXIED* ]".PadRight(16)) "DarkGray"
                            } else {
                                $rnd1 = Get-Random -Min 10 -Max 255; $rnd2 = Get-Random -Min 10 -Max 255
                                Out-Str $X.IP $j.Row ("$rnd1.$rnd2.$($j.Row).$($f%255)".PadRight(16)) "DarkGray"
                            }
                            
                            # Анимацию пинга оставляем для красоты процесса
                            Out-Str $X.Lat $j.Row ("$((Get-Random -Min 15 -Max 99))ms".PadRight(6)) "DarkGray"
                        }
                    }
                }
                
                if ($AllDone) { break } 
                [System.Threading.Thread]::Sleep(50) 
            }
            
            foreach($j in $script:ActiveJobs) {
                try { 
                    if ($Aborted) { $null = $j.P.BeginStop($null, $null) }
                    $j.P.Dispose() 
                } catch {}
            }
            
            if ($Aborted) {
                Out-Str 2 $UI_Y ("[ ABORTED ] SCAN STOPPED. [ENTER] RESTART | [H] HELP | [P] PROXY | [T] TEST | [Q] QUIT".PadRight(121)) "Black" "Red"
            } else {
                Out-Str 2 $UI_Y ("[ SUCCESS ] SCAN FINISHED. [ENTER] RESTART | [H] HELP | [P] PROXY | [S] SAVE | [Q] QUIT".PadRight(121)) "Black" "Green"
            }
            Clear-KeyBuffer
        }
    }
    [System.Threading.Thread]::Sleep(50)
}