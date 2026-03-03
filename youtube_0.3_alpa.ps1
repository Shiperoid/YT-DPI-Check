# Настройка окружения
$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Определяем доступные протоколы (TLS 1.3 доступен только на Win 10 21H1+ / Win 11)
$IsWin7 = ([Environment]::OSVersion.Version.Major -eq 6 -and [Environment]::OSVersion.Version.Minor -eq 1)
if ($IsWin7) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
} else {
    # Для Win 10/11 пробуем TLS 1.2 + 1.3
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 12288
    $GlobalProtocol = [System.Security.Authentication.SslProtocols]::Tls12
}

# --- Функция динамического поиска ближайшего CDN ---
function Get-LocalCDN {
    $cdnHost = "redirector.googlevideo.com"
    try {
        # Разрешаем CNAME/IP для ближайшего узла
        $addresses = [System.Net.Dns]::GetHostAddresses($cdnHost)
        $hostName = [System.Net.Dns]::GetHostEntry($addresses[0]).HostName
        return $hostName
    } catch {
        return "rr1---sn-uxax-5u6e.googlevideo.com" # Фолбэк если DNS перехвачен
    }
}

# --- Ядро проверки ---
function Test-NetworkDPI {
    param([string]$Target)
    $timeout = 2500
    $res = @{ Domain=$Target.PadRight(38); IP="?"; TCP="FAIL"; TLS="FAIL"; UDP="FAIL"; Latency=0; Verdict="BLOCKED" }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcp = New-Object System.Net.Sockets.TcpClient
    
    try {
        # 0. DNS Resolve
        $ips = [System.Net.Dns]::GetHostAddresses($Target)
        $res.IP = $ips[0].IPAddressToString.PadRight(15)

        # 1. TCP Check (443)
        $ar = $tcp.BeginConnect($Target, 443, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne($timeout)) {
            $tcp.EndConnect($ar)
            $res.TCP = "OK  "
            $res.Latency = $sw.ElapsedMilliseconds
        } else {
            $res.Verdict = "IP BLOCK"
            return $res
        }

        # 2. TLS Handshake (SNI) - Тест блокировки ТСПУ
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
        $arSsl = $ssl.BeginAuthenticateAsClient($Target, $null, $GlobalProtocol, $false, $null, $null)
        if ($arSsl.AsyncWaitHandle.WaitOne($timeout)) {
            $ssl.EndAuthenticateAsClient($arSsl)
            $res.TLS = "OK  "
        } else {
            $res.TLS = "DROP" # Пакет ушел, ответа нет (DPI)
            $res.Verdict = "DPI BLOCK (SNI)"
            return $res
        }

        # 3. UDP Check (QUIC/HTTP3)
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Connect($Target, 443)
        $udp.Send([byte[]](1..10), 10) | Out-Null
        $res.UDP = "SENT" # UDP не имеет состояния, если не было ICMP отбоя - считаем SENT
        $udp.Close()

        $res.Verdict = "AVAILABLE"
    } catch {
        $res.Verdict = "ERROR: $($_.Exception.Message.Substring(0,10))"
    } finally {
        if ($ssl) { $ssl.Dispose() }
        if ($tcp) { $tcp.Dispose() }
    }
    return $res
}

# --- Выполнение ---
Clear-Host
Write-Host "--- SCANNING NETWORK FOR YOUTUBE BLOCKING (WIN 7/10/11) ---"
Write-Host "Resolving local Google Global Cache node..."
$localCDN = Get-LocalCDN
Write-Host "Detected your CDN: $localCDN" -ForegroundColor Cyan

$targets = @(
    "google.com",                  # Контроль доступа к Google
    "www.youtube.com",             # Вход на сайт
    "m.youtube.com",               # Мобильный интерфейс
    "i.ytimg.com",                 # Обложки/картинки
    "yt3.ggpht.com",               # Аватары
    "manifest.googlevideo.com",    # Метаданные потока
    $localCDN                      # Ваш локальный сервер видео (CDN)
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

    # Вывод одной строкой
    Write-Host "$($report.Domain)" -NoNewline
    Write-Host "$($report.IP) " -NoNewline -ForegroundColor Gray
    Write-Host "$($report.TCP)  " -NoNewline
    Write-Host "$($report.TLS)  " -NoNewline
    Write-Host "$($report.UDP)   " -NoNewline -ForegroundColor Gray
    Write-Host "$($report.Latency.ToString().PadLeft(4))ms " -NoNewline -ForegroundColor Cyan
    Write-Host " [$($report.Verdict)]" -ForegroundColor $color
}

Write-Host "--------------------------------------------------------------------------------------------"
Read-Host "`nДиагностика завершена. Нажмите Enter..."