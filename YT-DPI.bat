<# :
@echo off
set "SCRIPT_PATH=%~f0"
title YT-DPI v2.2.0
chcp 65001 >nul

:: Проверяем наличие PowerShell 7 (pwsh.exe)
where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "PS_EXE=pwsh"
) else (
    set "PS_EXE=powershell"
)

%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "iex ([System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::UTF8))"
exit /b
#>
$script:OriginalFilePath = [System.Environment]::GetEnvironmentVariable("SCRIPT_PATH", "Process")
if (-not $script:OriginalFilePath) { $script:OriginalFilePath = $MyInvocation.MyCommand.Path }
if (-not $script:OriginalFilePath) { $script:OriginalFilePath = $MyInvocation.InvocationName }
$ErrorActionPreference = "SilentlyContinue"
$script:CurrentWindowWidth = 0
$script:CurrentWindowHeight = 0
[Console]::BufferHeight = [Console]::WindowHeight #потестить с этим параметром отрисовка быстрее но нет прокрутки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::CursorVisible = $false
$ErrorActionPreference = "Continue"
$DebugPreference = "SilentlyContinue"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
[System.Net.ServicePointManager]::DefaultConnectionLimit = 100

$scriptVersion = "2.2.0"   # текущая версия yt-dpi
# ===== ОТЛАДКА =====
$DEBUG_ENABLED = $true
$DebugLogFile = Join-Path (Get-Location).Path "YT-DPI_Debug.log"
$DebugLogMutex = New-Object System.Threading.Mutex($false, "Global\YT-DPI-Debug-Mutex")
$script:LogLock = New-Object System.Object

function Write-DebugLog($msg, $level = "DEBUG") {
    if (-not $DEBUG_ENABLED) { return }
    $line = "[$(Get-Date -Format 'HH:mm:ss.fff')] [$level] $msg`r`n"
    $retries = 3
    while ($retries -gt 0) {
        try {
            [System.Threading.Monitor]::Enter($script:LogLock)
            [System.IO.File]::AppendAllText($DebugLogFile, $line, [System.Text.Encoding]::UTF8)
            break
        }
        catch {
            $retries -= 1
            if ($retries -eq 0) { break }
            Start-Sleep -Milliseconds 50
        }
        finally {
            [System.Threading.Monitor]::Exit($script:LogLock)
        }
    }
}

# ===== ЛОГИРОВАНИЕ И РОТАЦИЯ =====
$maxLogSizeBytes = 5 * 1024 * 1024
if (Test-Path $DebugLogFile) {
    try {
        $fileInfo = Get-Item $DebugLogFile
        if ($fileInfo.Length -gt $maxLogSizeBytes) {
            $backupName = [System.IO.Path]::GetFileNameWithoutExtension($DebugLogFile) + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log"
            Move-Item $DebugLogFile (Join-Path (Split-Path $DebugLogFile -Parent) $backupName) -Force
        } else {
            Remove-Item $DebugLogFile -Force -ErrorAction SilentlyContinue
        }
    } catch { Remove-Item $DebugLogFile -Force -ErrorAction SilentlyContinue }
}

# ТЕПЕРЬ ПИШЕМ ИНФО-БЛОК (Когда файл уже чистый)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
try { $osInfo = Get-CimInstance Win32_OperatingSystem } catch { $osInfo = @{Caption="Windows (Legacy)"; Version="Unknown"} }

Write-DebugLog "==================== YT-DPI SESSION START ====================" "INFO"
Write-DebugLog "Скрипт версия: $scriptVersion" "INFO"
Write-DebugLog "ОС: $($osInfo.Caption) ($($osInfo.Version))" "INFO"
Write-DebugLog "PowerShell: $($PSVersionTable.PSVersion.ToString())" "INFO"
Write-DebugLog "Права: $(if($isAdmin){'Администратор'}else{'Пользователь'})" "INFO"
Write-DebugLog "Локаль: $([System.Globalization.CultureInfo]::CurrentCulture.Name)" "INFO"
Write-DebugLog "Путь: $script:OriginalFilePath" "INFO"
Write-DebugLog "============================================================" "INFO"

Write-DebugLog "Старый лог-файл очищен, начало новой сессии." "INFO"
# --- ОТКЛЮЧЕНИЕ ВЫДЕЛЕНИЯ МЫШЬЮ ---
Write-DebugLog "Отключаем QuickEdit..."
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
if (-not ([System.Management.Automation.PSTypeName]'ConsoleHelper').Type) {
    Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    [ConsoleHelper]::DisableQuickEdit()
    Write-DebugLog "QuickEdit отключён." "INFO"
}

# --- ГЛОБАЛЬНЫЕ НАСТРОЙКИ ---
$global:ProxyConfig = @{ Enabled = $false; Type = "HTTP"; Host = ""; Port = 0; User = ""; Pass = "" }
$script:DnsCache = @{}
$script:DnsCacheLock = New-Object System.Threading.Mutex($false, "Global\YT-DPI-DNS-Cache")
$script:NetInfo = $null
$script:Targets = $null
$script:LastScanResults = @()
$script:DynamicColPos = $null
$script:IpColumnWidth = 16
$script:UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# --- КОНСТАНТЫ ---
$SCRIPT:CONST = @{
    TimeoutMs    = 1500
    ProxyTimeout = 2500
    HttpPort     = 80
    HttpsPort    = 443
    Tls13Proto   = 12288
    UI = @{
        Num = 1      # Номер домена (новая колонка)
        Dom = 6      # TARGET DOMAIN (было 2, теперь 6)
        IP  = 50     # IP ADDRESS (было 45, сдвинуто на 5)
        HTTP = 68    # HTTP (было 63)
        T12 = 76     # TLS 1.2 (было 71)
        T13 = 86     # TLS 1.3 (было 81)
        Lat = 96     # LAT (было 91)
        Ver = 104    # RESULT (было 99)
    }
        NavStr = "[READY] [ENTER] SCAN | [S] SETTINGS | [P] PROXY | [D] DEEP TRACE | [R] REPORT | [H] HELP | [Q] QUIT"
}
Write-DebugLog "Константы инициализированы."

# --- ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ ОКРУЖЕНИЯ ---
$script:Config = $null
$script:NetInfo = $null
$script:DnsCache = [hashtable]::Synchronized(@{}) # Сразу делаем его потокобезопасным
$script:LastScanResults = @()


# --- НИЗКОУРОВНЕВЫЙ TLS ДВИЖОК (C#) ---
$tlsCode = @"
using System;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Linq;

public class TlsScanner {
    public static string TestT13(string targetIp, string host, string proxyHost, int proxyPort, string user, string pass, int timeout) {
        try {
            using (TcpClient tcp = new TcpClient()) {
                string connectHost = string.IsNullOrEmpty(proxyHost) ? targetIp : proxyHost;
                int connectPort = string.IsNullOrEmpty(proxyHost) ? 443 : proxyPort;

                var ar = tcp.BeginConnect(connectHost, connectPort, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeout)) return "DRP";
                tcp.EndConnect(ar);
                
                NetworkStream stream = tcp.GetStream();
                stream.ReadTimeout = timeout;
                stream.WriteTimeout = timeout;

                if (!string.IsNullOrEmpty(proxyHost)) {
                    byte[] greeting = new byte[] { 0x05, 0x01, 0x00 };
                    stream.Write(greeting, 0, greeting.Length);
                    byte[] authResp = new byte[2];
                    stream.Read(authResp, 0, 2);
                    
                    byte[] connectReq = BuildSocksConnect(host, 443);
                    stream.Write(connectReq, 0, connectReq.Length);
                    byte[] connResp = new byte[10];
                    stream.Read(connResp, 0, 10);
                    if (connResp[1] != 0x00) return "PRX_ERR";
                }

                // Шлем исправленный пакет
                byte[] hello = BuildModernHello(host);
                stream.Write(hello, 0, hello.Length);

                byte[] header = new byte[5];
                int read = 0;
                try {
                    read = stream.Read(header, 0, 5);
                } catch (System.IO.IOException ex) {
                    string m = ex.Message.ToLower();
                    if (m.Contains("reset") || m.Contains("сброс")) return "RST";
                    return "DRP";
                }

                if (read < 5) return "DRP";

                // 0x16 = Handshake (Server Hello) - Успех
                if (header[0] == 0x16) return "OK"; 
                
                // 0x15 = TLS Alert. Если сервер прислал это, значит пакет валиден, 
                // но серверу что-то не нравится. Для теста доступности это "OK" (сервер ответил).
                if (header[0] == 0x15) return "OK"; 
                
                return "DRP";
            }
        } catch (Exception ex) {
            string m = ex.Message.ToLower();
            if (m.Contains("reset") || m.Contains("closed")) return "RST";
            return "DRP";
        }
    }

    private static byte[] BuildSocksConnect(string host, int port) {
        List<byte> req = new List<byte> { 0x05, 0x01, 0x00, 0x03 };
        byte[] h = Encoding.ASCII.GetBytes(host);
        req.Add((byte)h.Length);
        req.AddRange(h);
        req.Add((byte)(port >> 8));
        req.Add((byte)(port & 0xFF));
        return req.ToArray();
    }

    private static byte[] BuildModernHello(string host) {
        List<byte> body = new List<byte>();
        body.AddRange(new byte[] { 0x03, 0x03 }); // TLS 1.2 (for compatibility header)
        
        Random rand = new Random();
        byte[] random = new byte[32];
        rand.NextBytes(random);
        body.AddRange(random);

        body.Add(0x00); // Session ID len
        body.AddRange(new byte[] { 0x00, 0x06, 0x13, 0x01, 0x13, 0x02, 0x13, 0x03 }); // Ciphers: TLS_AES_128_GCM_SHA256 и др.
        body.Add(0x20); // Length 32
        byte[] sessId = new byte[32]; rand.NextBytes(sessId);
        body.AddRange(sessId);

        List<byte> exts = new List<byte>();
        
        // 1. SNI
        byte[] h = Encoding.ASCII.GetBytes(host);
        exts.AddRange(new byte[] { 0x00, 0x00 }); // Type SNI
        int sniLen = h.Length + 5;
        exts.Add((byte)(sniLen >> 8)); exts.Add((byte)(sniLen & 0xFF));
        exts.Add((byte)((h.Length + 3) >> 8)); exts.Add((byte)((h.Length + 3) & 0xFF));
        exts.Add(0x00); // Name type: host_name
        exts.Add((byte)(h.Length >> 8)); exts.Add((byte)(h.Length & 0xFF));
        exts.AddRange(h);

        // 2. Extended Master Secret (0x0017)
        exts.AddRange(new byte[] { 0x00, 0x17, 0x00, 0x00 });

        // 3. Supported Groups (0x000a) - x25519
        exts.AddRange(new byte[] { 0x00, 0x0a, 0x00, 0x04, 0x00, 0x02, 0x00, 0x1d });

        // 4. Signature Algorithms (0x000d) - КРИТИЧНО ДЛЯ GOOGLE
        // ecdsa_secp256r1_sha256, rsa_pss_rsae_sha256, rsa_pkcs1_sha256
        exts.AddRange(new byte[] { 0x00, 0x0d, 0x00, 0x08, 0x00, 0x06, 0x04, 0x03, 0x08, 0x04, 0x04, 0x01 });

        // 5. Supported Versions (0x002b) - TLS 1.3
        exts.AddRange(new byte[] { 0x00, 0x2b, 0x00, 0x03, 0x02, 0x03, 0x04 });

        // 6. PSK Key Exchange Modes (0x002d) - КРИТИЧНО ДЛЯ TLS 1.3
        exts.AddRange(new byte[] { 0x00, 0x2d, 0x00, 0x02, 0x01, 0x01 });

        // 7. Key Share (0x0033)
        exts.AddRange(new byte[] { 0x00, 0x33, 0x00, 0x26, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20 });
        byte[] key = new byte[32]; rand.NextBytes(key);
        exts.AddRange(key);

        body.Add((byte)(exts.Count >> 8)); body.Add((byte)(exts.Count & 0xFF));
        body.AddRange(exts);

        List<byte> pkt = new List<byte> { 0x16, 0x03, 0x01 }; // Record Header
        pkt.Add((byte)(body.Count >> 8)); pkt.Add((byte)(body.Count & 0xFF));
        pkt.AddRange(body);
        return pkt.ToArray();
    }
}
"@
try { Add-Type -TypeDefinition $tlsCode -ErrorAction SilentlyContinue } catch {}


# --- ГЛОБАЛЬНЫЕ ПУТИ ---
# Лог кладем строго в папку, где лежит сам файл .bat
$script:ParentDir = Split-Path -Parent $script:OriginalFilePath
$DebugLogFile = Join-Path $script:ParentDir "YT-DPI_Debug.log"

# Конфиг остается в профиле пользователя (AppData)
$script:ConfigDir = Join-Path $env:LOCALAPPDATA "YT-DPI"
$script:ConfigFile = Join-Path $script:ConfigDir "YT-DPI_config.json"

# Создаём папку в AppData, если её нет (для конфига)
if (-not (Test-Path $script:ConfigDir)) {
    try { New-Item -Path $script:ConfigDir -ItemType Directory -Force | Out-Null } catch {}
}


function Normalize-Version($v) {
    $clean = ($v -replace '[^0-9.]', '').Trim('.')
    if (-not $clean) { return [version]"0.0.0" }
    $parts = $clean -split '\.'
    while ($parts.Count -lt 3) { $parts += '0' }
    return [version]($parts[0..2] -join '.')
}

function New-ConfigObject {
    return [PSCustomObject]@{
        RunCount = 0
        LastPromptRun = 0
        LastCheckedVersion = ""
        IpPreference = "IPv6"   # <--- НОВОЕ: "IPv6" (приоритет) или "IPv4"
        Proxy = @{ Enabled = $false; Type = "HTTP"; Host = ""; Port = 0; User = ""; Pass = "" }
        ProxyHistory = @()
        NetCache = @{ 
            ISP = "Loading..."; LOC = "Unknown"; DNS = "8.8.8.8"; 
            CDN = "manifest.googlevideo.com"; 
            TimestampTicks = (Get-Date).AddDays(-1).Ticks;
            HasIPv6 = $false
        }
        DnsCache = @{} 
    }
}

function Get-PaddedCenter {
    param($text, $width)
    $spaces = $width - $text.Length
    if ($spaces -le 0) { return $text }
    $left = [Math]::Floor($spaces / 2)
    return (" " * $left) + $text
}

# --- Структура конфига в AppData ---
function Load-Config {
    Write-DebugLog "Загрузка конфигурации..."
    $default = New-ConfigObject
    
    if (Test-Path $script:ConfigFile) {
        try {
            $config = Get-Content $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $config) { return $default }

            # --- МИГРАЦИЯ: Добавляем недостающие поля из дефолтного конфига ---
            foreach ($prop in $default.PSObject.Properties) {
                if ($null -eq $config.$($prop.Name)) {
                    # Используем Add-Member, чтобы расширить объект «на лету»
                    $config | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                    Write-DebugLog "Миграция: Добавлено отсутствующее поле $($prop.Name)" "INFO"
                }
            }

            # Санитария DNS-кэша
            if ($config.DnsCache -and $config.DnsCache.PSObject) {
                $cleanDns = @{}
                foreach ($p in $config.DnsCache.PSObject.Properties) {
                    if ($p.Value -match '\..*\.' -or $p.Value -match ':') { $cleanDns[$p.Name] = $p.Value }
                }
                $config.DnsCache = $cleanDns
            }

            $lastTicks = if ($config.NetCache.TimestampTicks) { $config.NetCache.TimestampTicks } else { 0 }
            $isStale = (Get-Date).Ticks - $lastTicks -gt ([TimeSpan]::FromHours(6).Ticks)
            $config | Add-Member -MemberType NoteProperty -Name "NetCacheStale" -Value $isStale -Force
            
            return $config
        } catch { 
            Write-DebugLog "Ошибка загрузки: $_" "WARN"
        }
    }
    return $default
}

function Save-Config($config) {
    if ($null -eq $config) { return }
    try {
        # Обновляем DNS кэш перед сохранением
        $config.DnsCache = $script:DnsCache
        $config.Proxy = $global:ProxyConfig
        
        # Удаляем временное поле
        if ($config.PSObject.Properties['NetCacheStale']) { $config.PSObject.Properties.Remove('NetCacheStale') }

        $json = $config | ConvertTo-Json -Depth 5 -Compress
        Set-Content -Path $script:ConfigFile -Value $json -Encoding UTF8 -Force
        Write-DebugLog "Конфиг сохранен успешно." "INFO"
    } catch { 
        Write-DebugLog "Ошибка сохранения: $_" "ERROR"
    }
}

function Start-Updater {
    param($currentFile, $downloadUrl)
    
    $parentPid = $PID
    $tempFile = Join-Path $env:TEMP "YT-DPI_new.bat"
    $logFile = Join-Path $env:TEMP "yt_updater_debug.log"
    $updaterPath = Join-Path $env:TEMP "yt_run_updater.ps1"

    Write-DebugLog "Запуск финальной версии апдейтера. Лог: $logFile"

    # Одинарные кавычки защищают код от раскрытия переменных
    $updaterTemplate = @'
$parentPid = "REPLACE_PID"
$currentFile = "REPLACE_FILE"
$downloadUrl = "REPLACE_URL"
$tempFile = "REPLACE_TEMP"
$logFile = "REPLACE_LOG"

function Write-Log($m) { 
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $m"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Write-Log "--- UPDATER SESSION START ---"
Write-Log "Waiting for PID $parentPid to exit..."

# 1. Ждем завершения процесса (до 15 секунд)
$count = 0
while (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) {
    if ($count -gt 150) { Write-Log "Force killing $parentPid"; Stop-Process -Id $parentPid -Force; break }
    Start-Sleep -Milliseconds 100
    $count++
}
Start-Sleep -Seconds 1 # Дополнительная пауза для снятия блокировки файла

try {
    Write-Log "Downloading from $downloadUrl..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $web = New-Object System.Net.WebClient
    $web.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $web.DownloadFile($downloadUrl, $tempFile)

    if (Test-Path $tempFile) {
        $size = (Get-Item $tempFile).Length
        $content = Get-Content $tempFile -Raw -Encoding UTF8
        Write-Log "Downloaded size: $size bytes."

        # ПРОВЕРКА ЦЕЛОСТНОСТИ (более гибкая)
        if ($size -gt 10000 -and ($content -match "scriptVersion" -or $content -match "YT-DPI")) {
            Write-Log "Integrity check passed."
            
            # 2. Пытаемся заменить файл (с повторами, если файл занят)
            $replaced = $false
            for ($i=1; $i -le 5; $i++) {
                try {
                    Copy-Item -Path $tempFile -Destination $currentFile -Force -ErrorAction Stop
                    $replaced = $true
                    Write-Log "File replaced on attempt $i."
                    break
                } catch {
                    Write-Log "Attempt $i failed: $($_.Exception.Message). Retrying..."
                    Start-Sleep -Seconds 1
                }
            }

            if ($replaced) {
                Write-Log "Update successful! Restarting..."
                Start-Process $currentFile
            } else {
                Write-Log "CRITICAL: Could not overwrite file after 5 attempts."
                Start-Process $currentFile
            }
        } else {
            Write-Log "Integrity FAIL: Content check failed (size $size)."
            Start-Process $currentFile
        }
    }
} catch {
    Write-Log "GENERAL ERROR: $($_.Exception.Message)"
    Start-Sleep -Seconds 3
    if (Test-Path $currentFile) { Start-Process $currentFile }
}

# Очистка
if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
Write-Log "--- UPDATER SESSION END ---"
'@

    # Заполнение путей
    $updaterContent = $updaterTemplate.
        Replace("REPLACE_PID", $parentPid).
        Replace("REPLACE_FILE", $currentFile).
        Replace("REPLACE_URL", $downloadUrl).
        Replace("REPLACE_TEMP", $tempFile).
        Replace("REPLACE_LOG", $logFile)

    try {
        Set-Content -Path $updaterPath -Value $updaterContent -Encoding UTF8 -Force
        
        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
        $pInfo.FileName = "powershell.exe"
        $pInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$updaterPath`""
        $pInfo.WindowStyle = "Hidden"
        [System.Diagnostics.Process]::Start($pInfo) | Out-Null
        
        # Мгновенно убиваем текущий процесс
        [System.Diagnostics.Process]::GetCurrentProcess().Kill()
    } catch {
        Write-DebugLog "Ошибка запуска апдейтера: $_"
    }
}

# ====================================================================================
# Список целей для теста
# ====================================================================================
$BaseTargets = @(
    "youtu.be",
    "youtube.com",
    "i.ytimg.com",
    "s.ytimg.com",
    "yt3.ggpht.com",
    "yt4.ggpht.com",
    "s.youtube.com",
    "m.youtube.com",
    "googleapis.com",
    "tv.youtube.com",
    "googlevideo.com",
    "www.youtube.com",
    "play.google.com",
    "youtubekids.com",
    "video.google.com",
    "music.youtube.com",
    "accounts.google.com",
    "clients6.google.com",
    "studio.youtube.com",
    "manifest.googlevideo.com",
    "youtubei.googleapis.com",
    "www.youtube-nocookie.com",
    "signaler-pa.youtube.com",
    "redirector.googlevideo.com",
    "youtubeembeddedplayer.googleapis.com"
)

# Функция для получения актуального списка целей
function Get-Targets {
    param($NetInfo)
    $targets = $BaseTargets
    if ($NetInfo.CDN -and $NetInfo.CDN -notin $targets) {
        $targets += $NetInfo.CDN
    }
    # Сортировка по длине строки
    return $targets | Sort-Object { $_.Length } | Select-Object -Unique
}

# ====================================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ И UI
# ====================================================================================
function Out-Str($x, $y, $str, $color="White", $bg="Black") {
    try {
        # Затираем всю область до конца строки
        $clearStr = $str + (" " * [Math]::Max(0, [Console]::WindowWidth - $x - $str.Length))
        [Console]::SetCursorPosition($x, $y)
        [Console]::ForegroundColor = $color
        [Console]::BackgroundColor = $bg
        [Console]::Write($clearStr)
        [Console]::BackgroundColor = "Black"
    } catch {}
}

function Clear-KeyBuffer {
    while ([Console]::KeyAvailable) {
        $null = [Console]::ReadKey($true)
    }
}

function Update-ConsoleSize {
    try {
        [Console]::SetCursorPosition(0, 0)
        $linesNeeded = $script:Targets.Count + 19
        $maxHeight = [Console]::LargestWindowHeight
        if ($linesNeeded -gt $maxHeight) {
            Write-DebugLog "Предупреждение: требуется $linesNeeded строк, доступно только $maxHeight"
            $linesNeeded = $maxHeight
            $script:Truncated = $true
        } else {
            $script:Truncated = $false
        }
        $w = 135
        $h = $linesNeeded
        $maxWidth = [Console]::LargestWindowWidth
        if ($w -gt $maxWidth) { $w = $maxWidth }
        
        try {
            if ($h -ne $script:CurrentWindowHeight -or $w -ne $script:CurrentWindowWidth) {
                [Console]::WindowWidth = $w
                [Console]::WindowHeight = $h
                [Console]::BufferWidth = $w
                [Console]::BufferHeight = $h
                $script:CurrentWindowWidth = $w
                $script:CurrentWindowHeight = $h
            }
        } catch {
            Write-DebugLog "Не удалось изменить размер окна: $_"
        }
    } catch {}
}
function Get-NavRow {
    param([int]$count)
    # 9 (начало таблицы) + 3 (заголовок и линия) + $count (строки результатов) + 2 (линия и отступ)
    return 9 + 3 + $count + 2
}

function Draw-StatusBar {
    param(
        [string]$Message = $null,
        [string]$Fg = "Black",
        [string]$Bg = "White"
    )
    if (-not $script:Targets) { return }
    $row = Get-NavRow -count $script:Targets.Count
    $width = [Console]::WindowWidth
    
    # 1. Сначала ПОЛНОСТЬЮ очищаем строку пробелами, чтобы убрать "призраков"
    Out-Str 0 $row (" " * $width) "Black" "Black"
    
    # 2. Готовим текст
    $text = if ($Message) { $Message } else { $CONST.NavStr }
    
    # 3. Обрезаем, если текст шире окна
    if ($text.Length -gt ($width - 4)) { $text = $text.Substring(0, $width - 7) + "..." }
    
    # 4. Рисуем новый статус с небольшим отступом для красоты
    Out-Str 2 $row " $text " $Fg $Bg
}

function Draw-UI ($NetInfo, $Targets, $Results, $ClearScreen = $true) {
    # $Results - массив объектов с результатами сканирования (свойство .IP)
    Write-DebugLog "Draw-UI: Targets count=$($Targets.Count), ClearScreen=$ClearScreen"

        # --- Динамический расчёт ширины колонки IP ---
    $ipColumnWidth = 16
    
    # 1. Проверяем текущие результаты (если они есть)
    if ($Results) {
        $maxIpLen = ($Results | ForEach-Object { if ($_.IP) { $_.IP.ToString().Length } else { 0 } } | Measure-Object -Maximum).Maximum
        if ($maxIpLen -gt $ipColumnWidth) { $ipColumnWidth = $maxIpLen + 2 }
    }
    
    # 2. Проверяем DNS-кэш (чтобы заранее знать про длинные IPv6)
    if ($script:DnsCache) {
        $cacheIpMax = ($script:DnsCache.Values | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        if ($cacheIpMax -gt $ipColumnWidth) { $ipColumnWidth = $cacheIpMax + 2 }
    }

    if ($ipColumnWidth -gt 45) { $ipColumnWidth = 45 }
    $script:IpColumnWidth = $ipColumnWidth

    # --- Пересчёт позиций колонок (остальные ширины фиксированы) ---
    $domStart  = 6
    $domWidth  = 42
    $ipStart   = $domStart + $domWidth + 2   # позиция после колонки Domain с отступом
    $ipWidth   = $ipColumnWidth
    $httpStart = $ipStart + $ipWidth + 2
    $httpWidth = 6
    $t12Start  = $httpStart + $httpWidth + 2
    $t12Width  = 8
    $t13Start  = $t12Start + $t12Width + 2
    $t13Width  = 8
    $latStart  = $t13Start + $t13Width + 2
    $latWidth  = 6
    $verStart  = $latStart + $latWidth + 2
    $verWidth  = 30

    Update-ConsoleSize
    if ($ClearScreen) { [Console]::Clear() }

    # --- Логотип и правая панель (без изменений) ---
    Out-Str 1 1 ' ██╗   ██╗████████╗    ██████╗ ██████╗ ██╗' 'Green'
    Out-Str 1 2 ' ╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║' 'Green'
    Out-Str 1 3 '  ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║' 'Green'
    Out-Str 1 4 '   ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║' 'Green'
    Out-Str 1 5 '    ██║      ██║       ██████║ ██║     ██║' 'Green'
    Out-Str 1 6 '    ╚═╝      ╚═╝       ╚═════╝ ╚═╝     ╚═╝' 'Green'

    Out-Str 45 1 '██████╗    ██████╗ ' 'Gray'
    Out-Str 45 2 '╚════██╗   ╚════██╗' 'Gray'
    Out-Str 45 3 ' █████╔╝    █████╔╝' 'Gray'
    Out-Str 45 4 '██╔═══╝    ██╔═══╝' 'Gray'
    Out-Str 45 5 '███████╗██╗███████╗' 'Gray'
    Out-Str 45 6 '╚══════╝╚═╝╚══════╝' 'Gray'

    Out-Str 65 1 "> SYS STATUS: [ ONLINE ]" "Green"
    Out-Str 65 2 "> ENGINE: Barebuh Pro v2.3.4" "Red"
    Out-Str 65 3 ("> LOCAL DNS: " + $NetInfo.DNS).PadRight(50) "Cyan"
    Out-Str 65 4 ("> CDN NODE: " + $NetInfo.CDN).PadRight(50) "Yellow"
    Out-Str 65 5 "> AUTHOR: github.com/Shiperoid" "Green"

    $dispIsp = $NetInfo.ISP
    if ($dispIsp.Length -gt 35) { $dispIsp = $dispIsp.Substring(0, 32) + "..." }
    $dispLoc = $NetInfo.LOC
    if ($dispLoc.Length -gt 30) { $dispLoc = $dispLoc.Substring(0, 27) + "..." }
    $ispStr = "> ISP / LOC: $dispIsp ($dispLoc)"
    Out-Str 65 6 ($ispStr.PadRight(80).Substring(0, 80)) "Magenta"

    $proxyStatus = if ($global:ProxyConfig.Enabled) { "> PROXY: $($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port) Connected" } else { "> PROXY: [ OFF ]" }
    Out-Str 65 7 ($proxyStatus.PadRight(58)) "DarkYellow"
    Out-Str 65 8 "> TG: t.me/YT_DPI | VERSION: $scriptVersion" "Green"

    # --- Таблица ---
    $y = 9
    $width = [Console]::WindowWidth

    # Верхняя граница таблицы
    Out-Str 0 $y ("=" * $width) "DarkCyan"

    # Заголовки
    Out-Str 1 ($y+1) "#" "White"
    Out-Str $domStart ($y+1) "TARGET DOMAIN" "White"
    Out-Str $ipStart ($y+1) "IP ADDRESS" "White"
    Out-Str $httpStart ($y+1) "HTTP" "White"
    Out-Str $t12Start ($y+1) "TLS 1.2" "White"
    Out-Str $t13Start ($y+1) "TLS 1.3" "White"
    Out-Str $latStart ($y+1) "LAT" "White"
    Out-Str $verStart ($y+1) "RESULT" "White"

    Out-Str 0 ($y+2) ("=" * $width) "DarkCyan"


    # Разделитель под заголовками
    Out-Str 0 ($y+2) ("=" * $width) "DarkCyan"

    # Строки результатов
    for($i=0; $i -lt $Targets.Count; $i++) {
        $currentRow = $y + 3 + $i
        $num = $i + 1
        $numStr = $num.ToString().PadRight(4)

        Out-Str 1 $currentRow $numStr "Cyan"
        Out-Str $domStart $currentRow ($Targets[$i].PadRight($domWidth).Substring(0, $domWidth)) "Gray"

        # Если есть результаты – используем их, иначе пустые значения
        if ($Results -and $i -lt $Results.Count) {
            $res = $Results[$i]
            $ipStr = if ($res.IP) { [string]$res.IP } else { "---" }
            if ($ipStr.Length -gt $ipWidth) { $ipStr = $ipStr.Substring(0, $ipWidth - 2) + ".." }
            Out-Str $ipStart $currentRow $ipStr.PadRight($ipWidth).Substring(0, $ipWidth) "DarkGray"

            $htStr = if ($res.HTTP) { [string]$res.HTTP } else { "---" }
            $hCol = if($htStr -eq "OK") {"Green"} elseif($htStr -eq "---") {"DarkGray"} else {"Red"}
            Out-Str $httpStart $currentRow $htStr.PadRight($httpWidth).Substring(0, $httpWidth) $hCol

            $t12Str = if ($res.T12) { [string]$res.T12 } else { "---" }
            $t12Col = if($t12Str -eq "OK") {"Green"} elseif($t12Str -eq "---") {"DarkGray"} else {"Red"}
            Out-Str $t12Start $currentRow $t12Str.PadRight($t12Width).Substring(0, $t12Width) $t12Col

            $t13Str = if ($res.T13) { [string]$res.T13 } else { "---" }
            $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A" -or $t13Str -eq "---") {"DarkGray"} else {"Red"}
            Out-Str $t13Start $currentRow $t13Str.PadRight($t13Width).Substring(0, $t13Width) $t13Col

            $latStr = if ($res.Lat) { [string]$res.Lat } else { "---" }
            $latCol = if($latStr -eq "---") {"DarkGray"} else {"Cyan"}
            Out-Str $latStart $currentRow $latStr.PadRight($latWidth).Substring(0, $latWidth) $latCol

            $verStr = if ($res.Verdict) { [string]$res.Verdict } else { "UNKNOWN" }
            Out-Str $verStart $currentRow $verStr.PadRight($verWidth).Substring(0, $verWidth) $res.Color
        } else {
            # Пустые строки
            Out-Str $ipStart $currentRow ("---.---.---.---".PadRight($ipWidth).Substring(0, $ipWidth)) "DarkGray"
            Out-Str $httpStart $currentRow ("--".PadRight($httpWidth).Substring(0, $httpWidth)) "DarkGray"
            Out-Str $t12Start $currentRow ("--".PadRight($t12Width).Substring(0, $t12Width)) "DarkGray"
            Out-Str $t13Start $currentRow ("--".PadRight($t13Width).Substring(0, $t13Width)) "DarkGray"
            Out-Str $latStart $currentRow ("----".PadRight($latWidth).Substring(0, $latWidth)) "DarkGray"
            Out-Str $verStart $currentRow ("IDLE".PadRight($verWidth).Substring(0, $verWidth)) "DarkGray"
        }
    }

    Out-Str 0 ($y + 3 + $Targets.Count) ("=" * $width) "DarkCyan"
}


function Get-ScanAnim($f, $row) {
    $frames = "[=   ]", "[ =  ]", "[  = ]", "[   =]", "[  = ]", "[ =  ]"
    return $frames[($f + $row) % $frames.Length]
}

function Write-ResultLine($row, $result) {
    if ($row -lt 0 -or $row -ge [Console]::BufferHeight) { return }

    $pos = if ($script:DynamicColPos) { $script:DynamicColPos } else { $CONST.UI }
    $ipWidth = if ($script:IpColumnWidth) { $script:IpColumnWidth } else { 16 }

    # Номер строки
    $numStr = if ($result.Number) { $result.Number.ToString().PadRight(4) } else { "    " }
    Out-Str $pos.Num $row $numStr "Cyan"

    # Домен
    Out-Str $pos.Dom $row $result.Target.PadRight(42).Substring(0, 42) "Gray"

    # IP
    $ipStr = if ($result.IP) { [string]$result.IP } else { "---" }
    if ($ipStr.Length -gt $ipWidth) { $ipStr = $ipStr.Substring(0, $ipWidth - 2) + ".." }
    $ipPadded = $ipStr.PadRight($ipWidth)
    Out-Str $pos.IP $row $ipPadded.Substring(0, $ipWidth) "DarkGray"

    # HTTP
    $htStr = if ($result.HTTP) { [string]$result.HTTP } else { "---" }
    $hCol = if($htStr -eq "OK") {"Green"} elseif($htStr -eq "---") {"DarkGray"} else {"Red"}
    $htPadded = $htStr.PadRight(6)
    Out-Str $pos.HTTP $row $htPadded.Substring(0, 6) $hCol

    # TLS 1.2
    $t12Str = if ($result.T12) { [string]$result.T12 } else { "---" }
    $t12Col = if($t12Str -eq "OK") {"Green"} elseif($t12Str -eq "---") {"DarkGray"} else {"Red"}
    $t12Padded = $t12Str.PadRight(8)
    Out-Str $pos.T12 $row $t12Padded.Substring(0, 8) $t12Col

    # TLS 1.3
    $t13Str = if ($result.T13) { [string]$result.T13 } else { "---" }
    $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A" -or $t13Str -eq "---") {"DarkGray"} else {"Red"}
    $t13Padded = $t13Str.PadRight(8)
    Out-Str $pos.T13 $row $t13Padded.Substring(0, 8) $t13Col

    # LAT
    $latStr = if ($result.Lat) { [string]$result.Lat } else { "---" }
    $latCol = if($latStr -eq "---") {"DarkGray"} else {"Cyan"}
    $latPadded = $latStr.PadRight(6)
    Out-Str $pos.Lat $row $latPadded.Substring(0, 6) $latCol

    # VERDICT
    $verStr = if ($result.Verdict) { [string]$result.Verdict } else { "UNKNOWN" }
    $verPadded = $verStr.PadRight(30)
    Out-Str $pos.Ver $row $verPadded.Substring(0, 30) $result.Color
}


function Check-UpdateVersion {
    param(
        [string]$Repo = "Shiperoid/YT-DPI",
        [string]$LastCheckedVersion = "",
        [switch]$IgnoreLastChecked = $false,
        [switch]$ManualMode = $false # Флаг ручного нажатия 'U'
    )
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        Write-DebugLog "Проверка обновлений (API)..."
        $request = [System.Net.WebRequest]::Create($apiUrl)
        $request.UserAgent = $script:UserAgent
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $json = $reader.ReadToEnd()
        $release = $json | ConvertFrom-Json
        $latestVersion = $release.tag_name -replace '^v', ''
        
        $vLatest = Normalize-Version $latestVersion
        $vCurrent = Normalize-Version $scriptVersion
        
        Write-DebugLog "GitHub: $latestVersion ($vLatest) | Локально: $scriptVersion ($vCurrent)"

        # Если мы нажали кнопку 'U', нам важно знать результат, даже если обнов нет
        if ($ManualMode) {
            if ($vLatest -gt $vCurrent) { return $latestVersion } # Есть новее
            if ($vLatest -eq $vCurrent) { return "LATEST" }      # Уже последняя
            return "DEV_VERSION"                                 # У нас новее (бета/дев)
        }

        # Автоматическая проверка (тихая)
        if (-not $IgnoreLastChecked -and $latestVersion -eq $LastCheckedVersion) { return $null }
        if ($vLatest -gt $vCurrent) { return $latestVersion }
        
    } catch {
        Write-DebugLog "Ошибка API GitHub: $_" "WARN"
    }
    return $null
}

function Stop-Script {
    Write-DebugLog "Инициировано завершение работы..."
    [Console]::CursorVisible = $true
    [Console]::ResetColor()
    
    # 1. Сначала сохраняем
    Save-Config $script:Config
    
    # 2. Небольшая пауза, чтобы файловая система успела "переварить" запись
    Start-Sleep -Milliseconds 200
    
    Write-DebugLog "--- СЕССИЯ ЗАВЕРШЕНА ---" "INFO"
    
    # 3. Убиваем процесс
    [System.Diagnostics.Process]::GetCurrentProcess().Kill()
}

function Trace-TcpRoute {
    param(
        [string]$Target,
        [int]$Port = 443,
        [int]$MaxHops = 15,
        [int]$TimeoutSec = 5,
        [scriptblock]$onProgress = $null
    )
    Write-DebugLog "Trace-TcpRoute: $Target`:$Port, MaxHops=$MaxHops, TimeoutSec=$TimeoutSec"

    # Разрешаем имя в IP
    $targetIp = $null
    try {
        $targetIp = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if (-not $targetIp) {
            Write-DebugLog "Не удалось разрешить $Target в IPv4"
            return "DNS error"
        }
        $targetIp = $targetIp.IPAddressToString
    } catch {
        Write-DebugLog "DNS ошибка: $_"
        return "DNS error"
    }

    # Проверяем версию Windows (raw sockets плохо работают на Windows 7)
    $osVersion = [System.Environment]::OSVersion.Version
    $isWin7 = ($osVersion.Major -eq 6 -and $osVersion.Minor -eq 1)
    
    # Проверяем права администратора
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    # Используем raw sockets только на Windows 8+ с правами администратора
    if ($isAdmin -and -not $isWin7) {
        Write-DebugLog "Попытка использовать raw sockets (TCP traceroute)"
        $result = Invoke-TcpTracerouteRaw -TargetIp $targetIp -Port $Port -MaxHops $MaxHops -TimeoutSec $TimeoutSec
        if ($result -isnot [string]) {
            return $result
        }
        Write-DebugLog "Raw sockets не удались, переходим к комбинированному методу: $result"
    } else {
        if ($isWin7) {
            Write-DebugLog "Windows 7 detected, skipping raw sockets"
        } elseif (-not $isAdmin) {
            Write-DebugLog "No admin rights, skipping raw sockets"
        }
    }

    # Комбинированный метод: ICMP traceroute + TCP probes к каждому узлу
    Write-DebugLog "Используем комбинированный метод (ICMP + TCP)"
    return Invoke-TcpTracerouteCombined -Target $Target -Port $Port -MaxHops $MaxHops -TimeoutSec $TimeoutSec -onProgress $onProgress
}

# --- Raw sockets TCP traceroute (требует админа) ---
function Invoke-TcpTracerouteRaw {
    param(
        [string]$TargetIp,
        [int]$Port,
        [int]$MaxHops,
        [int]$TimeoutSec
    )
    try {
        # Создаём raw сокет для отправки TCP SYN
        $sendSocket = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork,
                                                            [System.Net.Sockets.SocketType]::Raw,
                                                            [System.Net.Sockets.ProtocolType]::IP)
        $sendSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                                    [System.Net.Sockets.SocketOptionName]::HeaderIncluded,
                                    $true)
        # Сокет для приёма (ICMP/TCP ответов)
        $recvSocket = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork,
                                                            [System.Net.Sockets.SocketType]::Raw,
                                                            [System.Net.Sockets.ProtocolType]::IP)
        $recvSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                                    [System.Net.Sockets.SocketOptionName]::HeaderIncluded,
                                    $true)
        $recvSocket.ReceiveTimeout = $TimeoutSec * 1000
        $recvSocket.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0))

        $localIp = Get-LocalIpAddress
        $hops = @()

        for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
            Write-DebugLog "Raw: отправка SYN с TTL=$ttl"

            # Устанавливаем TTL
            $sendSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                                        [System.Net.Sockets.SocketOptionName]::IpTimeToLive,
                                        $ttl)

            $srcPort = Get-Random -Minimum 1024 -Maximum 65535
            $seq = Get-Random -Minimum 1 -Maximum ([uint32]::MaxValue)
            $tcpPacket = Build-TcpSynPacket -SourcePort $srcPort -DestPort $Port -Seq $seq
            $ipPacket = Build-IpPacket -SourceIp $localIp -DestIp $TargetIp -Protocol 6 -Payload $tcpPacket

            $endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($TargetIp), 0)
            $sendSocket.SendTo($ipPacket, $endpoint) | Out-Null

            $start = Get-Date
            $responderIp = $null
            $responseType = "Timeout"
            $rttMs = $null

            while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
                $buffer = New-Object byte[] 4096
                $remoteEp = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                if ($recvSocket.Poll(1000, [System.Net.Sockets.SelectMode]::SelectRead)) {
                    $bytes = $recvSocket.ReceiveFrom($buffer, [ref]$remoteEp)
                    if ($bytes -gt 0) {
                        $rttMs = ((Get-Date) - $start).TotalMilliseconds
                        $responderIp = $remoteEp.Address.ToString()
                        $responseType = Parse-IpResponse -Buffer $buffer -Bytes $bytes -TargetIp $TargetIp -TargetPort $Port
                        break
                    }
                }
            }

            $hop = [PSCustomObject]@{
                Hop          = $ttl
                IP           = $responderIp
                TcpStatus    = $responseType
                RttMs        = $rttMs
                IsBlocking   = ($responseType -eq "RST" -and $responderIp -ne $TargetIp) -or
                               ($responseType -eq "Timeout" -and $ttl -eq $MaxHops)
            }
            $hops += $hop
            Write-DebugLog "Хоп $ttl : $responderIp -> $responseType, RTT=$rttMs ms"

            # Если достигли целевого узла (SYN-ACK) или получили RST от него, выходим
            if (($responseType -eq "SYNACK" -and $responderIp -eq $TargetIp) -or
                ($responseType -eq "RST" -and $responderIp -eq $TargetIp)) {
                break
            }
        }

        return $hops
    } catch {
        Write-DebugLog "Raw sockets ошибка: $_"
        return "Raw sockets error: $_"
    } finally {
        if ($sendSocket) { $sendSocket.Close() }
        if ($recvSocket) { $recvSocket.Close() }
    }
}

# --- Комбинированный метод: ICMP traceroute + TCP probes ---
function Invoke-TcpTracerouteCombined {
    param(
        [string]$Target,
        [int]$Port,
        [int]$MaxHops,
        [int]$TimeoutSec,
        [scriptblock]$onProgress = $null
    )

    $icmpHops = @()
    
    # Пробуем Test-NetConnection
    if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
        try {
            Write-DebugLog "Пробуем Test-NetConnection"
            $result = Test-NetConnection -ComputerName $Target -Port $Port -TraceRoute -InformationLevel Detailed -ErrorAction Stop
            $hopIndex = 1
            foreach ($hop in $result.TraceRoute) {
                $icmpHops += [PSCustomObject]@{
                    Hop = $hopIndex
                    IP  = $hop.IPAddress.ToString()
                }
                $hopIndex++
            }
            Write-DebugLog "Test-NetConnection вернул $($icmpHops.Count) хопов"
        } catch {
            Write-DebugLog "Test-NetConnection не удался: $_"
        }
    }

    # Если Test-NetConnection не сработал, пробуем tracert
    if ($icmpHops.Count -eq 0) {
        Write-DebugLog "Пробуем tracert с таймаутом $TimeoutSec сек"
        
        try {
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = "tracert"
            $pinfo.Arguments = "-h $MaxHops -w 500 -4 $Target"
            $pinfo.UseShellExecute = $false
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.CreateNoWindow = $true
            
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
            
            $output = $p.StandardOutput.ReadToEnd()
            $completed = $p.WaitForExit($TimeoutSec * 1000)
            
            if (-not $completed) {
                Write-DebugLog "tracert превысил таймаут, убиваем процесс"
                try { $p.Kill() } catch { }
            }
            
            if ($output) {
                $lines = $output -split "`r`n"
                $pattern = '^\s*(\d+)\s+(\d+)\s+ms\s+(\d+)\s+ms\s+(\d+)\s+ms\s+(.*)$'
                
                foreach ($line in $lines) {
                    if ($line -match $pattern) {
                        $hopNum = [int]$matches[1]
                        $ip = $matches[5].Trim()
                        if ($ip -ne "*" -and $ip -ne "" -and $ip -match '^\d+\.\d+\.\d+\.\d+$') {
                            $icmpHops += [PSCustomObject]@{
                                Hop = $hopNum
                                IP  = $ip
                            }
                            Write-DebugLog "Найден хоп $hopNum : $ip"
                        }
                    }
                }
                Write-DebugLog "tracert распарсил $($icmpHops.Count) хопов"
            }
        } catch {
            Write-DebugLog "Ошибка при выполнении tracert: $_"
        }
    }

    # Если нет хопов, используем прямой IP
    if ($icmpHops.Count -eq 0) {
        Write-DebugLog "Не удалось получить маршрут, используем прямое подключение к цели"
        try {
            $targetResolved = [System.Net.Dns]::GetHostAddresses($Target) | 
                              Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
                              Select-Object -First 1 -ExpandProperty IPAddressToString
            if ($targetResolved) {
                $icmpHops += [PSCustomObject]@{
                    Hop = 1
                    IP  = $targetResolved
                }
                Write-DebugLog "Используем целевой IP: $targetResolved"
            }
        } catch {
            Write-DebugLog "Не удалось разрешить целевой IP: $_"
            return @()
        }
    }

    # Проверяем каждый хоп: TCP и TLS
    $resultHops = @()
    $targetResolved = $null
    try {
        $targetResolved = [System.Net.Dns]::GetHostAddresses($Target) | 
                          Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
                          Select-Object -First 1 -ExpandProperty IPAddressToString
    } catch {}

    $hopIndex = 0
    foreach ($hop in $icmpHops) {
        $hopIndex++
        
        # Проверка на прерывание по ESC (если передан блок обновления статуса)
        if ($onProgress -and [Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key
            if ($key -eq "Escape") {
                Write-DebugLog "Трассировка прервана пользователем"
                return @()
            }
        }

        # Обновляем прогресс, если передан callback
        if ($onProgress) {
            $msg = "[TRACE] Hop $($hop.Hop)/$MaxHops : $($hop.IP) - проверка TCP..."
            & $onProgress $msg
        }

        Write-DebugLog "Проверка хопа $($hop.Hop): $($hop.IP)"
        
        # 1. TCP проверка
        $tcpResult = Test-TcpPort -TargetIp $hop.IP -Port $Port -TimeoutSec 2
        
        # 2. TLS проверка (если TCP успешен)
        $tlsStatus = "N/A"
        if ($tcpResult.Status -eq "SYNACK") {
            if ($onProgress) {
                $msg = "[TRACE] Hop $($hop.Hop)/$MaxHops : $($hop.IP) - TCP OK, проверка TLS..."
                & $onProgress $msg
            }
            Write-DebugLog "  TCP OK, проверяем TLS на хопе $($hop.Hop)"
            $tlsResult = Test-TlsHandshake -TargetIp $hop.IP -Port $Port -TimeoutSec 2
            $tlsStatus = $tlsResult.Status
            Write-DebugLog "  TLS результат: $tlsStatus"
        }
        
        $resultHops += [PSCustomObject]@{
            Hop          = $hop.Hop
            IP           = $hop.IP
            TcpStatus    = $tcpResult.Status
            TlsStatus    = $tlsStatus
            RttMs        = $tcpResult.RttMs
            IsBlocking   = ($tlsStatus -eq "Timeout") -or ($tcpResult.Status -eq "RST")
        }
        
        # Обновляем прогресс с результатом
        if ($onProgress) {
            $resultMsg = if ($tlsStatus -eq "OK") { "OK" } elseif ($tcpResult.Status -eq "SYNACK") { "TCP OK" } else { $tcpResult.Status }
            $msg = "[TRACE] Hop $($hop.Hop)/$MaxHops : $($hop.IP) -> $resultMsg"
            & $onProgress $msg
        }
        
        Write-DebugLog "Хоп $($hop.Hop): $($hop.IP) -> TCP: $($tcpResult.Status), TLS: $tlsStatus, RTT=$($tcpResult.RttMs) ms"
        
        # Если TLS таймаут на промежуточном узле, это вероятное место блокировки
        if ($tlsStatus -eq "Timeout" -and $hop.IP -ne $targetResolved) {
            Write-DebugLog "!!! TLS BLOCK обнаружен на хопе $($hop.Hop) от $($hop.IP) - DPI блокирует TLS !!!"
            break
        }
        
        # Если получили RST от промежуточного узла
        if ($tcpResult.Status -eq "RST" -and $hop.IP -ne $targetResolved) {
            Write-DebugLog "!!! RST обнаружен на хопе $($hop.Hop) от $($hop.IP) - вероятно DPI !!!"
            break
        }
        
        # Если достигли целевого узла и TLS успешен
        if ($targetResolved -and $hop.IP -eq $targetResolved -and $tlsStatus -eq "OK") {
            Write-DebugLog "Достигнут целевой узел $targetResolved с успешным TLS"
            break
        }
    }

    return $resultHops
}

# Новая функция для проверки TLS рукопожатия
function Test-TlsHandshake {
    param(
        [string]$TargetIp,
        [int]$Port,
        [int]$TimeoutSec
    )
    
    $tcp = $null
    $ssl = $null
    
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $async = $tcp.BeginConnect($TargetIp, $Port, $null, $null)
        
        $hopTimeout = [Math]::Min($TimeoutSec * 1000, 3000)
        
        if (-not $async.AsyncWaitHandle.WaitOne($hopTimeout)) {
            Write-DebugLog "TLS: TCP connect timeout to $TargetIp`:$Port"
            return @{ Status = "Timeout" }
        }
        
        $tcp.EndConnect($async)
        $tcp.ReceiveTimeout = $hopTimeout
        $tcp.SendTimeout = $hopTimeout
        
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $true, { $true })
        
        $sslAsync = $ssl.BeginAuthenticateAsClient($TargetIp, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false, $null, $null)
        
        if ($sslAsync.AsyncWaitHandle.WaitOne($hopTimeout)) {
            $ssl.EndAuthenticateAsClient($sslAsync)
            $rttMs = $sw.ElapsedMilliseconds
            Write-DebugLog "TLS OK to $TargetIp`:$Port in ${rttMs}ms"
            return @{ Status = "OK"; RttMs = $rttMs }
        } else {
            Write-DebugLog "TLS timeout to $TargetIp`:$Port after $hopTimeout ms"
            return @{ Status = "Timeout" }
        }
    } catch {
        $msg = $_.Exception.Message
        Write-DebugLog "TLS error to $TargetIp`:$Port : $msg"
        if ($msg -match "сброс|reset|RST|разорвано|refused|отказано") {
            return @{ Status = "RST" }
        }
        if ($msg -match "certificate|сертификат") {
            # Сертификат может быть проблемой, но соединение установлено
            return @{ Status = "OK" }
        }
        return @{ Status = "Error" }
    } finally {
        if ($ssl) { try { $ssl.Close() } catch {} }
        if ($tcp) { try { $tcp.Close() } catch {} }
    }
}

# ====================================================================================
# UPDATER АПДЕЙТЕР ОБНОВЛЕНИЕ СКРИПТА ЧЕРЕЗ GITHUB
# ====================================================================================
function Invoke-Update {
    param($Config)
    Draw-StatusBar -Message "[ UPDATE ] Checking GitHub for latest release..." -Fg "Black" -Bg "Cyan"
    
    $res = Check-UpdateVersion -ManualMode -IgnoreLastChecked
    
    if ($res -eq "LATEST") {
        Draw-StatusBar -Message "[ UPDATE ] You are already using the latest version ($scriptVersion)." -Fg "Black" -Bg "DarkGreen"
        # Обновляем LastCheckedVersion
        $Config.LastCheckedVersion = $scriptVersion
        Save-Config $Config
        Start-Sleep -Seconds 2
    }
    elseif ($res -eq "DEV_VERSION") {
        Draw-StatusBar -Message "[ UPDATE ] Your version ($scriptVersion) is newer than GitHub release ($res)." -Fg "Black" -Bg "Magenta"
        # Обновляем LastCheckedVersion, чтобы не показывать снова
        $Config.LastCheckedVersion = $scriptVersion
        Save-Config $Config
        Start-Sleep -Seconds 3
    }
    elseif ($null -ne $res) {
        Draw-StatusBar -Message "[ UPDATE ] New version $res available! Download now? (Y/N)" -Fg "Black" -Bg "Yellow"
        $key = [Console]::ReadKey($true).KeyChar
        if ($key -eq 'y' -or $key -eq 'Y') {
            $currentFile = $script:OriginalFilePath
            $downloadUrl = "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.bat"
            Start-Updater $currentFile $downloadUrl
            exit
        } else {
            # Если отказались, запоминаем, что предложили эту версию
            $Config.LastCheckedVersion = $res
            Save-Config $Config
        }
    } else {
        Draw-StatusBar -Message "[ UPDATE ] Update server unreachable or API limit reached." -Fg "Black" -Bg "Red"
        Start-Sleep -Seconds 2
    }
}

# --- Вспомогательные функции ---
function Get-LocalIpAddress {
    try {
        # Способ 1: через WMI (работает на Windows 7)
        $ip = Get-WmiObject Win32_NetworkAdapterConfiguration | 
              Where-Object { $_.IPEnabled -and $_.DefaultIPGateway } | 
              Select-Object -First 1 -ExpandProperty IPAddress | 
              Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | 
              Select-Object -First 1
        
        if (-not $ip) {
            # Способ 2: через .NET DNS
            $hostName = [System.Net.Dns]::GetHostName()
            $ip = [System.Net.Dns]::GetHostAddresses($hostName) | 
                  Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
                  Select-Object -First 1 -ExpandProperty IPAddressToString
        }
        
        if (-not $ip) {
            $ip = "127.0.0.1"
        }
        
        Write-DebugLog "Get-LocalIpAddress: $ip"
        return $ip
    } catch {
        Write-DebugLog "Get-LocalIpAddress ошибка: $_"
        return "127.0.0.1"
    }
}

function Build-TcpSynPacket {
    param(
        [int]$SourcePort,
        [int]$DestPort,
        [uint32]$Seq
    )
    $tcp = New-Object byte[] 20
    [System.BitConverter]::GetBytes([uint16]$SourcePort).CopyTo($tcp, 0)
    [System.BitConverter]::GetBytes([uint16]$DestPort).CopyTo($tcp, 2)
    [System.BitConverter]::GetBytes($Seq).CopyTo($tcp, 4)
    $tcp[12] = 0x50   # Data offset 5
    $tcp[13] = 0x02   # SYN flag
    [System.BitConverter]::GetBytes([uint16]8192).CopyTo($tcp, 14)
    # Checksum позже, временно 0
    return $tcp
}

function Build-IpPacket {
    param(
        [string]$SourceIp,
        [string]$DestIp,
        [byte]$Protocol,
        [byte[]]$Payload
    )
    $totalLen = 20 + $Payload.Length
    $ip = New-Object byte[] $totalLen
    $ip[0] = 0x45
    [System.BitConverter]::GetBytes([uint16]$totalLen).CopyTo($ip, 2)
    $ip[8] = 64
    $ip[9] = $Protocol
    [System.Net.IPAddress]::Parse($SourceIp).GetAddressBytes().CopyTo($ip, 12)
    [System.Net.IPAddress]::Parse($DestIp).GetAddressBytes().CopyTo($ip, 16)
    
    $checksum = Compute-IpChecksum $ip
    [System.BitConverter]::GetBytes($checksum).CopyTo($ip, 10)
    $Payload.CopyTo($ip, 20)
    return $ip
}

function Compute-IpChecksum {
    param([byte[]]$header)
    $sum = 0
    for ($i = 0; $i -lt $header.Length - 1; $i += 2) {
        $word = [System.BitConverter]::ToUInt16($header, $i)
        $sum += $word
        if ($sum -gt 0xFFFF) { 
            $sum = ($sum -band 0xFFFF) + 1 
        }
    }
    # Побитовое дополнение (one's complement)
    $sum = (-bnot $sum) -band 0xFFFF
    return [uint16]$sum
}

function Parse-IpResponse {
    param(
        [byte[]]$Buffer,
        [int]$Bytes,
        [string]$TargetIp,
        [int]$TargetPort
    )
    if ($Bytes -lt 20) { return "Unknown" }
    $protocol = $Buffer[9]
    if ($protocol -eq 1) { # ICMP
        $type = $Buffer[20]
        if ($type -eq 11) { return "TimeExceeded" }
        else { return "ICMP_$type" }
    } elseif ($protocol -eq 6) { # TCP
        $ipHeaderLen = ($Buffer[0] -band 0x0F) * 4
        if ($Bytes -lt $ipHeaderLen + 20) { return "Unknown" }
        $tcpOffset = $ipHeaderLen
        $flags = $Buffer[$tcpOffset + 13]
        if (($flags -band 0x12) -eq 0x12) { return "SYNACK" }
        if (($flags -band 0x04) -eq 0x04) { return "RST" }
        return "TCP_Other"
    }
    return "Unknown"
}

function Test-TcpPort {
    param(
        [string]$TargetIp,
        [int]$Port,
        [int]$TimeoutSec
    )
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $async = $tcp.BeginConnect($TargetIp, $Port, $null, $null)
        
        # Уменьшаем таймаут для отдельных хопов
        $hopTimeout = [Math]::Min($TimeoutSec * 1000, 2000)
        
        if ($async.AsyncWaitHandle.WaitOne($hopTimeout)) {
            $tcp.EndConnect($async)
            $rttMs = $sw.ElapsedMilliseconds
            return @{ Status = "SYNACK"; RttMs = $rttMs }
        } else {
            Write-DebugLog "Timeout connecting to $TargetIp`:$Port after $hopTimeout ms"
            return @{ Status = "Timeout"; RttMs = $null }
        }
    } catch {
        $msg = $_.Exception.Message
        Write-DebugLog "Connection error to $TargetIp`:$Port : $msg"
        if ($msg -match "сброс|reset|RST|разорвано|refused|отказано") {
            return @{ Status = "RST"; RttMs = $null }
        }
        return @{ Status = "Error"; RttMs = $null }
    } finally {
        if ($tcp) { 
            try { $tcp.Close() } catch { }
        }
    }
}

# ====================================================================================
# ФУНКЦИЯ ПОДКЛЮЧЕНИЯ ЧЕРЕЗ ПРОКСИ
# ====================================================================================
function Connect-ThroughProxy {
        param(
            $TargetHost,
            $TargetPort,
            $ProxyConfig,
            [int]$Timeout = $CONST.ProxyTimeout
        )
        Write-DebugLog "Connect-ThroughProxy: $($ProxyConfig.Type) $($ProxyConfig.Host):$($ProxyConfig.Port) -> $($TargetHost):$($TargetPort)"
        
        $maxAttempts = 3
        $delayMs = 500
        $lastError = $null

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $tcp = $null
            $stream = $null
            try {
                Write-DebugLog "Попытка $attempt подключения к $($ProxyConfig.Host):$($ProxyConfig.Port)"
                $tcp = New-Object System.Net.Sockets.TcpClient
                $asyn = $tcp.BeginConnect($ProxyConfig.Host, $ProxyConfig.Port, $null, $null)
                if (-not $asyn.AsyncWaitHandle.WaitOne($Timeout)) {
                    throw "Proxy connection timeout"
                }
                $tcp.EndConnect($asyn)
                $stream = $tcp.GetStream()
                $stream.ReadTimeout = $Timeout
                $stream.WriteTimeout = $Timeout

                if ($ProxyConfig.Type -eq "SOCKS5") {
                    Write-DebugLog "SOCKS5: начало рукопожатия"

                    # === Определяем, какие методы аутентификации предложить ===
                    $methods = @()
                    if ($ProxyConfig.User -and $ProxyConfig.Pass) {
                        # Если есть логин/пароль, предлагаем сначала аутентификацию по паролю (0x02), затем без аутентификации (0x00)
                        $methods = @(0x02, 0x00)
                    } else {
                        # Без аутентификации предлагаем только 0x00
                        $methods = @(0x00)
                    }
                    $greeting = [byte[]](@(0x05, $methods.Count) + $methods)
                    $stream.Write($greeting, 0, $greeting.Length)

                    # Читаем ответ сервера (2 байта: VER, METHOD)
                    $resp = New-Object byte[] 2
                    if ($stream.Read($resp, 0, 2) -ne 2) {
                        throw "SOCKS5: нет ответа на выбор метода"
                    }
                    if ($resp[0] -ne 0x05) {
                        throw "SOCKS5: неверная версия ответа (ожидалась 0x05, получена 0x$('{0:X2}' -f $resp[0]))"
                    }

                    $method = $resp[1]
                    Write-DebugLog "SOCKS5: сервер выбрал метод аутентификации 0x$('{0:X2}' -f $method)"

                    # === Обработка выбранного метода ===
                    if ($method -eq 0x00) {
                        # Без аутентификации — ничего не делаем
                        Write-DebugLog "SOCKS5: аутентификация не требуется"
                    }
                    elseif ($method -eq 0x02) {
                        # Аутентификация по логину/паролю
                        if (-not $ProxyConfig.User -or -not $ProxyConfig.Pass) {
                            throw "SOCKS5: сервер требует логин/пароль, но они не указаны в настройках"
                        }
                        $u = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.User)
                        $p = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.Pass)
                        $authMsg = [byte[]](@(0x01, $u.Length) + $u + @($p.Length) + $p)
                        $stream.Write($authMsg, 0, $authMsg.Length)

                        $authResp = New-Object byte[] 2
                        if ($stream.Read($authResp, 0, 2) -ne 2) {
                            throw "SOCKS5: нет ответа на аутентификацию"
                        }
                        if ($authResp[0] -ne 0x01 -or $authResp[1] -ne 0x00) {
                            throw "SOCKS5: неверный логин/пароль (код $($authResp[1]))"
                        }
                        Write-DebugLog "SOCKS5: аутентификация успешна"
                    }
                    elseif ($method -eq 0xFF) {
                        throw "SOCKS5: сервер отверг все предложенные методы аутентификации (0xFF). Проверьте, требуется ли аутентификация."
                    }
                    else {
                        throw "SOCKS5: сервер выбрал неподдерживаемый метод аутентификации 0x$('{0:X2}' -f $method)"
                    }

                    # === Запрос на подключение к целевому хосту ===
                    $addrType = 0x03   # domain name
                    $hostBytes = [Text.Encoding]::UTF8.GetBytes($TargetHost)
                    $req = [byte[]](@(0x05, 0x01, 0x00, $addrType, $hostBytes.Length) + $hostBytes + @([math]::Floor($TargetPort/256), ($TargetPort%256)))
                    $stream.Write($req, 0, $req.Length)

                    # Читаем ответ (минимум 10 байт)
                    $resp = New-Object byte[] 10
                    $read = 0
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($read -lt 10 -and $sw.ElapsedMilliseconds -lt $Timeout) {
                        if ($stream.DataAvailable) {
                            $r = $stream.Read($resp, $read, 10 - $read)
                            if ($r -eq 0) { break }
                            $read += $r
                        } else { Start-Sleep -Milliseconds 20 }
                    }
                    if ($read -lt 10) { throw "SOCKS5: неполный ответ на запрос подключения" }
                    if ($resp[0] -ne 0x05) { throw "SOCKS5: неверная версия в ответе на подключение" }
                    if ($resp[1] -ne 0x00) {
                        $repCode = $resp[1]
                        $errorMap = @{
                            0x01 = "general failure"
                            0x02 = "connection not allowed"
                            0x03 = "network unreachable"
                            0x04 = "host unreachable"
                            0x05 = "connection refused"
                            0x06 = "TTL expired"
                            0x07 = "command not supported"
                            0x08 = "address type not supported"
                        }
                        $errText = if ($errorMap.ContainsKey($repCode)) { $errorMap[$repCode] } else { "unknown error 0x$('{0:X2}' -f $repCode)" }
                        throw "SOCKS5: сервер вернул ошибку - $errText"
                    }
                    Write-DebugLog "SOCKS5: маршрут установлен успешно"
                    return @{ Tcp = $tcp; Stream = $stream }
                }
            } catch {
                $lastError = $_
                Write-DebugLog "Ошибка подключения к прокси (попытка $attempt): $lastError"
                if ($tcp) { try { $tcp.Close() } catch {} }
                if ($attempt -eq $maxAttempts) { throw $lastError }
                $sleep = $delayMs * [math]::Pow(2, $attempt - 1)
                Start-Sleep -Milliseconds $sleep
            }
        }
    }

    # Вспомогательная функция для чтения фиксированного количества байт с таймаутом
    function Read-StreamWithTimeout($stream, $buffer, $count, $timeout) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $totalRead = 0
        while ($totalRead -lt $count) {
            if ($sw.ElapsedMilliseconds -ge $timeout) { return $totalRead }
            if ($stream.DataAvailable) {
                $read = $stream.Read($buffer, $totalRead, $count - $totalRead)
                if ($read -eq 0) { return $totalRead }
                $totalRead += $read
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
        return $totalRead
    }

    # Вспомогательная функция для чтения HTTP-ответа до \r\n\r\n
    function Read-HttpResponse($stream, $timeout) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = ""
        $buffer = New-Object byte[] 1024
        while ($sw.ElapsedMilliseconds -lt $timeout) {
            if ($stream.DataAvailable) {
                $read = $stream.Read($buffer, 0, 1024)
                if ($read -gt 0) {
                    $response += [Text.Encoding]::ASCII.GetString($buffer, 0, $read)
                    if ($response -match "\r\n\r\n") { break }
                } else { break }
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
        return $response
    }

# ====================================================================================
# СЕТЕВЫЕ ФУНКЦИИ
# ====================================================================================
function Invoke-WebRequestViaProxy($Url, $Method = "GET", $Timeout = $CONST.TimeoutMs) {
    Write-DebugLog "Invoke-WebRequestViaProxy: $Method $Url"
    $uri = [System.Uri]$Url
    
    # Режим прямого подключения или HTTP-прокси
    if (-not $global:ProxyConfig.Enabled -or $global:ProxyConfig.Type -eq "HTTP") {
        try {
            $req = [System.Net.WebRequest]::Create($uri)
            $req.Timeout = $Timeout
            $req.UserAgent = $script:UserAgent
            if ($global:ProxyConfig.Enabled) {
                $wp = New-Object System.Net.WebProxy($global:ProxyConfig.Host, $global:ProxyConfig.Port)
                if ($global:ProxyConfig.User) { $wp.Credentials = New-Object System.Net.NetworkCredential($global:ProxyConfig.User, $global:ProxyConfig.Pass) }
                $req.Proxy = $wp
            } else { $req.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy() }
            
            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $content = $reader.ReadToEnd()
            $resp.Close()
            return $content
        } catch { return "" }
    } 
    # Режим SOCKS5 (Исправлено для HTTPS)
    else {
        try {
            $conn = Connect-ThroughProxy $uri.Host $uri.Port $global:ProxyConfig $Timeout
            $stream = $conn.Stream

            # --- КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: SSL-обертка для SOCKS ---
            if ($uri.Scheme -eq "https") {
                $sslStream = New-Object System.Net.Security.SslStream($stream, $false, { $true })
                $sslStream.AuthenticateAsClient($uri.Host)
                $stream = $sslStream
            }

            $request = "$Method $($uri.PathAndQuery) HTTP/1.1`r`nHost: $($uri.Host)`r`nUser-Agent: $script:UserAgent`r`nConnection: close`r`n`r`n"
            $reqBytes = [Text.Encoding]::ASCII.GetBytes($request)
            $stream.Write($reqBytes, 0, $reqBytes.Length)

            $buf = New-Object byte[] 8192
            $respBytes = New-Object System.Collections.Generic.List[byte]
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            while ($sw.ElapsedMilliseconds -lt $Timeout) {
                if ($conn.Tcp.Available -gt 0 -or ($uri.Scheme -eq "https" -and $true)) {
                    try {
                        $read = $stream.Read($buf, 0, 8192)
                        if ($read -gt 0) { 
                            for ($i=0; $i -lt $read; $i++) { $respBytes.Add($buf[$i]) } 
                        } else { break }
                    } catch { break }
                } else { Start-Sleep -Milliseconds 50 }
            }
            
            $fullResponse = [Text.Encoding]::UTF8.GetString($respBytes.ToArray())
            $conn.Tcp.Close()
            
            # Извлекаем только тело ответа (после \r\n\r\n)
            if ($fullResponse -match '(?s)\r\n\r\n(.*)') {
                return $matches[1]
            }
            return $fullResponse
        } catch {
            Write-DebugLog "SOCKS WebRequest Error: $($_.Exception.Message)"
            return ""
        }
    }
}

function Get-NetworkInfo {
    Write-DebugLog "Get-NetworkInfo: начало"
    $dns = "UNKNOWN"
    try {
        $wmi = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | 
               Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
        if ($wmi) { $dns = $wmi.DNSServerSearchOrder[0] }
    } catch { }

    $cdn = "manifest.googlevideo.com"
    $isp = "UNKNOWN"; $loc = "UNKNOWN"
    
    # Список провайдеров ГЕО (отсортированы по надежности через прокси)
    $geoProviders = @(
        @{ url = "http://ip-api.com/json/?fields=status,countryCode,city,isp"; type = "ip-api" },
        @{ url = "https://ipapi.co/json/"; type = "ipapi-co" },
        @{ url = "http://worldtimeapi.org/api/ip"; type = "worldtime" } # Резерв для LOC
    )

    :providerLoop foreach ($prov in $geoProviders) {
        Write-DebugLog "Попытка ГЕО через $($prov.type)..."
        $raw = Invoke-WebRequestViaProxy $prov.url -Timeout 5000
        if ($raw -match '\{.*\}') {
            try {
                $data = $raw | ConvertFrom-Json
                if ($prov.type -eq "ip-api" -and $data.status -eq "success") {
                    $isp = $data.isp; $loc = "$($data.city), $($data.countryCode)"
                }
                elseif ($prov.type -eq "ipapi-co" -and $data.org) {
                    $isp = $data.org; $loc = "$($data.city), $($data.country_code)"
                }
                
                if ($isp -ne "UNKNOWN" -and $isp -ne $null) {
                    Write-DebugLog "Гео получено ($($prov.type)): $isp" "INFO"
                    break providerLoop
                }
            } catch { }
        }
    }

    # Очистка названия ISP
    $isp = $isp -replace '(?i)\s*(LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC|Private Enterprise|Group|Corporation)', ''
    if ($isp.Length -gt 25) { $isp = $isp.Substring(0, 22) + '...' }

    # Быстрый тест IPv6
    # 4. Проверка IPv6 (только если не выбран режим IPv4 Only)
    $hasV6 = $false
    if ($script:Config.IpPreference -ne "IPv4") {
        try {
            $t = New-Object System.Net.Sockets.TcpClient([System.Net.Sockets.AddressFamily]::InterNetworkV6)
            $a = $t.BeginConnect("ipv6.google.com", 80, $null, $null)
            if ($a.AsyncWaitHandle.WaitOne(1000)) { # Уменьшили до 1 сек
                $t.EndConnect($a)
                $hasV6 = $true 
            }
            $t.Close()
        } catch { }
    }

    return @{ DNS=$dns; CDN=$cdn; ISP=$isp; LOC=$loc; TimestampTicks=(Get-Date).Ticks; HasIPv6=$hasV6 }
}

function Show-SettingsMenu {
    while ($true) {
        [Console]::Clear()
        $w = [Console]::WindowWidth
        if ($w -gt 80) { $w = 80 }
        $line = "═" * $w
        
        Write-Host "`n $line" -ForegroundColor Cyan
        Write-Host (Get-PaddedCenter "SETTINGS / НАСТРОЙКИ" $w) -ForegroundColor Yellow
        Write-Host " $line" -ForegroundColor Cyan

        # Безопасное получение текущей настройки
        $curPref = "IPv6"
        if ($script:Config -and $script:Config.IpPreference) { 
            $curPref = $script:Config.IpPreference 
        }

        Write-Host "`n  1. Протокол IP : " -NoNewline -ForegroundColor White
        if ($curPref -eq "IPv6") {
            Write-Host "[ IPv6 ПРИОРИТЕТ ]" -ForegroundColor Green
            Write-Host "     (Используется IPv6, если доступен. Откат на IPv4 при ошибках)" -ForegroundColor Gray
        } else {
            Write-Host "[ ТОЛЬКО IPv4 ]" -ForegroundColor Yellow
            Write-Host "     (IPv6 полностью игнорируется)" -ForegroundColor Gray
        }

        Write-Host "`n  2. Сброс сетевого кэша" -ForegroundColor White
        Write-Host "     (Очистка DNS-записей и данных о провайдере)" -ForegroundColor Gray

        Write-Host "`n  0. Назад в главное меню" -ForegroundColor DarkGray
        Write-Host "`n $line" -ForegroundColor Cyan
        Write-Host " ВЫБЕРИТЕ ПУНКТ: " -NoNewline -ForegroundColor Yellow

        $key = [Console]::ReadKey($true).KeyChar
        
        try {
            if ($key -eq "1") {
                $newVal = if ($curPref -eq "IPv6") { "IPv4" } else { "IPv6" }
                
                # Вместо прямого присвоения используем Add-Member с ключом -Force
                # Это сработает, даже если поля не было
                $script:Config | Add-Member -MemberType NoteProperty -Name "IpPreference" -Value $newVal -Force
                
                $script:DnsCache = [hashtable]::Synchronized(@{}) 
                Save-Config $script:Config
            }
            elseif ($key -eq "2") {
                # Безопасная очистка
                $script:DnsCache = [hashtable]::Synchronized(@{})
                
                if ($script:Config.NetCache) {
                    $script:Config.NetCache.ISP = "Loading..."
                }
                
                Save-Config $script:Config
                Write-Host "`n  [OK] Кэш очищен!" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            elseif ($key -eq "0" -or $key -eq "`r") {
                break
            }
        } catch {
            Write-DebugLog "Ошибка в меню настроек: $_" "ERROR"
            # Ошибка не выводится в консоль, чтобы не пугать юзера, а пишется в лог
        }
    }
}

function Show-ProxyMenu {
    [Console]::Clear()
    $w = [Console]::WindowWidth
    if ($w -gt 100) { $w = 100 }
    $line = "═" * $w
    $dash = "─" * $w
    
    # Заголовок
    Write-Host "`n $line" -ForegroundColor Cyan
    Write-Host (Get-PaddedCenter "НАСТРОЙКА ПРОКСИ" $w) -ForegroundColor Yellow
    Write-Host " $line" -ForegroundColor Cyan
    
    # Текущий статус
    if ($global:ProxyConfig.Enabled) {
        Write-Host "`n  ТЕКУЩИЙ ПРОКСИ: " -NoNewline -ForegroundColor White
        Write-Host "$($global:ProxyConfig.Type)://" -NoNewline -ForegroundColor Green
        if ($global:ProxyConfig.User) {
            Write-Host "$($global:ProxyConfig.User):*****@" -NoNewline -ForegroundColor DarkYellow
        }
        Write-Host "$($global:ProxyConfig.Host):$($global:ProxyConfig.Port)" -ForegroundColor Green
    } else {
        Write-Host "`n  ТЕКУЩИЙ ПРОКСИ: " -NoNewline -ForegroundColor White
        Write-Host "ОТКЛЮЧЕН" -ForegroundColor Red
    }
    
    # История
    $history = $script:Config.ProxyHistory
    if ($history -and $history.Count -gt 0) {
        Write-Host "`n  ИСТОРИЯ (выберите номер):" -ForegroundColor Cyan
        for ($i = 0; $i -lt $history.Count; $i++) {
            Write-Host "    $($i+1). $($history[$i])" -ForegroundColor Gray
        }
        Write-Host "    0. Очистить историю" -ForegroundColor DarkGray
    }
    
    # Инструкция
    Write-Host "`n $dash" -ForegroundColor Gray
    Write-Host "  ФОРМАТЫ ВВОДА:" -ForegroundColor Cyan
    Write-Host "    * host:port                      - HTTP (автоопределение)" -ForegroundColor Gray
    Write-Host "    * http://host:port               - HTTP явно" -ForegroundColor Gray
    Write-Host "    * socks5://host:port             - SOCKS5 явно" -ForegroundColor Gray
    Write-Host "    * user:pass@host:port            - с аутентификацией" -ForegroundColor Gray
    Write-Host "    * http://user:pass@host:port     - HTTP с аутентификацией" -ForegroundColor Gray
    Write-Host "    * socks5://user:pass@host:port   - SOCKS5 с аутентификацией" -ForegroundColor Gray
    Write-Host "    * OFF / 0 / пусто                - отключить прокси" -ForegroundColor Gray
    Write-Host "    * TEST                           - протестировать текущий прокси" -ForegroundColor Gray
    Write-Host "    * CLEAR                          - очистить историю" -ForegroundColor Gray
    
    Write-Host "`n $dash" -ForegroundColor Gray
    Write-Host "  ВВОД: " -NoNewline -ForegroundColor Yellow
    
    [Console]::ForegroundColor = "White"
    [Console]::CursorVisible = $true
    $userInput = [Console]::ReadLine().Trim()
    [Console]::CursorVisible = $false
    
    Write-DebugLog "Show-ProxyMenu: Введено = '$userInput'"
    
    # Обработка команд
    if ($userInput -eq "" -or $userInput -eq "OFF" -or $userInput -eq "off" -or $userInput -eq "0") {
        $global:ProxyConfig.Enabled = $false
        $global:ProxyConfig.User = ""
        $global:ProxyConfig.Pass = ""
        Write-Host "`n  [OK] Прокси отключен." -ForegroundColor Green
        Save-Config $script:Config
        Start-Sleep -Seconds 1.5
        return
    }
    
    if ($userInput -eq "TEST" -or $userInput -eq "test") {
        if (-not $global:ProxyConfig.Enabled) {
            Write-Host "`n  [FAIL] Прокси не включен. Сначала настройте его." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Show-ProxyMenu
            return
        }
        Write-Host "`n  [WAIT] Тестирование прокси..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500
        Test-ProxyConnection
        Show-ProxyMenu
        return
    }
    
    if ($userInput -eq "CLEAR" -or $userInput -eq "clear") {
        $script:Config.ProxyHistory = @()
        Save-Config $script:Config
        Write-Host "`n  [OK] История прокси очищена." -ForegroundColor Green
        Start-Sleep -Seconds 1.5
        Show-ProxyMenu
        return
    }
    
    # Проверяем, не номер ли это из истории
    $selectedIndex = -1
    if ($userInput -match '^\d+$') {
        $num = [int]$userInput
        if ($num -ge 1 -and $num -le $history.Count) {
            $selectedIndex = $num - 1
            Write-DebugLog "Show-ProxyMenu: Выбран прокси из истории #$num"
            # Распарсим строку истории
            $historyEntry = $history[$selectedIndex]
            # Формат: Type://[user:*****@]host:port
            if ($historyEntry -match '^(?i)(http|socks5)://(?:([^:]+):\*\*\*\*\*@)?([^:]+):(\d+)$') {
                $proto = $matches[1].ToUpper()
                $user = if ($matches[2]) { $matches[2] } else { "" }
                $proxyHost = $matches[3]   # переименовано
                $port = [int]$matches[4]
                $pass = ""
                # Если есть логин, запросим пароль
                if ($user) {
                    Write-Host "`n  [i] Прокси с аутентификацией. Введите пароль:" -ForegroundColor Yellow
                    [Console]::CursorVisible = $true
                    $pass = [Console]::ReadLine()
                    [Console]::CursorVisible = $false
                }
                # Сохраняем конфиг
                $global:ProxyConfig.Enabled = $true
                $global:ProxyConfig.Type = $proto
                $global:ProxyConfig.Host = $proxyHost
                $global:ProxyConfig.Port = $port
                $global:ProxyConfig.User = $user
                $global:ProxyConfig.Pass = $pass
                Write-Host "`n  [WAIT] Проверка работоспособности прокси..." -ForegroundColor Yellow
                $testResult = Test-ProxyQuick $global:ProxyConfig
                if ($testResult.Success) {
                    Write-Host "  [OK] Прокси работает! (задержка: $($testResult.Latency) мс)" -ForegroundColor Green
                    Write-Host "  [OK] Тип: $($global:ProxyConfig.Type)" -ForegroundColor Green
                    if ($user) {
                        Write-Host "  [OK] Аутентификация настроена" -ForegroundColor Green
                    }
                    # Добавляем в историю (обновим, чтобы пароль в истории был скрыт, но запись может уже быть)
                    Add-ToProxyHistory $global:ProxyConfig
                    Save-Config $script:Config
                    Start-Sleep -Seconds 2
                    return
                } else {
                    Write-Host "  [FAIL] Прокси НЕ РАБОТАЕТ: $($testResult.Error)" -ForegroundColor Red
                    Write-Host "  [i] Проверьте параметры." -ForegroundColor Gray
                    Start-Sleep -Seconds 3
                    Show-ProxyMenu
                    return
                }
            } else {
                Write-Host "`n  [FAIL] Не удалось распарсить запись истории." -ForegroundColor Red
                Start-Sleep -Seconds 2
                Show-ProxyMenu
                return
            }
        }
    }
    
    # --- ПАРСИНГ нового прокси ---
    Write-DebugLog "Show-ProxyMenu: Начинаем парсинг нового прокси '$userInput'"

    $proxyType = "AUTO"
    $user = ""
    $pass = ""
    $proxyHost = ""
    $port = 0

    # Удаляем пробелы
    $userInput = $userInput.Trim()
    if ($userInput -eq "") {
        Write-Host "`n  [FAIL] Пустой ввод." -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-ProxyMenu
        return
    }

    # 1. Проверяем наличие протокола (http:// или socks5://)
    if ($userInput -match '^(?i)(http|socks5)://') {
        $protocol = $matches[1].ToUpper()
        $proxyType = $protocol
        $userInput = $userInput -replace '^(?i)(http|socks5)://', ''
        Write-DebugLog "Show-ProxyMenu: Обнаружен протокол $proxyType, остаток = '$userInput'"
    }

    # 2. Проверяем наличие аутентификации user:pass@
    if ($userInput -match '^([^@]+)@') {
        $authPart = $matches[1]
        $userInput = $userInput -replace '^[^@]+@', ''
        Write-DebugLog "Show-ProxyMenu: Обнаружена аутентификация, authPart = '$authPart'"
        if ($authPart -match '^([^:]+):(.+)$') {
            $user = $matches[1]
            $pass = $matches[2]
            Write-DebugLog "Show-ProxyMenu: User = '$user', Pass = '***'"
        } else {
            Write-DebugLog "Show-ProxyMenu: Ошибка формата аутентификации"
            Write-Host "`n  [FAIL] Неверный формат аутентификации! Используйте user:pass@host:port" -ForegroundColor Red
            Start-Sleep -Seconds 3
            Show-ProxyMenu
            return
        }
    }

    # 3. Парсим хост и порт (последнее двоеточие)
    $lastColon = $userInput.LastIndexOf(':')
    if ($lastColon -le 0) {
        Write-DebugLog "Show-ProxyMenu: Не найдено двоеточие в '$userInput'"
        Write-Host "`n  [FAIL] Неверный формат! Используйте host:port (например 127.0.0.1:1080)" -ForegroundColor Red
        Start-Sleep -Seconds 3
        Show-ProxyMenu
        return
    }

    $proxyHost = $userInput.Substring(0, $lastColon)
    $portStr = $userInput.Substring($lastColon + 1)

    Write-DebugLog "Show-ProxyMenu: Host = '$proxyHost', PortStr = '$portStr'"

    if (-not [int]::TryParse($portStr, [ref]$port)) {
        Write-DebugLog "Show-ProxyMenu: Не удалось распарсить порт"
        Write-Host "`n  [FAIL] Неверный формат порта! Порт должен быть числом (1-65535)" -ForegroundColor Red
        Start-Sleep -Seconds 3
        Show-ProxyMenu
        return
    }

    if ($port -lt 1 -or $port -gt 65535) {
        Write-DebugLog "Show-ProxyMenu: Порт вне диапазона: $port"
        Write-Host "`n  [FAIL] Порт должен быть в диапазоне 1-65535" -ForegroundColor Red
        Start-Sleep -Seconds 3
        Show-ProxyMenu
        return
    }

    if ([string]::IsNullOrEmpty($proxyHost)) {
        Write-DebugLog "Show-ProxyMenu: Пустой хост"
        Write-Host "`n  [FAIL] Хост не указан" -ForegroundColor Red
        Start-Sleep -Seconds 3
        Show-ProxyMenu
        return
    }

    Write-DebugLog "Show-ProxyMenu: Парсинг успешен! Host='$proxyHost', Port=$port, Type=$proxyType, User='$user'"

    Write-Host "`n  [WAIT] Проверка работоспособности прокси..." -ForegroundColor Yellow

    # Если тип AUTO, пытаемся определить
    if ($proxyType -eq "AUTO") {
        Write-DebugLog "Show-ProxyMenu: Определяем тип прокси для $proxyHost`:$port"
        $detected = Detect-ProxyType $proxyHost $port
        if ($detected.Type -eq "UNKNOWN") {
            Write-Host "`n  [FAIL] Не удалось определить тип прокси (проверьте порт)" -ForegroundColor Red
            Start-Sleep -Seconds 3
            Show-ProxyMenu
            return
        }
        $proxyType = $detected.Type
        Write-DebugLog "Show-ProxyMenu: Определен тип = $proxyType"
    }

    # Сохраняем настройки
    $global:ProxyConfig.Enabled = $true
    $global:ProxyConfig.Type = $proxyType
    $global:ProxyConfig.Host = $proxyHost
    $global:ProxyConfig.Port = $port
    $global:ProxyConfig.User = $user
    $global:ProxyConfig.Pass = $pass

    # Тестируем прокси
    $testResult = Test-ProxyQuick $global:ProxyConfig

    if ($testResult.Success) {
        Write-Host "  [OK] Прокси работает! (задержка: $($testResult.Latency) мс)" -ForegroundColor Green
        Write-Host "  [OK] Тип: $($global:ProxyConfig.Type)" -ForegroundColor Green
        if ($global:ProxyConfig.User) {
            Write-Host "  [OK] Аутентификация настроена" -ForegroundColor Green
        }
        # Добавляем в историю
        Add-ToProxyHistory $global:ProxyConfig
        Save-Config $script:Config
        Start-Sleep -Seconds 2
    } else {
        Write-Host "  [FAIL] Прокси НЕ РАБОТАЕТ: $($testResult.Error)" -ForegroundColor Red
        Write-Host "  [i] Проверьте адрес, порт и тип прокси" -ForegroundColor Gray
        $global:ProxyConfig.Enabled = $false
        Start-Sleep -Seconds 3
        Show-ProxyMenu
        return
    }
}



function Detect-ProxyType {
    param([string]$targetHost, [int]$targetPort)
    
    $result = @{
        Type = "UNKNOWN"
        User = ""
        Pass = ""
    }
    
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($targetHost, $targetPort, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(2000)) {
            return $result
        }
        $tcp.EndConnect($async)
        $stream = $tcp.GetStream()
        $stream.ReadTimeout = 2000
        $stream.WriteTimeout = 2000
        
        # Пробуем SOCKS5
        try {
            $stream.Write([byte[]]@(0x05, 0x01, 0x00), 0, 3)
            $buf = New-Object byte[] 2
            $read = $stream.Read($buf, 0, 2)
            if ($read -eq 2 -and $buf[0] -eq 0x05) {
                $result.Type = "SOCKS5"
                return $result
            }
        } catch { 
            # Не SOCKS5, пробуем HTTP
        }
        
        # Пробуем HTTP CONNECT
        try {
            $req = [Text.Encoding]::ASCII.GetBytes("CONNECT google.com:80 HTTP/1.1`r`nHost: google.com:80`r`n`r`n")
            $stream.Write($req, 0, $req.Length)
            $buf = New-Object byte[] 128
            $read = $stream.Read($buf, 0, 128)
            $response = [Text.Encoding]::ASCII.GetString($buf, 0, $read)
            if ($response -match "HTTP/1.[01]\s+200") {
                $result.Type = "HTTP"
                return $result
            }
        } catch {
            # Не HTTP
        }
        
    } catch {
        # Ошибка подключения
    } finally {
        if ($tcp) { $tcp.Close() }
    }
    
    return $result
}

function Test-ProxyQuick {
    param($ProxyConfig)
    
    $result = @{
        Success = $false
        Latency = $null
        Error = ""
    }
    
    if ([string]::IsNullOrEmpty($ProxyConfig.Host) -or $ProxyConfig.Port -le 0) {
        $result.Error = "Прокси не настроен (хост/порт пуст)"
        return $result
    }
    
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $conn = Connect-ThroughProxy "google.com" 80 $ProxyConfig 5000
        if ($conn) {
            $result.Latency = $sw.ElapsedMilliseconds
            $result.Success = $true
            $conn.Tcp.Close()
        } else {
            $result.Error = "Не удалось установить туннель"
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-DebugLog "Test-ProxyQuick error: $errMsg"
        if ($errMsg -match "таймаут|timeout") {
            $result.Error = "Таймаут подключения (возможно, порт закрыт или прокси не отвечает)"
        } elseif ($errMsg -match "отказано|refused") {
            $result.Error = "Соединение отклонено (проверьте порт, возможно, прокси не работает)"
        } elseif ($errMsg -match "аутентификация|authentication") {
            $result.Error = "Ошибка аутентификации (неверный логин/пароль)"
        } elseif ($errMsg -match "не удалось разрешить|unable to resolve") {
            $result.Error = "Не удалось разрешить имя хоста прокси"
        } else {
            $result.Error = $errMsg
        }
    }
    
    return $result
}

function Show-HelpMenu {
    Write-DebugLog "Show-HelpMenu: Открытие краткой справки..."
    
    $oldBufH = [Console]::BufferHeight
    try { if ([Console]::BufferHeight -lt 100) { [Console]::BufferHeight = 100 } } catch {}

    [Console]::Clear()
    [Console]::CursorVisible = $false
    
    $w = [Console]::WindowWidth
    if ($w -gt 100) { $w = 100 }
    $line = "─" * $w

    # Заголовок
    Write-Host "`n $($line)" -ForegroundColor Gray
    Write-Host "   YT-DPI v$($scriptVersion) - СПРАВКА ПО ИСПОЛЬЗОВАНИЮ" -ForegroundColor Cyan
    Write-Host " $($line)" -ForegroundColor Gray

    # Кнопки управления
    Write-Host "`n [ КНОПКИ УПРАВЛЕНИЯ ]" -ForegroundColor White
    Write-Host "   ENTER          " -ForegroundColor Yellow -NoNewline; Write-Host "- Запустить проверку всех доменов" -ForegroundColor Gray
    Write-Host "   D (Deep Trace) " -ForegroundColor Yellow -NoNewline; Write-Host "- Трассировка (показывает, где именно блокировка)" -ForegroundColor Gray
    Write-Host "   P (Proxy)      " -ForegroundColor Yellow -NoNewline; Write-Host "- Настроить прокси (SOCKS5/HTTP)" -ForegroundColor Gray
    Write-Host "   R (Report)     " -ForegroundColor Yellow -NoNewline; Write-Host "- Сохранить результаты в YT-DPI_Report.txt" -ForegroundColor Gray
    Write-Host "   S (Settings)   " -ForegroundColor Yellow -NoNewline; Write-Host "- Настройки (IPv4/IPv6, очистка кэша)" -ForegroundColor Gray
    Write-Host "   Q / ESC        " -ForegroundColor Yellow -NoNewline; Write-Host "- Выйти из программы" -ForegroundColor Gray

    # Статусы
    Write-Host "`n [ ЧТО ЗНАЧАТ ЦВЕТА ]" -ForegroundColor White
    Write-Host "   AVAILABLE      " -ForegroundColor Green -NoNewline; Write-Host "- Всё хорошо, домен полностью доступен." -ForegroundColor Gray
    Write-Host "   THROTTLED      " -ForegroundColor Yellow -NoNewline; Write-Host "- Частичная блокировка (DPI мешает, один из протоколов сбоит)." -ForegroundColor Gray
    Write-Host "   DPI BLOCK/RESET" -ForegroundColor Red -NoNewline; Write-Host "- Жесткая блокировка по SNI (нужен обход DPI)." -ForegroundColor Gray
    Write-Host "   IP BLOCK       " -ForegroundColor Red -NoNewline; Write-Host "- Сервер недоступен (заблокирован сам адрес или нет интернета)." -ForegroundColor Gray

    # Решение проблем
    Write-Host "`n [ СОВЕТЫ ]" -ForegroundColor White
    Write-Host "   1. Если YouTube тормозит при статусе " -ForegroundColor Gray -NoNewline
    Write-Host "THROTTLED" -ForegroundColor Yellow -NoNewline
    Write-Host ", включите средство обхода DPI." -ForegroundColor Gray
    
    Write-Host "   2. Отключите Kyber в браузере для стабильности: " -ForegroundColor Gray
    Write-Host "      chrome://flags/#enable-tls13-kyber -> Disabled" -ForegroundColor Cyan
    
    Write-Host "   3. Если Deep Trace не работает, запустите скрипт от Администратора." -ForegroundColor Gray

    # Футер
    Write-Host "`n $($line)" -ForegroundColor Gray
    Write-Host (Get-PaddedCenter "Нажмите любую клавишу, чтобы вернуться назад" $w) -ForegroundColor Gray
    Write-Host " $($line)" -ForegroundColor Gray

    Clear-KeyBuffer
    $null = [Console]::ReadKey($true)
    
    try { [Console]::BufferHeight = $oldBufH } catch {}
}

function Add-ToProxyHistory {
    param($ProxyConfig)
    
    # Формируем строку для истории (без пароля)
    $entry = "$($ProxyConfig.Type)://"
    if ($ProxyConfig.User) {
        $entry += "$($ProxyConfig.User):*****@"
    }
    $entry += "$($ProxyConfig.Host):$($ProxyConfig.Port)"
    
    # Получаем текущую историю
    $history = @($script:Config.ProxyHistory)
    # Удаляем дубликат, если есть
    $history = $history | Where-Object { $_ -ne $entry }
    # Добавляем в начало
    $history = @($entry) + $history
    # Обрезаем до 5
    if ($history.Count -gt 5) { $history = $history[0..4] }
    $script:Config.ProxyHistory = $history
    Save-Config $script:Config
    Write-DebugLog "Proxy history updated: $entry"
}

# ====================================================================================
# РАБОЧИЙ ПОТОК
# ====================================================================================
$Worker = {
    param($Target, $ProxyConfig, $CONST, $DebugLogFile, $DEBUG_ENABLED, $DnsCache, $DnsCacheLock, $NetInfo, $IpPreference)
    
    function Write-DebugLog($msg, $level = "DEBUG") {
        if (-not $DEBUG_ENABLED) { return }
        $line = "[$(Get-Date -Format 'HH:mm:ss.fff')] [Worker $($Target)] [$($level)] $($msg)`r`n"
        try { [System.IO.File]::AppendAllText($DebugLogFile, $line, [System.Text.Encoding]::UTF8) } catch {}
    }

    # --- ВНУТРЕННИЕ ФУНКЦИИ ---
    function Connect-ThroughProxy {
        param($TargetHost, $TargetPort, $ProxyConfig, [int]$Timeout = $CONST.ProxyTimeout)
        if ([string]::IsNullOrEmpty($ProxyConfig.Host) -or $ProxyConfig.Port -le 0) {
            throw "Некорректная конфигурация прокси: хост='$($ProxyConfig.Host)', порт=$($ProxyConfig.Port)"
        }
        Write-DebugLog "Подключение через прокси $($ProxyConfig.Type) к $($TargetHost):$($TargetPort)"
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $asyn = $tcp.BeginConnect($ProxyConfig.Host, $ProxyConfig.Port, $null, $null)
            if (-not $asyn.AsyncWaitHandle.WaitOne($Timeout)) { throw "Таймаут подключения к прокси" }
            $tcp.EndConnect($asyn); $stream = $tcp.GetStream()
            $stream.ReadTimeout = $Timeout; $stream.WriteTimeout = $Timeout

            if ($ProxyConfig.Type -eq "SOCKS5") {
                Write-DebugLog "SOCKS5: начало рукопожатия"

                # === Определяем, какие методы аутентификации предложить ===
                $methods = @()
                if ($ProxyConfig.User -and $ProxyConfig.Pass) {
                    # Если есть логин/пароль, предлагаем сначала аутентификацию по паролю (0x02), затем без аутентификации (0x00)
                    $methods = @(0x02, 0x00)
                } else {
                    # Без аутентификации предлагаем только 0x00
                    $methods = @(0x00)
                }
                $greeting = [byte[]](@(0x05, $methods.Count) + $methods)
                $stream.Write($greeting, 0, $greeting.Length)

                # Читаем ответ сервера (2 байта: VER, METHOD)
                $resp = New-Object byte[] 2
                if ($stream.Read($resp, 0, 2) -ne 2) {
                    throw "SOCKS5: нет ответа на выбор метода"
                }
                if ($resp[0] -ne 0x05) {
                    throw "SOCKS5: неверная версия ответа (ожидалась 0x05, получена 0x$('{0:X2}' -f $resp[0]))"
                }

                $method = $resp[1]
                Write-DebugLog "SOCKS5: сервер выбрал метод аутентификации 0x$('{0:X2}' -f $method)"

                # === Обработка выбранного метода ===
                if ($method -eq 0x00) {
                    # Без аутентификации — ничего не делаем
                    Write-DebugLog "SOCKS5: аутентификация не требуется"
                }
                elseif ($method -eq 0x02) {
                    # Аутентификация по логину/паролю
                    if (-not $ProxyConfig.User -or -not $ProxyConfig.Pass) {
                        throw "SOCKS5: сервер требует логин/пароль, но они не указаны в настройках"
                    }
                    $u = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.User)
                    $p = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.Pass)
                    $authMsg = [byte[]](@(0x01, $u.Length) + $u + @($p.Length) + $p)
                    $stream.Write($authMsg, 0, $authMsg.Length)

                    $authResp = New-Object byte[] 2
                    if ($stream.Read($authResp, 0, 2) -ne 2) {
                        throw "SOCKS5: нет ответа на аутентификацию"
                    }
                    if ($authResp[0] -ne 0x01 -or $authResp[1] -ne 0x00) {
                        throw "SOCKS5: неверный логин/пароль (код $($authResp[1]))"
                    }
                    Write-DebugLog "SOCKS5: аутентификация успешна"
                }
                elseif ($method -eq 0xFF) {
                    throw "SOCKS5: сервер отверг все предложенные методы аутентификации (0xFF). Проверьте, требуется ли аутентификация."
                }
                else {
                    throw "SOCKS5: сервер выбрал неподдерживаемый метод аутентификации 0x$('{0:X2}' -f $method)"
                }

                # === Запрос на подключение к целевому хосту ===
                $addrType = 0x03   # domain name
                $hostBytes = [Text.Encoding]::UTF8.GetBytes($TargetHost)
                $req = [byte[]](@(0x05, 0x01, 0x00, $addrType, $hostBytes.Length) + $hostBytes + @([math]::Floor($TargetPort/256), ($TargetPort%256)))
                $stream.Write($req, 0, $req.Length)

                # Читаем ответ (минимум 10 байт)
                $resp = New-Object byte[] 10
                $read = 0
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                while ($read -lt 10 -and $sw.ElapsedMilliseconds -lt $Timeout) {
                    if ($stream.DataAvailable) {
                        $r = $stream.Read($resp, $read, 10 - $read)
                        if ($r -eq 0) { break }
                        $read += $r
                    } else { Start-Sleep -Milliseconds 20 }
                }
                if ($read -lt 10) { throw "SOCKS5: неполный ответ на запрос подключения" }
                if ($resp[0] -ne 0x05) { throw "SOCKS5: неверная версия в ответе на подключение" }
                if ($resp[1] -ne 0x00) {
                    $repCode = $resp[1]
                    $errorMap = @{
                        0x01 = "general failure"
                        0x02 = "connection not allowed"
                        0x03 = "network unreachable"
                        0x04 = "host unreachable"
                        0x05 = "connection refused"
                        0x06 = "TTL expired"
                        0x07 = "command not supported"
                        0x08 = "address type not supported"
                    }
                    $errText = if ($errorMap.ContainsKey($repCode)) { $errorMap[$repCode] } else { "unknown error 0x$('{0:X2}' -f $repCode)" }
                    throw "SOCKS5: сервер вернул ошибку - $errText"
                }
                Write-DebugLog "SOCKS5: маршрут установлен успешно"
                return @{ Tcp = $tcp; Stream = $stream }
            }
        } catch {
            if($tcp){$tcp.Close()}
            Write-DebugLog "Ошибка прокси: $($_.Exception.Message)" "WARN"
            throw $_
        }
    }

    $Result = [PSCustomObject]@{ IP="FAILED"; HTTP="---"; T12="---"; T13="---"; Lat="---"; Verdict="UNKNOWN"; Color="White"; Target=$Target; Number=0 }
    $TO = if ($ProxyConfig.Enabled) { $CONST.ProxyTimeout } else { $CONST.TimeoutMs }

    Write-DebugLog "--- НАЧАЛО ПРОВЕРКИ ---"

    function Invoke-TcpConnectWithFallback {
        param($TargetIp, $TargetPort, $TimeoutMs)
        $tcp = $null
        try {
            $ipAddress = [System.Net.IPAddress]::Parse($TargetIp)
            $tcp = New-Object System.Net.Sockets.TcpClient($ipAddress.AddressFamily)
            $async = $tcp.BeginConnect($ipAddress, $TargetPort, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw "Timeout" }
            $tcp.EndConnect($async)
            return $tcp
        } catch {
            if ($_.Exception.Message -match "address family|None of the discovered") {
                # Если это IPv6, пытаемся получить IPv4
                if ($TargetIp -match ':') {
                    Write-DebugLog "Ошибка семейства адресов при использовании IPv6 ($TargetIp), пробуем получить IPv4 для $Target"
                    $v4Address = $null
                    try {
                        $ips = [System.Net.Dns]::GetHostAddresses($Target)
                        $v4 = $ips | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                        if ($v4) {
                            $v4Address = $v4.IPAddressToString
                            Write-DebugLog "Найден IPv4: $v4Address"
                            # Обновляем кэш
                            if ($DnsCacheLock.WaitOne(1000)) {
                                $DnsCache[$Target] = $v4Address
                                [void]$DnsCacheLock.ReleaseMutex()
                            }
                            # Повторяем попытку с IPv4
                            $ipAddressV4 = [System.Net.IPAddress]::Parse($v4Address)
                            $tcp = New-Object System.Net.Sockets.TcpClient($ipAddressV4.AddressFamily)
                            $async = $tcp.BeginConnect($ipAddressV4, $TargetPort, $null, $null)
                            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw "Timeout after fallback" }
                            $tcp.EndConnect($async)
                            $Result.IP = $v4Address
                            return $tcp
                        } else {
                            Write-DebugLog "Не удалось найти IPv4 для $Target"
                        }
                    } catch {
                        Write-DebugLog "Ошибка резолвинга IPv4 для $Target : $_"
                    }
                }
            }
            throw $_
        }
    }

    # 1. DNS
    $ipStr = $null
    if (-not $ProxyConfig.Enabled) {
        try {
            if ($DnsCacheLock.WaitOne(1000)) {
                if ($DnsCache.ContainsKey($Target)) { $ipStr = $DnsCache[$Target] }
                [void]$DnsCacheLock.ReleaseMutex()
            }
            if (-not $ipStr) {
                $ips = [System.Net.Dns]::GetHostAddresses($Target)
                $v4 = $ips | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                $v6 = $ips | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' } | Select-Object -First 1
                
                # ЛОГИКА ВЫБОРА:
                if ($IpPreference -eq "IPv6" -and $v6 -and $NetInfo.HasIPv6) {
                    $ipStr = $v6.IPAddressToString
                } else {
                    $ipStr = if ($v4) { $v4.IPAddressToString } else { $v6.IPAddressToString }
                }

                if ($DnsCacheLock.WaitOne(1000)) { 
                    $DnsCache[$Target] = $ipStr
                    [void]$DnsCacheLock.ReleaseMutex()
                }
            }
        } catch { $ipStr = "DNS_ERR" }
        $Result.IP = $ipStr
    } else { $Result.IP = "[ PROXIED ]" }

    # 2. HTTP Проверка
    Write-DebugLog "HTTP: Тест порта 80..."
    $conn = $null
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        if ($ProxyConfig.Enabled) { 
            $conn = Connect-ThroughProxy $Target 80 $ProxyConfig $TO 
        } else {
            # Используем новую функцию с fallback на IPv4
            $tcp = Invoke-TcpConnectWithFallback -TargetIp $Result.IP -TargetPort 80 -TimeoutMs $TO
            $conn = @{ Tcp = $tcp; Stream = $tcp.GetStream() }
        }
        $Result.Lat = "$($sw.ElapsedMilliseconds)ms"
        $Result.HTTP = "OK"
        Write-DebugLog "HTTP: OK (Ping: $($Result.Lat))"
    } catch {
        $Result.HTTP = "ERR"
        Write-DebugLog "HTTP: Ошибка -> $($_.Exception.Message)" "WARN"
    } finally { if ($conn) { $conn.Tcp.Close() } }

    if ($Result.HTTP -eq "ERR") {
    $Result.T12 = "---"
    $Result.T13 = "---"
    $Result.Verdict = "IP BLOCK"
    $Result.Color = "Red"
    return $Result # Сразу выходим, не тратя время на TLS
}

    # 3. TLS Проверки
    # Проверка TLS 1.3
    $pHost = if ($ProxyConfig.Enabled) { $ProxyConfig.Host } else { "" }
    $pPort = if ($ProxyConfig.Enabled) { [int]$ProxyConfig.Port } else { 0 }
    $Result.T13 = [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, 2000)
    Write-DebugLog "TLS T13 : [RAW] Host=$Target Result=$($Result.T13)"

    # Проверка TLS 1.2
    $conn = $null; $ssl = $null
    try {
        if ($ProxyConfig.Enabled) { $conn = Connect-ThroughProxy $Target 443 $ProxyConfig 2000 }
        else {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $ar = $tcp.BeginConnect($Result.IP, 443, $null, $null)
            if (-not $ar.AsyncWaitHandle.WaitOne(2000)) { throw "TcpTimeout" }
            $tcp.EndConnect($ar); $conn = @{ Tcp = $tcp; Stream = $tcp.GetStream() }
        }
        $ssl = [System.Net.Security.SslStream]::new($conn.Stream, $false, { $true })
        $ssl.AuthenticateAsClient($Target, $null, "Tls12", $false)
        $Result.T12 = if ($ssl.IsAuthenticated) { "OK" } else { "DRP" }
    } catch {
        $m = $_.Exception.Message + $_.Exception.InnerException.Message
        if ($m -match "reset|сброс|forcibly|closed|разорвано|failed") { $Result.T12 = "RST" }
        elseif ($m -match "certificate|сертификат|remote|success") { $Result.T12 = "OK" }
        else { $Result.T12 = "DRP" }
    } finally { if($ssl){$ssl.Close()}; if($conn){$conn.Tcp.Close()} }

    # 4. Логика вердикта
    $t12Ok = ($Result.T12 -eq "OK")
    $t13Ok = ($Result.T13 -eq "OK")
    $t12Blocked = ($Result.T12 -eq "RST" -or $Result.T12 -eq "DRP")
    $t13Blocked = ($Result.T13 -eq "RST" -or $Result.T13 -eq "DRP")

    if ($t12Ok -and $t13Ok) {
        $Result.Verdict = "AVAILABLE"; $Result.Color = "Green"
    }
    elseif ($t12Ok -or $t13Ok) {
        # Один из протоколов работает, другой — нет
        if ($t12Blocked -or $t13Blocked) {
            $Result.Verdict = "THROTTLED"; $Result.Color = "Yellow"
        } else {
            # Например, один OK, а другой ERR (проблема настройки, а не блокировка)
            $Result.Verdict = "AVAILABLE"; $Result.Color = "Green"
        }
    }
    elseif ($Result.T12 -eq "RST" -or $Result.T13 -eq "RST") {
        $Result.Verdict = "DPI RESET"; $Result.Color = "Red"
    }
    elseif ($Result.T12 -eq "DRP" -or $Result.T13 -eq "DRP") {
        $Result.Verdict = "DPI BLOCK"; $Result.Color = "Red"
    }
    else {
        $Result.Verdict = "IP BLOCK"; $Result.Color = "Red"
    }
    return $Result
}
# ====================================================================================
# АСИНХРОННОЕ СКАНИРОВАНИЕ
# ====================================================================================
function Start-ScanWithAnimation($Targets, $ProxyConfig) {
    Write-DebugLog "Start-ScanWithAnimation: Режим Ultra-Smooth Waterfall..."
    
    # --- ДИНАМИЧЕСКИЙ РАСЧЁТ ПОЗИЦИЙ ДЛЯ АНИМАЦИИ ---
    # Эти позиции ДОЛЖНЫ совпадать с теми, что используются в Draw-UI и Write-ResultLine
    $domStart  = 6
    $domWidth  = 42
    $ipStart   = $domStart + $domWidth + 2
    $ipWidth   = if ($script:IpColumnWidth) { $script:IpColumnWidth } else { 16 }
    $httpStart = $ipStart + $ipWidth + 2
    $httpWidth = 6
    $t12Start  = $httpStart + $httpWidth + 2
    $t12Width  = 8
    $t13Start  = $t12Start + $t12Width + 2
    $t13Width  = 8
    $latStart  = $t13Start + $t13Width + 2
    $latWidth  = 6
    $verStart  = $latStart + $latWidth + 2
    $verWidth  = 30
    
    # Сохраняем в глобальную переменную для Write-ResultLine
    $script:DynamicColPos = @{
        Num  = 1
        Dom  = $domStart
        IP   = $ipStart
        HTTP = $httpStart
        T12  = $t12Start
        T13  = $t13Start
        Lat  = $latStart
        Ver  = $verStart
    }
    # --- КОНЕЦ РАСЧЁТА ПОЗИЦИЙ ---
    
    $cpuCount = [Environment]::ProcessorCount
    # Для сетевых задач ядра не важны, важна параллельность.
    # Позволяем запускать до 50 проверок одновременно.
    $maxThreads = [Math]::Min($Targets.Count, 50)
    Write-DebugLog "Запуск пула потоков: $maxThreads воркеров."
    
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()
    $jobs = @()
    $results = New-Object 'object[]' $Targets.Count
    $completedTasks = 0
    $animationBuffer = @{}
    
    $waveChars = @("─     ", "──    ", "───   ", "────  ", "───── ", "──────", "───── ", "────  ", "───   ", "──    ")
    
    for ($i=0; $i -lt $Targets.Count; $i++) {
        $ps = [PowerShell]::Create().AddScript($Worker).
            AddArgument($Targets[$i]).            # 1. $Target
            AddArgument($ProxyConfig).           # 2. $ProxyConfig
            AddArgument($CONST).                 # 3. $CONST
            AddArgument($DebugLogFile).          # 4. $DebugLogFile
            AddArgument($DEBUG_ENABLED).         # 5. $DEBUG_ENABLED
            AddArgument($script:DnsCache).       # 6. $DnsCache
            AddArgument($script:DnsCacheLock).   # 7. $DnsCacheLock
            AddArgument($script:NetInfo).        # 8. $NetInfo
            AddArgument($script:Config.IpPreference) # 9. $IpPreference
            
        $ps.RunspacePool = $pool
        $jobs += [PSCustomObject]@{
            PowerShell = $ps; Handle = $ps.BeginInvoke(); Index = $i; Number = $i + 1
            Target = $Targets[$i]; DoneInBg = $false; Row = 12 + $i; Result = $null; Revealed = $false
        }
    }
    
    $aborted = $false
    $frameCounter = 0
    $revealIndex = -1
    $lastRevealTime = [System.Diagnostics.Stopwatch]::StartNew()

    # --- ЕДИНЫЙ ЦИКЛ (Скан + Плавный водопад) ---
    while (-not $aborted) {
        $frameCounter++
        
        # 1. Проверка клавиш
        if ([Console]::KeyAvailable) {
            if ([Console]::ReadKey($true).Key -in @("Q", "Escape")) { $aborted = $true; break }
        }
        
        # 2. Проверка завершения потоков в фоне
        foreach ($j in $jobs) {
            if (-not $j.DoneInBg -and $j.Handle.IsCompleted) {
                try {
                    $raw = $j.PowerShell.EndInvoke($j.Handle)
                    $res = if ($raw.PSObject -and $raw.Count -gt 1) { $raw[0] } else { $raw }
                    $res | Add-Member -MemberType NoteProperty -Name "Number" -Value $j.Number -Force
                    $j.Result = $res; $results[$j.Index] = $res; $j.DoneInBg = $true; $completedTasks++
                } catch { $j.DoneInBg = $true; $completedTasks++ }
            }
        }

        # 3. Логика "Водопада" (Real-time: показываем по мере готовности)
        # Если текущая строка по списку готова, разрешаем её "раскрыть"
        if ($revealIndex + 1 -lt $Targets.Count) {
            if ($jobs[$revealIndex + 1].DoneInBg) {
                $revealIndex++
                $lastRevealTime.Restart()
            }
        }

        # 4. ОТРИСОВКА КАДРА (используем ДИНАМИЧЕСКИЕ позиции)
        for ($i = 0; $i -lt $Targets.Count; $i++) {
            $j = $jobs[$i]
            if ($j.Revealed) { continue }

            if ($i -le $revealIndex) {
                $res = $j.Result
                if ($null -eq $res) { 
                    $res = [PSCustomObject]@{ 
                        Target=$j.Target; Number=$j.Number; IP="ERR"; HTTP="---"; 
                        T12="---"; T13="---"; Lat="---"; Verdict="TIMEOUT"; Color="Red" 
                    } 
                }
                Write-ResultLine $j.Row $res
                $j.Revealed = $true
            } 
            else {
                # АНИМАЦИЯ с использованием ДИНАМИЧЕСКОЙ позиции LAT
                $rowChar = Get-ScanAnim $frameCounter $j.Row
                $statusText = " SCANNING $($rowChar)".PadRight(30)
                $latWave = $waveChars[($frameCounter + $j.Row) % $waveChars.Length].PadRight(7)
                
                $combinedFrame = "$($latWave)$($statusText)"
                
                $cacheKey = "R$($j.Row)"
                if ($animationBuffer[$cacheKey] -ne $combinedFrame) {
                    # ВАЖНО: используем $script:DynamicColPos.Lat вместо $CONST.UI.Lat
                    Out-Str $script:DynamicColPos.Lat $j.Row $combinedFrame "Cyan"
                    $animationBuffer[$cacheKey] = $combinedFrame
                }
            }
        }

        if ($revealIndex -eq ($Targets.Count - 1)) { break }
        Start-Sleep -Milliseconds 30
    }
    
    $pool.Close(); $pool.Dispose()
    foreach ($j in $jobs) { try { $j.PowerShell.Dispose() } catch {} }
    
    # Проверка на ложный IPv6
    $allIpBlock = ($results | Where-Object { $_.Verdict -ne "IP BLOCK" -and $_.Verdict -ne "UNKNOWN" }) -eq $null
    if ($allIpBlock -and $NetInfo.HasIPv6 -eq $true) {
        Write-DebugLog "Все тесты дали IP BLOCK, но HasIPv6=true. Переключаем HasIPv6 в false." "WARN"
        $script:NetInfo.HasIPv6 = $false
        $script:Config.NetCache.HasIPv6 = $false
        Save-Config $script:Config
        if ($DnsCacheLock.WaitOne(1000)) {
            $toRemove = @()
            foreach ($key in $DnsCache.Keys) {
                if ($DnsCache[$key] -match ':') { $toRemove += $key }
            }
            foreach ($key in $toRemove) { $DnsCache.Remove($key) }
            [void]$DnsCacheLock.ReleaseMutex()
        }
    }
    
    # Обновляем ширину IP колонки на основе реальных результатов
    if ($results) {
        $maxIp = ($results | ForEach-Object { 
            if ($_.IP -and $_.IP -ne "[ PROXIED ]") { $_.IP.Length } else { 16 } 
        } | Measure-Object -Maximum).Maximum
        $script:IpColumnWidth = [Math]::Max($maxIp, 16)
    }
    
    return [PSCustomObject]@{ Results = $results; Aborted = $aborted }
}

# ====================================================================================
# ГЛАВНЫЙ ЦИКЛ ПРОГРАММЫ (ENGINE START)
# ====================================================================================

# 1. Загрузка конфигурации (Мгновенно)
$script:Config = Load-Config
$global:ProxyConfig = $script:Config.Proxy
$script:Config.RunCount++

# 2. Синхронизация DNS кэша
$script:DnsCache = [hashtable]::Synchronized(@{})
if ($script:Config.DnsCache -and $script:Config.DnsCache.PSObject) {
    foreach ($prop in $script:Config.DnsCache.PSObject.Properties) {
        if ($prop.MemberType -eq "NoteProperty") { $script:DnsCache[$prop.Name] = $prop.Value }
    }
}

# 3. !!! МГНОВЕННАЯ ОТРИСОВКА UI !!!
# Используем данные из кэша, чтобы не ждать сеть
$script:NetInfo = $script:Config.NetCache
$script:Targets = Get-Targets -NetInfo $script:NetInfo
[Console]::Clear()
Draw-UI $script:NetInfo $script:Targets $null $false
Draw-StatusBar -Message "[ WAIT ] INITIALIZING NETWORK..." -Fg "Black" -Bg "Yellow"


# 5. Обновление сети только если кэш устарел или это первый запуск
if ($script:Config.NetCacheStale -or $script:Config.RunCount -le 1 -or $script:NetInfo.ISP -eq "Loading...") {
    $script:NetInfo = Get-NetworkInfo
    $script:Config.NetCache = $script:NetInfo
    # Перерисовываем UI с новыми данными об ISP без полной очистки
    Draw-UI $script:NetInfo $script:Targets $null $false
}

# 6. Проверка обновлений (только раз в 10 запусков, чтобы не бесить)
if ($script:Config.RunCount % 10 -eq 0) {
    $newVer = Check-UpdateVersion -Repo "Shiperoid/YT-DPI" -LastCheckedVersion $script:Config.LastCheckedVersion
    if ($newVer) {
        Draw-StatusBar -Message "[ UPDATE ] NEW VERSION v$newVer AVAILABLE! PRESS 'U' TO UPDATE." -Fg "White" -Bg "DarkMagenta"
        Start-Sleep -Seconds 3
    }
}

Draw-StatusBar -Message $CONST.NavStr
Write-DebugLog "--- СИСТЕМА ГОТОВА ---" "INFO"
Clear-KeyBuffer
$FirstRun = $false

while ($true) {
    if ($FirstRun) {
        Write-DebugLog "Первый запуск: получение сетевой информации"
        $script:NetInfo = Get-NetworkInfo
        $script:Targets = Get-Targets -NetInfo $script:NetInfo
        Write-DebugLog "Целей: $($script:Targets.Count)"
        Draw-UI $script:NetInfo $script:Targets $null $true
        Draw-StatusBar
        $FirstRun = $false
    }


    # Проверяем наличие клавиши, если нет - ждем
    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true).Key
        
        if ($k -eq "Q" -or $k -eq "Escape") { 
            Stop-Script 
        }
        elseif ($k -eq "H") { 
            Write-DebugLog "Показ справки"
            Show-HelpMenu
            Draw-UI $script:NetInfo $script:Targets $true
            Draw-StatusBar
            Clear-KeyBuffer  # Очищаем после меню
            continue 
        }
        elseif ($k -eq "D") {
            Write-DebugLog "Глубокий анализ хоста"
            
            # Получаем строку статуса
            $row = Get-NavRow -count $script:Targets.Count
            $width = [Console]::WindowWidth
            
            # ПОЛНОСТЬЮ очищаем строку статуса (от начала до конца)
            Out-Str 0 $row (" " * $width) "Black"
            
            # Выводим сообщение с ярким фоном
            $promptMsg = "[ TRACE ] Enter domain number (1..$($script:Targets.Count)): "
            Out-Str 2 $row $promptMsg -Fg "White" -Bg "DarkBlue"
            
            # Устанавливаем курсор для ввода (после сообщения)
            $inputX = 2 + $promptMsg.Length
            [Console]::SetCursorPosition($inputX, $row)
            [Console]::CursorVisible = $true
            [Console]::ForegroundColor = "Yellow"
            [Console]::BackgroundColor = "DarkBlue"
            
            # Читаем ввод
            $input = [Console]::ReadLine()
            [Console]::CursorVisible = $false
            
            # Очищаем строку перед следующим сообщением
            Out-Str 0 $row (" " * $width) "Black"
            
            $idx = 0
            if ([int]::TryParse($input, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:Targets.Count) {
                $target = $script:Targets[$idx-1]
                
                # Показываем сообщение о начале трассировки
                $traceMsg = "[ TRACE ] Tracing #$idx - $target ... (may take 60-90 seconds)"
                Out-Str 2 $row $traceMsg -Fg "White" -Bg "DarkCyan"
                # Добиваем пробелами до конца строки, чтобы стереть остатки
                $remaining = $width - (2 + $traceMsg.Length)
                if ($remaining -gt 0) {
                    Out-Str (2 + $traceMsg.Length) $row (" " * $remaining) "Black"
                }
                
                # Выполняем трассировку
                $aborted = $false
                $trace = $null
                $progressRow = Get-NavRow -count $script:Targets.Count

                # Функция обновления статуса во время трассировки
                $progressBlock = {
                    param($message)
                    # Обновляем статус-бар с сообщением
                    Out-Str 2 $progressRow $message -Fg "White" -Bg "DarkCyan"
                    # Дополнительно проверяем прерывание извне (флаг $aborted)
                }

                try {
                    $trace = Trace-TcpRoute -Target $target -Port 443 -MaxHops 15 -TimeoutSec 5 -onProgress $progressBlock
                } catch {
                    # Обработка ошибок
                }
                
                # Очищаем строку перед результатом
                Out-Str 0 $row (" " * $width) "Black"
                
                if ($trace -is [string]) {
                    $resultMsg = "[ TRACE ] $($target): $trace"
                    Out-Str 2 $row $resultMsg -Fg "White" -Bg "DarkRed"
                } elseif ($trace.Count -eq 0) {
                    $resultMsg = "[ TRACE ] $($target): No hops found"
                    Out-Str 2 $row $resultMsg -Fg "White" -Bg "DarkRed"
                } else {
                    # Анализируем результат
                    $firstResponsive = $trace | Where-Object { $_.TcpStatus -eq "SYNACK" -or $_.TcpStatus -eq "RST" } | Select-Object -First 1
                    $timeoutHops = $trace | Where-Object { $_.TcpStatus -eq "Timeout" }
                    $errorHops = $trace | Where-Object { $_.TcpStatus -eq "Error" }
                    
                    $resultMsg = ""
                    $bgColor = ""
                    
                    if ($firstResponsive) {
                        if ($firstResponsive.TcpStatus -eq "RST") {
                            $resultMsg = "[ TRACE ] $($target): RST at hop $($firstResponsive.Hop) ($($firstResponsive.IP)) - DPI blocking"
                            $bgColor = "DarkRed"
                        } elseif ($firstResponsive.TcpStatus -eq "SYNACK") {
                            $resultMsg = "[ TRACE ] $($target): TCP OK at hop $($firstResponsive.Hop) ($($firstResponsive.IP))"
                            $bgColor = "DarkGreen"
                        }
                    } elseif ($timeoutHops.Count -gt 0) {
                        $firstTimeout = $timeoutHops | Select-Object -First 1
                        $resultMsg = "[ TRACE ] $($target): Timeout at hop $($firstTimeout.Hop) ($($firstTimeout.IP)) - connection blocked"
                        $bgColor = "DarkYellow"
                    } elseif ($errorHops.Count -gt 0) {
                        $firstError = $errorHops | Select-Object -First 1
                        $resultMsg = "[ TRACE ] $($target): Refused at hop $($firstError.Hop) ($($firstError.IP))"
                        $bgColor = "DarkRed"
                    } else {
                        $resultMsg = "[ TRACE ] $($target): No TCP responses"
                        $bgColor = "DarkGray"
                    }
                    
                    Out-Str 2 $row $resultMsg -Fg "White" -Bg $bgColor
                    
                    # Добиваем пробелами до конца строки
                    $remaining = $width - (2 + $resultMsg.Length)
                    if ($remaining -gt 0) {
                        Out-Str (2 + $resultMsg.Length) $row (" " * $remaining) "Black"
                    }
                    
                    # Детальный вывод в лог
                    Write-DebugLog "=== Trace results for $target ==="
                    foreach ($hop in $trace) {
                        Write-DebugLog "Hop $($hop.Hop): $($hop.IP) -> TCP: $($hop.TcpStatus), RTT=$($hop.RttMs)ms"
                    }
                }
                
                Start-Sleep -Seconds 4
                
                # Восстанавливаем статус-бар
                Out-Str 0 $row (" " * $width) "Black"
                Draw-StatusBar
                Clear-KeyBuffer
                continue
            } else {
                # Ошибка ввода
                $errorMsg = "[ ERROR ] Invalid number. Use 1..$($script:Targets.Count)"
                Out-Str 2 $row $errorMsg -Fg "White" -Bg "DarkRed"
                
                # Добиваем пробелами до конца строки
                $remaining = $width - (2 + $errorMsg.Length)
                if ($remaining -gt 0) {
                    Out-Str (2 + $errorMsg.Length) $row (" " * $remaining) "Black"
                }
                
                Start-Sleep -Seconds 2
                
                # Восстанавливаем статус-бар
                Out-Str 0 $row (" " * $width) "Black"
                Draw-StatusBar
                Clear-KeyBuffer
                continue
            }
        }
        elseif ($k -eq "U") { 
            Write-DebugLog "Запуск обновления"
            Invoke-Update -Repo "Shiperoid/YT-DPI" -Config $config
            
            # Вместо полной перерисовки Draw-UI просто восстанавливаем статус-бар
            Draw-StatusBar 
            Clear-KeyBuffer
            continue 
        }
        elseif ($k -eq "P") { 
            Write-DebugLog "Открыто меню прокси"
            Show-ProxyMenu
            Draw-UI $script:NetInfo $script:Targets $true
            Draw-StatusBar
            Clear-KeyBuffer  # Очищаем после меню
            continue 
        }
        elseif ($k -eq "T") { 
            Write-DebugLog "Тест прокси"
            Test-ProxyConnection
            Draw-UI $script:NetInfo $script:Targets $true
            Draw-StatusBar
            Clear-KeyBuffer  # Очищаем после теста
            continue 
        }
        
        elseif ($k -eq "S") { 
            Write-DebugLog "Открыты настройки"
            Show-SettingsMenu
            Draw-UI $script:NetInfo $script:Targets $true
            Draw-StatusBar
            continue 
        }

        elseif ($k -eq "R") { 
            Write-DebugLog "Сохранение отчёта"
            Draw-StatusBar -Message "[ WAIT ] SAVING RESULTS TO FILE..." -Fg "Black" -Bg "Cyan"
            $logPath = Join-Path -Path (Get-Location).Path -ChildPath "YT-DPI_Report.txt"
            
            $logContent = "=== YT-DPI REPORT ===`r`n"
            $logContent += "TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
            $logContent += "ISP:  $($script:NetInfo.ISP) ($($script:NetInfo.LOC))`r`n"
            $logContent += "DNS:  $($script:NetInfo.DNS)`r`n"
            $logContent += "PROXY: $(if($global:ProxyConfig.Enabled) {"$($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)"} else {"OFF"})`r`n"
            $logContent += "-" * 90 + "`r`n"
            $logContent += "{0,-38} {1,-16} {2,-6} {3,-8} {4,-8} {5,-6} {6}`r`n" -f "TARGET DOMAIN", "IP ADDRESS", "HTTP", "TLS 1.2", "TLS 1.3", "LAT", "RESULT"
            $logContent += "-" * 90 + "`r`n"
            
            if ($script:LastScanResults -and $script:LastScanResults.Count -gt 0) {
                foreach ($i in 0..($script:Targets.Count-1)) {
                    $res = $script:LastScanResults[$i]
                    if ($res -and $res.Verdict -ne "SCAN ABORTED") {
                        $ip = if($global:ProxyConfig.Enabled) {"[ PROXIED ]"} else {$res.IP}
                        $logContent += "{0,-38} {1,-16} {2,-6} {3,-8} {4,-8} {5,-6} {6}`r`n" -f $script:Targets[$i], $ip, $res.HTTP, $res.T12, $res.T13, $res.Lat, $res.Verdict
                    } else {
                        $logContent += "{0,-38} {1,-16} {2,-6} {3,-8} {4,-8} {5,-6} {6}`r`n" -f $script:Targets[$i], "NOT SCANNED", "---", "---", "---", "---", "NO DATA"
                    }
                }
            } else {
                $logContent += "`r`n[!] No scan results available. Please run a scan first (press ENTER).`r`n"
            }
            
            [IO.File]::WriteAllText($logPath, $logContent, [System.Text.Encoding]::UTF8)
            
            if ($script:LastScanResults -and $script:LastScanResults.Count -gt 0) {
                Draw-StatusBar -Message "[ SUCCESS ] SAVED TO: $logPath" -Fg "Black" -Bg "Green"
            } else {
                Draw-StatusBar -Message "[ WARNING ] NO SCAN DATA. SAVED EMPTY REPORT TO: $logPath" -Fg "Black" -Bg "Yellow"
            }
            Start-Sleep -Seconds 2
            Draw-StatusBar
            Clear-KeyBuffer  # Очищаем после сохранения
            continue 
        }

        # Обработка Enter
        if ($k -eq "Enter") {
            Write-DebugLog "Запуск сканирования по Enter"
            
            # --- ФИКС ЗАДВАИВАНИЯ ---
            # Стираем старый статус по старым координатам, пока Targets еще не обновились
            $oldRow = Get-NavRow -count $script:Targets.Count
            Out-Str 0 $oldRow (" " * [Console]::WindowWidth) "Black" "Black"
            # ------------------------

            # Быстрая проверка интернета
            $internetAvailable = $false
            try {
                $tcpTest = New-Object System.Net.Sockets.TcpClient
                $async = $tcpTest.BeginConnect("8.8.8.8", 53, $null, $null)
                if ($async.AsyncWaitHandle.WaitOne(2000)) {
                    $tcpTest.EndConnect($async)
                    $internetAvailable = $true
                }
                $tcpTest.Close()
            } catch {}

            if (-not $internetAvailable) {
                Draw-StatusBar -Message "[ ERROR ] NO INTERNET CONNECTION DETECTED. CHECK YOUR NETWORK." -Fg "Black" -Bg "Red"
                Start-Sleep -Seconds 3
                Draw-StatusBar
                Clear-KeyBuffer
                continue
            }
            
            Draw-StatusBar -Message "[ WAIT ] REFRESHING NETWORK STATE..." -Fg "Black" -Bg "Cyan"
            $script:NetInfo = Get-NetworkInfo
            
            $NewTargets = Get-Targets -NetInfo $script:NetInfo
            $NeedClear = ($NewTargets.Count -ne $script:Targets.Count)
            $script:Targets = $NewTargets
            
            Draw-UI $script:NetInfo $script:Targets $NeedClear
            
            for($i=0; $i -lt $script:Targets.Count; $i++) { 
                Out-Str $CONST.UI.Ver (12 + $i) ("PREPARING...".PadRight(30)) "DarkGray"
            }
            
            Draw-StatusBar -Message "[ WAIT ] SCANNING IN PROGRESS..." -Fg "Black" -Bg "Cyan"
            
            # Запуск движка
            $scanResult = Start-ScanWithAnimation $script:Targets $global:ProxyConfig
            $script:LastScanResults = $scanResult.Results
            
            # --- ПАУЗА ПЕРЕД ФИНАЛОМ ---
            # Даем глазу зафиксировать заполненную таблицу
            Start-Sleep -Milliseconds 400

            if ($scanResult.Aborted) {
                Draw-StatusBar -Message "[ ABORTED ] SCAN STOPPED. PRESS ENTER TO CONTINUE..." -Fg "Black" -Bg "Red"
            } else {
                Draw-StatusBar -Message "[ SUCCESS ] SCAN FINISHED. PRESS ENTER TO CONTINUE..." -Fg "Black" -Bg "Green"
            }
            
            Start-Sleep -Seconds 2
            Draw-StatusBar
            Clear-KeyBuffer
        }
    }
    
    # Небольшая задержка для снижения нагрузки на CPU
    Start-Sleep -Milliseconds 50
}