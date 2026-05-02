<# :
@echo off
setlocal
title Google CDN Debugger
cd /d "%~dp0"
chcp 65001 >nul
where /q pwsh.exe
if not errorlevel 1 (set "PS_EXE=pwsh.exe") else (set "PS_EXE=powershell.exe")
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0' -Encoding UTF8) -join [Environment]::NewLine)"
pause
exit /b
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

function Write-C ($text, $color="White") { Write-Host $text -ForegroundColor $color }

Write-C "=== GOOGLE CDN NODE DEBUGGER ===" "Cyan"

# 1. Поиск локального CDN
Write-C "`n[*] 1. Определение локального кэш-сервера (CDN)..." "Yellow"
$rnd = [guid]::NewGuid().ToString().Substring(0,8)
$cdn = "manifest.googlevideo.com"
try {
    $req = [System.Net.WebRequest]::Create("http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd")
    $req.Timeout = 3000
    $resp = $req.GetResponse()
    $raw = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
    $resp.Close()
    if ($raw -match "=>\s+([\w-]+)") { 
        $cdn = "r1.$($matches[1]).googlevideo.com" 
        Write-C "  [+] Найден узел: $cdn" "Green"
    } else {
        Write-C "  [-] Не удалось определить узел, используем дефолтный: $cdn" "Red"
    }
} catch {
    Write-C "  [!] Ошибка связи с redirector.googlevideo.com: $($_.Exception.Message)" "Red"
    exit
}

# 2. Резолв DNS
Write-C "`n[*] 2. Разрешение DNS (IP-адрес)..." "Yellow"
$ip = $null
try {
    $dns = [System.Net.Dns]::GetHostAddresses($cdn)
    $ip = $dns[0].IPAddressToString
    Write-C "  [+] IP-адрес узла: $ip" "Green"
} catch {
    Write-C "  [!] Ошибка DNS: Узел не найден. Возможно, блокировка на уровне DNS." "Red"
    exit
}

# 3. Тест HTTP (Порт 80)
Write-C "`n[*] 3. Тест HTTP (Порт 80 - Открытый текст)..." "Yellow"
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcp = New-Object System.Net.Sockets.TcpClient
    $asyn = $tcp.BeginConnect($ip, 80, $null, $null)
    
    if ($asyn.AsyncWaitHandle.WaitOne(3000)) {
        $tcp.EndConnect($asyn)
        Write-C "  [+] TCP Соединение установлено за $($sw.ElapsedMilliseconds) мс." "Green"
        
        $stream = $tcp.GetStream()
        $stream.ReadTimeout = 3000
        $reqMsg = "GET / HTTP/1.1`r`nHost: $cdn`r`nUser-Agent: curl/7.88.1`r`nConnection: close`r`n`r`n"
        $buf = [System.Text.Encoding]::ASCII.GetBytes($reqMsg)
        $stream.Write($buf, 0, $buf.Length)
        
        $respBuf = New-Object byte[] 1024
        $bytes = $stream.Read($respBuf, 0, 1024)
        if ($bytes -gt 0) {
            $httpResp = [System.Text.Encoding]::ASCII.GetString($respBuf, 0, $bytes)
            $firstLine = ($httpResp -split "`r`n")[0]
            Write-C "  [+] Ответ сервера: $firstLine" "Green"
            if ($firstLine -match "404|400|403") {
                Write-C "      (Примечание: Ошибка 40x от Google - это норма для 'голых' запросов)" "DarkGray"
            }
        } else {
            Write-C "  [-] Соединение установлено, но сервер не прислал данные (Пустой ответ)." "Red"
        }
    } else {
        Write-C "  [!] ТАЙМАУТ: Пакеты исчезают (ТСПУ Blackhole / Сервер мертв)." "Red"
    }
    $tcp.Close()
} catch {
    Write-C "  [!] ОШИБКА СОЕДИНЕНИЯ: $($_.Exception.Message)" "Red"
}

# 4. Тест TLS (Порт 443)
Write-C "`n[*] 4. Тест TLS (Порт 443 - Шифрованный трафик)..." "Yellow"
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcp = New-Object System.Net.Sockets.TcpClient
    $asyn = $tcp.BeginConnect($ip, 443, $null, $null)
    
    if ($asyn.AsyncWaitHandle.WaitOne(3000)) {
        $tcp.EndConnect($asyn)
        Write-C "  [+] TCP Соединение установлено за $($sw.ElapsedMilliseconds) мс." "Green"
        
        Write-C "  [*] Начинаем TLS рукопожатие (Игнорируем ошибки сертификата)..." "DarkGray"
        
        # Хак для обхода проверки сертификата прямо в потоке
        $certCallback = { param($sender, $cert, $chain, $errors) return $true }
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $certCallback)
        
        $ssl.AuthenticateAsClient($cdn)
        
        $cert = $ssl.RemoteCertificate
        if ($cert) {
            Write-C "  [!] ВНИМАНИЕ! Соединение перехвачено!" "Magenta"
            Write-C "  [+] Сертификат выдан КОМУ: $($cert.Subject)" "Cyan"
            Write-C "  [+] Сертификат выдан КЕМ:  $($cert.Issuer)" "Cyan"
        }
        $ssl.Close()
    } else {
        Write-C "  [!] ТАЙМАУТ: Пакеты исчезают." "Red"
    }
    $tcp.Close()
} catch {
    Write-C "  [!] ОШИБКА TLS: $($_.Exception.Message)" "Red"
}

Write-C "`n=== ТЕСТ ЗАВЕРШЕН ===" "Cyan"