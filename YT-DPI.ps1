$script:OriginalFilePath = [System.Environment]::GetEnvironmentVariable("SCRIPT_PATH", "Process")
if (-not $script:OriginalFilePath) { $script:OriginalFilePath = $MyInvocation.MyCommand.Path }
if (-not $script:OriginalFilePath) { $script:OriginalFilePath = $MyInvocation.InvocationName }
$ErrorActionPreference = "SilentlyContinue"
$script:CurrentWindowWidth = 0
$script:CurrentWindowHeight = 0
$script:UiLayoutWidth = $null
$script:UiLayoutHeight = $null
[Console]::BufferHeight = [Console]::WindowHeight #потестить с этим параметром отрисовка быстрее но нет прокрутки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::CursorVisible = $false
try { [Console]::CursorSize = 1 } catch { }  # минимальная «полоска» курсора, меньше мигания
try {
    [Console]::ForegroundColor = "Cyan"
    [Console]::WriteLine("[ BOOT ] Loading YT-DPI...")
    [Console]::ResetColor()
} catch {}
$ErrorActionPreference = "Continue"

$DebugPreference = "SilentlyContinue"

# Безопасно по умолчанию: не отключаем проверку TLS-сертификатов
$script:AllowInsecureTls = $false
if ($script:AllowInsecureTls) {
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
[System.Net.ServicePointManager]::DefaultConnectionLimit = 100

$scriptVersion = "2.3.3"   # текущая версия yt-dpi
# ===== ОТЛАДКА =====
$debugEnvRaw = [System.Environment]::GetEnvironmentVariable("YT_DPI_DEBUG", "Process")
if (-not $debugEnvRaw) { $debugEnvRaw = [System.Environment]::GetEnvironmentVariable("YT_DPI_DEBUG", "User") }
if (-not $debugEnvRaw) { $debugEnvRaw = [System.Environment]::GetEnvironmentVariable("YT_DPI_DEBUG", "Machine") }
$DEBUG_ENABLED = [string]$debugEnvRaw -match '^(?i:1|true|yes|on)$'
# В хвосте строки DEBUG в UI: добавить PID (по умолчанию выкл — безопаснее для скриншотов)
$script:DebugHudIncludePid = $false

$forceFreshEnvRaw = [System.Environment]::GetEnvironmentVariable("YT_DPI_FORCE_NET_REFRESH", "Process")
if (-not $forceFreshEnvRaw) { $forceFreshEnvRaw = [System.Environment]::GetEnvironmentVariable("YT_DPI_FORCE_NET_REFRESH", "User") }
if (-not $forceFreshEnvRaw) { $forceFreshEnvRaw = [System.Environment]::GetEnvironmentVariable("YT_DPI_FORCE_NET_REFRESH", "Machine") }
$script:ForceFreshNetInfo = [string]$forceFreshEnvRaw -match '^(?i:1|true|yes|on)$'
$DebugLogFile = Join-Path (Get-Location).Path "YT-DPI_Debug.log"
# Один mutex на все процессы/потоки, пишущие в YT-DPI_Debug.log (иначе Add-Content/параллельный append даёт сбои).
$script:DebugLogMutexName = "Global\YT-DPI-Debug-Mutex"
$DebugLogMutex = New-Object System.Threading.Mutex($false, $script:DebugLogMutexName)

$SCRIPT:CONST = @{
    TimeoutMs    = 700       # Снижено с 1500
    ProxyTimeout = 1200      # Снижено с 2500
    HttpPort     = 80
    HttpsPort    = 443
    Tls13Proto   = 12288
    AnimFps      = 30
    ScanPoolMinWorkers    = 8
    ScanPoolDirectMax     = 24
    ScanPoolProxyMax      = 12
    ScanPoolCpuMultiplier = 3
    Mutex = @{ WaitMs = 7000 }   # Снижено с 15000
    Scan = @{
        HttpDirectCapMs       = 600    # Снижено с 1200
        TlsFastMsDirect       = 800    # Снижено с 1600
        TlsFastMsProxy        = 1200   # Снижено с 2200
        TlsRetryMsDirect      = 1300   # Снижено с 2600
        TlsRetryMsProxyFloor  = 1300   # Снижено с 2600
    }
    NetInfo = @{
        WebFastDefaultMs      = 1000   # Снижено с 3000
        RedirectorMs          = 700    # Снижено с 2000
        GeoPerRequestMs       = 500    # Снижено с 1500
        Ipv6ProbeWaitMs       = 350    # Снижено с 1000
        RedirectorRequestMs   = 700    # Снижено с 3000
    }
    Traceroute = @{
        DefaultTimeoutSec       = 2   # Снижено с 5
        HopTcpTlsTimeoutSec     = 1   # Снижено с 2
        HopTlsCapMs             = 1200   # Снижено с 3000
        HopTcpCapMs             = 800    # Снижено с 2000
        TracertHopWaitMs        = 120    # Снижено с 350
        TraceProcessKillMsBase  = 5000    # Снижено с 12000
        TraceProcessKillMsPerHop = 400    # Снижено с 1400
        WaitForExitAfterKillMs  = 400     # Снижено с 1000
        TcpPollSliceMs          = 40      # Снижено с 90
        UdpRecvPollMs           = 300     # Снижено с 1000
    }
    ProxySelfTest = @{
        DetectTcpConnectMs = 700     # Снижено с 2000
        DetectStreamRwMs   = 800     # Снижено с 2000
        QuickTunnelMs      = 2000    # Снижено с 5000
        TcpToProxyMs       = 1500    # Снижено с 4000
        Tunnel443Ms        = 2000    # Снижено с 7000
        HttpGstaticMs      = 1300    # Снижено с 5000
        HttpSlowWarnMs     = 1500    # Снижено с 4800
        PauseAfterTcpMs    = 60      # Снижено с 120
        PauseAfterTunnelMs = 60      # Снижено с 150
        PauseAfterHttpMs   = 80      # Снижено с 200
    }
    UiScan = @{
        StatusBarThrottleCollectMs = 90   # Снижено с 240
        StatusBarThrottleRevealMs  = 110  # Снижено с 280
        RevealAnimFps            = 48
    }
    Internet = @{
        PingTimeoutMs    = 400    # Снижено с 1000
        TcpFallbackMs    = 400    # Снижено с 1000
    }
    HttpMisc = @{
        GitHubReleaseApiMs      = 1500   # Снижено с 5000
        RedirectorViaProxyMs    = 1200   # Снижено с 3000
        GeoProviderViaProxyMs   = 500    # Снижено с 1500
    }
    UI = @{
        Num = 1; Dom = 6; IP = 50; HTTP = 68; T12 = 76; T13 = 86; Lat = 96; Ver = 106
    }
    NavStr = "[READY] [ENTER] SCAN | [S] SETTINGS | [P] PROXY | [D] TRACE | [U] UPDATE | [R] REPORT | [H] HELP | [Q] QUIT"
}
$CONST = $SCRIPT:CONST

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

function Test-DebugLogEnabled {
    if ($DEBUG_ENABLED) { return $true }
    try {
        if ($script:Config -and ($script:Config.DebugLogEnabled -eq $true)) { return $true }
    } catch { }
    return $false
}

# Полные ПК/пользователь/пути в заголовке лога — только при явном согласии (конфиг или YT_DPI_DEBUG_IDENTIFIERS).
function Test-DebugLogWriteFullIdentifiers {
    $raw = [System.Environment]::GetEnvironmentVariable("YT_DPI_DEBUG_IDENTIFIERS", "Process")
    if (-not $raw) { $raw = [System.Environment]::GetEnvironmentVariable("YT_DPI_DEBUG_IDENTIFIERS", "User") }
    if (-not $raw) { $raw = [System.Environment]::GetEnvironmentVariable("YT_DPI_DEBUG_IDENTIFIERS", "Machine") }
    if ([string]$raw -match '^(?i:1|true|yes|on)$') { return $true }
    try {
        if ($script:Config -and ($script:Config.DebugLogFullIdentifiers -eq $true)) { return $true }
    } catch { }
    return $false
}

function Get-DebugHudTail {
    param([int]$maxLen = 0)

    # Определяем редакцию (Core / Desktop) и версию PowerShell
    $edition = if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
    $version = $PSVersionTable.PSVersion.ToString()  # например "7.6.2" или "5.1.19041.1"
    $editionVersion = "$edition $version"

    # Проверка прав администратора
    try {
        $isAdm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $isAdm = $false }
    $au = if ($isAdm) { 'Adm' } else { 'Usr' }

    # IpPreference из конфига
    $ipPref = '?'
    try { if ($script:Config -and $script:Config.IpPreference) { $ipPref = [string]$script:Config.IpPreference } } catch { }

    # TlsMode из конфига
    $tls = 'Auto'
    try { if ($script:Config -and $script:Config.TlsMode) { $tls = [string]$script:Config.TlsMode } } catch { }

    # Прокси
    $px = if ($global:ProxyConfig -and $global:ProxyConfig.Enabled) { 'Px1' } else { 'Px0' }

    # Размер окна консоли
    try {
        $ww = [Console]::WindowWidth
        $wh = [Console]::WindowHeight
    } catch { $ww = 0; $wh = 0 }

    # Собираем базовую строку (теперь с редакцией и версией)
    $base = " ${editionVersion} ${au} ${ipPref} ${tls} ${px} ${ww}x${wh}"

    # Добавляем PID, если требуется
    if ($script:DebugHudIncludePid) { $base = "PID=$PID $base" }

    # Обрезаем до максимальной длины, если нужно
    if ($maxLen -gt 0 -and $base.Length -gt $maxLen) { return $base.Substring(0, $maxLen) }
    return $base
}

function Write-DebugLog($msg, $level = "DEBUG") {
    if (-not (Test-DebugLogEnabled)) { return }
    $line = "[$(Get-Date -Format 'HH:mm:ss.fff')] [$level] $msg`r`n"
    $got = $false
    try {
        try { $got = $DebugLogMutex.WaitOne([int]$CONST.Mutex.WaitMs) } catch { $got = $false }
        if (-not $got) { return }
        [System.IO.File]::AppendAllText($DebugLogFile, $line, [System.Text.Encoding]::UTF8)
    } catch { }
    finally {
        if ($got) {
            try { [void]$DebugLogMutex.ReleaseMutex() } catch { }
        }
    }
}

# Данные для заголовка лога: собираем всегда (раньше только при YT_DPI_DEBUG — в логе из конфига были «заглушки»)
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { $isAdmin = $false }
try { $osInfo = Get-CimInstance Win32_OperatingSystem } catch { $osInfo = @{ Caption = "Windows (Legacy)"; Version = "Unknown" } }

$script:DebugSessionHeaderWritten = $false

function Write-DebugLogSessionHeaderIfNeeded {
    if (-not (Test-DebugLogEnabled)) { return }
    if ($script:DebugSessionHeaderWritten) { return }
    $script:DebugSessionHeaderWritten = $true

    Write-DebugLog "==================== YT-DPI SESSION START ====================" "INFO"
    Write-DebugLog "Скрипт версия: $scriptVersion" "INFO"
    Write-DebugLog "ОС: $($osInfo.Caption) ($($osInfo.Version))" "INFO"
    Write-DebugLog "PowerShell: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion) | PID: $PID" "INFO"
    Write-DebugLog "Права: $(if ($isAdmin) { 'Администратор' } else { 'Пользователь' })" "INFO"
    if (Test-DebugLogWriteFullIdentifiers) {
        Write-DebugLog "Компьютер: $env:COMPUTERNAME | Пользователь Windows: $env:USERNAME | Домен/рабочая группа: $env:USERDOMAIN" "INFO"
    } else {
        Write-DebugLog "Узел/пользователь Windows: [обезличено] (полные данные: п.5 в настройках или YT_DPI_DEBUG_IDENTIFIERS=1)" "INFO"
    }
    Write-DebugLog "Локаль: $([System.Globalization.CultureInfo]::CurrentCulture.Name)" "INFO"
    try {
        Write-DebugLog "Архитектура: OS 64-bit=$([System.Environment]::Is64BitOperatingSystem), процесс PowerShell 64-bit=$([System.Environment]::Is64BitProcess)" "INFO"
    } catch { }
    if (Test-DebugLogWriteFullIdentifiers) {
        Write-DebugLog "Путь к скрипту: $script:OriginalFilePath" "INFO"
        Write-DebugLog "Рабочая папка: $((Get-Location).Path)" "INFO"
        Write-DebugLog "Лог-файл: $DebugLogFile | YT_DPI_DEBUG (env): $DEBUG_ENABLED | DebugLogEnabled (config): $(if ($script:Config -and $script:Config.DebugLogEnabled) { $true } else { $false })" "INFO"
    } else {
        $scriptLeaf = if ($script:OriginalFilePath) { [System.IO.Path]::GetFileName($script:OriginalFilePath) } else { '?' }
        Write-DebugLog "Путь к скрипту: [обезличено] (только имя файла: $scriptLeaf)" "INFO"
        Write-DebugLog "Рабочая папка: [обезличено]" "INFO"
        Write-DebugLog "Лог-файл: YT-DPI_Debug.log (рядом со скриптом, полный путь скрыт) | YT_DPI_DEBUG (env): $DEBUG_ENABLED | DebugLogEnabled (config): $(if ($script:Config -and $script:Config.DebugLogEnabled) { $true } else { $false })" "INFO"
    }
    Write-DebugLog "============================================================" "INFO"
    if ($DEBUG_ENABLED) {
        Write-DebugLog "Лог при старте очищался/ротировался по правилам env YT_DPI_DEBUG." "INFO"
    } else {
        Write-DebugLog "Запись лога включена без очистки файла при старте (только конфиг или env без предочистки)." "INFO"
    }
}

# Заголовок сессии пишем после финального пути к логу и Load-Config (см. Initialize-AppState)
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
function Initialize-ConsoleHelper {
    if (-not ([System.Management.Automation.PSTypeName]'ConsoleHelper').Type) {
        Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }
    if (([System.Management.Automation.PSTypeName]'ConsoleHelper').Type) {
        [ConsoleHelper]::DisableQuickEdit()
        Write-DebugLog "QuickEdit отключён." "INFO"
    }
}
Initialize-ConsoleHelper

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

# --- ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ ОКРУЖЕНИЯ ---
$script:Config = $null
$script:NetInfo = $null
$script:DnsCache = [hashtable]::Synchronized(@{}) # Сразу делаем его потокобезопасным
$script:LastScanResults = @()
# Уже был хотя бы один завершённый скан (для частичного «водопада» и отключения idle-арта)
$script:HasCompletedScan = $false
$script:StatusFeedbackCacheKey = $null
$script:StatusControlsCacheKey = $null

# Фоновая задача для предзагрузки NetInfo
$script:BackgroundNetInfo = $null
$script:NetInfoUpdating = $false

function Start-BackgroundNetInfoUpdate {
    if ($script:NetInfoUpdating) { return }
    $script:NetInfoUpdating = $true

    $existing = Get-Job -Name "NetInfoUpdater" -ErrorAction SilentlyContinue
    if ($existing) {
        try { Stop-Job $existing -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $existing -Force -ErrorAction SilentlyContinue } catch {}
    }

    Start-Job -Name "NetInfoUpdater" -ScriptBlock {
        function Invoke-WebRequestFast($url, $timeout = 3000) {
            try {
                $req = [System.Net.WebRequest]::Create($url)
                $req.Timeout = $timeout
                $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                $resp = $req.GetResponse()
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $content = $reader.ReadToEnd()
                $resp.Close()
                return $content
            } catch { return "" }
        }

        $result = @{
            DNS = "UNKNOWN"
            CDN = "manifest.googlevideo.com"
            ISP = "Loading..."
            LOC = "Unknown"
            HasIPv6 = $false
        }

        # DNS
        try {
            $wmi = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" |
                   Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
            if ($wmi) { $result.DNS = $wmi.DNSServerSearchOrder[0] }
        } catch {}

        # CDN через redirector
        try {
            $rnd = [guid]::NewGuid().ToString().Substring(0,8)
            $raw = Invoke-WebRequestFast "http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd" 2000
            $cdnShort = $null
            if ($raw -match '=>\s+([\w-]+)') {
                $cdnShort = $matches[1]
            }
            if ($cdnShort -and $cdnShort -ne 'r1') {
                $result.CDN = "r1.$cdnShort.googlevideo.com"
            } else {
                if ($raw -match '=>\s*([a-zA-Z0-9.\-]+\.googlevideo\.com)') {
                    $result.CDN = $matches[1]
                }
            }
        } catch {}

        # GEO (с агрессивным таймаутом - 1.5 секунды на каждый)
        $geoUrls = @(
            "https://ip-api.com/json/?fields=status,countryCode,city,isp",
            "https://ipapi.co/json/"
        )
        foreach ($url in $geoUrls) {
            $raw = Invoke-WebRequestFast $url 1500
            if ($raw -match '\{.*\}') {
                try {
                    $data = $raw | ConvertFrom-Json
                    if ($data.status -eq "success" -and $data.isp) {
                        $result.ISP = $data.isp -replace '(?i)\s*(LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC|Private Enterprise|Group|Corporation)', ''
                        $result.LOC = "$($data.city), $($data.countryCode)"
                        break
                    } elseif ($data.org) {
                        $result.ISP = $data.org
                        $result.LOC = "$($data.city), $($data.country_code)"
                        break
                    }
                } catch {}
            }
        }

        if ($result.ISP.Length -gt 25) { $result.ISP = $result.ISP.Substring(0, 22) + "..." }

        # IPv6 тест (быстрый)
        try {
            $t = New-Object System.Net.Sockets.TcpClient([System.Net.Sockets.AddressFamily]::InterNetworkV6)
            $a = $t.BeginConnect("ipv6.google.com", 80, $null, $null)
            if ($a.AsyncWaitHandle.WaitOne(1000)) {
                $t.EndConnect($a)
                $result.HasIPv6 = $true
            }
            $t.Close()
        } catch {}

        $result.TimestampTicks = (Get-Date).Ticks
        return $result
    } | Out-Null
}

# Функция проверки готовности фонового обновления
function Get-ReadyNetInfo {
    $job = Get-Job -Name "NetInfoUpdater" -ErrorAction SilentlyContinue
    if ($job -and $job.State -eq "Completed") {
        $script:BackgroundNetInfo = Receive-Job $job
        Remove-Job $job
        $script:NetInfoUpdating = $false
        Write-DebugLog "Фоновое обновление NetInfo завершено" "INFO"
    }

    if (Test-NetInfoUsable $script:BackgroundNetInfo) {
        return $script:BackgroundNetInfo
    } elseif (Test-NetInfoUsable $script:Config.NetCache) {
        return $script:Config.NetCache
    } else {
        # Возвращаем заглушку, скан начнется мгновенно
        return @{
            DNS = "UNKNOWN"
            CDN = "manifest.googlevideo.com"
            ISP = "Detecting..."
            LOC = "Unknown"
            HasIPv6 = $false
            TimestampTicks = (Get-Date).Ticks
        }
    }
}


# --- НИЗКОУРОВНЕВЫЙ TLS ДВИЖОК (C#) ---
$tlsCode = @"
using System;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Linq;
using System.Security.Cryptography;

public class TlsScanner {
    private static void FillRandomBytes(byte[] buffer) {
        using (var rng = RandomNumberGenerator.Create()) {
            rng.GetBytes(buffer);
        }
    }
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

        byte[] random = new byte[32];
        FillRandomBytes(random);
        body.AddRange(random);

        body.Add(0x00); // Session ID len
        body.AddRange(new byte[] { 0x00, 0x06, 0x13, 0x01, 0x13, 0x02, 0x13, 0x03 }); // Ciphers: TLS_AES_128_GCM_SHA256 и др.
        body.Add(0x20); // Length 32
        byte[] sessId = new byte[32]; FillRandomBytes(sessId);
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
        byte[] key = new byte[32]; FillRandomBytes(key);
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
$script:TlsScannerLoaded = $false
$script:TlsScannerLoadFailed = $false

function Test-TlsScannerReady {
    if ($script:TlsScannerLoaded -or ([System.Management.Automation.PSTypeName]'TlsScanner').Type) {
        $script:TlsScannerLoaded = $true
        return $true
    }
    return $false
}

function Ensure-TlsScannerLoaded {
    if (Test-TlsScannerReady) { return $true }
    if ($script:TlsScannerLoadFailed) { return $false }

    try {
        Add-Type -TypeDefinition $tlsCode -ErrorAction Stop
        $script:TlsScannerLoaded = $true
        Write-DebugLog "TLS C# компонент загружен" "INFO"
        return $true
    } catch {
        $script:TlsScannerLoadFailed = $true
        Write-DebugLog "Ошибка загрузки TLS C#: $_" "ERROR"
        return $false
    }
}

# Компилируем C# код traceroute
$traceCode = @"
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// Не использовать System.Progress: в pw7 без SynchronizationContext колбэки идут в ThreadPool,
/// а обновление консоли из фонового потока приводит к аварийному завершению процесса.
/// </summary>
public sealed class SynchronousProgress : IProgress<string>
{
    private readonly Action<string> _handler;
    public SynchronousProgress(Action<string> handler) { _handler = handler; }
    public void Report(string value) { if (_handler != null) { _handler.Invoke(value); } }
}

public class AdvancedTraceroute
{
    private static readonly object s_synRngLock = new object();
    private static readonly Random s_synRng = new Random();

    private static int NextBoundedInt(int minInclusive, int maxExclusive)
    {
        lock (s_synRngLock) { return s_synRng.Next(minInclusive, maxExclusive); }
    }

    // ========== ПУБЛИЧНЫЕ МЕТОДЫ ==========

    /// <summary>
    /// Выполняет трассировку с автоопределением лучшего метода
    /// </summary>
    public static List<TraceHop> Trace(string target, int maxHops = 30, int timeoutMs = 3000,
                                       TraceMethod method = TraceMethod.Auto, IProgress<string> progress = null)
    {
        // Разрешаем DNS
        if (progress != null) { progress.Report(string.Format("[*] Разрешение DNS: {0}", target)); }
        var targetIp = ResolveTarget(target);
        if (targetIp == null)
        {
            if (progress != null) { progress.Report(string.Format("[!] Не удалось разрешить DNS: {0}", target)); }
            return new List<TraceHop>();
        }
        if (progress != null) { progress.Report(string.Format("[+] Целевой IP: {0}", targetIp)); }

        // Автоопределение метода
        if (method == TraceMethod.Auto)
        {
            method = DetectBestMethod(targetIp);
            if (progress != null) { progress.Report(string.Format("[*] Выбран метод: {0}", method)); }
        }

        // Выполняем трассировку
        switch (method)
        {
            case TraceMethod.Icmp:
                return TraceWithIcmp(targetIp, maxHops, timeoutMs, progress);
            case TraceMethod.TcpSyn:
                return TraceWithTcpSyn(targetIp, 443, maxHops, timeoutMs, progress);
            case TraceMethod.Udp:
                return TraceWithUdp(targetIp, 33434, maxHops, timeoutMs, progress);
            default:
                return TraceWithIcmp(targetIp, maxHops, timeoutMs, progress);
        }
    }

    /// <summary>
    /// Быстрая трассировка TCP SYN (обходит ICMP блокировки)
    /// </summary>
    public static List<TraceHop> QuickTcpTrace(string target, int port = 443, int maxHops = 15)
    {
        return TraceWithTcpSyn(ResolveTarget(target), port, maxHops, 2000, null);
    }

    // ========== ВНУТРЕННИЕ МЕТОДЫ ==========

    private static IPAddress ResolveTarget(string target)
    {
        try
        {
            var addresses = Dns.GetHostAddresses(target);
            return addresses.FirstOrDefault(ip => ip.AddressFamily == AddressFamily.InterNetwork)
                   ?? addresses.FirstOrDefault();
        }
        catch { return null; }
    }

    public class NetworkInfoFast {
    public static dynamic GetCachedInfo() {
        var result = new Dictionary<string, object>();

        // DNS (быстро)
        try {
            var hostName = Dns.GetHostName();
            var ips = Dns.GetHostAddresses(hostName);
            var dns = ips.FirstOrDefault(ip => ip.AddressFamily == AddressFamily.InterNetwork);
            result["DNS"] = (dns != null ? dns.ToString() : null) ?? "UNKNOWN";
        } catch { result["DNS"] = "UNKNOWN"; }

        // CDN через DNS (быстро, без HTTP)
        try {
            var cdnIps = Dns.GetHostAddresses("redirector.googlevideo.com");
            result["CDN"] = "redirector.googlevideo.com (DNS resolved)";
        } catch { result["CDN"] = "manifest.googlevideo.com"; }

        result["ISP"] = "Detected via C#";
        result["LOC"] = "Fast mode";
        result["HasIPv6"] = Socket.OSSupportsIPv6;
        result["TimestampTicks"] = DateTime.Now.Ticks;

        return result;
    }
}

    private static TraceMethod DetectBestMethod(IPAddress targetIp)
    {
        // Пробуем ICMP (быстрый тест)
        using (var ping = new Ping())
        {
            try
            {
                var reply = ping.Send(targetIp, 1000);
                if (reply != null && reply.Status == IPStatus.Success)
                    return TraceMethod.Icmp;
            }
            catch { }
        }

        // Если ICMP заблокирован, пробуем TCP
        using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.Tcp))
        {
            try
            {
                socket.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.IpTimeToLive, 1);
                return TraceMethod.TcpSyn;
            }
            catch (SocketException)
            {
                // Raw sockets требуют админских прав
                return TraceMethod.Udp; // UDP работает без админа
            }
        }
    }

    // SocketError.TtlExpired отсутствует в public enum .NET 5+ (см. System.Net.Sockets.SocketError) — только эвристика по тексту.
    private static bool LooksLikeTracerouteTtlExpired(SocketException ex)
    {
        if (ex == null) return false;
        string m = ex.Message ?? string.Empty;
        return m.IndexOf("TTL", StringComparison.OrdinalIgnoreCase) >= 0
            || m.IndexOf("time to live", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    // ========== ICMP TRACEROUTE (ТРЕБУЕТ АДМИНА) ==========

    private static List<TraceHop> TraceWithIcmp(IPAddress targetIp, int maxHops, int timeoutMs,
                                                 IProgress<string> progress)
    {
        var results = new List<TraceHop>();
        using (var ping = new Ping())
        {
            var options = new PingOptions(1, true);
            var buffer = new byte[32];

            for (int ttl = 1; ttl <= maxHops; ttl++)
            {
                if (progress != null) { progress.Report(string.Format("[TRACE] Hop {0}/{1} (ICMP)...", ttl, maxHops)); }
                options.Ttl = ttl;

                try
                {
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    var reply = ping.Send(targetIp, timeoutMs, buffer, options);
                    sw.Stop();

                    var hop = new TraceHop
                    {
                        HopNumber = ttl,
                        IP = (reply.Address != null ? reply.Address.ToString() : null) ?? "*",
                        RttMs = (int)sw.ElapsedMilliseconds,
                        Status = MapIcmpStatus(reply.Status)
                    };

                    results.Add(hop);
                    if (progress != null) { progress.Report(string.Format("[OK] Hop {0}: {1} - {2} ({3}ms)", ttl, hop.IP, hop.Status, hop.RttMs)); }

                    if (reply.Status == IPStatus.Success ||
                        (reply.Address != null && reply.Address.Equals(targetIp)))
                        break;
                }
                catch (PingException)
                {
                    results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "TIMEOUT" });
                    if (progress != null) { progress.Report(string.Format("[!] Hop {0}: TIMEOUT", ttl)); }
                }
                catch (Exception ex)
                {
                    if (progress != null) { progress.Report(string.Format("[ERROR] Hop {0}: {1}", ttl, ex.Message)); }
                }

                Thread.Sleep(20); // Небольшая задержка между хопами
            }
        }
        return results;
    }

    // ========== TCP SYN TRACEROUTE (ОБХОДИТ ICMP, ТРЕБУЕТ АДМИНА) ==========

    private static List<TraceHop> TraceWithTcpSyn(IPAddress targetIp, int port, int maxHops,
                                                   int timeoutMs, IProgress<string> progress)
    {
        var results = new List<TraceHop>();
        var localIp = GetLocalIpAddress();

        for (int ttl = 1; ttl <= maxHops; ttl++)
        {
            if (progress != null) { progress.Report(string.Format("[TRACE] Hop {0}/{1} (TCP SYN:{2})...", ttl, maxHops, port)); }

            using (var sender = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.IP))
            using (var receiver = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.IP))
            {
                try
                {
                    // Настройка сокетов
                    sender.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.HeaderIncluded, true);
                    sender.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.IpTimeToLive, ttl);

                    receiver.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.HeaderIncluded, true);
                    receiver.ReceiveTimeout = timeoutMs;
                    receiver.Bind(new IPEndPoint(IPAddress.Any, 0));

                    // Собираем TCP SYN пакет
                    var srcPort = NextBoundedInt(1024, 65535);
                    var seq = (uint)NextBoundedInt(1, int.MaxValue);

                    var tcpPacket = BuildTcpSynPacket(srcPort, port, seq);
                    var ipPacket = BuildIpPacket(localIp, targetIp, 6, tcpPacket);

                    // Отправляем
                    var endpoint = new IPEndPoint(targetIp, 0);
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    sender.SendTo(ipPacket, endpoint);

                    // Ждем ответ
                    var buffer = new byte[4096];
                    var remoteEp = (EndPoint)new IPEndPoint(IPAddress.Any, 0);

                    string responderIp = null;
                    string status = "TIMEOUT";
                    int rttMs = -1;

                    if (receiver.Poll(timeoutMs * 1000, SelectMode.SelectRead))
                    {
                        var bytes = receiver.ReceiveFrom(buffer, ref remoteEp);
                        sw.Stop();
                        rttMs = (int)sw.ElapsedMilliseconds;

                        responderIp = ((IPEndPoint)remoteEp).Address.ToString();
                        status = ParseIpResponse(buffer, bytes, targetIp, port);
                    }

                    var hop = new TraceHop
                    {
                        HopNumber = ttl,
                        IP = responderIp ?? "*",
                        TcpStatus = status,
                        RttMs = rttMs,
                        Status = status == "SYNACK" ? "RESPONDED" :
                                (status == "RST" ? "BLOCKED" : "TIMEOUT")
                    };

                    results.Add(hop);
                    if (progress != null) { progress.Report(string.Format("[OK] Hop {0}: {1} - {2} ({3}ms)", ttl, hop.IP, hop.Status, hop.RttMs)); }

                    if (status == "SYNACK" || (responderIp == targetIp.ToString()))
                        break;
                }
                catch (SocketException ex)
                {
                    if (progress != null) { progress.Report(string.Format("[!] Hop {0}: SOCKET ERROR - {1}", ttl, ex.Message)); }
                    results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "ERROR" });
                }
                catch (Exception ex)
                {
                    if (progress != null) { progress.Report(string.Format("[ERROR] Hop {0}: {1}", ttl, ex.Message)); }
                }
            }
            Thread.Sleep(20);
        }
        return results;
    }

    // ========== UDP TRACEROUTE (НЕ ТРЕБУЕТ АДМИНА, РАБОТАЕТ ВЕЗДЕ) ==========

    private static List<TraceHop> TraceWithUdp(IPAddress targetIp, int startPort, int maxHops,
                                                int timeoutMs, IProgress<string> progress)
    {
        var results = new List<TraceHop>();

        for (int ttl = 1; ttl <= maxHops; ttl++)
        {
            if (progress != null) { progress.Report(string.Format("[TRACE] Hop {0}/{1} (UDP)...", ttl, maxHops)); }

            using (var sender = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
            using (var receiver = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.Icmp))
            {
                try
                {
                    sender.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.IpTimeToLive, ttl);
                    receiver.ReceiveTimeout = timeoutMs;
                    receiver.Bind(new IPEndPoint(IPAddress.Any, 0));

                    var sendPort = startPort + ttl;
                    var endpoint = new IPEndPoint(targetIp, sendPort);
                    var buffer = new byte[] { 0x00 };

                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    sender.SendTo(buffer, endpoint);

                    var responseBuffer = new byte[256];
                    var remoteEp = (EndPoint)new IPEndPoint(IPAddress.Any, 0);

                    string responderIp = null;
                    string status = "TIMEOUT";
                    int rttMs = -1;

                    if (receiver.Poll(timeoutMs * 1000, SelectMode.SelectRead))
                    {
                        var bytes = receiver.ReceiveFrom(responseBuffer, ref remoteEp);
                        sw.Stop();
                        rttMs = (int)sw.ElapsedMilliseconds;
                        responderIp = ((IPEndPoint)remoteEp).Address.ToString();
                        status = "RESPONDED";
                    }

                    var hop = new TraceHop
                    {
                        HopNumber = ttl,
                        IP = responderIp ?? "*",
                        RttMs = rttMs,
                        Status = status
                    };

                    results.Add(hop);
                    if (progress != null) { progress.Report(string.Format("[OK] Hop {0}: {1} - {2} ({3}ms)", ttl, hop.IP, hop.Status, hop.RttMs)); }

                    if (responderIp == targetIp.ToString())
                        break;
                }
                catch (SocketException ex)
                {
                    if (LooksLikeTracerouteTtlExpired(ex))
                    {
                        // TTL истек - это нормально для промежуточных хопов
                        if (progress != null) { progress.Report(string.Format("[*] Hop {0}: TTL expired", ttl)); }
                        results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "TTL_EXPIRED" });
                    }
                    else
                    {
                        if (progress != null) { progress.Report(string.Format("[!] Hop {0}: {1}", ttl, ex.Message)); }
                        results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "ERROR" });
                    }
                }
            }
            Thread.Sleep(20);
        }
        return results;
    }

    // ========== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ==========

    private static IPAddress GetLocalIpAddress()
    {
        using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
        {
            socket.Connect("8.8.8.8", 53);
            var endPoint = socket.LocalEndPoint as IPEndPoint;
            return (endPoint == null) ? null : endPoint.Address;
        }
    }

    private static byte[] BuildTcpSynPacket(int srcPort, int dstPort, uint seq)
    {
        var tcp = new byte[20];

        // Source port
        tcp[0] = (byte)(srcPort >> 8);
        tcp[1] = (byte)(srcPort & 0xFF);
        // Destination port
        tcp[2] = (byte)(dstPort >> 8);
        tcp[3] = (byte)(dstPort & 0xFF);
        // Sequence number
        tcp[4] = (byte)(seq >> 24);
        tcp[5] = (byte)(seq >> 16);
        tcp[6] = (byte)(seq >> 8);
        tcp[7] = (byte)(seq & 0xFF);
        // Data offset (5 = 20 bytes header) + flags (SYN)
        tcp[12] = 0x50; // Data offset = 5 (20 bytes)
        tcp[13] = 0x02; // SYN flag
        // Window size
        tcp[14] = 0x20;
        tcp[15] = 0x00;

        return tcp;
    }

    private static byte[] BuildIpPacket(IPAddress source, IPAddress destination,
                                        byte protocol, byte[] payload)
    {
        var totalLen = 20 + payload.Length;
        var packet = new byte[totalLen];

        // IP version (4) + header length (5)
        packet[0] = 0x45;
        // Total length
        packet[2] = (byte)(totalLen >> 8);
        packet[3] = (byte)(totalLen & 0xFF);
        // TTL (64)
        packet[8] = 64;
        // Protocol
        packet[9] = protocol;
        // Source IP
        source.GetAddressBytes().CopyTo(packet, 12);
        // Destination IP
        destination.GetAddressBytes().CopyTo(packet, 16);

        // Calculate checksum
        // Контрольная сумма только по IPv4-заголовку (20 байт), не по TCP payload (RFC 791).
        var checksum = ComputeIpChecksum(packet, 20);
        packet[10] = (byte)(checksum >> 8);
        packet[11] = (byte)(checksum & 0xFF);

        // Payload
        payload.CopyTo(packet, 20);

        return packet;
    }

    private static ushort ComputeIpChecksum(byte[] packet, int ipHeaderLength)
    {
        uint sum = 0;
        for (int i = 0; i < ipHeaderLength; i += 2)
        {
            if (i + 1 < ipHeaderLength)
                sum += (uint)((packet[i] << 8) | packet[i + 1]);
            else
                sum += (uint)(packet[i] << 8);

            if ((sum & 0xFFFF0000) != 0)
            {
                sum = (sum & 0xFFFF) + (sum >> 16);
            }
        }

        return (ushort)~sum;
    }

    private static string ParseIpResponse(byte[] buffer, int bytes, IPAddress targetIp, int targetPort)
    {
        if (bytes < 20) return "UNKNOWN";

        var protocol = buffer[9];

        if (protocol == 1) // ICMP
        {
            var type = buffer[20];
            if (type == 11) return "TTL_EXPIRED";
            if (type == 3) return "PORT_UNREACHABLE";
            return string.Format("ICMP_{0}", type);
        }
        else if (protocol == 6) // TCP
        {
            var ipHeaderLen = (buffer[0] & 0x0F) * 4;
            if (bytes < ipHeaderLen + 20) return "UNKNOWN";

            var tcpOffset = ipHeaderLen;
            var flags = buffer[tcpOffset + 13];

            if ((flags & 0x12) == 0x12) return "SYNACK";
            if ((flags & 0x04) == 0x04) return "RST";
            return "TCP_OTHER";
        }

        return "UNKNOWN";
    }

    private static string MapIcmpStatus(IPStatus status)
    {
        switch (status)
        {
            case IPStatus.Success: return "RESPONDED";
            case IPStatus.TtlExpired: return "TTL_EXPIRED";
            case IPStatus.TimedOut: return "TIMEOUT";
            case IPStatus.DestinationUnreachable: return "UNREACHABLE";
            default: return status.ToString();
        }
    }
}

// ========== ВСПОМОГАТЕЛЬНЫЕ КЛАССЫ ==========

public enum TraceMethod
{
    Auto,
    Icmp,
    TcpSyn,
    Udp
}

public class TraceHop
{
    public int HopNumber { get; set; }
    public string IP { get; set; }
    public int RttMs { get; set; }
    public string Status { get; set; }
    public string TcpStatus { get; set; } // Для TCP метода (SYNACK/RST)

    public bool IsBlocking { get { return Status == "BLOCKED" || TcpStatus == "RST"; } }
    public bool IsTimeout { get { return Status == "TIMEOUT" || Status == "TTL_EXPIRED"; } }

    public override string ToString()
    {
        string rttPart = (RttMs > 0) ? string.Format("({0}ms)", RttMs) : "";
        return string.Format("Hop {0,2}: {1,-15} {2} {3}", HopNumber, IP == null ? "" : IP, Status == null ? "" : Status, rttPart);
    }
}
"@

$script:TracerouteLoaded = $false
$script:TracerouteLoadFailed = $false

function Test-TracerouteReady {
    if ($script:TracerouteLoaded -or ([System.Management.Automation.PSTypeName]'AdvancedTraceroute').Type) {
        $script:TracerouteLoaded = $true
        return $true
    }
    return $false
}

function Ensure-TracerouteLoaded {
    if (Test-TracerouteReady) { return $true }
    if ($script:TracerouteLoadFailed) { return $false }

    try {
        Add-Type -TypeDefinition $traceCode -ErrorAction Stop
        $script:TracerouteLoaded = $true
        Write-DebugLog "Traceroute C# компонент загружен" "INFO"
        return $true
    } catch {
        $script:TracerouteLoadFailed = $true
        Write-DebugLog "Ошибка загрузки traceroute: $_" "ERROR"
        return $false
    }
}


# --- ГЛОБАЛЬНЫЕ ПУТИ ---
# Лог кладем строго в папку, где лежит сам файл .bat
$script:ParentDir = Split-Path -Parent $script:OriginalFilePath
$DebugLogFile = Join-Path $script:ParentDir "YT-DPI_Debug.log"
# При отладке через env — заголовок сразу в финальный путь к логу (до Load-Config конфиг в логе ещё не виден)
if ($DEBUG_ENABLED) { Write-DebugLogSessionHeaderIfNeeded }

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
        IpPreference = "IPv6"
        TlsMode = "Auto"       # NEW: "Auto", "TLS12", "TLS13"
        Proxy = @{ Enabled = $false; Type = "HTTP"; Host = ""; Port = 0; User = ""; Pass = "" }
        ProxyHistory = @()
        NetCache = @{
            ISP = "Loading..."; LOC = "Unknown"; DNS = "8.8.8.8";
            CDN = "manifest.googlevideo.com";
            TimestampTicks = (Get-Date).AddDays(-1).Ticks;
            HasIPv6 = $false
        }
        DnsCache = @{}
        DebugLogEnabled = $false
        # true = в заголовке лога полные имя ПК, учётная запись и пути (осторожно при публикации лога)
        DebugLogFullIdentifiers = $false
        # Первый проход T13+T12 через ThreadPool Tasks в воркере нестабилен — по умолчанию выключено.
        ScanParallelTlsFirstPass = $false
    }
}

function Initialize-DisableBrokenParallelTlsTasks {
    if (-not $script:Config) { return }
    if ($null -ne $script:Config.ParallelTlsTasksDisabled032026) { return }
    $script:Config | Add-Member -MemberType NoteProperty -Name "ParallelTlsTasksDisabled032026" -Value $true -Force
    $script:Config | Add-Member -MemberType NoteProperty -Name "ScanParallelTlsFirstPass" -Value $false -Force
    Write-DebugLog "Миграция: параллельный первый проход TLS отключён по умолчанию (ParallelTlsTasksDisabled032026)" "INFO"
    Save-Config $script:Config
}

function Get-PaddedCenter {
    param($text, $width)
    $spaces = $width - $text.Length
    if ($spaces -le 0) { return $text }
    $left = [Math]::Floor($spaces / 2)
    return (" " * $left) + $text
}

function Format-CellCenter {
    param($text, [int]$width)
    $value = [string]$text
    if ($width -le 0) { return "" }
    if ($value.Length -gt $width) { return $value.Substring(0, $width) }
    $left = [Math]::Floor(($width - $value.Length) / 2)
    return ((" " * $left) + $value).PadRight($width)
}

function Format-CellLeft {
    param($text, [int]$width)
    $value = [string]$text
    if ($width -le 0) { return "" }
    if ($value.Length -gt $width) { return $value.Substring(0, $width) }
    return $value.PadRight($width)
}

function New-PlaceholderResultRow {
    param(
        [int]$Number,
        [string]$Target
    )
    return [PSCustomObject]@{
        Number = $Number
        Target = $Target
        IP = "---"
        HTTP = "---"
        T12 = "---"
        T13 = "---"
        Lat = "---"
        Verdict = "IDLE"
        Color = "DarkGray"
    }
}

function New-PlaceholderResultRows {
    param([array]$Targets)
    $rows = New-Object 'object[]' $Targets.Count
    for ($i = 0; $i -lt $Targets.Count; $i++) {
        $rows[$i] = New-PlaceholderResultRow -Number ($i + 1) -Target $Targets[$i]
    }
    return $rows
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

function Test-NetInfoUsable {
    param($NetInfo)
    if ($null -eq $NetInfo) { return $false }
    $isp = [string]$NetInfo.ISP
    $loc = [string]$NetInfo.LOC
    if ([string]::IsNullOrWhiteSpace($isp)) { return $false }
    if ($isp -in @("Loading...", "Detecting...", "Background update", "Unknown")) { return $false }
    if ($loc -in @("Please wait", "Next scan")) { return $false }
    return $true
}

function Set-NetInfoCacheIfUsable {
    param($NetInfo)
    if (Test-NetInfoUsable $NetInfo) {
        $script:Config.NetCache = $NetInfo
        return $true
    }
    Write-DebugLog "NetInfo cache not updated: unusable ISP/LOC ($($NetInfo.ISP) / $($NetInfo.LOC))" "WARN"
    return $false
}

function Start-Updater {
    param(
        [Parameter(Mandatory = $true)]
        [string]$currentFile,
        [Parameter(Mandatory = $true)]
        [string]$downloadUrl
    )

    # Проверка входных параметров
    if ([string]::IsNullOrWhiteSpace($currentFile) -or -not (Test-Path -LiteralPath $currentFile -PathType Leaf)) {
        Write-DebugLog "Start-Updater: currentFile='$currentFile' не существует или не указан."
        return
    }

    $parentPid = $pid
    $tempFile = Join-Path $env:TEMP ("YT-DPI_update_" + [Guid]::NewGuid().ToString("N") + ".tmp")
    $logFile = Join-Path $env:TEMP "yt_updater_debug.log"
    $updaterPath = Join-Path $env:TEMP "yt_run_updater.ps1"

    Write-DebugLog "Запуск апдейтера. Лог: $logFile"

    # Получаем родительскую директорию через .NET – надёжно и без «parameter set»
    $mainDir = [System.IO.Path]::GetDirectoryName($currentFile)
    if ([string]::IsNullOrEmpty($mainDir)) {
        Write-DebugLog "Не удалось определить директорию для файла $currentFile"
        return
    }

    $companionUrl = $null
    $companionDest = $null
    if ($currentFile -match '\.(?i)bat$') {
        $companionUrl = "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.ps1"
        $companionDest = Join-Path $mainDir "YT-DPI.ps1"
    } elseif ($currentFile -match '\.(?i)ps1$') {
        $companionUrl = "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.bat"
        $companionDest = Join-Path $mainDir "YT-DPI.bat"
    }

    # Условия целостности (выражения, которые будут вставлены в генерируемый скрипт)
    if ($currentFile -match '\.(?i)bat$') {
        $integrityExpr = '$size -gt 300 -and ($content -match "YT-DPI.ps1")'
        $compMin = "300"
        $compPat = "YT-DPI.ps1"
    } else {
        $integrityExpr = '$size -gt 8000 -and ($content -match "scriptVersion")'
        $compMin = "8000"
        $compPat = "scriptVersion"
    }

    # Безопасное получение имени файла компаньона
    $companionLeaf = if (-not [string]::IsNullOrEmpty($companionDest)) { [System.IO.Path]::GetFileName($companionDest) } else { "" }
    $compDestEsc = if (-not [string]::IsNullOrEmpty($companionDest)) { $companionDest -replace "'", "''" } else { "" }

    $companionTpl = @'
                try {
                    Write-Log "Downloading companion (REPLACE_COMP_LEAF)..."
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                    $wc2 = New-Object System.Net.WebClient
                    $wc2.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    $bytes2 = $wc2.DownloadData('REPLACE_COMP_URL')
                    $t2 = [System.Text.Encoding]::UTF8.GetString($bytes2)
                    if ($t2.Length -gt 0 -and [int][char]$t2[0] -eq 0xFEFF) { $t2 = $t2.Substring(1) }
                    $t2 = $t2 -replace "`r`n", "`n" -replace "`n", "`r`n"
                    $utf8WithBom = New-Object System.Text.UTF8Encoding $true
                    $tf2 = Join-Path $env:TEMP ("yt_comp_" + [Guid]::NewGuid().ToString("N") + ".tmp")
                    [System.IO.File]::WriteAllText($tf2, $t2, $utf8WithBom)
                    $sz2 = (Get-Item $tf2).Length
                    $raw2 = Get-Content $tf2 -Raw -Encoding UTF8
                    if ($sz2 -gt REPLACE_COMP_MIN -and ($raw2 -match "REPLACE_COMP_PATTERN")) {
                        Copy-Item -LiteralPath $tf2 -Destination 'REPLACE_COMP_DEST' -Force -ErrorAction Stop
                        Write-Log "Companion installed ($sz2 bytes)."
                    } else { Write-Log "Companion integrity FAIL." }
                    Remove-Item $tf2 -Force -ErrorAction SilentlyContinue
                } catch { Write-Log "Companion error: $($_.Exception.Message)" }
'@

    $companionBlock = ""
    if ($companionUrl -and $companionDest) {
        $companionBlock = $companionTpl.
            Replace("REPLACE_COMP_LEAF", $companionLeaf).
            Replace("REPLACE_COMP_URL", $companionUrl).
            Replace("REPLACE_COMP_MIN", $compMin).
            Replace("REPLACE_COMP_PATTERN", $compPat).
            Replace("REPLACE_COMP_DEST", $compDestEsc)
    }

    # Шаблон апдейтера — все сохранения с BOM (UTF8Encoding $true)
    $updaterTemplate = @'
$parentPid = REPLACE_PID
$currentFile = 'REPLACE_FILE'
$downloadUrl = 'REPLACE_URL'
$tempFile = 'REPLACE_TEMP'
$logFile = 'REPLACE_LOG'

function Write-Log($m) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $m`r`n"
    try { [System.IO.File]::AppendAllText($logFile, $line, [System.Text.Encoding]::UTF8) } catch { }
}

Write-Log "--- UPDATER SESSION START ---"

# 1. Принудительно убиваем старый процесс
Write-Log "Killing old process $parentPid..."
try {
    Stop-Process -Id $parentPid -Force -ErrorAction Stop
    Write-Log "Process killed successfully"
} catch {
    Write-Log "Could not kill process: $_"
}
Start-Sleep -Seconds 1

# 2. Дополнительная проверка, что процесс действительно завершён
$count = 0
while (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) {
    if ($count -gt 30) {
        Write-Log "Force killing again"
        Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue
        break
    }
    Start-Sleep -Milliseconds 100
    $count++
}
Start-Sleep -Seconds 1

# 3. Скачивание и замена файла (с конвертацией CRLF и сохранением с BOM)
try {
    Write-Log "Downloading from $downloadUrl..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $web = New-Object System.Net.WebClient
    $web.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $bytes = $web.DownloadData($downloadUrl)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    # Конвертируем LF -> CRLF
    $text = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
    # Удаляем BOM, если он был (чтобы не дублировать)
    if ($text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

    $utf8WithBom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($tempFile, $text, $utf8WithBom)

    Write-Log "Downloaded and fixed. Size: $($text.Length)"

    if (Test-Path $tempFile) {
        $size = (Get-Item $tempFile).Length
        $content = Get-Content $tempFile -Raw -Encoding UTF8
        if (REPLACE_INTEGRITY_EXPR) {
            Write-Log "Integrity check passed."
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
REPLACE_COMPANION_BLOCK
                Write-Log "Update successful! Restarting..."
                $dir = [System.IO.Path]::GetDirectoryName($currentFile)
                $rb = [System.IO.Path]::Combine($dir, "YT-DPI.bat")
                if (Test-Path -LiteralPath $rb) { Start-Process -FilePath $rb } else { Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$currentFile" }
            } else {
                Write-Log "CRITICAL: Could not overwrite file."
                $dir = [System.IO.Path]::GetDirectoryName($currentFile)
                $rb = [System.IO.Path]::Combine($dir, "YT-DPI.bat")
                if (Test-Path -LiteralPath $rb) { Start-Process -FilePath $rb } else { Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$currentFile" }
            }
        } else {
            Write-Log "Integrity FAIL."
            $dir = [System.IO.Path]::GetDirectoryName($currentFile)
            $rb = [System.IO.Path]::Combine($dir, "YT-DPI.bat")
            if (Test-Path -LiteralPath $rb) { Start-Process -FilePath $rb } else { Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$currentFile" }
        }
    }
} catch {
    Write-Log "GENERAL ERROR: $($_.Exception.Message)"
    Start-Sleep -Seconds 3
    if (Test-Path $currentFile) {
        $dir = [System.IO.Path]::GetDirectoryName($currentFile)
        $rb = [System.IO.Path]::Combine($dir, "YT-DPI.bat")
        if (Test-Path -LiteralPath $rb) { Start-Process -FilePath $rb } else { Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$currentFile" }
    }
}

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
Write-Log "--- UPDATER SESSION END ---"
'@

    # Подстановка значений с экранированием для одинарных кавычек
    $updaterContent = $updaterTemplate.
        Replace("REPLACE_PID", $parentPid).
        Replace("REPLACE_FILE", ($currentFile -replace "'", "''")).
        Replace("REPLACE_URL", ($downloadUrl -replace "'", "''")).
        Replace("REPLACE_TEMP", ($tempFile -replace "'", "''")).
        Replace("REPLACE_LOG", ($logFile -replace "'", "''")).
        Replace("REPLACE_INTEGRITY_EXPR", $integrityExpr).
        Replace("REPLACE_COMPANION_BLOCK", $companionBlock)

    # Сохраняем сам апдейтер-скрипт тоже с BOM
    $utf8WithBom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($updaterPath, $updaterContent, $utf8WithBom)

    # Запускаем апдейтер в скрытом окне
    $pInfo = New-Object System.Diagnostics.ProcessStartInfo
    $pInfo.FileName = "powershell.exe"
    $pInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$updaterPath`""
    $pInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    [System.Diagnostics.Process]::Start($pInfo) | Out-Null

    Start-Sleep -Milliseconds 500
    exit
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
        [Console]::CursorVisible = $false
        [Console]::SetCursorPosition($x, $y)
        [Console]::ForegroundColor = $color
        [Console]::BackgroundColor = $bg
        [Console]::Write($str)
        [Console]::BackgroundColor = "Black"
    } catch {}
}

function Clear-KeyBuffer {
    while ([Console]::KeyAvailable) {
        $null = [Console]::ReadKey($true)
    }
}

function Read-MenuKeyOrResize {
    while ($true) {
        [Console]::CursorVisible = $false
        if (Test-UiConsoleLayoutChanged) {
            return [PSCustomObject]@{ Resized = $true; Key = $null; KeyChar = [char]0 }
        }
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            return [PSCustomObject]@{ Resized = $false; Key = $k.Key; KeyChar = $k.KeyChar }
        }
        Start-Sleep -Milliseconds 50
    }
}

function Read-MenuLineOrResize {
    param([string]$Prompt = "")

    $value = ""
    [Console]::CursorVisible = $false
    while ($true) {
        if (Test-UiConsoleLayoutChanged) {
            return [PSCustomObject]@{ Resized = $true; Text = $value; Cancelled = $false }
        }
        if (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            continue
        }

        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "Enter") {
            return [PSCustomObject]@{ Resized = $false; Text = $value; Cancelled = $false }
        }
        elseif ($key.Key -eq "Escape") {
            return [PSCustomObject]@{ Resized = $false; Text = ""; Cancelled = $true }
        }
        elseif ($key.Key -eq "Backspace") {
            if ($value.Length -gt 0) {
                $value = $value.Substring(0, $value.Length - 1)
                [Console]::Write("`b `b")
            }
        }
        elseif (-not [char]::IsControl($key.KeyChar)) {
            $value += [string]$key.KeyChar
            [Console]::Write($key.KeyChar)
        }
    }
}

function Update-ConsoleSize {
    try {
        [Console]::CursorVisible = $false
        try { [Console]::CursorSize = 1 } catch { }
        [Console]::SetCursorPosition(0, 0)
        $linesNeeded = $script:Targets.Count + 20
        $maxHeight = [Console]::LargestWindowHeight
        if ($linesNeeded -gt $maxHeight) {
            Write-DebugLog "Предупреждение: требуется $linesNeeded строк, доступно только $maxHeight"
            $linesNeeded = $maxHeight
            $script:Truncated = $true
        } else {
            $script:Truncated = $false
        }
        $w = if ($script:DesiredConsoleWidth) { [int]$script:DesiredConsoleWidth } else { 135 }
        $h = $linesNeeded
        $maxWidth = [Console]::LargestWindowWidth
        if ($w -gt $maxWidth) { $w = $maxWidth }

        try {
            if ($script:CurrentWindowHeight -le 0 -or $script:CurrentWindowWidth -le 0) {
                [Console]::BufferWidth = $w
                [Console]::WindowWidth = $w
                [Console]::WindowHeight = $h
                [Console]::BufferWidth = $w
                [Console]::BufferHeight = $h
                $script:CurrentWindowWidth = $w
                $script:CurrentWindowHeight = $h
            }
            else {
                if ([Console]::BufferWidth -lt $w) { [Console]::BufferWidth = $w }
                if ([Console]::BufferHeight -lt $h) { [Console]::BufferHeight = $h }
                $script:CurrentWindowWidth = [Console]::WindowWidth
                $script:CurrentWindowHeight = [Console]::WindowHeight
            }
        } catch {
            Write-DebugLog "Не удалось изменить размер окна: $_"
        }
    } catch {}
}

function Sync-DynamicColPosFromLayout {
    $ipW = if ($script:IpColumnWidth) { $script:IpColumnWidth } else { 16 }
    $domStart = 6
    $ipStart = $domStart + 42 + 2
    $httpStart = $ipStart + $ipW + 2
    $t12Start = $httpStart + 6 + 2
    $t13Start = $t12Start + 8 + 2
    $latStart = $t13Start + 8 + 2
    $verStart = $latStart + 8 + 2
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
}

function Update-UiConsoleSnapshot {
    try {
        $script:UiLayoutWidth = [Console]::WindowWidth
        $script:UiLayoutHeight = [Console]::WindowHeight
    } catch {}
}

function Test-UiConsoleLayoutChanged {
    try {
        if ($null -eq $script:UiLayoutWidth) { return $false }
        return ([Console]::WindowWidth -ne $script:UiLayoutWidth -or
                [Console]::WindowHeight -ne $script:UiLayoutHeight)
    } catch { return $false }
}

# Во время скана сравниваем с локальным снимком и порогом >1 колонка/строка — иначе дребезг
# WindowWidth/Height даёт ложные «ресайзы» и полный Draw-UI на каждом тике статус-бара.
function Test-ScanPhaseConsoleLayoutChanged {
    try {
        if ($null -ne $script:ScanLayoutSnapW -and $null -ne $script:ScanLayoutSnapH) {
            $cw = [Console]::WindowWidth
            $ch = [Console]::WindowHeight
            $dw = [Math]::Abs($cw - $script:ScanLayoutSnapW)
            $dh = [Math]::Abs($ch - $script:ScanLayoutSnapH)
            return ($dw -gt 1 -or $dh -gt 1)
        }
        return (Test-UiConsoleLayoutChanged)
    } catch { return $false }
}

function Invoke-FullUiRedrawIfConsoleResized {
    if (-not (Test-UiConsoleLayoutChanged)) { return $false }
    Write-DebugLog "Изменён размер консоли — полная перерисовка UI" "INFO"
    Update-ConsoleSize
    $scanRows = $null
    if ($script:LastScanResults -and $script:Targets -and $script:LastScanResults.Count -eq $script:Targets.Count) {
        $scanRows = $script:LastScanResults
    }
    Draw-UI $script:NetInfo $script:Targets $scanRows $true
    Sync-DynamicColPosFromLayout
    Draw-StatusBar
    Update-UiConsoleSnapshot
    return $true
}

function Invoke-ScanRedrawIfConsoleResized {
    param(
        [object[]]$LiveResults,
        [array]$Targets,
        [string]$StatusBarMessage = $null,
        [double]$Progress = -1
    )
    $resized = Test-ScanPhaseConsoleLayoutChanged
    if ($resized) {
        Write-DebugLog "Ресайз во время скана — перерисовка (без Clear)" "INFO"
        Update-ConsoleSize
        Draw-UI $script:NetInfo $Targets $LiveResults $false
        Sync-DynamicColPosFromLayout
        try {
            $script:ScanLayoutSnapW = [Console]::WindowWidth
            $script:ScanLayoutSnapH = [Console]::WindowHeight
        } catch {}
        Update-UiConsoleSnapshot
    }
    if ($null -ne $Progress -and $Progress -ge 0) {
        $msg = if ($StatusBarMessage) { $StatusBarMessage } else { "[ SCAN ]" }
        Draw-StatusBar -Message $msg -Fg "Black" -Bg "Green" -Progress $Progress
        Update-UiConsoleSnapshot
    }
    elseif ($resized) {
        if ($StatusBarMessage) {
            Draw-StatusBar -Message $StatusBarMessage -Fg "Black" -Bg "Green"
        } else {
            Draw-StatusBar
        }
        Update-UiConsoleSnapshot
    }
}

function Read-MainLoopKey {
    $pollMs = 50
    while ($true) {
        [Console]::CursorVisible = $false
        try { [Console]::CursorSize = 1 } catch { }
        if (Test-UiConsoleLayoutChanged) {
            $null = Invoke-FullUiRedrawIfConsoleResized
        }
        if ([Console]::KeyAvailable) {
            return [Console]::ReadKey($true).Key
        }
        $nowNet = [Environment]::TickCount64
        if ($null -eq $script:_netInfoPollMs) { $script:_netInfoPollMs = $nowNet }
        if (($nowNet - $script:_netInfoPollMs) -ge 1000) {
            $script:_netInfoPollMs = $nowNet
            Update-NetInfoFromCompletedJob
        }
        Start-Sleep -Milliseconds $pollMs
    }
}

function Get-ControlsRow {
    param([int]$count)
    # 9 (начало таблицы) + 3 (заголовок и линия) + $count (строки результатов) + 2 (нижняя линия и отступ)
    return 9 + 3 + $count + 2
}

function Get-FeedbackRow {
    param([int]$count)
    return (Get-ControlsRow -count $count) + 1
}

function Get-NavRow {
    param([int]$count)
    return Get-ControlsRow -count $count
}

function Write-StatusLine {
    param(
        [int]$Row,
        [string]$Message,
        [string]$Fg = "White",
        [string]$Bg = "Black",
        [int]$X = 2
    )
    if ($Row -lt 0 -or $Row -ge [Console]::BufferHeight) { return }

    $width = [Console]::WindowWidth
    $text = [string]$Message

    if ($script:Targets) {
        $controlsText = ([string]$CONST.NavStr) -replace '^\[READY\]\s*', ''
        $navLine = " $controlsText "
        if ($navLine.Length -gt $width) { $navLine = $navLine.Substring(0, [Math]::Max(0, $width - 3)) + "..." }
        $barX = [Math]::Max(0, [Math]::Floor(($width - $navLine.Length) / 2))
        $barWidth = $navLine.Length

        if ([string]::IsNullOrWhiteSpace($text)) {
            Out-Str $barX $Row (" " * $barWidth) "Black" "Black"
            Reset-StatusBarCache
            return
        }

        if ($text.Length -gt ($barWidth - 2)) {
            $text = $text.Substring(0, [Math]::Max(0, $barWidth - 5)) + "..."
        }
        $line = Format-CellCenter $text $barWidth
        $statusKey = "manual|$Row|$barX|Black|Green|$line"
        if ($script:StatusFeedbackCacheKey -ne $statusKey) {
            Out-Str $barX $Row $line "Black" "Green"
            $script:StatusFeedbackCacheKey = $statusKey
        }
        return
    }

    Out-Str 0 $Row (" " * $width) "Black" "Black"
    $maxTextWidth = [Math]::Max(0, $width - $X)
    if ($maxTextWidth -le 0) { return }
    if ($text.Length -gt $maxTextWidth) { $text = $text.Substring(0, [Math]::Max(0, $maxTextWidth - 3)) + "..." }
    Out-Str $X $Row ($text.PadRight($maxTextWidth)) "Black" "Green"
    Reset-StatusBarCache
}

function Read-StatusBarNumberInput {
    param(
        [int]$Row,
        [string]$Prompt
    )

    $inputText = ""
    $currentRow = $Row
    while ($true) {
        if (Test-UiConsoleLayoutChanged) {
            $null = Invoke-FullUiRedrawIfConsoleResized
            $currentRow = Get-FeedbackRow -count $script:Targets.Count
        }

        Write-StatusLine -Row $currentRow -Message ($Prompt + $inputText) -Fg "Black" -Bg "Green"
        [Console]::CursorVisible = $false

        if (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            continue
        }

        $key = [Console]::ReadKey($true)
        if ($key.Key -in @("Enter", "Escape")) {
            if ($key.Key -eq "Escape") { return "" }
            return $inputText
        }
        elseif ($key.Key -eq "Backspace") {
            if ($inputText.Length -gt 0) {
                $inputText = $inputText.Substring(0, $inputText.Length - 1)
            }
        }
        elseif ($key.KeyChar -ge '0' -and $key.KeyChar -le '9') {
            $inputText += [string]$key.KeyChar
        }
    }
}

function Reset-StatusBarCache {
    $script:StatusFeedbackCacheKey = $null
    $script:StatusControlsCacheKey = $null
}

function Clear-StatusBlock {
    if (-not $script:Targets) { return }
    $width = [Console]::WindowWidth
    $feedbackRow = Get-FeedbackRow -count $script:Targets.Count
    $controlsRow = Get-ControlsRow -count $script:Targets.Count
    Out-Str 0 $feedbackRow (" " * $width) "Black" "Black"
    Out-Str 0 $controlsRow (" " * $width) "Black" "Black"
    Reset-StatusBarCache
}

function Get-IdleStatusMessage {
    if (-not $script:HasCompletedScan -or -not $script:LastScanResults -or $script:LastScanResults.Count -lt 1) {
        return [PSCustomObject]@{ Text = "STATUS: ГОТОВ"; Fg = "Black"; Bg = "Green" }
    }

    $rows = @($script:LastScanResults | Where-Object { $_ })
    if ($rows.Count -lt 1) {
        return [PSCustomObject]@{ Text = "STATUS: ГОТОВ"; Fg = "Black"; Bg = "Green" }
    }

    $available = @($rows | Where-Object { $_.Verdict -eq "AVAILABLE" }).Count
    $throttled = @($rows | Where-Object { $_.Verdict -eq "THROTTLED" }).Count
    $dpi = @($rows | Where-Object { $_.Verdict -in @("DPI RESET", "DPI BLOCK") }).Count
    $ipBlock = @($rows | Where-Object { $_.Verdict -eq "IP BLOCK" }).Count
    $timeout = @($rows | Where-Object { $_.Verdict -eq "TIMEOUT" }).Count
    $unknown = @($rows | Where-Object { $_.Verdict -eq "UNKNOWN" }).Count

    if ($available -eq $rows.Count) {
        return [PSCustomObject]@{ Text = "SCAN RESULT: OK | $available HOSTS AVAILABLE"; Fg = "Black"; Bg = "Green" }
    }

    $parts = @()
   # if ($available -gt 0) { $parts += "$available AVAILABLE" } # пока пишем только заблоченные
    if ($throttled -gt 0) { $parts += "$throttled THROTTLED" }
    if ($dpi -gt 0) { $parts += "$dpi DPI BLOCK/RESET" }
    if ($ipBlock -gt 0) { $parts += "$ipBlock IP BLOCK" }
    if ($timeout -gt 0) { $parts += "$timeout TIMEOUT" }
    if ($unknown -gt 0) { $parts += "$unknown UNKNOWN" }

    return [PSCustomObject]@{
        Text = "SCAN RESULT: DPI DETECTED | " + ($parts -join " | ")
        Fg = "Black"
        Bg = "Yellow"
    }
}

function Draw-StatusBar {
    param(
        [string]$Message = $null,
        [string]$Fg = "Black",
        [string]$Bg = "Green",
        [double]$Progress = -1
    )
    if (-not $script:Targets) { return }
    [Console]::CursorVisible = $false
    $feedbackRow = Get-FeedbackRow -count $script:Targets.Count
    $controlsRow = Get-ControlsRow -count $script:Targets.Count
    $width = [Console]::WindowWidth

    $controlsText = ([string]$CONST.NavStr) -replace '^\[READY\]\s*', ''
    $navLine = " $controlsText "
    if ($navLine.Length -gt $width) { $navLine = $navLine.Substring(0, [Math]::Max(0, $width - 3)) + "..." }
    $navX = [Math]::Max(0, [Math]::Floor(($width - $navLine.Length) / 2))
    $statusWidth = $navLine.Length

    $idleStatus = $null
    if ($Message) {
        $text = $Message
        $Fg = "Black"
        $Bg = "Green"
    } else {
        $idleStatus = Get-IdleStatusMessage
        $text = $idleStatus.Text
        $Fg = $idleStatus.Fg
        $Bg = $idleStatus.Bg
    }

    # Полоска прогресса 0..1 в правой части строки (во время скана)
    $tail = ""
    if ($null -ne $Progress -and $Progress -ge 0) {
        $p = [double]$Progress
        if ($p -gt 1) { $p = 1 }
        if ($p -lt 0) { $p = 0 }
        $barW = [Math]::Min(18, [Math]::Max(8, $width / 8))
        $filled = [int][Math]::Floor($p * $barW + 0.001)
        if ($filled -gt $barW) { $filled = $barW }
        $tail = " [" + ("=" * $filled) + ("-" * ($barW - $filled)) + "] " + ([int]($p * 100)).ToString() + "%"
        $reserve = $tail.Length + 2
        $maxMsg = [Math]::Max(12, $statusWidth - 2 - $reserve)
        if ($text.Length -gt $maxMsg) { $text = $text.Substring(0, $maxMsg - 3) + "..." }
    }
    else {
        if ($text.Length -gt ($statusWidth - 2)) { $text = $text.Substring(0, [Math]::Max(0, $statusWidth - 5)) + "..." }
    }

    if ($text -or $tail) {
        $line = " $text$tail "
        if ($line.Length -gt $statusWidth) { $line = $line.Substring(0, $statusWidth) }
        $line = Format-CellCenter $line.Trim() $statusWidth
        $feedbackKey = "$feedbackRow|$navX|$Fg|$Bg|$line"
        if ($script:StatusFeedbackCacheKey -ne $feedbackKey) {
            Out-Str $navX $feedbackRow $line $Fg $Bg
            $script:StatusFeedbackCacheKey = $feedbackKey
        }
    }

    $controlsKey = "$controlsRow|$navX|Black|Green|$navLine"
    if ($script:StatusControlsCacheKey -ne $controlsKey) {
        Out-Str $navX $controlsRow $navLine "Black" "Green"
        $script:StatusControlsCacheKey = $controlsKey
    }
}

function Update-NetInfoPanel {
    param($NetInfo)
    if ($null -eq $NetInfo) { return }

    $rightW = [Math]::Max(20, [Console]::WindowWidth - 66)
    Out-Str 65 3 (Format-CellLeft ("> LOCAL DNS: " + $NetInfo.DNS) $rightW) "Cyan"
    Out-Str 65 4 (Format-CellLeft ("> CDN NODE: " + $NetInfo.CDN) $rightW) "Yellow"

    $dispIsp = [string]$NetInfo.ISP
    if ($dispIsp.Length -gt 35) { $dispIsp = $dispIsp.Substring(0, 32) + "..." }
    $dispLoc = [string]$NetInfo.LOC
    if ($dispLoc.Length -gt 30) { $dispLoc = $dispLoc.Substring(0, 27) + "..." }
    Out-Str 65 6 (Format-CellLeft ("> ISP / LOC: $dispIsp ($dispLoc)") $rightW) "Magenta"
}

function Initialize-ScannerEngines {
    $needTls = (-not (Test-TlsScannerReady)) -and (-not $script:TlsScannerLoadFailed)
    $needTrace = (-not (Test-TracerouteReady)) -and (-not $script:TracerouteLoadFailed)
    if (-not $needTls -and -not $needTrace) { return }

    Draw-StatusBar -Message "[ ENGINE ] Loading scan engines..." -Fg "Black" -Bg "Yellow"
    $null = Ensure-TlsScannerLoaded
    $null = Ensure-TracerouteLoaded
    Draw-StatusBar
}

function Draw-UI ($NetInfo, $Targets, $Results, $ClearScreen = $true) {
    # $Results - массив объектов с результатами сканирования (свойство .IP)
    # ClearScreen=$false: без [Console]::Clear — перерисовка поверх старых ячеек (меньше мигания).
    # Выборочная перерисовка (только одна строка/колонка) пока не вынесена в отдельные API — при изменении
    # данных таблицы без смены числа строк обычно достаточно Draw-UI ... $false.
    Write-DebugLog "Draw-UI: Targets count=$($Targets.Count), ClearScreen=$ClearScreen"

    [Console]::CursorVisible = $false

    # Исторически в третий параметр ошибочно передавали $true/$NeedClear (bool); у скаляра .Count=1 → ломалась только первая строка таблицы
    if ($null -ne $Results -and $Results -is [bool]) { $Results = $null }

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
    $latWidth  = 8
    $verStart  = $latStart + $latWidth + 2
    $verWidth  = 18
    $script:DesiredConsoleWidth = [Math]::Max(118, $verStart + $verWidth + 1)

    Update-ConsoleSize
    if ($ClearScreen) {
        [Console]::Clear()
        Reset-StatusBarCache
    }

    # YT-DPI-LOGO-BEGIN (между BEGIN/END — только вызовы Out-Str; tools/logo.ps1 и tools/logo.bat подхватывают этот блок)
    Out-Str 1 1 ' ██╗   ██╗████████╗    ██████╗ ██████╗ ██╗' 'Green'
    Out-Str 1 2 ' ╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║' 'Green'
    Out-Str 1 3 '  ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║' 'Green'
    Out-Str 1 4 '   ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║' 'Green'
    Out-Str 1 5 '    ██║      ██║       ██████║ ██║     ██║' 'Green'
    Out-Str 1 6 '    ╚═╝      ╚═╝       ╚═════╝ ╚═╝     ╚═╝' 'Green'

    Out-Str 45 1 '██████╗    ██████╗ ' 'Gray'
    Out-Str 45 2 '╚════██╗   ╚════██╗' 'Gray'
    Out-Str 45 3 ' █████╔╝    █████╔╝' 'Gray'
    Out-Str 45 4 '██╔═══╝     ╚═══██╗' 'Gray'
    Out-Str 45 5 '███████╗██╗██████╔╝' 'Gray'
    Out-Str 45 6 '╚══════╝╚═╝╚═════╝' 'Gray'
    # YT-DPI-LOGO-END
    
    $rightW = [Math]::Max(20, [Console]::WindowWidth - 66)
    $statusY = 1
    $statusX0 = 65
    if (Test-DebugLogEnabled) {
        $px = $statusX0
        $rem = $rightW
        $prefix = "> SYS STATUS: "
        $badge = "[ DEBUG ]"
        if ($rem -gt 0) {
            $pl = [Math]::Min($rem, $prefix.Length)
            $prefPart = if ($pl -eq $prefix.Length) { $prefix } else { $prefix.Substring(0, $pl) }
            Out-Str $px $statusY (Format-CellLeft $prefPart $pl) "Green" "Black"
            $px += $pl
            $rem -= $pl
        }
        if ($rem -gt 0) {
            $bl = [Math]::Min($rem, $badge.Length)
            $badgePart = if ($bl -eq $badge.Length) { $badge } else { $badge.Substring(0, $bl) }
            Out-Str $px $statusY $badgePart "White" "Red"
            $px += $bl
            $rem -= $bl
        }
        if ($rem -gt 0) {
            $tail = Get-DebugHudTail -maxLen $rem
            Out-Str $px $statusY (Format-CellLeft $tail $rem) "Green" "Black"
        }
    } else {
        Out-Str $statusX0 $statusY (Format-CellLeft "> SYS STATUS: [ ONLINE ]" $rightW) "Green"
    }
    Out-Str 65 2 (Format-CellLeft "> ENGINE: Barebuh Pro v2.3.4" $rightW) "Red"
    Out-Str 65 3 (Format-CellLeft ("> LOCAL DNS: " + $NetInfo.DNS) $rightW) "Cyan"
    Out-Str 65 4 (Format-CellLeft ("> CDN NODE: " + $NetInfo.CDN) $rightW) "Yellow"
    Out-Str 65 5 (Format-CellLeft "> AUTHOR: github.com/Shiperoid" $rightW) "Green"

    $dispIsp = $NetInfo.ISP
    if ($dispIsp.Length -gt 35) { $dispIsp = $dispIsp.Substring(0, 32) + "..." }
    $dispLoc = $NetInfo.LOC
    if ($dispLoc.Length -gt 30) { $dispLoc = $dispLoc.Substring(0, 27) + "..." }
    $ispStr = "> ISP / LOC: $dispIsp ($dispLoc)"
    Out-Str 65 6 (Format-CellLeft $ispStr $rightW) "Magenta"

    $proxyStatus = if ($global:ProxyConfig.Enabled) { "> PROXY: $($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port) Connected" } else { "> PROXY: [ OFF ]" }
    Out-Str 65 7 (Format-CellLeft $proxyStatus $rightW) "DarkYellow"
    Out-Str 65 8 (Format-CellLeft "> TG: t.me/YT_DPI | VERSION: $scriptVersion" $rightW) "Green"

    # --- Таблица ---
    $y = 9
    $width = [Console]::WindowWidth

    # Верхняя граница таблицы
    Out-Str 0 $y ("=" * $width) "DarkCyan"

    # Заголовки
    Out-Str 1 ($y+1) (Format-CellCenter "#" 4) "White"
    Out-Str $domStart ($y+1) "TARGET DOMAIN" "White"
    Out-Str $ipStart ($y+1) "IP ADDRESS" "White"
    Out-Str $httpStart ($y+1) (Format-CellCenter "HTTP" $httpWidth) "White"
    Out-Str $t12Start ($y+1) (Format-CellCenter "TLS 1.2" $t12Width) "White"
    Out-Str $t13Start ($y+1) (Format-CellCenter "TLS 1.3" $t13Width) "White"
    Out-Str $latStart ($y+1) (Format-CellCenter "LAT (ms)" $latWidth) "White"
    Out-Str $verStart ($y+1) (Format-CellCenter "RESULT" $verWidth) "White"

    Out-Str 0 ($y+2) ("=" * $width) "DarkCyan"


    # Разделитель под заголовками
    Out-Str 0 ($y+2) ("=" * $width) "DarkCyan"

    # Строки результатов
    for($i=0; $i -lt $Targets.Count; $i++) {
        $currentRow = $y + 3 + $i
        $num = $i + 1
        $numStr = Format-CellCenter $num.ToString() 4

        Out-Str 1 $currentRow $numStr "Cyan"
        Out-Str $domStart $currentRow ($Targets[$i].PadRight($domWidth).Substring(0, $domWidth)) "Gray"

        $res = $null
        if ($Results -and $i -lt $Results.Count) { $res = $Results[$i] }
        if ($null -eq $res) { $res = New-PlaceholderResultRow -Number $num -Target $Targets[$i] }
        if ($null -ne $res) {
            $ipStr = if ($res.IP) { [string]$res.IP } else { "---" }
            if ($ipStr.Length -gt $ipWidth) { $ipStr = $ipStr.Substring(0, $ipWidth - 2) + ".." }
            Out-Str $ipStart $currentRow $ipStr.PadRight($ipWidth).Substring(0, $ipWidth) "DarkGray"

            $htStr = if ($res.HTTP) { [string]$res.HTTP } else { "---" }
            $hCol = if($htStr -eq "OK") {"Green"} elseif($htStr -eq "---") {"DarkGray"} else {"Red"}
            Out-Str $httpStart $currentRow (Format-CellCenter $htStr $httpWidth) $hCol

            $t12Str = if ($res.T12) { [string]$res.T12 } else { "---" }
            $t12Col = if($t12Str -eq "OK") {"Green"} elseif($t12Str -eq "N/A" -or $t12Str -eq "---") {"DarkGray"} else {"Red"}
            Out-Str $t12Start $currentRow (Format-CellCenter $t12Str $t12Width) $t12Col

            $t13Str = if ($res.T13) { [string]$res.T13 } else { "---" }
            $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A" -or $t13Str -eq "---") {"DarkGray"} else {"Red"}
            Out-Str $t13Start $currentRow (Format-CellCenter $t13Str $t13Width) $t13Col

            $latStr = if ($res.Lat) { [string]$res.Lat } else { "---" }
            $latCol = if($latStr -eq "---") {"DarkGray"} else {"Cyan"}
            Out-Str $latStart $currentRow (Format-CellCenter $latStr $latWidth) $latCol

            $verStr = if ($res.Verdict) { [string]$res.Verdict } else { "UNKNOWN" }
            Out-Str $verStart $currentRow (Format-CellCenter $verStr $verWidth) $res.Color
        }
    }

    Out-Str 0 ($y + 3 + $Targets.Count) ("=" * $width) "DarkCyan"
    [Console]::CursorVisible = $false
    Sync-DynamicColPosFromLayout
    Update-UiConsoleSnapshot
}


function Get-ScanAnim($f, $row) {
    $frames = "[=   ]", "[ =  ]", "[  = ]", "[   =]", "[  = ]", "[ =  ]"
    return $frames[($f + $row) % $frames.Length]
}

function Write-ResultLine {
    param(
        [int]$row,
        $result,
        [switch]$IncludeStaticCells
    )
    if ($row -lt 0 -or $row -ge [Console]::BufferHeight) { return }

    [Console]::CursorVisible = $false
    $pos = if ($script:DynamicColPos) { $script:DynamicColPos } else { $CONST.UI }
    $ipWidth = if ($script:IpColumnWidth) { $script:IpColumnWidth } else { 16 }

    if ($IncludeStaticCells) {
        # Номер и домен стабильны между сканами; обновляем их только при явной полной строке.
        $numStr = if ($result.Number) { $result.Number.ToString() } else { "" }
        Out-Str $pos.Num $row (Format-CellCenter $numStr 4) "Cyan"

        Out-Str $pos.Dom $row $result.Target.PadRight(42).Substring(0, 42) "Gray"
    }

    # IP
    $ipStr = if ($result.IP) { [string]$result.IP } else { "---" }
    if ($ipStr.Length -gt $ipWidth) { $ipStr = $ipStr.Substring(0, $ipWidth - 2) + ".." }
    $ipPadded = $ipStr.PadRight($ipWidth)
    Out-Str $pos.IP $row $ipPadded.Substring(0, $ipWidth) "DarkGray"

    # HTTP
    $htStr = if ($result.HTTP) { [string]$result.HTTP } else { "---" }
    $hCol = if($htStr -eq "OK") {"Green"} elseif($htStr -eq "---") {"DarkGray"} else {"Red"}
    Out-Str $pos.HTTP $row (Format-CellCenter $htStr 6) $hCol

    # TLS 1.2
    $t12Str = if ($result.T12) { [string]$result.T12 } else { "---" }
    $t12Col = if($t12Str -eq "OK") {"Green"} elseif($t12Str -eq "N/A" -or $t12Str -eq "---") {"DarkGray"} else {"Red"}
    Out-Str $pos.T12 $row (Format-CellCenter $t12Str 8) $t12Col

    # TLS 1.3
    $t13Str = if ($result.T13) { [string]$result.T13 } else { "---" }
    $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A" -or $t13Str -eq "---") {"DarkGray"} else {"Red"}
    Out-Str $pos.T13 $row (Format-CellCenter $t13Str 8) $t13Col

    # LAT
    $latStr = if ($result.Lat) { [string]$result.Lat } else { "---" }
    $latCol = if($latStr -eq "---") {"DarkGray"} else {"Cyan"}
    Out-Str $pos.Lat $row (Format-CellCenter $latStr 8) $latCol

    # VERDICT
    $verStr = if ($result.Verdict) { [string]$result.Verdict } else { "UNKNOWN" }
    Out-Str $pos.Ver $row (Format-CellCenter $verStr 18) $result.Color
}

function Write-ResultLatency($row, $result) {
    if ($row -lt 0 -or $row -ge [Console]::BufferHeight) { return }

    [Console]::CursorVisible = $false
    $pos = if ($script:DynamicColPos) { $script:DynamicColPos } else { $CONST.UI }
    $latStr = if ($result.Lat) { [string]$result.Lat } else { "---" }
    $latCol = if($latStr -eq "---") {"DarkGray"} else {"Cyan"}
    Out-Str $pos.Lat $row (Format-CellCenter $latStr 8) $latCol
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

    Write-DebugLog "Trace-TcpRoute (C#): $Target, MaxHops=$MaxHops"

    if ($onProgress -and -not (Test-TracerouteReady) -and -not $script:TracerouteLoadFailed) {
        & $onProgress "[ TRACE ] Loading traceroute engine..."
    }
    if (-not (Ensure-TracerouteLoaded)) {
        Write-DebugLog "Traceroute C# недоступен, используем fallback метод" "WARN"
        try {
            return Invoke-TcpTracerouteCombined -Target $Target -Port $Port -MaxHops $MaxHops -TimeoutSec $TimeoutSec -onProgress $onProgress
        } catch {
            Write-DebugLog "Fallback traceroute: $_" "ERROR"
            return @()
        }
    }

    # Прогресс только синхронно (тот же поток, что и Trace) — см. SynchronousProgress в C#.
    $progressLogger = $null
    if ($onProgress) {
        try {
            $del = { param([string]$msg) if ($onProgress) { & $onProgress $msg } }
            $progressLogger = [SynchronousProgress]::new([Action[string]]$del)
        } catch {
            Write-DebugLog "SynchronousProgress: не удалось создать ($_) — трассировка без строк прогресса" "WARN"
        }
    }

    try {
        # Auto: ICMP → raw TCP (только с админом) → UDP. Принудительный TcpSyn без прав даёт «доступ к сокету запрещён».
        $method = [TraceMethod]::Auto

        # Выполняем трассировку
        $hops = [AdvancedTraceroute]::Trace($Target, $MaxHops, $TimeoutSec * 1000, $method, $progressLogger)

        # Конвертируем в формат, понятный старому коду
        $result = @()
        foreach ($hop in $hops) {
            $result += [PSCustomObject]@{
                Hop          = $hop.HopNumber
                IP           = $hop.IP
                TcpStatus    = if ($hop.TcpStatus) { $hop.TcpStatus } else { $hop.Status }
                TlsStatus    = "N/A"
                RttMs        = if ($hop.RttMs -gt 0) { $hop.RttMs } else { $null }
                IsBlocking   = $hop.IsBlocking
            }
        }

        Write-DebugLog "Трассировка завершена, получено $($result.Count) хопов"
        return $result

    } catch {
        Write-DebugLog "Ошибка C# traceroute: $_" "ERROR"

        # Fallback на старый метод
        Write-DebugLog "Используем fallback метод (ICMP + TCP)" "WARN"
        try {
            return Invoke-TcpTracerouteCombined -Target $Target -Port $Port -MaxHops $MaxHops -TimeoutSec $TimeoutSec -onProgress $onProgress
        } catch {
            Write-DebugLog "Fallback traceroute: $_" "ERROR"
            return @()
        }
    }
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
            $pinfo.Arguments = "-d -h $MaxHops -w 350 -4 $Target"
            $pinfo.UseShellExecute = $false
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.CreateNoWindow = $true

            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null

            # Реальный лимит времени для tracert: 3 пробы на хоп + запас.
            $traceTimeoutMs = [Math]::Max(12000, $MaxHops * 1400)
            $completed = $p.WaitForExit($traceTimeoutMs)

            if (-not $completed) {
                Write-DebugLog "tracert превысил лимит (${traceTimeoutMs}ms), убиваем процесс"
                try { $p.Kill() } catch { }
                try { $p.WaitForExit(1000) | Out-Null } catch {}
            }

            $output = ""
            try { $output = $p.StandardOutput.ReadToEnd() } catch {}

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

        if ($script:AllowInsecureTls) {
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $true, { $true })
        } else {
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $true)
        }

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
    Draw-StatusBar -Message "[ UPDATE ] Проверка обновлений на GitHub..." -Fg "Black" -Bg "Cyan"

    $res = Check-UpdateVersion -ManualMode -IgnoreLastChecked

    if ($res -eq "LATEST") {
        Draw-StatusBar -Message "[ UPDATE ] Вы уже используете последнюю версию ($scriptVersion)" -Fg "Black" -Bg "DarkGreen"
        # Обновляем LastCheckedVersion
        $Config.LastCheckedVersion = $scriptVersion
        Save-Config $Config
        Start-Sleep -Seconds 2
    }
    elseif ($res -eq "DEV_VERSION") {
        Draw-StatusBar -Message "[ UPDATE ] Ваша верися ($scriptVersion) новее, чем GitHub релиз ($res)." -Fg "Black" -Bg "Magenta"
        # Обновляем LastCheckedVersion, чтобы не показывать снова
        $Config.LastCheckedVersion = $scriptVersion
        Save-Config $Config
        Start-Sleep -Seconds 3
    }
    elseif ($null -ne $res) {
        Draw-StatusBar -Message "[ UPDATE ] Новая версия $res доступна! Установить сейчас? (Y/N)" -Fg "Black" -Bg "Yellow"
        $menuKey = Read-MenuKeyOrResize
        if ($menuKey.Resized) { continue }
        $key = $menuKey.KeyChar
        if ($key -eq 'y' -or $key -eq 'Y' -or $key -eq 'н' -or $key -eq 'Н') { #Добавил обработку кириллицы
            $currentFile = $script:OriginalFilePath
            $downloadUrl = if ($currentFile -match '\.(?i)bat$') {
                "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.bat"
            } else {
                "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.ps1"
            }
            Start-Updater $currentFile $downloadUrl
            exit
        } else {
            # Если отказались, запоминаем, что предложили эту версию
            $Config.LastCheckedVersion = $res
            Save-Config $Config
        }
    } else {
        Draw-StatusBar -Message "[ UPDATE ] Сервер обновлений недоступен или достигнул лимит API." -Fg "Black" -Bg "Red"
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
                elseif ($ProxyConfig.Type -eq "HTTP") {
                    $hdr = "CONNECT ${TargetHost}:$TargetPort HTTP/1.1`r`nHost: ${TargetHost}:$TargetPort`r`n"
                    if ($ProxyConfig.User -and $ProxyConfig.Pass) {
                        $authBytes = [Text.Encoding]::ASCII.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)")
                        $hdr += "Proxy-Authorization: Basic $([Convert]::ToBase64String($authBytes))`r`n"
                    }
                    $hdr += "`r`n"
                    $reqBytes = [Text.Encoding]::ASCII.GetBytes($hdr)
                    $stream.Write($reqBytes, 0, $reqBytes.Length)
                    $swRead = [System.Diagnostics.Stopwatch]::StartNew()
                    $response = ""
                    $buf = New-Object byte[] 1024
                    while ($swRead.ElapsedMilliseconds -lt $Timeout) {
                        if ($stream.DataAvailable) {
                            $r = $stream.Read($buf, 0, 1024)
                            if ($r -le 0) { break }
                            $response += [Text.Encoding]::ASCII.GetString($buf, 0, $r)
                            if ($response -match "`r`n`r`n") { break }
                        } else { Start-Sleep -Milliseconds 20 }
                    }
                    if ($response -match '(?m)HTTP/1\.\d\s+200') {
                        Write-DebugLog "HTTP CONNECT tunnel OK -> ${TargetHost}:$TargetPort"
                        return @{ Tcp = $tcp; Stream = $stream }
                    }
                    $snip = if ($response.Length -gt 160) { $response.Substring(0, 160) + "..." } else { $response }
                    throw "HTTP CONNECT не 200: $snip"
                }
                else {
                    throw "Неподдерживаемый тип прокси для туннеля: $($ProxyConfig.Type)"
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
                if ($script:AllowInsecureTls) {
                    $sslStream = New-Object System.Net.Security.SslStream($stream, $false, { $true })
                } else {
                    $sslStream = New-Object System.Net.Security.SslStream($stream, $false)
                }
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

# ===== ГЕО-КЭШ С ПРОДЛЕННЫМ TTL =====
$script:GeoCacheFile = Join-Path $script:ConfigDir "geo_cache.json"
$script:LastGeoUpdate = $null

function Get-GeoProxyKey {
    if (-not $global:ProxyConfig.Enabled) { return "direct" }
    $t = $global:ProxyConfig.Type
    $h = $global:ProxyConfig.Host
    $p = $global:ProxyConfig.Port
    return "${t}|${h}:${p}"
}

function Get-CachedGeoInfo {
    param([int]$MaxAgeHours = 24)

    $wantProxyKey = Get-GeoProxyKey
    if (Test-Path $script:GeoCacheFile) {
        try {
            $cached = Get-Content $script:GeoCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $cacheAge = (Get-Date).Ticks - $cached.TimestampTicks
            $ageHours = [TimeSpan]::FromTicks($cacheAge).TotalHours
            $cachedKey = if ($cached.ProxyKey) { [string]$cached.ProxyKey } else { "" }
            if ($cachedKey -ne $wantProxyKey) {
                Write-DebugLog "GEO кэш отброшен: другой прокси/VPN контекст (кэш='$cachedKey', сейчас='$wantProxyKey')" "INFO"
                return $null
            }

            if ($ageHours -lt $MaxAgeHours) {
                Write-DebugLog "Используем GEO кэш (возраст: $([math]::Round($ageHours,1)) часов)" "INFO"
                return @{
                    ISP = $cached.ISP
                    LOC = $cached.LOC
                    IsCached = $true
                    AgeHours = $ageHours
                }
            } else {
                Write-DebugLog "GEO кэш устарел (возраст: $([math]::Round($ageHours,1)) часов)" "INFO"
            }
        } catch {
            Write-DebugLog "Ошибка чтения GEO кэша: $_" "WARN"
        }
    }
    return $null
}

function Save-GeoCache {
    param($isp, $loc)

    $cacheData = @{
        ISP = $isp
        LOC = $loc
        ProxyKey = (Get-GeoProxyKey)
        TimestampTicks = (Get-Date).Ticks
        ScriptVersion = $scriptVersion
    }

    try {
        $cacheData | ConvertTo-Json | Set-Content $script:GeoCacheFile -Encoding UTF8 -Force
        Write-DebugLog "GEO кэш сохранен: $isp / $loc" "INFO"
    } catch {
        Write-DebugLog "Ошибка сохранения GEO кэша: $_" "WARN"
    }
}

function Get-NetworkInfo {
    Write-DebugLog "Get-NetworkInfo: начало"

    # 1. БЫСТРЫЙ DNS
    $dns = "UNKNOWN"
    try {
        $wmi = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" |
               Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
        if ($wmi -and $wmi.DNSServerSearchOrder) {
            $dns = $wmi.DNSServerSearchOrder[0]
        }
    } catch { }

    # 2. CDN через redirector (через тот же путь, что и остальной HTTP: $global:ProxyConfig)
    $cdn = "manifest.googlevideo.com"
    try {
        $rnd = [guid]::NewGuid().ToString().Substring(0, 8)
        $redirectorUrl = "http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd"
        $rawCdn = Invoke-WebRequestViaProxy $redirectorUrl "GET" 3000
        if ($rawCdn) {
            $cdnShort = $null
            if ($rawCdn -match '=>\s+([\w-]+)') { $cdnShort = $matches[1] }
            if ($cdnShort -and $cdnShort -ne 'r1') {
                $cdn = "r1.$cdnShort.googlevideo.com"
            }
            elseif ($rawCdn -match '=>\s*([a-zA-Z0-9.\-]+\.googlevideo\.com)') {
                $cdn = $matches[1]
            }
        }
    } catch { Write-DebugLog "CDN redirector: $_" "WARN" }

    # 3. ГЕО-ИНФОРМАЦИЯ (синхронно; запросы идут через Invoke-WebRequestViaProxy = учёт HTTP/SOCKS5 прокси)
    $isp = "Detecting..."
    $loc = "Please wait"

    $cachedGeo = Get-CachedGeoInfo -MaxAgeHours 24
    if ($cachedGeo) {
        $isp = $cachedGeo.ISP
        $loc = $cachedGeo.LOC
        Write-DebugLog "GEO из кэша: $isp / $loc"
    }
    else {
        # Список провайдеров (URL, проверка, извлечение ISP / LOC)
        $providers = @(
            [PSCustomObject]@{
                Name   = "ip-api.com"
                Url    = "https://ip-api.com/json/?fields=status,countryCode,city,isp"
                Check  = { param($j) $j.status -eq "success" }
                GetISP = { param($j) $j.isp }
                GetLOC = { param($j) "$($j.city), $($j.countryCode)" }
            }
            [PSCustomObject]@{
                Name   = "ifconfig.co"
                Url    = "https://ifconfig.co/json"
                Check  = { param($j) $j.org -and $j.country }
                GetISP = { param($j) $j.org }
                GetLOC = { param($j) "$($j.city), $($j.country)" }
            }
            [PSCustomObject]@{
                Name   = "ipapi.co"
                Url    = "https://ipapi.co/json/"
                Check  = { param($j) -not $j.error -and $j.org -and $j.country_code }
                GetISP = { param($j) $j.org }
                GetLOC = { param($j) "$($j.city), $($j.country_code)" }
            }
            [PSCustomObject]@{
                Name   = "ipwhois.io"
                Url    = "https://ipwhois.app/json/"
                Check  = { param($j) $j.success -eq $true -and $j.isp }
                GetISP = { param($j) $j.isp }
                GetLOC = { param($j) "$($j.city), $($j.country_code)" }
            }
            [PSCustomObject]@{
                Name   = "ipinfo.io"
                Url    = "https://ipinfo.io/json"
                Check  = { param($j) -not $j.error -and $j.org -and $j.country }
                GetISP = { param($j) ($j.org -split '\s+')[0..1] -join ' ' }
                GetLOC = { param($j) "$($j.city), $($j.country)" }
            }
        )

        $geoResult = $null
        foreach ($provider in $providers) {
            try {
                Write-DebugLog "GEO: пробуем $($provider.Name)"
                $raw = Invoke-WebRequestViaProxy $provider.Url "GET" 1500
                if ($raw -match '\{.*\}') {
                    $json = $raw | ConvertFrom-Json
                    if (& $provider.Check $json) {
                        $ispRaw = & $provider.GetISP $json
                        $locRaw = & $provider.GetLOC $json
                        if ($ispRaw -and $locRaw) {
                            $geoResult = [PSCustomObject]@{
                                ISP = $ispRaw -replace '(?i)\s*(LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC|Private Enterprise|Group|Corporation|Ltd|Limited)', ''
                                LOC = $locRaw
                            }
                            Write-DebugLog "GEO успех ($($provider.Name)): $($geoResult.ISP) / $($geoResult.LOC)"
                            break
                        }
                    }
                }
            }
            catch {
                Write-DebugLog "GEO $($provider.Name) ошибка: $_"
            }
        }

        if ($geoResult) {
            $isp = $geoResult.ISP
            $loc = $geoResult.LOC
            Save-GeoCache -isp $isp -loc $loc
        }
        else {
            Write-DebugLog "Все GEO-провайдеры недоступны"
            $isp = "Geo unavailable"
            $loc = "Use --fast-mode"
        }
    }

    if ($isp.Length -gt 30) { $isp = $isp.Substring(0, 27) + "..." }

    # 4. IPv6 тест
    $hasV6 = $false
    if ($script:Config.IpPreference -ne "IPv4") {
        try {
            $t = New-Object System.Net.Sockets.TcpClient([System.Net.Sockets.AddressFamily]::InterNetworkV6)
            $a = $t.BeginConnect("ipv6.google.com", 80, $null, $null)
            if ($a.AsyncWaitHandle.WaitOne(1000)) {
                $t.EndConnect($a)
                $hasV6 = $true
            }
            $t.Close()
        } catch { }
    }

    $result = @{
        DNS = $dns
        CDN = $cdn
        ISP = $isp
        LOC = $loc
        TimestampTicks = (Get-Date).Ticks
        HasIPv6 = $hasV6
    }

    return $result
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

        $curTls = "Auto"
        if ($script:Config -and $script:Config.TlsMode) {
            $curTls = [string]$script:Config.TlsMode
        }
        if ([string]::IsNullOrWhiteSpace($curTls)) { $curTls = "Auto" }

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

        Write-Host "`n  3. Режим TLS при сканировании " -NoNewline -ForegroundColor White
        Write-Host "[ $curTls ]" -ForegroundColor Cyan
        Write-Host "     Auto — колонки T12 и T13 (как по умолчанию)." -ForegroundColor Gray
        Write-Host "     TLS12 — в таблице осмысленен столбец T12 (T13 остаётся N/A); при DRP/RST тихо проверяется T13 только для вердикта." -ForegroundColor Gray
        Write-Host "     TLS13 — наоборот: столбец T13 основной (T12 N/A); при DRP/RST тихо проверяется T12 для вердикта." -ForegroundColor Gray
        Write-Host "     Нажмите 3, чтобы переключить: Auto → TLS12 → TLS13 → Auto" -ForegroundColor DarkGray

        $curParallelTls = $false
        if ($script:Config -and ($script:Config.ScanParallelTlsFirstPass -eq $true)) { $curParallelTls = $true }

        $curDbgLog = $false
        if ($script:Config -and ($script:Config.DebugLogEnabled -eq $true)) { $curDbgLog = $true }
        Write-Host "`n  4. Запись отладки в файл " -NoNewline -ForegroundColor White
        if ($curDbgLog) {
            Write-Host "[ ВКЛ ]" -ForegroundColor Green
        } else {
            Write-Host "[ ВЫКЛ ]" -ForegroundColor DarkGray
        }
        Write-Host "     Файл: YT-DPI_Debug.log (рядом со скриптом). Дополнительно: переменная YT_DPI_DEBUG." -ForegroundColor Gray
        Write-Host "     Включено, если ВКЛ в меню или задана YT_DPI_DEBUG=1." -ForegroundColor DarkGray

        $curFullId = $false
        if ($script:Config -and ($script:Config.DebugLogFullIdentifiers -eq $true)) { $curFullId = $true }
        Write-Host "`n  5. Полные идентификаторы в заголовке лога " -NoNewline -ForegroundColor White
        if ($curFullId) {
            Write-Host "[ ВКЛ — ПК, пользователь, пути ]" -ForegroundColor Yellow
        } else {
            Write-Host "[ ВЫКЛ — обезличено ]" -ForegroundColor Green
        }
        Write-Host "     Для разового полного заголовка: YT_DPI_DEBUG_IDENTIFIERS=1 (перекрывает ВЫКЛ в конфиге)." -ForegroundColor Gray

        Write-Host "`n  6. Параллельный первый проход TLS (Auto, T13+T12) " -NoNewline -ForegroundColor White
        if ($curParallelTls) { Write-Host "[ ВКЛ ]" -ForegroundColor Yellow } else { Write-Host "[ ВЫКЛ ]" -ForegroundColor DarkGray }
        Write-Host "     Если ВКЛ: эксперимент, параллельные Tasks; при сбое — последовательный TLS без ложного IP BLOCK." -ForegroundColor Gray
        Write-Host "     Если ВЫКЛ: последовательно T13 → T12 (медленнее строка скана)." -ForegroundColor Gray

        Write-Host "`n  0. Назад в главное меню" -ForegroundColor DarkGray
        Write-Host "`n $line" -ForegroundColor Cyan
        Write-Host " ВЫБЕРИТЕ ПУНКТ (1–6, 0): " -NoNewline -ForegroundColor Yellow

        Update-UiConsoleSnapshot
        $menuKey = Read-MenuKeyOrResize
        if ($menuKey.Resized) { continue }
        $key = $menuKey.KeyChar

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
                if (Test-Path $script:GeoCacheFile) {
                    try { Remove-Item $script:GeoCacheFile -Force -ErrorAction SilentlyContinue } catch {}
                }

                Save-Config $script:Config
                Write-Host "`n  [OK] Кэш очищен!" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            elseif ($key -eq "3") {
                $tm = if ($script:Config.TlsMode) { [string]$script:Config.TlsMode } else { "Auto" }
                if ([string]::IsNullOrWhiteSpace($tm)) { $tm = "Auto" }
                $nextTls = "Auto"
                if ($tm -match '^(?i)Auto$') {
                    $nextTls = "TLS12"
                }
                elseif ($tm -match '^(?i)TLS12$') {
                    $nextTls = "TLS13"
                }
                else {
                    $nextTls = "Auto"
                }
                $script:Config | Add-Member -MemberType NoteProperty -Name "TlsMode" -Value $nextTls -Force
                Save-Config $script:Config
                Write-Host "`n  [OK] Режим TLS: $nextTls (сохранено в конфиг)" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            elseif ($key -eq "4") {
                $nextDbg = -not $curDbgLog
                $script:Config | Add-Member -MemberType NoteProperty -Name "DebugLogEnabled" -Value $nextDbg -Force
                Save-Config $script:Config
                if ($nextDbg) {
                    $script:DebugSessionHeaderWritten = $false
                    Write-DebugLogSessionHeaderIfNeeded
                }
                $st = if ($nextDbg) { "ВКЛ" } else { "ВЫКЛ" }
                Write-Host "`n  [OK] Отладочный лог в файл: $st (сохранено в конфиг)" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            elseif ($key -eq "5") {
                $nextFull = -not $curFullId
                $script:Config | Add-Member -MemberType NoteProperty -Name "DebugLogFullIdentifiers" -Value $nextFull -Force
                Save-Config $script:Config
                if (Test-DebugLogEnabled) {
                    $script:DebugSessionHeaderWritten = $false
                    Write-DebugLogSessionHeaderIfNeeded
                }
                $st5 = if ($nextFull) { "ВКЛ (осторожно при отправке лога в чат)" } else { "ВЫКЛ (обезличивание)" }
                Write-Host "`n  [OK] Полные идентификаторы в логе: $st5" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            elseif ($key -eq "6") {
                $nextPar = -not $curParallelTls
                $script:Config | Add-Member -MemberType NoteProperty -Name "ScanParallelTlsFirstPass" -Value $nextPar -Force
                Save-Config $script:Config
                $st6 = if ($nextPar) { "ВКЛ" } else { "ВЫКЛ" }
                Write-Host "`n  [OK] Параллельный первый проход TLS: $st6 (сохранено в конфиг)" -ForegroundColor Green
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

function Copy-ProxyConfigSnapshot {
    return @{
        Enabled = [bool]$global:ProxyConfig.Enabled
        Type    = [string]$global:ProxyConfig.Type
        Host    = [string]$global:ProxyConfig.Host
        Port    = [int]$global:ProxyConfig.Port
        User    = [string]$global:ProxyConfig.User
        Pass    = [string]$global:ProxyConfig.Pass
    }
}

function Restore-ProxyConfigSnapshot($snap) {
    if (-not $snap) { return }
    $global:ProxyConfig.Enabled = $snap.Enabled
    $global:ProxyConfig.Type = $snap.Type
    $global:ProxyConfig.Host = $snap.Host
    $global:ProxyConfig.Port = $snap.Port
    $global:ProxyConfig.User = $snap.User
    $global:ProxyConfig.Pass = $snap.Pass
}

function Read-ProxyMenuDigitKey {
    while ($true) {
        $mk = Read-MenuKeyOrResize
        if ($mk.Resized) {
            return [PSCustomObject]@{ Kind = "Resize" }
        }
        if ($mk.Key -eq [ConsoleKey]::Escape) {
            return [PSCustomObject]@{ Kind = "Exit" }
        }
        $k = $mk.Key
        if ($k -ge [ConsoleKey]::D0 -and $k -le [ConsoleKey]::D9) {
            return [PSCustomObject]@{ Kind = "Digit"; Digit = [int]($k - [ConsoleKey]::D0) }
        }
        if ($k -ge [ConsoleKey]::NumPad0 -and $k -le [ConsoleKey]::NumPad9) {
            return [PSCustomObject]@{ Kind = "Digit"; Digit = [int]($k - [ConsoleKey]::NumPad0) }
        }
    }
}

function Invoke-ProxyMenuActivateHistoryIndex {
    param([int]$Index, [array]$History)

    $historyEntry = $History[$Index]
    Write-DebugLog "Show-ProxyMenu: Выбран прокси из истории [#$($Index + 1)]"
    if ($historyEntry -match '^(?i)(http|socks5)://(?:([^:]+):\*\*\*\*\*@)?([^:]+):(\d+)$') {
        $proto = $matches[1].ToUpper()
        $user = if ($matches[2]) { $matches[2] } else { "" }
        $proxyHost = $matches[3]
        $port = [int]$matches[4]
        $pass = ""
        if ($user) {
            Write-Host "`n  [i] Прокси с аутентификацией. Введите пароль (Esc — отмена):" -ForegroundColor Yellow
            [Console]::CursorVisible = $false
            $passInput = Read-MenuLineOrResize
            if ($passInput.Resized) {
                Show-ProxyMenu
                return
            }
            if ($passInput.Cancelled) {
                Write-Host "  [i] Отмена." -ForegroundColor DarkGray
                Start-Sleep -Milliseconds 800
                Show-ProxyMenu
                return
            }
            $pass = $passInput.Text
            [Console]::CursorVisible = $false
        }
        $snapBefore = Copy-ProxyConfigSnapshot
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
            Add-ToProxyHistory $global:ProxyConfig
            Save-Config $script:Config
            Start-Sleep -Seconds 2
            return
        }
        Restore-ProxyConfigSnapshot $snapBefore
        Save-Config $script:Config
        Write-Host "  [FAIL] Прокси НЕ РАБОТАЕТ: $($testResult.Error)" -ForegroundColor Red
        Write-Host "  [i] Предыдущие настройки прокси восстановлены." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        Show-ProxyMenu
        return
    }
    Write-Host "`n  [FAIL] Не удалось распарсить запись истории." -ForegroundColor Red
    Start-Sleep -Seconds 2
    Show-ProxyMenu
}

function Invoke-ProxyMenuManualString {
    param([string]$RawInput)

    $userInput = $RawInput.Trim()
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "`n  [i] Пустой ввод — отмена." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
        Show-ProxyMenu
        return
    }

    Write-DebugLog "Show-ProxyMenu: Парсинг нового прокси '$userInput'"

    $proxyType = "AUTO"
    $user = ""
    $pass = ""
    $proxyHost = ""
    $port = 0

    if ($userInput -match '^(?i)(http|socks5)://') {
        $protocol = $matches[1].ToUpper()
        $proxyType = $protocol
        $userInput = $userInput -replace '^(?i)(http|socks5)://', ''
        Write-DebugLog "Show-ProxyMenu: Обнаружен протокол $proxyType, остаток = '$userInput'"
    }

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

    if ($proxyType -eq "AUTO") {
        Write-DebugLog "Show-ProxyMenu: Определяем тип прокси для $proxyHost`:$port"
        $detected = Detect-ProxyType $proxyHost $port
        if ($detected.Type -eq "UNKNOWN") {
            Write-Host "`n  [FAIL] Не удалось определить тип прокси. Укажите явно: http://$proxyHost`:$port или socks5://$proxyHost`:$port" -ForegroundColor Red
            Start-Sleep -Seconds 3
            Show-ProxyMenu
            return
        }
        $proxyType = $detected.Type
        Write-DebugLog "Show-ProxyMenu: Определен тип = $proxyType"
    }

    $snapBefore = Copy-ProxyConfigSnapshot

    $global:ProxyConfig.Enabled = $true
    $global:ProxyConfig.Type = $proxyType
    $global:ProxyConfig.Host = $proxyHost
    $global:ProxyConfig.Port = $port
    $global:ProxyConfig.User = $user
    $global:ProxyConfig.Pass = $pass

    $testResult = Test-ProxyQuick $global:ProxyConfig

    if ($testResult.Success) {
        Write-Host "  [OK] Прокси работает! (задержка: $($testResult.Latency) мс)" -ForegroundColor Green
        Write-Host "  [OK] Тип: $($global:ProxyConfig.Type)" -ForegroundColor Green
        if ($global:ProxyConfig.User) {
            Write-Host "  [OK] Аутентификация настроена" -ForegroundColor Green
        }
        Add-ToProxyHistory $global:ProxyConfig
        Save-Config $script:Config
        Start-Sleep -Seconds 2
    } else {
        Restore-ProxyConfigSnapshot $snapBefore
        Save-Config $script:Config
        Write-Host "  [FAIL] Прокси НЕ РАБОТАЕТ: $($testResult.Error)" -ForegroundColor Red
        Write-Host "  [i] Предыдущие настройки восстановлены. Проверьте адрес, порт или укажите тип явно (socks5://…)." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        Show-ProxyMenu
    }
}

function Show-ProxyMenu {
    [Console]::Clear()
    $w = [Console]::WindowWidth
    if ($w -gt 100) { $w = 100 }
    $line = "═" * $w
    $dash = "─" * $w

    $history = @($script:Config.ProxyHistory)
    $histBase = 5
    $maxChoice = 4 + $history.Count

    Write-Host "`n $line" -ForegroundColor Cyan
    Write-Host (Get-PaddedCenter "НАСТРОЙКА ПРОКСИ" $w) -ForegroundColor Yellow
    Write-Host " $line" -ForegroundColor Cyan

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

    Write-Host "`n $dash" -ForegroundColor Gray
    Write-Host "  ДЕЙСТВИЯ:" -ForegroundColor White
    Write-Host "    1 — Проверить текущий прокси (полный тест)" -ForegroundColor Gray
    Write-Host "    2 — Выключить прокси и сбросить адрес" -ForegroundColor Gray
    Write-Host "    3 — Очистить историю (подтверждение Y/N)" -ForegroundColor Gray
    Write-Host "    4 — Ввести новый адрес прокси" -ForegroundColor Gray

    if ($history.Count -gt 0) {
        Write-Host "`n  ИЗ ИСТОРИИ:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $history.Count; $i++) {
            $mn = $histBase + $i
            $suffix = if ($i -eq 0) { "  (последний)" } else { "" }
            Write-Host "    $mn — $($history[$i])$suffix" -ForegroundColor Gray
        }
    }

    Write-Host "`n  П.4: host:port · http://host:port · socks5://host:port · user:pass@host:port" -ForegroundColor DarkGray
    Write-Host "  Пример: " -NoNewline -ForegroundColor DarkGray
    Write-Host "127.0.0.1:1080" -ForegroundColor Cyan -NoNewline
    Write-Host " (SOCKS), " -NoNewline -ForegroundColor DarkGray
    Write-Host ":8080" -ForegroundColor Cyan -NoNewline
    Write-Host " часто HTTP" -ForegroundColor DarkGray

    Write-Host "`n    0 или Esc — выход в главное меню" -ForegroundColor DarkGray

    Write-Host "`n $dash" -ForegroundColor Gray

    Update-UiConsoleSnapshot
    [Console]::ForegroundColor = "White"
    [Console]::CursorVisible = $false
    Clear-KeyBuffer

    $rk = Read-ProxyMenuDigitKey
    if ($rk.Kind -eq "Resize") {
        Show-ProxyMenu
        return
    }
    if ($rk.Kind -eq "Exit") {
        Write-DebugLog "Show-ProxyMenu: выход по Esc"
        return
    }

    $d = $rk.Digit
    if ($d -eq 0) {
        return
    }

    if ($d -lt 1 -or $d -gt $maxChoice) {
        Write-Host "`n  [i] Нажмите цифру от 0 до $maxChoice." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        Show-ProxyMenu
        return
    }

    if ($d -eq 1) {
        if (-not $global:ProxyConfig.Enabled) {
            Write-Host "`n  [i] Сначала задайте прокси: пункт 4 или $($histBase)…$maxChoice из истории." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            Show-ProxyMenu
            return
        }
        Test-ProxyConnection
        Show-ProxyMenu
        return
    }

    if ($d -eq 2) {
        $global:ProxyConfig.Enabled = $false
        $global:ProxyConfig.User = ""
        $global:ProxyConfig.Pass = ""
        $global:ProxyConfig.Host = ""
        $global:ProxyConfig.Port = 0
        $global:ProxyConfig.Type = "HTTP"
        Write-Host "`n  [OK] Прокси выключен, адрес сброшен." -ForegroundColor Green
        Save-Config $script:Config
        Start-Sleep -Seconds 1
        return
    }

    if ($d -eq 3) {
        if ($history.Count -eq 0) {
            Write-Host "`n  [i] История уже пуста." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            Show-ProxyMenu
            return
        }
        Write-Host "`n  Очистить всю историю ($($history.Count) записей)?  Y — да / N — нет " -ForegroundColor Yellow
        Clear-KeyBuffer
        Update-UiConsoleSnapshot
        $confirmed = $false
        while ($true) {
            $mk = Read-MenuKeyOrResize
            if ($mk.Resized) {
                Show-ProxyMenu
                return
            }
            $ch = [string]$mk.KeyChar
            if ($ch -eq "y" -or $ch -eq "Y") {
                $confirmed = $true
                break
            }
            if ($ch -eq "n" -or $ch -eq "N" -or $mk.Key -eq "Escape") {
                break
            }
        }
        if (-not $confirmed) {
            Write-Host "  [i] Очистка отменена." -ForegroundColor DarkGray
            Start-Sleep -Seconds 1
            Show-ProxyMenu
            return
        }
        $script:Config.ProxyHistory = @()
        Save-Config $script:Config
        Write-Host "  [OK] История прокси очищена." -ForegroundColor Green
        Start-Sleep -Seconds 1
        Show-ProxyMenu
        return
    }

    if ($d -eq 4) {
        Write-Host "`n $dash" -ForegroundColor Gray
        Write-Host "  Введите адрес прокси (Esc — отмена):" -ForegroundColor White
        Write-Host "  > " -NoNewline -ForegroundColor Yellow
        $lineInput = Read-MenuLineOrResize
        if ($lineInput.Resized) {
            Show-ProxyMenu
            return
        }
        if ($lineInput.Cancelled) {
            Write-Host "`n  [i] Отмена." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 600
            Show-ProxyMenu
            return
        }
        Invoke-ProxyMenuManualString $lineInput.Text
        return
    }

    $histIdx = $d - $histBase
    Invoke-ProxyMenuActivateHistoryIndex -Index $histIdx -History $history
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

function Wait-TcpBeginConnectWithStatus([System.Net.Sockets.TcpClient]$Tcp, [System.IAsyncResult]$Ar, [int]$TimeoutMs, [string]$DetailLabel) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Ar.IsCompleted) {
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) { return $false }
        $null = $Ar.AsyncWaitHandle.WaitOne(90)
    }
    return $true
}

function Test-ProxyConnection {
    Write-DebugLog "Test-ProxyConnection: расширенный тест прокси"
    [Console]::CursorVisible = $false
    if (-not $global:ProxyConfig.Enabled) {
        Write-Host "`n  [FAIL] Включите прокси в меню [P] или введите адрес." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    $pc = $global:ProxyConfig
    [Console]::Clear()
    $w = [Console]::WindowWidth
    if ($w -gt 100) { $w = 100 }
    $line = "─" * $w
    Write-Host "`n $line" -ForegroundColor Cyan
    Write-Host (Get-PaddedCenter "ПРОВЕРКА ПРОКСИ" $w) -ForegroundColor Yellow
    Write-Host " $line" -ForegroundColor Cyan
    Write-Host "`n  $($pc.Type) $($pc.Host):$($pc.Port)" -ForegroundColor Green

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("══ ПРОВЕРКА ПРОКСИ ══")
    $lines.Add("Тип: $($pc.Type)  Адрес: $($pc.Host):$($pc.Port)  Логин: $(if ($pc.User) { $pc.User } else { '(нет)' })")
    $lines.Add("")

    # 1) TCP до хоста прокси (с «живым» ожиданием)
    $swTcp = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Write-Host "`n  [1/4] TCP до прокси..." -ForegroundColor Cyan
        $tcpP = New-Object System.Net.Sockets.TcpClient
        $arP = $tcpP.BeginConnect($pc.Host, $pc.Port, $null, $null)
        if (-not (Wait-TcpBeginConnectWithStatus $tcpP $arP 4000 "1/4 TCP до прокси")) {
            try { $tcpP.Close() } catch { }
            throw "Таймаут TCP до прокси (4 c)"
        }
        $tcpP.EndConnect($arP)
        $swTcp.Stop()
        $lines.Add("[OK] TCP до прокси: $($swTcp.ElapsedMilliseconds) мс")
        $tcpP.Close()
        Write-Host "       OK $($swTcp.ElapsedMilliseconds) ms" -ForegroundColor Green
        Start-Sleep -Milliseconds 120
    } catch {
        $lines.Add("[FAIL] TCP до прокси: $($_.Exception.Message)")
        Show-ProxyTestResultPanel $lines $false
        return
    }

    # 2) Туннель :80
    Write-Host "  [2/4] Туннель google.com:80..." -ForegroundColor Cyan
    $q80 = Test-ProxyQuick $pc
    if ($q80.Success) {
        $lines.Add("[OK] Туннель google.com:80 — $($q80.Latency) мс")
        Write-Host "       OK $($q80.Latency) ms" -ForegroundColor Green
    } else {
        $lines.Add("[FAIL] Туннель google.com:80 — $($q80.Error)")
        Write-Host "       FAIL $($q80.Error)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 150

    # 3) Туннель :443
    $ok443 = $false
    Write-Host "  [3/4] Туннель google.com:443..." -ForegroundColor Cyan
    $sw443 = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $c443 = Connect-ThroughProxy "google.com" 443 $pc 7000
        if ($c443 -and $c443.Tcp) {
            $sw443.Stop()
            $ok443 = $true
            $lines.Add("[OK] Туннель google.com:443 — $($sw443.ElapsedMilliseconds) мс")
            Write-Host "       OK $($sw443.ElapsedMilliseconds) ms" -ForegroundColor Green
            try { $c443.Tcp.Close() } catch { }
        } else {
            $lines.Add("[FAIL] Туннель google.com:443 — нет сокета после CONNECT")
            Write-Host "       FAIL нет сокета после CONNECT" -ForegroundColor Red
        }
    } catch {
        $lines.Add("[FAIL] Туннель google.com:443 — $($_.Exception.Message)")
        Write-Host "       FAIL $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 150

    # 4) HTTP как у GEO
    Write-Host "  [4/4] HTTP через прокси..." -ForegroundColor Cyan
    try {
        $swHttp = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Invoke-WebRequestViaProxy "http://www.gstatic.com/generate_204" "GET" 5000
        $swHttp.Stop()
        if ($swHttp.ElapsedMilliseconds -ge 4800) {
            $lines.Add("[WARN] HTTP через прокси: очень долго ($($swHttp.ElapsedMilliseconds) мс)")
            Write-Host "       WARN долго $($swHttp.ElapsedMilliseconds) ms" -ForegroundColor Yellow
        } else {
            $lines.Add("[OK] HTTP через прокси (gstatic 204) — $($swHttp.ElapsedMilliseconds) мс")
            Write-Host "       OK $($swHttp.ElapsedMilliseconds) ms" -ForegroundColor Green
        }
    } catch {
        $lines.Add("[FAIL] HTTP через прокси: $($_.Exception.Message)")
        Write-Host "       FAIL $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 200

    $allCriticalOk = $q80.Success -and $ok443
    Show-ProxyTestResultPanel $lines $allCriticalOk
}

function Show-ProxyTestResultPanel {
    param([System.Collections.Generic.List[string]]$Lines, [bool]$OverallOk)
    $oldBufH = [Console]::BufferHeight
    try { if ([Console]::BufferHeight -lt 80) { [Console]::BufferHeight = 80 } } catch {}
    [Console]::Clear()
    [Console]::CursorVisible = $false
    $w = [Console]::WindowWidth
    if ($w -gt 100) { $w = 100 }
    $line = "─" * $w
    Write-Host "`n $line" -ForegroundColor Cyan
    Write-Host (Get-PaddedCenter "РЕЗУЛЬТАТ ТЕСТА ПРОКСИ" $w) -ForegroundColor $(if ($OverallOk) { "Green" } else { "Yellow" })
    Write-Host " $line" -ForegroundColor Cyan
    foreach ($ln in $Lines) {
        if ($ln -match '^\[OK\]') { Write-Host " $ln" -ForegroundColor Green }
        elseif ($ln -match '^\[FAIL\]') { Write-Host " $ln" -ForegroundColor Red }
        elseif ($ln -match '^\[WARN\]|^\[i\]') { Write-Host " $ln" -ForegroundColor DarkYellow }
        elseif ($ln -match '^═') { Write-Host "`n $ln" -ForegroundColor White }
        else { Write-Host " $ln" -ForegroundColor Gray }
    }
    Write-Host "`n $line" -ForegroundColor Gray
    Write-Host (Get-PaddedCenter "Любая клавиша — назад" $w) -ForegroundColor Gray
    Clear-KeyBuffer
    Update-UiConsoleSnapshot
    $panelKey = Read-MenuKeyOrResize
    if ($panelKey.Resized) {
        Show-ProxyTestResultPanel $Lines $OverallOk
        return
    }
    try { [Console]::BufferHeight = $oldBufH } catch {}
}

function Show-HelpMenu {
    param([int]$ResumePage = 0)

    Write-DebugLog "Show-HelpMenu: Справка (возврат на стр. $ResumePage)..."

    $oldBufH = [Console]::BufferHeight
    try {
        $needBuf = [Math]::Max(100, [Console]::WindowHeight + 60)
        if ([Console]::BufferHeight -lt $needBuf) { [Console]::BufferHeight = $needBuf }
    } catch {}

    $totalPages = 5
    $page = [Math]::Max(0, [Math]::Min($ResumePage, $totalPages - 1))

    while ($true) {
        [Console]::Clear()
        [Console]::CursorVisible = $false

        $w = [Console]::WindowWidth
        if ($w -gt 108) { $w = 108 }
        $line = "─" * $w

        Write-Host "`n $($line)" -ForegroundColor Gray
        Write-Host "   YT-DPI v$scriptVersion — справка  (страница $($page + 1) / $totalPages)" -ForegroundColor Cyan
        Write-Host " $($line)" -ForegroundColor Gray

        switch ($page) {
            0 {
                Write-Host "`n [ ЧТО ДЕЛАЕТ ПРОГРАММА ]" -ForegroundColor White
                Write-Host "   Параллельно проверяет список доменов: TCP/HTTP на порту 80, TLS 1.2 и TLS 1.3 на 443" -ForegroundColor Gray
                Write-Host "   с реальным именем хоста (SNI). Это диагностика сети/DPI, не обход блокировок." -ForegroundColor Gray

                Write-Host "`n [ ГОРЯЧИЕ КЛАВИШИ (главный экран) ]" -ForegroundColor White
                Write-Host "   ENTER     " -ForegroundColor Yellow -NoNewline; Write-Host " — полное сканирование таблицы (после проверки сети)." -ForegroundColor Gray
                Write-Host "   S         " -ForegroundColor Yellow -NoNewline; Write-Host " — настройки: IP (1), кэш (2), TLS (3), лог (4), полные идентификаторы в логе (5)." -ForegroundColor Gray
                Write-Host "   P         " -ForegroundColor Yellow -NoNewline; Write-Host " — меню прокси (цифры 1–4 и история с 5, 0/Esc — выход)." -ForegroundColor Gray
                Write-Host "   D         " -ForegroundColor Yellow -NoNewline; Write-Host " — Deep Trace: трассировка и TCP-проверка по пути к выбранному домену." -ForegroundColor Gray
                Write-Host "   U         " -ForegroundColor Yellow -NoNewline; Write-Host " — проверка и загрузка обновления с GitHub." -ForegroundColor Gray
                Write-Host "   R         " -ForegroundColor Yellow -NoNewline; Write-Host " — сохранить отчёт в файл YT-DPI_Report.txt (если скана не было — пустой шаблон)." -ForegroundColor Gray
                Write-Host "   H         " -ForegroundColor Yellow -NoNewline; Write-Host " — эта справка." -ForegroundColor Gray
                Write-Host "   Q / ESC   " -ForegroundColor Yellow -NoNewline; Write-Host " — выход (сохраняется конфиг)." -ForegroundColor Gray
                Write-Host "`n   Во время скана следуйте подсказкам в строке статуса (прерывание, повтор и т.д.)." -ForegroundColor DarkGray
            }
            1 {
                Write-Host "`n [ КОЛОНКИ ТАБЛИЦЫ ]" -ForegroundColor White
                Write-Host "   № / TARGET — номер строки (нужен для Deep Trace) и проверяемый домен." -ForegroundColor Gray
                Write-Host "   IP — резолв IPv4/IPv6 по настройкам; [ PROXIED ] при скане через прокси; DNS_ERR — ошибка DNS." -ForegroundColor Gray
                Write-Host "   HTTP — доступность порта 80 (не «веб-страница», а именно TCP до сервера)." -ForegroundColor Gray
                Write-Host "   T12 / T13 — результат TLS-handshake для версии 1.2 и «современного» клиента (1.3+)." -ForegroundColor Gray
                Write-Host "   LAT — задержка HTTP-проверки в миллисекундах (грубый ping-подобный показатель)." -ForegroundColor Gray
                Write-Host "   RESULT — итоговый вердикт по комбинации HTTP+TLS (см. след. страницу)." -ForegroundColor Gray

                Write-Host "`n [ КОДЫ В ЯЧЕЙКАХ HTTP / TLS ]" -ForegroundColor White
                Write-Host "   OK      " -ForegroundColor Green -NoNewline; Write-Host " — проверка прошла (для TLS: рукопожатие до ответа сервера)." -ForegroundColor Gray
                Write-Host "   ERR     " -ForegroundColor Red -NoNewline; Write-Host " — порт 80 недоступен; TLS дальше не проверяются (показывается ---)." -ForegroundColor Gray
                Write-Host "   RST     " -ForegroundColor Red -NoNewline; Write-Host " — соединение сброшено (частая картина при DPI с TCP RST)." -ForegroundColor Gray
                Write-Host "   DRP     " -ForegroundColor Red -NoNewline; Write-Host " — обрыв/таймаут/«чёрная дыра» без нормального ответа." -ForegroundColor Gray
                Write-Host "   PRX_ERR " -ForegroundColor Red -NoNewline; Write-Host " — ошибка туннеля SOCKS к цели (в колонке T13 при прокси)." -ForegroundColor Gray
                Write-Host "   N/A     " -ForegroundColor DarkGray -NoNewline; Write-Host " — TLS 1.3 не применим/не получилось классифицировать (редко в таблице)." -ForegroundColor Gray
                Write-Host "   ---     " -ForegroundColor DarkGray -NoNewline; Write-Host " — значение ещё не получено или проверка пропущена (например после ERR по HTTP)." -ForegroundColor Gray
            }
            2 {
                Write-Host "`n [ ВЕРДИКТЫ (RESULT) ]" -ForegroundColor White
                Write-Host "   AVAILABLE   " -ForegroundColor Green -NoNewline
                Write-Host " — оба TLS (1.2 и 1.3) в состоянии OK; доступ к узлу по HTTPS выглядит нормальным." -ForegroundColor Gray
                Write-Host "   THROTTLED   " -ForegroundColor Yellow -NoNewline
                Write-Host " — один из TLS OK, второй даёт RST/DRP: типичный частичный DPI или деградация одного пути." -ForegroundColor Gray
                Write-Host "   DPI RESET   " -ForegroundColor Red -NoNewline
                Write-Host " — хотя бы один TLS завершился кодом RST (жёсткий сброс)." -ForegroundColor Gray
                Write-Host "   DPI BLOCK   " -ForegroundColor Red -NoNewline
                Write-Host " — есть DRP без сценария выше (обрыв/таймаут на TLS)." -ForegroundColor Gray
                Write-Host "   IP BLOCK    " -ForegroundColor Red -NoNewline
                Write-Host " — HTTP недоступен или оба TLS не дали рабочей картины (смотрите ячейки)." -ForegroundColor Gray
                Write-Host "   TIMEOUT     " -ForegroundColor Red -NoNewline
                Write-Host " — строка не успела завершиться в лимите времени скана." -ForegroundColor Gray
                Write-Host "   UNKNOWN     " -ForegroundColor DarkGray -NoNewline
                Write-Host " — внутренняя ошибка воркера или неожиданное состояние." -ForegroundColor Gray
                Write-Host "   IDLE        " -ForegroundColor DarkGray -NoNewline
                Write-Host " — строка ещё не сканировалась (начальное состояние)." -ForegroundColor Gray

                Write-Host "`n [ КАК ЭТО ЧИТАТЬ ПРАКТИЧЕСКИ ]" -ForegroundColor White
                Write-Host "   Сначала HTTP: если ERR — проблема шире TLS (маршрут, IP, прокси, «падает» порт 80)." -ForegroundColor Gray
                Write-Host "   Если HTTP OK, смотрите T12 и T13: оба OK — хорошо; расхождение — смотрите THROTTLED/DPI*." -ForegroundColor Gray
                Write-Host "   Вердикт обобщает таблицу; детали всегда в отдельных ячейках и в отчёте (R)." -ForegroundColor Gray
            }
            3 {
                Write-Host "`n [ DEEP TRACE (клавиша D) ]" -ForegroundColor White
                Write-Host "   1. Нажмите D — внизу запросится номер домена из таблицы (1 … N), введите число и Enter." -ForegroundColor Gray
                Write-Host "   2. Строится трассировка к целевому IP (до 15 хопов), затем на каждом отвечающем хопе" -ForegroundColor Gray
                Write-Host "      проверяется TCP к порту 443 (как проходит путь к «ближайшему» узлу на маршруте)." -ForegroundColor Gray
                Write-Host "   3. Прогресс и сообщения движка выводятся в строке статуса под таблицей." -ForegroundColor Gray
                Write-Host "   4. Краткий итог там же: например RST на раннем хопе — типичный признак оборудования/DPI на пути;" -ForegroundColor Gray
                Write-Host "      TCP OK на хопе — сегмент пути до этого узла SYN/ACK принимает." -ForegroundColor Gray
                Write-Host "   5. После вывода результата нажмите Enter, Esc или пробел, чтобы вернуться к таблице." -ForegroundColor Gray
                Write-Host "`n   Движок может использовать ICMP или сырые TCP SYN (часть режимов на Windows требует прав" -ForegroundColor DarkGray
                Write-Host "   администратора для raw sockets). Если прав нет, включается запасной метод — трассировка" -ForegroundColor DarkGray
                Write-Host "   всё равно выполняется, но точность и скорость могут отличаться." -ForegroundColor DarkGray
                Write-Host "`n   Deep Trace дополняет таблицу, но не заменяет её: смотрите оба инструмента вместе." -ForegroundColor Gray
            }
            4 {
                Write-Host "`n [ МЕНЮ ПРОКСИ (P) ]" -ForegroundColor White
                Write-Host "   Введите строку прокси (см. подсказки в самом меню) или номер из истории." -ForegroundColor Gray
                Write-Host "   Цифры: 1 — тест, 2 — выкл., 3 — очистить историю, 4 — новый адрес; 5+ — слоты истории; 0/Esc — выход." -ForegroundColor Gray
                Write-Host "   Отдельной клавиши «T» на главном экране нет — тест прокси только из меню P." -ForegroundColor DarkGray

                Write-Host "`n [ НАСТРОЙКИ (S) ]" -ForegroundColor White
                Write-Host "   1 — IPv6 приоритет / только IPv4; 2 — сброс DNS и GEO-кэша; 3 — режим скана TLS (Auto / только 1.2 / только 1.3)." -ForegroundColor Gray
                Write-Host "   4 — запись отладки в YT-DPI_Debug.log (рядом со скриптом); плюс можно включить через YT_DPI_DEBUG=1." -ForegroundColor Gray
                Write-Host "   5 — полные ПК/пользователь/пути в заголовке лога (по умолчанию ВЫКЛ = обезличено); или YT_DPI_DEBUG_IDENTIFIERS=1." -ForegroundColor Gray
                Write-Host "   Режим TLS и флаги отладки сохраняются в конфиг; лог активен, если ВКЛ в меню или задана переменная окружения." -ForegroundColor DarkGray

                Write-Host "`n [ ОБНОВЛЕНИЕ (U) ]" -ForegroundColor White
                Write-Host "   Сверка версии с релизом на GitHub и замена локальных файлов по подтверждению (Y/N)." -ForegroundColor Gray

                Write-Host "`n [ TLS, БРАУЗЕР И ЛОЖНЫЕ СРАБАТЫВАНИЯ ]" -ForegroundColor White
                Write-Host "   TLS 1.3 в браузерах может использовать пост-квантовые дополнения (например Kyber)." -ForegroundColor Gray
                Write-Host "   Если картина нестабильна, попробуйте отключить эксперимент: " -ForegroundColor Gray -NoNewline
                Write-Host "chrome://flags/#enable-tls13-kyber" -ForegroundColor Cyan
                Write-Host "   Сканер не открывает сайт в браузере — только сетевой уровень; различайте «сайт тормозит»" -ForegroundColor Gray
                Write-Host "   (CDN, GGC, контент) и «TLS режется по имени» (DPI по SNI)." -ForegroundColor Gray

                Write-Host "`n [ БЫСТРЫЕ ОТВЕТЫ ]" -ForegroundColor White
                Write-Host "   THROTTLED + живой YouTube — часто помогает обход DPI или смена сети/прокси." -ForegroundColor Gray
                Write-Host "   Все строки IP BLOCK — проверьте интернет, VPN/прокси, DNS и что скан не ушёл в «пустой» кэш." -ForegroundColor Gray
                Write-Host "   Сохраняйте отчёт (R) перед тем как делиться логами в чатах поддержки." -ForegroundColor Gray
            }
        }

        Write-Host "`n $($line)" -ForegroundColor DarkGray
        Write-Host (Get-PaddedCenter "N / → / PgDn — далее    P / ← / PgUp — назад    Enter / Esc — закрыть" $w) -ForegroundColor DarkGray
        Write-Host " $($line)" -ForegroundColor DarkGray

        Clear-KeyBuffer
        Update-UiConsoleSnapshot
        $helpKey = Read-MenuKeyOrResize
        if ($helpKey.Resized) {
            try { [Console]::BufferHeight = $oldBufH } catch {}
            Show-HelpMenu -ResumePage $page
            return
        }

        $hk = $helpKey.Key
        $navNext = @([ConsoleKey]::N, [ConsoleKey]::RightArrow, [ConsoleKey]::DownArrow, [ConsoleKey]::PageDown)
        $navPrev = @([ConsoleKey]::P, [ConsoleKey]::LeftArrow, [ConsoleKey]::UpArrow, [ConsoleKey]::PageUp)

        if ($hk -in @([ConsoleKey]::Enter, [ConsoleKey]::Escape)) {
            break
        }
        elseif ($hk -in $navNext) {
            $page = ($page + 1) % $totalPages
        }
        elseif ($hk -in $navPrev) {
            $page = ($page - 1 + $totalPages) % $totalPages
        }
        else {
            # любая другая клавиша — выход (удобно при нестандартной раскладке)
            break
        }
    }

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
    param($Target, $ProxyConfig, $CONST, $DebugLogFile, $DEBUG_ENABLED, $DnsCache, $DnsCacheLock, $NetInfo, $IpPreference, $TlsMode, $DebugLogMutexName, [bool]$ParallelTlsFirstPass)

    function Write-DebugLog($msg, $level = "DEBUG") {
        if (-not $DEBUG_ENABLED) { return }
        $line = "[$(Get-Date -Format 'HH:mm:ss.fff')] [Worker $($Target)] [$($level)] $($msg)`r`n"
        $mtx = $null
        $got = $false
        try {
            try { $mtx = if ($DebugLogMutexName) { [System.Threading.Mutex]::OpenExisting($DebugLogMutexName) } else { $null } } catch { $mtx = $null }
            if ($mtx) {
                try { $got = $mtx.WaitOne([int]$CONST.Mutex.WaitMs) } catch { $got = $false }
            }
            if ($got) {
                [System.IO.File]::AppendAllText($DebugLogFile, $line, [System.Text.Encoding]::UTF8)
            } else {
                try { [System.IO.File]::AppendAllText($DebugLogFile, $line, [System.Text.Encoding]::UTF8) } catch { }
            }
        } catch { }
        finally {
            if ($got -and $mtx) { try { [void]$mtx.ReleaseMutex() } catch { } }
            if ($mtx) { try { $mtx.Dispose() } catch { } }
        }
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
            elseif ($ProxyConfig.Type -eq "HTTP") {
                $hdr = "CONNECT ${TargetHost}:$TargetPort HTTP/1.1`r`nHost: ${TargetHost}:$TargetPort`r`n"
                if ($ProxyConfig.User -and $ProxyConfig.Pass) {
                    $authBytes = [Text.Encoding]::ASCII.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)")
                    $hdr += "Proxy-Authorization: Basic $([Convert]::ToBase64String($authBytes))`r`n"
                }
                $hdr += "`r`n"
                $reqBytes = [Text.Encoding]::ASCII.GetBytes($hdr)
                $stream.Write($reqBytes, 0, $reqBytes.Length)

                $swRead = [System.Diagnostics.Stopwatch]::StartNew()
                $response = ""
                $buf = New-Object byte[] 1024
                while ($swRead.ElapsedMilliseconds -lt $Timeout) {
                    if ($stream.DataAvailable) {
                        $r = $stream.Read($buf, 0, 1024)
                        if ($r -le 0) { break }
                        $response += [Text.Encoding]::ASCII.GetString($buf, 0, $r)
                        if ($response -match "`r`n`r`n") { break }
                    } else { Start-Sleep -Milliseconds 20 }
                }

                if ($response -match '(?m)HTTP/1\.\d\s+200') {
                    Write-DebugLog "HTTP CONNECT tunnel OK -> ${TargetHost}:$TargetPort"
                    return @{ Tcp = $tcp; Stream = $stream }
                }

                $snip = if ($response.Length -gt 160) { $response.Substring(0, 160) + "..." } else { $response }
                throw "HTTP CONNECT не 200: $snip"
            }
            else {
                throw "Неподдерживаемый тип прокси для туннеля: $($ProxyConfig.Type)"
            }
        } catch {
            if($tcp){$tcp.Close()}
            Write-DebugLog "Ошибка прокси: $($_.Exception.Message)" "WARN"
            throw $_
        }
    }

    function Set-Verdict-DualTlsCells {
        param([string]$Cell12, [string]$Cell13)
        $t12Ok = ($Cell12 -eq "OK")
        $t13Ok = ($Cell13 -eq "OK")
        $t12Blocked = ($Cell12 -eq "RST" -or $Cell12 -eq "DRP")
        $t13Blocked = ($Cell13 -eq "RST" -or $Cell13 -eq "DRP")
        if ($t12Ok -and $t13Ok) { return @{ Verdict = "AVAILABLE"; Color = "Green" } }
        if ($t12Ok -or $t13Ok) {
            if ($t12Blocked -or $t13Blocked) { return @{ Verdict = "THROTTLED"; Color = "Yellow" } }
            return @{ Verdict = "AVAILABLE"; Color = "Green" }
        }
        if ($Cell12 -eq "RST" -or $Cell13 -eq "RST") { return @{ Verdict = "DPI RESET"; Color = "Red" } }
        if ($Cell12 -eq "DRP" -or $Cell13 -eq "DRP") { return @{ Verdict = "DPI BLOCK"; Color = "Red" } }
        return @{ Verdict = "IP BLOCK"; Color = "Red" }
    }

    function Invoke-Tls12HandshakeOnce {
        param([int]$TimeoutMs)
        $timedOut = $false
        $cell = "---"
        $conn = $null; $ssl = $null
        try {
            if ($ProxyConfig.Enabled) { $conn = Connect-ThroughProxy $Target 443 $ProxyConfig $TimeoutMs }
            else {
                $tcp = [System.Net.Sockets.TcpClient]::new()
                $ar = $tcp.BeginConnect($Result.IP, 443, $null, $null)
                if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw "TcpTimeout" }
                $tcp.EndConnect($ar); $conn = @{ Tcp = $tcp; Stream = $tcp.GetStream() }
            }
            $ssl = [System.Net.Security.SslStream]::new($conn.Stream, $false)
            $enabled = [System.Security.Authentication.SslProtocols]::Tls12
            $auth = $ssl.BeginAuthenticateAsClient($Target, $null, $enabled, $false, $null, $null)
            if (-not $auth.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                $timedOut = $true
                try { $ssl.Close() } catch {}
                throw "TLS12_TIMEOUT"
            }
            $ssl.EndAuthenticateAsClient($auth)
            $cell = if ($ssl.IsAuthenticated) { "OK" } else { "DRP" }
        } catch {
            if ($_.Exception.Message -eq "TLS12_TIMEOUT") {
                $cell = "DRP"
            } else {
                $m = $_.Exception.Message
                if ($_.Exception.InnerException) { $m += " | Inner: $($_.Exception.InnerException.Message)" }
                if ($m -match "reset|сброс|forcibly|closed|разорвано|failed") { $cell = "RST" }
                elseif ($m -match "certificate|сертификат|remote|success") { $cell = "OK" }
                else { $cell = "DRP" }
            }
        } finally {
            if ($ssl) { try { $ssl.Close() } catch {} }
            if ($conn) { try { $conn.Tcp.Close() } catch {} }
        }
        return [PSCustomObject]@{ Cell = $cell; TimedOut = $timedOut }
    }

    $Result = [PSCustomObject]@{ IP="FAILED"; HTTP="---"; T12="---"; T13="---"; Lat="---"; Verdict="UNKNOWN"; Color="White"; Target=$Target; Number=0 }
    $TO = if ($ProxyConfig.Enabled) { $CONST.ProxyTimeout } else { $CONST.TimeoutMs }
    $httpCap = [int]$CONST.Scan.HttpDirectCapMs
    $HttpTimeoutFast = if ($ProxyConfig.Enabled) { $CONST.ProxyTimeout } else { [Math]::Min($TO, $httpCap) }
    $TlsTimeoutFast  = if ($ProxyConfig.Enabled) { [int]$CONST.Scan.TlsFastMsProxy } else { [int]$CONST.Scan.TlsFastMsDirect }
    $TlsTimeoutRetry = if ($ProxyConfig.Enabled) { [Math]::Max([int]$CONST.Scan.TlsRetryMsProxyFloor, $CONST.ProxyTimeout) } else { [int]$CONST.Scan.TlsRetryMsDirect }

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
            $tcp = Invoke-TcpConnectWithFallback -TargetIp $Result.IP -TargetPort 80 -TimeoutMs $HttpTimeoutFast
            $conn = @{ Tcp = $tcp; Stream = $tcp.GetStream() }
        }
        $Result.Lat = "$($sw.ElapsedMilliseconds)"
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

    $tlsModeRaw = if ($TlsMode) { [string]$TlsMode } else { "Auto" }
    $consider13 = ($tlsModeRaw -notmatch '^(?i)TLS12$')
    $consider12 = ($tlsModeRaw -notmatch '^(?i)TLS13$')

    # 3. TLS Проверки
    $pHost = if ($ProxyConfig.Enabled) { $ProxyConfig.Host } else { "" }
    $pPort = if ($ProxyConfig.Enabled) { [int]$ProxyConfig.Port } else { 0 }

    $parallelTlsHandled = $false
    $t12TimedOut = $false

    if ($consider13 -and $consider12 -and $ParallelTlsFirstPass) {
        try {
            $t13task = [System.Threading.Tasks.Task]::Run({
                [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, $TlsTimeoutFast)
            })
            $t12task = [System.Threading.Tasks.Task]::Run({
                Invoke-Tls12HandshakeOnce -TimeoutMs $TlsTimeoutFast
            })
            [System.Threading.Tasks.Task]::WaitAll(@($t13task, $t12task))
            $parallelOk = (-not $t13task.IsFaulted) -and (-not $t12task.IsFaulted)
            $tr = $null
            $hr = $null
            if ($parallelOk) {
                try { $tr = $t13task.Result } catch { $parallelOk = $false }
                try { $hr = $t12task.Result } catch { $parallelOk = $false }
            }
            if ($parallelOk -and ($null -ne $tr) -and ($null -ne $hr)) {
                $Result.T13 = [string]$tr
                $Result.T12 = [string]$hr.Cell
                $t12TimedOut = [bool]$hr.TimedOut
                $parallelTlsHandled = $true
                Write-DebugLog "TLS: параллельный первый проход T13/T12 завершён" "INFO"
                if ($Result.T13 -eq "DRP") {
                    Write-DebugLog "TLS T13: повтор с увеличенным таймаутом ($TlsTimeoutRetry ms)" "INFO"
                    $retryT13 = [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, $TlsTimeoutRetry)
                    if ($retryT13 -eq "OK" -or $retryT13 -eq "RST") { $Result.T13 = $retryT13 }
                }
            } else {
                Write-DebugLog "TLS: параллельный первый проход не удался, переход на последовательный путь" "WARN"
            }
        } catch {
            Write-DebugLog "TLS: ошибка параллельного первого прохода: $($_.Exception.Message)" "WARN"
        }
    }

    if (-not $parallelTlsHandled) {
        if ($consider13) {
            $Result.T13 = [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, $TlsTimeoutFast)
            Write-DebugLog "TLS T13 : [RAW] Host=$Target Result=$($Result.T13)"
            if ($Result.T13 -eq "DRP") {
                Write-DebugLog "TLS T13: повтор с увеличенным таймаутом ($TlsTimeoutRetry ms)" "INFO"
                $retryT13 = [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, $TlsTimeoutRetry)
                if ($retryT13 -eq "OK" -or $retryT13 -eq "RST") { $Result.T13 = $retryT13 }
            }
        } else {
            $Result.T13 = "N/A"
            Write-DebugLog "TLS T13: пропущено (режим TLS12)"
        }

        if ($consider12) {
            $hFirst = Invoke-Tls12HandshakeOnce -TimeoutMs $TlsTimeoutFast
            $Result.T12 = $hFirst.Cell
            $t12TimedOut = $hFirst.TimedOut
        } else {
            $Result.T12 = "N/A"
            Write-DebugLog "TLS T12: пропущено (режим TLS13)"
        }
    }

    # Retry при timeout T12: в Auto — только если T13 OK; в режиме только TLS12 — всегда при timeout
    $doT12Retry = $t12TimedOut -and $consider12 -and (($consider13 -and $Result.T13 -eq "OK") -or (-not $consider13))
    if ($doT12Retry) {
        Write-DebugLog "TLS T12: retry после timeout ($TlsTimeoutRetry ms)" "INFO"
        $hRetry = Invoke-Tls12HandshakeOnce -TimeoutMs $TlsTimeoutRetry
        $Result.T12 = $hRetry.Cell
    }

    $auxVerdictT13 = $null
    $auxVerdictT12 = $null
    if (-not $consider13) {
        if ($Result.T12 -eq "DRP" -or $Result.T12 -eq "RST") {
            $auxVerdictT13 = [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, $TlsTimeoutFast)
            if ($auxVerdictT13 -eq "DRP") {
                $retryAux = [TlsScanner]::TestT13($Result.IP, $Target, $pHost, $pPort, $ProxyConfig.User, $ProxyConfig.Pass, $TlsTimeoutRetry)
                if ($retryAux -eq "OK" -or $retryAux -eq "RST") { $auxVerdictT13 = $retryAux }
            }
        }
    }
    if (-not $consider12) {
        if ($Result.T13 -eq "DRP" -or $Result.T13 -eq "RST") {
            $hx = Invoke-Tls12HandshakeOnce -TimeoutMs $TlsTimeoutFast
            $auxVerdictT12 = $hx.Cell
            if ($hx.TimedOut) {
                $hx2 = Invoke-Tls12HandshakeOnce -TimeoutMs $TlsTimeoutRetry
                $auxVerdictT12 = $hx2.Cell
            }
        }
    }

    # 4. Логика вердикта (с учётом TlsMode: только 1.2 / только 1.3 / оба)
    if (-not $consider13) {
        if ($null -ne $auxVerdictT13) {
            $vd = Set-Verdict-DualTlsCells -Cell12 $Result.T12 -Cell13 $auxVerdictT13
            $Result.Verdict = $vd.Verdict
            $Result.Color = $vd.Color
        } else {
            if ($Result.T12 -eq "OK") { $Result.Verdict = "AVAILABLE"; $Result.Color = "Green" }
            elseif ($Result.T12 -eq "RST") { $Result.Verdict = "DPI RESET"; $Result.Color = "Red" }
            elseif ($Result.T12 -eq "DRP") { $Result.Verdict = "DPI BLOCK"; $Result.Color = "Red" }
            else { $Result.Verdict = "IP BLOCK"; $Result.Color = "Red" }
        }
        return $Result
    }
    if (-not $consider12) {
        if ($null -ne $auxVerdictT12) {
            $vd = Set-Verdict-DualTlsCells -Cell12 $auxVerdictT12 -Cell13 $Result.T13
            $Result.Verdict = $vd.Verdict
            $Result.Color = $vd.Color
        } else {
            if ($Result.T13 -eq "OK") { $Result.Verdict = "AVAILABLE"; $Result.Color = "Green" }
            elseif ($Result.T13 -eq "RST") { $Result.Verdict = "DPI RESET"; $Result.Color = "Red" }
            elseif ($Result.T13 -eq "DRP") { $Result.Verdict = "DPI BLOCK"; $Result.Color = "Red" }
            else { $Result.Verdict = "IP BLOCK"; $Result.Color = "Red" }
        }
        return $Result
    }

    $vdAuto = Set-Verdict-DualTlsCells -Cell12 $Result.T12 -Cell13 $Result.T13
    $Result.Verdict = $vdAuto.Verdict
    $Result.Color = $vdAuto.Color
    return $Result
}

function Test-ScanRowVisualChanged {
    param($OldRow, $NewRow)
    if ($null -eq $OldRow -or $null -eq $NewRow) { return $true }
    # Latency changes on almost every run; compare stable status fields so repeat scans only repaint meaningful changes.
    $a = "$($OldRow.Number)|$($OldRow.Target)|$($OldRow.IP)|$($OldRow.HTTP)|$($OldRow.T12)|$($OldRow.T13)|$($OldRow.Verdict)|$($OldRow.Color)"
    $b = "$($NewRow.Number)|$($NewRow.Target)|$($NewRow.IP)|$($NewRow.HTTP)|$($NewRow.T12)|$($NewRow.T13)|$($NewRow.Verdict)|$($NewRow.Color)"
    return $a -ne $b
}

# ====================================================================================
# АСИНХРОННОЕ СКАНИРОВАНИЕ
# ====================================================================================
function Start-ScanWithAnimation($Targets, $ProxyConfig, [bool]$PlaceholderRowsVisible = $false) {
    Write-DebugLog "Start-ScanWithAnimation: сбор результатов + водопад (полный / по изменившимся строкам)"
    # Снимок предыдущего скана до перезаписи LastScanResults в вызывающем коде
    $prevSnap = $null
    if ($script:LastScanResults -and $script:LastScanResults.Count -eq $Targets.Count) {
        $prevSnap = @($script:LastScanResults)
    }
    $useFullWaterfall = (-not $script:HasCompletedScan) -or ($null -eq $prevSnap)

    Sync-DynamicColPosFromLayout

    $cpuCount = [Environment]::ProcessorCount
    $poolMin = [int]$CONST.ScanPoolMinWorkers
    $poolDirectMax = [int]$CONST.ScanPoolDirectMax
    $poolProxyMax = [int]$CONST.ScanPoolProxyMax
    $poolCpuMul = [int]$CONST.ScanPoolCpuMultiplier
    $recommendedThreads = [Math]::Max($poolMin, [Math]::Min($poolDirectMax, $cpuCount * $poolCpuMul))
    if ($ProxyConfig.Enabled) {
        $recommendedThreads = [Math]::Min($recommendedThreads, $poolProxyMax)
    }
    $maxThreads = [Math]::Min($Targets.Count, $recommendedThreads)
    Write-DebugLog "Запуск пула потоков: $maxThreads воркеров (CPU=$cpuCount, proxy=$($ProxyConfig.Enabled))."

    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()
    $jobs = [System.Collections.Generic.List[object]]::new()
    $results = New-Object 'object[]' $Targets.Count
    $completedTasks = 0

    for ($i=0; $i -lt $Targets.Count; $i++) {
        $ps = [PowerShell]::Create().AddScript($Worker).
            AddArgument($Targets[$i]).            # 1. $Target
            AddArgument($ProxyConfig).           # 2. $ProxyConfig
            AddArgument($CONST).                 # 3. $CONST
            AddArgument($DebugLogFile).          # 4. $DebugLogFile
            AddArgument([bool](Test-DebugLogEnabled)). # 5. effective debug (env или конфиг)
            AddArgument($script:DnsCache).       # 6. $DnsCache
            AddArgument($script:DnsCacheLock).   # 7. $DnsCacheLock
            AddArgument($script:NetInfo).        # 8. $NetInfo
            AddArgument($script:Config.IpPreference). # 9. $IpPreference
            AddArgument([string]$script:Config.TlsMode). # 10. $TlsMode
            AddArgument([string]$script:DebugLogMutexName). # 11. mutex для записи в общий лог
            AddArgument([bool]($script:Config.ScanParallelTlsFirstPass -eq $true)) # 12. параллельный первый проход TLS

        $ps.RunspacePool = $pool
        [void]$jobs.Add([PSCustomObject]@{
            PowerShell = $ps; Handle = $ps.BeginInvoke(); Index = $i; Number = $i + 1
            Target = $Targets[$i]; DoneInBg = $false; Row = 12 + $i; Result = $null; Revealed = $false
        })
    }

    # Первый скан рисует пустые строки. Повторный скан оставляет прошлые результаты до выборочного водопада.
    Sync-DynamicColPosFromLayout
    if ($useFullWaterfall -and -not $PlaceholderRowsVisible) {
        foreach ($jb in $jobs) {
            $ph = New-PlaceholderResultRow -Number $jb.Number -Target $jb.Target
            Write-ResultLine $jb.Row $ph
        }
    }
    try {
        $script:ScanLayoutSnapW = [Console]::WindowWidth
        $script:ScanLayoutSnapH = [Console]::WindowHeight
    } catch {
        $script:ScanLayoutSnapW = $null
        $script:ScanLayoutSnapH = $null
    }

    $aborted = $false
    $frameCounter = 0
    $animTargetMs = 1000.0 / [double]($CONST.AnimFps)
    $frameSw = [System.Diagnostics.Stopwatch]::StartNew()

    # Троттлинг статус-бара: полная строка не каждый кадр (~30 FPS), чтобы не «дребезжало»
    $scanBarLastMs = [Environment]::TickCount64
    $scanBarLastDone = -9999
    $scanBarLastBucket = -9999
    $uiThrottleCollect = if ($CONST.UiScan -and $null -ne $CONST.UiScan.StatusBarThrottleCollectMs) { [int]$CONST.UiScan.StatusBarThrottleCollectMs } else { 240 }

    # --- ЭТАП 1 ---
    while (-not $aborted) {
        $frameCounter++

        $tcScan = [Math]::Max(1, $Targets.Count)
        $pctScan = $completedTasks / [double]$tcScan
        $resizedScan = Test-ScanPhaseConsoleLayoutChanged
        $nowBar = [Environment]::TickCount64
        $bucketScan = [int]($pctScan * 40)
        if ($resizedScan -or ($completedTasks -ne $scanBarLastDone) -or (($nowBar - $scanBarLastMs) -ge $uiThrottleCollect) -or ($bucketScan -ne $scanBarLastBucket)) {
            $scanBarLastMs = $nowBar
            $scanBarLastDone = $completedTasks
            $scanBarLastBucket = $bucketScan
            Invoke-ScanRedrawIfConsoleResized -LiveResults $results -Targets $Targets -StatusBarMessage "[ SCAN ] Сбор: $completedTasks / $tcScan" -Progress $pctScan
        }

        if ([Console]::KeyAvailable) {
            if ([Console]::ReadKey($true).Key -in @("Q", "Escape")) {
                [Console]::CursorVisible = $false
                try { [Console]::CursorSize = 1 } catch { }
                $aborted = $true; break
            }
        }

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

        if ($completedTasks -ge $Targets.Count) { break }
        $sleepMs = $animTargetMs - $frameSw.Elapsed.TotalMilliseconds
        if ($sleepMs -gt 0.5) { [System.Threading.Thread]::Sleep([int][math]::Floor($sleepMs)) }
        $frameSw.Restart()
    }

    $pool.Close(); $pool.Dispose()
    foreach ($j in $jobs) { try { $j.PowerShell.Dispose() } catch {} }

    # --- ЭТАП 2: «водопад» — первый успешный проход полностью; дальше только задержка на изменившихся строках ---
    if (-not $aborted) {
        $totalCount = $Targets.Count
        $frameCounter = 0
        $revealFps = [double]$CONST.AnimFps
        if ($CONST.UiScan -and ($null -ne $CONST.UiScan.RevealAnimFps)) {
            try {
                $ri = [int]$CONST.UiScan.RevealAnimFps
                if ($ri -gt 0) { $revealFps = [double]$ri }
            } catch { }
        }
        $animTargetMs = 1000.0 / $revealFps
        $frameSw.Restart()
        $revealBarLastMs = [Environment]::TickCount64
        $revealBarLastI = -9999
        $revealBarLastBucket = -9999
        $uiThrottleReveal = if ($CONST.UiScan -and $null -ne $CONST.UiScan.StatusBarThrottleRevealMs) { [int]$CONST.UiScan.StatusBarThrottleRevealMs } else { 280 }

        for ($i = 0; $i -lt $totalCount; $i++) {
            $frameCounter++

            $pctReveal = ($i + 1) / [double][Math]::Max(1, $totalCount)
            $resizedReveal = Test-ScanPhaseConsoleLayoutChanged
            $nowRv = [Environment]::TickCount64
            $bucketRv = [int]($pctReveal * 40)
            if ($resizedReveal -or ($i -ne $revealBarLastI) -or (($nowRv - $revealBarLastMs) -ge $uiThrottleReveal) -or ($bucketRv -ne $revealBarLastBucket)) {
                $revealBarLastMs = $nowRv
                $revealBarLastI = $i
                $revealBarLastBucket = $bucketRv
                Invoke-ScanRedrawIfConsoleResized -LiveResults $results -Targets $Targets -StatusBarMessage "[ SCAN ] Раскрытие: $($i+1) / $totalCount" -Progress $pctReveal
            }

            $j = $jobs[$i]
            $res = $results[$i]

            if ($null -eq $res) {
                $res = [PSCustomObject]@{
                    Target=$j.Target; Number=$j.Number; IP="ERR"; HTTP="---";
                    T12="---"; T13="---"; Lat="---"; Verdict="TIMEOUT"; Color="Red"
                }
                $results[$i] = $res
            }

            $rowChanged = $true
            if (-not $useFullWaterfall -and $prevSnap -and $i -lt $prevSnap.Count) {
                $rowChanged = Test-ScanRowVisualChanged -OldRow $prevSnap[$i] -NewRow $res
            }

            if ($useFullWaterfall -or $rowChanged) {
                Write-ResultLine $j.Row $res
                $sleepMs = $animTargetMs - $frameSw.Elapsed.TotalMilliseconds
                if ($sleepMs -gt 0.5) { [System.Threading.Thread]::Sleep([int][math]::Floor($sleepMs)) }
            }
            else {
                Write-ResultLatency $j.Row $res
            }
            $frameSw.Restart()
        }

        $script:HasCompletedScan = $true
        Draw-StatusBar
    }

    # Обновляем NetInfo только при необходимости

    $currentISP = $script:NetInfo.ISP
    $currentLOC = $script:NetInfo.LOC
    $cacheAge = (Get-Date).Ticks - $script:NetInfo.TimestampTicks
    $ageMinutes = [TimeSpan]::FromTicks($cacheAge).TotalMinutes

    $needUpdate = $false
    if ($ageMinutes -gt 30) {
        Write-DebugLog "NetInfo устарел (${ageMinutes} мин), обновляем"
        $needUpdate = $true
    }
    if ($currentISP -eq "Loading..." -or $currentISP -eq "Detecting..." -or $currentISP -eq "Unknown") {
        Write-DebugLog "ISP не определён, обновляем"
        $needUpdate = $true
    }
    if ($currentISP -eq "Background update" -or $currentLOC -eq "Next scan") {
        Write-DebugLog "ISP временный (фон), обновляем"
        $needUpdate = $true
    }

    if ($needUpdate) {
        Write-DebugLog "Запуск синхронного обновления NetInfo..."
        Draw-StatusBar -Message "[ NET ] Обновление информации о сети..." -Fg "Black" -Bg "Cyan"

        $newNetInfo = Get-NetworkInfo

        # Проверяем, что новое значение не хуже старого
        if ($newNetInfo.ISP -ne "Unknown" -and $newNetInfo.ISP -ne "Loading...") {
            $script:NetInfo = $newNetInfo
            $null = Set-NetInfoCacheIfUsable $newNetInfo
            Save-Config $script:Config

            # Обновляем только строку с ISP в UI (без полной перерисовки)
            $ispStr = "> ISP / LOC: $($newNetInfo.ISP) ($($newNetInfo.LOC))"
            if ($ispStr.Length -gt 70) { $ispStr = $ispStr.Substring(0, 67) + "..." }
            [Console]::CursorVisible = $false
            Out-Str 65 6 ($ispStr.PadRight(70)) "Magenta"

            Write-DebugLog "NetInfo обновлён: ISP=$($newNetInfo.ISP), LOC=$($newNetInfo.LOC)"
        } else {
            Write-DebugLog "Новые данные не лучше старых, оставляем текущий ISP: $currentISP"
        }

        Draw-StatusBar
    } else {
        Write-DebugLog "NetInfo актуален, пропускаем обновление (ISP=$currentISP, возраст=${ageMinutes} мин)"
    }

    # Ложный IPv6: только если скан завершён полностью и каждая строка — IP BLOCK или UNKNOWN
    $resolved = @($results | Where-Object { $_ })
    $nonIpBlock = @($resolved | Where-Object { $_.Verdict -ne "IP BLOCK" -and $_.Verdict -ne "UNKNOWN" })
    $allIpBlock = (-not $aborted) -and ($resolved.Count -gt 0) -and ($resolved.Count -eq $results.Count) -and ($nonIpBlock.Count -eq 0)
    if ($allIpBlock -and $script:NetInfo.HasIPv6 -eq $true) {
        Write-DebugLog "Все тесты дали IP BLOCK, но HasIPv6=true. Переключаем HasIPv6 в false." "WARN"
        $script:NetInfo.HasIPv6 = $false
        if ($script:Config.NetCache) { $script:Config.NetCache.HasIPv6 = $false }
        Save-Config $script:Config
        if ($script:DnsCacheLock.WaitOne(1000)) {
            $toRemove = @()
            foreach ($key in $script:DnsCache.Keys) {
                if ($script:DnsCache[$key] -match ':') { $toRemove += $key }
            }
            foreach ($key in $toRemove) { $script:DnsCache.Remove($key) }
            [void]$script:DnsCacheLock.ReleaseMutex()
        }
    }

    # Обновляем ширину IP колонки на основе реальных результатов
    if ($results) {
        $maxIp = ($results | ForEach-Object {
            if ($_.IP -and $_.IP -ne "[ PROXIED ]") { $_.IP.Length } else { 16 }
        } | Measure-Object -Maximum).Maximum
        $script:IpColumnWidth = [Math]::Max($maxIp, 16)
    }

    Sync-DynamicColPosFromLayout
    $script:ScanLayoutSnapW = $null
    $script:ScanLayoutSnapH = $null
    Update-UiConsoleSnapshot
    return [PSCustomObject]@{ Results = $results; Aborted = $aborted }
}

function Sync-DnsCacheFromConfig {
    $script:DnsCache = [hashtable]::Synchronized(@{})
    if ($script:Config.DnsCache -and $script:Config.DnsCache.PSObject) {
        foreach ($prop in $script:Config.DnsCache.PSObject.Properties) {
            if ($prop.MemberType -eq "NoteProperty") { $script:DnsCache[$prop.Name] = $prop.Value }
        }
    }
}

function Test-InternetAvailable {
    $internetAvailable = $false
    try {
        # Самый быстрый тест - ping до 8.8.8.8
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send("8.8.8.8", 1000)
        $internetAvailable = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
        $ping.Dispose()
    } catch {
        # Если ping не работает, пробуем TCP
        try {
            $tcpTest = New-Object System.Net.Sockets.TcpClient
            $async = $tcpTest.BeginConnect("8.8.8.8", 53, $null, $null)
            if ($async.AsyncWaitHandle.WaitOne(1000)) {
                $tcpTest.EndConnect($async)
                $internetAvailable = $true
            }
            $tcpTest.Close()
        } catch { $internetAvailable = $false }
    }
    return $internetAvailable
}

function Start-QuickNetInfoUpdater {
    param([double]$AgeMinutes)

    Write-DebugLog "Кэш устарел ($([math]::Round($AgeMinutes,1)) мин), запускаем фоновое обновление" "INFO"

    # Запускаем обновление в фоне (не блокируем скан!) — отдельный процесс PS, чтобы не грузить процесс UI
    $existing = Get-Job -Name "NetInfoUpdater" -ErrorAction SilentlyContinue
    if ($existing) {
        try { Stop-Job $existing -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $existing -Force -ErrorAction SilentlyContinue } catch {}
    }

    Start-Job -Name "NetInfoUpdater" -ScriptBlock {
        param($configDir, $debugLog, $userAgent, $mutexName, $mutexWaitMs)

        function Write-BgLog($msg) {
            $line = "[$(Get-Date -Format 'HH:mm:ss')] [BG] $msg`r`n"
            $mtx = $null
            $got = $false
            try {
                try { $mtx = if ($mutexName) { [System.Threading.Mutex]::OpenExisting($mutexName) } else { $null } } catch { $mtx = $null }
                if ($mtx) { try { $got = $mtx.WaitOne([int]$mutexWaitMs) } catch { $got = $false } }
                if ($got) {
                    [System.IO.File]::AppendAllText($debugLog, $line, [System.Text.Encoding]::UTF8)
                } else {
                    try { [System.IO.File]::AppendAllText($debugLog, $line, [System.Text.Encoding]::UTF8) } catch { }
                }
            } catch { }
            finally {
                if ($got -and $mtx) { try { [void]$mtx.ReleaseMutex() } catch { } }
                if ($mtx) { try { $mtx.Dispose() } catch { } }
            }
        }

        Write-BgLog "Фоновое обновление NetInfo начато"

        # Быстрое получение DNS
        $dns = "UNKNOWN"
        try {
            $wmi = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" |
                Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
            if ($wmi) { $dns = $wmi.DNSServerSearchOrder[0] }
        } catch {}

        # 2. Локальный CDN через redirector (ИСПРАВЛЕННАЯ версия)
        $cdn = "manifest.googlevideo.com"  # fallback
        try {
            $rnd = [guid]::NewGuid().ToString().Substring(0,8)
            $redirectorUrl = "http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd"

            Write-BgLog "Запрос локального CDN: $redirectorUrl"

            $req = [System.Net.WebRequest]::Create($redirectorUrl)
            $req.Timeout = 3000
            if ($userAgent) { $req.UserAgent = $userAgent }

            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $raw = $reader.ReadToEnd()
            $resp.Close()

            Write-BgLog "Ответ redirector: [$raw]"

            # НОВЫЙ, более надежный парсинг
            # Пример ответа: " => r1.freedom-voz3.googlevideo.com"
            # Или: "=> r1.freedom-voz3.googlevideo.com"
            # Или: "=> r1-123.googlevideo.com"

            $cdnShort = $null
            if ($raw -match '=>\s+([\w-]+)') {
                $cdnShort = $matches[1]
            }

            if ($cdnShort -and $cdnShort -ne 'r1') {
                # как в tools/cdn-tester.bat: => <short>  -> r1.<short>.googlevideo.com
                $cdn = "r1.$cdnShort.googlevideo.com"
                Write-BgLog "Найден локальный CDN (короткая форма): $cdn"
            }
            elseif ($raw -match '=>\s*([a-zA-Z0-9.\-]+\.googlevideo\.com)') {
                $cdn = $matches[1]
                Write-BgLog "Найден локальный CDN (full domain): $cdn"
            }
            else {
                Write-BgLog "Не удалось распарсить ответ, используем fallback: $cdn"
            }

        } catch {
            Write-BgLog "CDN определение не удалось: $($_.Exception.Message)"
            $cdn = "manifest.googlevideo.com"
        }

        # Финальная очистка - только чистое значение
        $cdn = $cdn.Trim()
        Write-BgLog "Финальный CDN: '$cdn'"

        # Дополнительная очистка - убираем пробелы и дубликаты
        $cdn = ($cdn -split '\s+')[0]  # Берем только первое слово, если вдруг их несколько

        # GEO из кэша (не обновляем, чтобы не тратить время)
        $isp = "Background update"
        $loc = "Next scan"

        # IPv6
        $hasV6 = $false
        try {
            $t = New-Object System.Net.Sockets.TcpClient([System.Net.Sockets.AddressFamily]::InterNetworkV6)
            $a = $t.BeginConnect("ipv6.google.com", 80, $null, $null)
            if ($a.AsyncWaitHandle.WaitOne(1000)) {
                $t.EndConnect($a)
                $hasV6 = $true
            }
            $t.Close()
        } catch {}

        $result = @{
            DNS = $dns
            CDN = $cdn
            ISP = $isp
            LOC = $loc
            TimestampTicks = (Get-Date).Ticks
            HasIPv6 = $hasV6
        }

        # Сохраняем в файл конфига
        $configFile = Join-Path $configDir "YT-DPI_config.json"
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($config.NetCache) {
                    $config.NetCache.DNS = $result.DNS
                    $config.NetCache.CDN = $result.CDN
                    $config.NetCache.TimestampTicks = $result.TimestampTicks
                    $config.NetCache.HasIPv6 = $result.HasIPv6
                } else {
                    $config.NetCache = $result
                }
                $config | ConvertTo-Json -Depth 5 -Compress | Set-Content $configFile -Encoding UTF8 -Force
                Write-BgLog "NetInfo network fields updated in config"
            } catch { Write-BgLog "Ошибка сохранения: $_" }
        }

        Write-BgLog "Фоновое обновление завершено"
        return $result
    } -ArgumentList $script:ConfigDir, $DebugLogFile, $script:UserAgent, $script:DebugLogMutexName, [int]$CONST.Mutex.WaitMs | Out-Null
}

function Update-TargetsBeforeScan {
    # Используем кэш только если это не заглушка Loading/Unknown.
    if (Test-NetInfoUsable $script:Config.NetCache) {
        $script:NetInfo = $script:Config.NetCache
    }

    # Проверяем, не пора ли обновить кэш в фоне
    $cacheAge = (Get-Date).Ticks - $script:NetInfo.TimestampTicks
    $ageMinutes = [TimeSpan]::FromTicks($cacheAge).TotalMinutes

    if ($ageMinutes -gt 10 -or -not (Test-NetInfoUsable $script:NetInfo)) {
        Start-QuickNetInfoUpdater -AgeMinutes $ageMinutes
    } else {
        Write-DebugLog "Используем свежий кэш (возраст: $([math]::Round($ageMinutes,1)) мин)" "INFO"
    }

    # === БЫСТРОЕ ОБНОВЛЕНИЕ ТАРГЕТОВ ===
    $NewTargets = Get-Targets -NetInfo $script:NetInfo
    $oldTargetsKey = if ($script:Targets) { (@($script:Targets) -join "`n") } else { "" }
    $newTargetsKey = if ($NewTargets) { (@($NewTargets) -join "`n") } else { "" }
    $NeedClear = ($NewTargets.Count -ne $script:Targets.Count)
    $NeedTableRefresh = $NeedClear -or ($oldTargetsKey -ne $newTargetsKey)
    $script:Targets = $NewTargets

    # Сохраняем предыдущие результаты на экране до старта сбора (строки «обнулятся» внутри Start-Scan)
    $rowsBeforeScan = if (-not $NeedTableRefresh -and $script:LastScanResults -and $script:LastScanResults.Count -eq $script:Targets.Count) {
        $script:LastScanResults
    } else { $null }

    return [PSCustomObject]@{ NeedClear = $NeedClear; NeedTableRefresh = $NeedTableRefresh; RowsBeforeScan = $rowsBeforeScan }
}

function Update-NetInfoFromCompletedJob {
    $bgJob = Get-Job -Name "NetInfoUpdater" -ErrorAction SilentlyContinue
    if ($bgJob -and $bgJob.State -eq "Completed") {
        $newNetInfo = Receive-Job $bgJob
        Remove-Job $bgJob
        $script:NetInfoUpdating = $false
        if ($newNetInfo -and (Test-NetInfoUsable $newNetInfo)) {
            Write-DebugLog "NetInfo обновлен в фоне, обновляем UI" "INFO"
            $null = Set-NetInfoCacheIfUsable $newNetInfo
            $oldTargetsKey = if ($script:Targets) { (@($script:Targets) -join "`n") } else { "" }
            $script:NetInfo = $newNetInfo
            $script:Targets = Get-Targets -NetInfo $script:NetInfo
            $newTargetsKey = if ($script:Targets) { (@($script:Targets) -join "`n") } else { "" }
            Save-Config $script:Config
            if (-not $script:HasCompletedScan) {
                if ($oldTargetsKey -ne $newTargetsKey) {
                    Draw-UI $script:NetInfo $script:Targets $null $false
                } else {
                    Update-NetInfoPanel $script:NetInfo
                }
                Draw-StatusBar
                return
            }
            Update-NetInfoPanel $script:NetInfo
        }
    }
}

function Save-ScanReport {
    Write-DebugLog "Сохранение отчёта"
    Draw-StatusBar -Message "[ WAIT ] SAVING RESULTS TO FILE..." -Fg "Black" -Bg "Cyan"
    $logPath = Join-Path -Path (Get-Location).Path -ChildPath "YT-DPI_Report.txt"

    $logContent = "=== YT-DPI REPORT ===`r`n"
    $logContent += "TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
    $logContent += "ISP:  $($script:NetInfo.ISP) ($($script:NetInfo.LOC))`r`n"
    $logContent += "DNS:  $($script:NetInfo.DNS)`r`n"
    $logContent += "PROXY: $(if($global:ProxyConfig.Enabled) {"$($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)"} else {"OFF"})`r`n"
    $logContent += "-" * 90 + "`r`n"
    $logContent += "{0,-38} {1,-16} {2,-6} {3,-8} {4,-8} {5,-6} {6}`r`n" -f "TARGET DOMAIN", "IP ADDRESS", "HTTP", "TLS 1.2", "TLS 1.3", "LAT (ms)", "RESULT"
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
}

function Invoke-TraceAction {
            Write-DebugLog "Глубокий анализ хоста"

            # Получаем строку статуса
            $row = Get-FeedbackRow -count $script:Targets.Count
            $width = [Console]::WindowWidth

            # ПОЛНОСТЬЮ очищаем строку статуса (от начала до конца)
            Write-StatusLine -Row $row -Message "" -Fg "White" -Bg "Black"

            # Выводим сообщение с ярким фоном
            $promptMsg = "[ TRACE ] Enter domain number (1..$($script:Targets.Count)): "

            # Читаем ввод
            $input = Read-StatusBarNumberInput -Row $row -Prompt $promptMsg
            $row = Get-FeedbackRow -count $script:Targets.Count
            [Console]::CursorVisible = $false
            [Console]::ForegroundColor = "White"
            [Console]::BackgroundColor = "Black"

            # Очищаем строку перед следующим сообщением
            Write-StatusLine -Row $row -Message "" -Fg "White" -Bg "Black"

            $idx = 0
            if ([int]::TryParse($input, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:Targets.Count) {
                $target = $script:Targets[$idx-1]

                # Показываем сообщение о начале трассировки
                $traceMsg = "[ TRACE ] Tracing #$idx - $target ... press ESC to cancel"
                Write-StatusLine -Row $row -Message $traceMsg -Fg "White" -Bg "DarkCyan"

                # Выполняем трассировку
                $aborted = $false
                $trace = $null
                $progressRow = Get-FeedbackRow -count $script:Targets.Count

                # Функция обновления статуса во время трассировки
                $progressBlock = {
                    param($message)
                    if (Test-UiConsoleLayoutChanged) {
                        $null = Invoke-FullUiRedrawIfConsoleResized
                        $progressRow = Get-FeedbackRow -count $script:Targets.Count
                    }
                    # Обновляем статус-бар с сообщением
                    Write-StatusLine -Row $progressRow -Message $message -Fg "White" -Bg "DarkCyan"
                    # Дополнительно проверяем прерывание извне (флаг $aborted)
                }

                try {
                    $trace = Trace-TcpRoute -Target $target -Port 443 -MaxHops 15 -TimeoutSec 5 -onProgress $progressBlock
                } catch {
                    Write-DebugLog "Invoke-TraceAction: Trace-TcpRoute: $_" "ERROR"
                    $trace = @()
                }
                $row = Get-FeedbackRow -count $script:Targets.Count

                # Очищаем строку перед результатом
                Write-StatusLine -Row $row -Message "" -Fg "White" -Bg "Black"
                $bgColor = "DarkGray"

                if ($trace -is [string]) {
                    $resultMsg = "[ TRACE ] $($target): $trace"
                    $bgColor = "DarkRed"
                    Write-StatusLine -Row $row -Message $resultMsg -Fg "White" -Bg "DarkRed"
                } elseif ($trace.Count -eq 0) {
                    $resultMsg = "[ TRACE ] $($target): No hops found"
                    $bgColor = "DarkRed"
                    Write-StatusLine -Row $row -Message $resultMsg -Fg "White" -Bg "DarkRed"
                } else {
                    # Анализируем результат
                    $firstResponsive = $trace | Where-Object { $_.TcpStatus -eq "SYNACK" -or $_.TcpStatus -eq "RST" } | Select-Object -First 1
                    $lastHop = $trace[-1]
                    $timeoutHopsAll = $trace | Where-Object { $_.TcpStatus -eq "Timeout" -or $_.TcpStatus -eq "TIMEOUT" }
                    # Таймаут только на последнем TTL — обычно «нет ответа до дедлайна», а не блокировка на середине пути
                    $timeoutHopsMidPath = $timeoutHopsAll | Where-Object { $_.Hop -ne $lastHop.Hop }
                    $errorHops = $trace | Where-Object { $_.TcpStatus -eq "Error" -or $_.TcpStatus -eq "ERROR" }

                    $resultMsg = ""
                    $bgColor = "DarkGray"

                    if ($firstResponsive) {
                        if ($firstResponsive.TcpStatus -eq "RST") {
                            $resultMsg = "[ TRACE ] $($target): RST at hop $($firstResponsive.Hop) ($($firstResponsive.IP)) - DPI blocking"
                            $bgColor = "DarkRed"
                        } elseif ($firstResponsive.TcpStatus -eq "SYNACK") {
                            $resultMsg = "[ TRACE ] $($target): TCP OK at hop $($firstResponsive.Hop) ($($firstResponsive.IP))"
                            $bgColor = "DarkGreen"
                        }
                    } elseif ($timeoutHopsMidPath.Count -gt 0) {
                        $firstTimeout = $timeoutHopsMidPath | Select-Object -First 1
                        $resultMsg = "[ TRACE ] $($target): Timeout at hop $($firstTimeout.Hop) ($($firstTimeout.IP)) - connection blocked"
                        $bgColor = "DarkYellow"
                    } elseif ($timeoutHopsAll.Count -gt 0) {
                        $resultMsg = "[ TRACE ] $($target): hop $($lastHop.Hop) ($($lastHop.IP)) — нет TCP-ответа к дедлайну"
                        $bgColor = "DarkGray"
                    } elseif ($errorHops.Count -gt 0) {
                        $firstError = $errorHops | Select-Object -First 1
                        $resultMsg = "[ TRACE ] $($target): Refused at hop $($firstError.Hop) ($($firstError.IP))"
                        $bgColor = "DarkRed"
                    } else {
                        $resultMsg = "[ TRACE ] $($target): No TCP responses"
                        $bgColor = "DarkGray"
                    }

                    Write-StatusLine -Row $row -Message $resultMsg -Fg "White" -Bg $bgColor

                    # Детальный вывод в лог
                    Write-DebugLog "=== Trace results for $target ==="
                    foreach ($hop in $trace) {
                        $ts = [string]$hop.TcpStatus
                        if ($hop.Hop -eq $lastHop.Hop -and ($ts -eq "TIMEOUT" -or $ts -eq "Timeout")) {
                            Write-DebugLog "Hop $($hop.Hop): $($hop.IP) -> TCP: NO_REPLY (дедлайн на последнем TTL, не mid-path timeout), RTT=$($hop.RttMs)ms"
                        } else {
                            Write-DebugLog "Hop $($hop.Hop): $($hop.IP) -> TCP: $ts, RTT=$($hop.RttMs)ms"
                        }
                    }
                }

                $hintMsg = " [ ENTER/ESC ] return"
                $fullMsg = $resultMsg + $hintMsg
                if ($fullMsg.Length -lt $width - 2) {
                    Write-StatusLine -Row $row -Message $fullMsg -Fg "White" -Bg $bgColor
                }

                while ($true) {
                    if (Test-UiConsoleLayoutChanged) {
                        $null = Invoke-FullUiRedrawIfConsoleResized
                        $row = Get-FeedbackRow -count $script:Targets.Count
                        Write-StatusLine -Row $row -Message $fullMsg -Fg "White" -Bg $bgColor
                    }
                    if ([Console]::KeyAvailable) {
                        $traceKey = [Console]::ReadKey($true).Key
                        if ($traceKey -in @("Enter", "Escape", "Spacebar")) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }

                Write-StatusLine -Row $row -Message "" -Fg "White" -Bg "Black"
                Draw-StatusBar
                Clear-KeyBuffer
                return
            } else {
                # Ошибка ввода
                $errorMsg = "[ ERROR ] Invalid number. Use 1..$($script:Targets.Count)"
                Write-StatusLine -Row $row -Message $errorMsg -Fg "White" -Bg "DarkRed"

                while ($true) {
                    if (Test-UiConsoleLayoutChanged) {
                        $null = Invoke-FullUiRedrawIfConsoleResized
                        $row = Get-FeedbackRow -count $script:Targets.Count
                        Write-StatusLine -Row $row -Message $errorMsg -Fg "White" -Bg "DarkRed"
                    }
                    if ([Console]::KeyAvailable) {
                        $traceKey = [Console]::ReadKey($true).Key
                        if ($traceKey -in @("Enter", "Escape", "Spacebar")) { break }
                    }
                    Start-Sleep -Milliseconds 50
                }

                Write-StatusLine -Row $row -Message "" -Fg "White" -Bg "Black"
                Draw-StatusBar
                Clear-KeyBuffer
                return
            }

}

function Get-MainTableResults {
    if ($script:LastScanResults -and $script:Targets -and $script:LastScanResults.Count -eq $script:Targets.Count) {
        return $script:LastScanResults
    }
    return $null
}

function Invoke-HelpAction {
    Write-DebugLog "Показ справки"
    Show-HelpMenu
    Draw-UI $script:NetInfo $script:Targets (Get-MainTableResults) $true
    Draw-StatusBar
    Clear-KeyBuffer  # Очищаем после меню
}

function Invoke-UpdateAction {
    Write-DebugLog "Запуск обновления"
    Invoke-Update -Repo "Shiperoid/YT-DPI" -Config $script:Config

    # Вместо полной перерисовки Draw-UI просто восстанавливаем статус-бар
    Draw-StatusBar
    Clear-KeyBuffer
}

function Invoke-ProxyMenuAction {
    Write-DebugLog "Открыто меню прокси"
    $proxyCtxBefore = Get-GeoProxyKey
    Show-ProxyMenu
    if ((Get-GeoProxyKey) -ne $proxyCtxBefore) {
        $newNetInfo = Get-NetworkInfo
        if (Test-NetInfoUsable $newNetInfo) {
            $script:NetInfo = $newNetInfo
            $null = Set-NetInfoCacheIfUsable $script:NetInfo
        }
        Save-Config $script:Config
        $script:Targets = Get-Targets -NetInfo $script:NetInfo
    }
    Draw-UI $script:NetInfo $script:Targets (Get-MainTableResults) $true
    Draw-StatusBar
    Clear-KeyBuffer  # Очищаем после меню
}

function Invoke-SettingsAction {
    Write-DebugLog "Открыты настройки"
    Show-SettingsMenu
    Draw-UI $script:NetInfo $script:Targets (Get-MainTableResults) $true
    Draw-StatusBar
}

function Invoke-ScanAction {
    Write-DebugLog "Запуск сканирования по Enter (ULTRA-FAST MODE)"

    # === МГНОВЕННАЯ ПРОВЕРКА ИНТЕРНЕТА ===
    Draw-StatusBar -Message "[ CHECK ] Проверка интернета..." -Fg "Black" -Bg "Cyan"
    if (-not (Test-InternetAvailable)) {
        Draw-StatusBar -Message "[ ERROR ] НЕТ ИНТЕРНЕТА! ПРОВЕРЬТЕ ПОДКЛЮЧЕНИЕ." -Fg "Black" -Bg "Red"
        Start-Sleep -Seconds 3
        Draw-StatusBar
        Clear-KeyBuffer
        return
    }

    # === МГНОВЕННАЯ ЗАГРУЗКА NETINFO (ИЗ КЭША) ===
    Draw-StatusBar -Message "[ CACHE ] Загрузка сетевых данных..." -Fg "Black" -Bg "Cyan"
    $scanPrep = Update-TargetsBeforeScan

    # === ОБНОВЛЕНИЕ ТАБЛИЦЫ ТОЛЬКО ЕСЛИ ИЗМЕНИЛИСЬ ЦЕЛИ/РАЗМЕР ===
    $placeholderRowsVisible = $false
    if ($scanPrep.NeedTableRefresh) {
        $rowsForDraw = $scanPrep.RowsBeforeScan
        if ($null -eq $rowsForDraw -and -not $script:HasCompletedScan) {
            $rowsForDraw = New-PlaceholderResultRows -Targets $script:Targets
            $placeholderRowsVisible = $true
        }
        Draw-UI $script:NetInfo $script:Targets $rowsForDraw $scanPrep.NeedClear
    }
    elseif (-not $script:HasCompletedScan) {
        $placeholderRowsVisible = $true
    }

    # === ЛЕНИВАЯ ЗАГРУЗКА TLS ENGINE ===
    if (-not (Test-TlsScannerReady) -and -not $script:TlsScannerLoadFailed) {
        Draw-StatusBar -Message "[ ENGINE ] Loading TLS scanner..." -Fg "Black" -Bg "Yellow"
    }
    if (-not (Ensure-TlsScannerLoaded)) {
        Draw-StatusBar -Message "[ ERROR ] TLS scanner failed to load. Scan cancelled." -Fg "White" -Bg "Red"
        Start-Sleep -Seconds 3
        Draw-StatusBar
        return
    }

    # === МГНОВЕННЫЙ СТАРТ СКАНА ===
    Draw-StatusBar -Message "[ SCAN ] Запуск сканирования..." -Fg "Black" -Bg "Green"
    Start-Sleep -Milliseconds 200  # Минимальная пауза для визуального отклика

    # Запускаем асинхронный скан
    $scanResult = Start-ScanWithAnimation $script:Targets $global:ProxyConfig $placeholderRowsVisible
    $script:LastScanResults = $scanResult.Results
    Sync-DynamicColPosFromLayout
    Update-UiConsoleSnapshot

    # === ФИНИШ ===
    Start-Sleep -Milliseconds 400

    if ($scanResult.Aborted) {
        Draw-StatusBar -Message "[ ABORTED ] Скан прерван. Нажмите ENTER для продолжения..." -Fg "Black" -Bg "Red"
    } else {
        Update-NetInfoFromCompletedJob
        Draw-StatusBar -Message "[ SUCCESS ] Скан завершен!" -Fg "Black" -Bg "Green"
    }

    Start-Sleep -Seconds 2
    Draw-StatusBar
    Clear-KeyBuffer
}

# ====================================================================================
# ГЛАВНЫЙ ЦИКЛ ПРОГРАММЫ (ENGINE START)
# ====================================================================================

function Initialize-AppState {
# 1. Загрузка конфигурации (Мгновенно)
$script:Config = Load-Config
$global:ProxyConfig = $script:Config.Proxy
Write-DebugLogSessionHeaderIfNeeded
$script:Config.RunCount++

# 2. Синхронизация DNS кэша
Sync-DnsCacheFromConfig
Initialize-DisableBrokenParallelTlsTasks

# 3. Выбираем готовые данные из завершённого фонового обновления/кэша или единую заглушку
$script:NetInfo = Get-ReadyNetInfo
$script:Targets = Get-Targets -NetInfo $script:NetInfo
[Console]::Clear()
Draw-UI $script:NetInfo $script:Targets $null $false
Draw-StatusBar
Initialize-ScannerEngines


# 4. Обновление сети запускаем после первого экрана; результат применится точечно.
if ($script:Config.NetCacheStale -or $script:Config.RunCount -le 1 -or -not (Test-NetInfoUsable $script:NetInfo)) {
    Start-BackgroundNetInfoUpdate
}

# 5. Проверка обновлений (только раз в 10 запусков, чтобы не бесить)
if ($script:Config.RunCount % 10 -eq 0) {
    $newVer = Check-UpdateVersion -Repo "Shiperoid/YT-DPI" -LastCheckedVersion $script:Config.LastCheckedVersion
    if ($newVer) {
        Draw-StatusBar -Message "[ UPDATE ] NEW VERSION v$newVer AVAILABLE! PRESS 'U' TO UPDATE." -Fg "White" -Bg "DarkMagenta"
        Start-Sleep -Seconds 3
    }
}

Draw-StatusBar
Write-DebugLog "--- СИСТЕМА ГОТОВА ---" "INFO"
Clear-KeyBuffer
$FirstRun = $false

}

function Start-MainLoop {
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


    $k = Read-MainLoopKey
    [Console]::CursorVisible = $false
    try { [Console]::CursorSize = 1 } catch { }

    $null = Invoke-FullUiRedrawIfConsoleResized

        if ($k -eq "Q" -or $k -eq "Escape") {
            Stop-Script
        }
        elseif ($k -eq "H") {
            Invoke-HelpAction
            continue
        }
        elseif ($k -eq "D") {
            Invoke-TraceAction
            continue
        }
        elseif ($k -eq "U") {
            Invoke-UpdateAction
            continue
        }
        elseif ($k -eq "P") {
            Invoke-ProxyMenuAction
            continue
        }
        elseif ($k -eq "S") {
            Invoke-SettingsAction
            continue
        }

        elseif ($k -eq "R") {
            Save-ScanReport
            continue
        }

        # Обработка Enter
        if ($k -eq "Enter") {
            Invoke-ScanAction
            continue
        }
}
}

Initialize-AppState
Start-MainLoop
