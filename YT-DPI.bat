<# :
@echo off
set "SCRIPT_PATH=%~f0"
title YT-DPI v2.1.4
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::UTF8))"
exit /b
#>
$script:OriginalFilePath = [System.Environment]::GetEnvironmentVariable("SCRIPT_PATH", "Process")
if (-not $script:OriginalFilePath) { $script:OriginalFilePath = $MyInvocation.MyCommand.Path }
if (-not $script:OriginalFilePath) { $script:OriginalFilePath = $MyInvocation.InvocationName }
$ErrorActionPreference = "SilentlyContinue"
$script:CurrentWindowWidth = 0
$script:CurrentWindowHeight = 0
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::CursorVisible = $false
$ErrorActionPreference = "Continue"
$DebugPreference = "SilentlyContinue"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
[System.Net.ServicePointManager]::DefaultConnectionLimit = 100

$scriptVersion = "2.1.4"   # текущая версия yt-dpi
# ===== ОТЛАДКА =====
$DEBUG_ENABLED = $false
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
            $retries--
            if ($retries -eq 0) { break }
            Start-Sleep -Milliseconds 50
        }
        finally {
            [System.Threading.Monitor]::Exit($script:LogLock)
        }
    }
}

Write-DebugLog "==================== СКРИПТ ЗАПУЩЕН ====================" "INFO"
Write-DebugLog "Версия PowerShell: $($PSVersionTable.PSVersion)" "INFO"
Write-DebugLog "ОС: $([System.Environment]::OSVersion.VersionString)" "INFO"
Write-DebugLog "Командная строка: $([Environment]::CommandLine)" "INFO"

Write-DebugLog "Путь к скрипту: $script:OriginalFilePath"
# РОТАЦИЯ ЛОГА ПРИ ЗАПУСКЕ (если превышен лимит 5 МБ)
$maxLogSizeBytes = 5 * 1024 * 1024   # 5 МБ
if (Test-Path $DebugLogFile) {
    try {
        $fileInfo = Get-Item $DebugLogFile -ErrorAction SilentlyContinue
        if ($fileInfo.Length -gt $maxLogSizeBytes) {
            $backupName = [System.IO.Path]::GetFileNameWithoutExtension($DebugLogFile) + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log"
            $backupPath = Join-Path (Split-Path $DebugLogFile -Parent) $backupName
            Move-Item $DebugLogFile $backupPath -Force
            # Создаём новый пустой файл (необязательно, т.к. AppendAllText создаст, но для ясности)
            New-Item $DebugLogFile -ItemType File -Force | Out-Null
            Write-DebugLog "Старый лог превышал $maxLogSizeBytes байт, переименован в $backupName" "INFO"
        } else {
            # Файл маленький — просто удаляем, чтобы начать чистый лог
            Remove-Item $DebugLogFile -Force -ErrorAction SilentlyContinue
            Write-DebugLog "Старый лог-файл удален (размер $($fileInfo.Length) байт)" "INFO"
        }
    } catch {
        # Если что‑то пошло не так, просто удаляем старый лог
        Remove-Item $DebugLogFile -Force -ErrorAction SilentlyContinue
        Write-DebugLog "Ошибка при ротации лога: $_" "WARN"
    }
}

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
$script:UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# --- КОНСТАНТЫ ---
$SCRIPT:CONST = @{
    TimeoutMs    = 3000
    ProxyTimeout = 4000
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
    NavStr = "[ *READY* ]  [ENTER] SCAN | [H] HELP | [P] PROXY  | [T] TEST PROXY | [D] DEEP TRACE | [S] SAVE | [U] UPDATE | [Q] QUIT"
}
Write-DebugLog "Константы инициализированы."

# --- ГЛОБАЛЬНЫЕ ПУТИ ---
$script:ConfigDir = Join-Path $env:LOCALAPPDATA "YT-DPI"
$script:ConfigFile = Join-Path $script:ConfigDir "YT-DPI_config.json"

$script:Config = $null
$script:NetInfo = $null
$script:DnsCache = @{}

# Создаём папку, если её нет
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
        Tls13Supported = $null
        Proxy = @{ Enabled = $false; Type = "HTTP"; Host = ""; Port = 0; User = ""; Pass = "" }
        NetCache = @{ 
            ISP = "Loading..."; LOC = "Unknown"; DNS = "8.8.8.8"; 
            CDN = "manifest.googlevideo.com"; 
            TimestampTicks = (Get-Date).AddDays(-1).Ticks # Храним как число
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
    if (Test-Path $script:ConfigFile) {
        try {
            $config = Get-Content $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            
            # Безопасная проверка свежести кэша через Ticks
            $lastTicks = if ($config.NetCache.TimestampTicks) { $config.NetCache.TimestampTicks } else { 0 }
            $diff = (Get-Date).Ticks - $lastTicks
            # 6 часов в тиках (1 тик = 100 наносекунд)
            $isStale = $diff -gt ([TimeSpan]::FromHours(6).Ticks)
            
            $config | Add-Member -MemberType NoteProperty -Name "NetCacheStale" -Value $isStale -Force
            Write-DebugLog "Конфиг загружен. Кэш устарел: $isStale" "INFO"
            return $config
        } catch { 
            Write-DebugLog "Ошибка JSON, создаем новый: $_" "WARN"
        }
    }
    return New-ConfigObject
}

function Save-Config($config) {
    if ($null -eq $config) { return }
    try {
        # Обновляем DNS кэш перед сохранением
        $config.DnsCache = $script:DnsCache
        $config.Proxy = $global:ProxyConfig
        $config.Tls13Supported = $global:Tls13Supported
        
        # Удаляем временное поле
        if ($config.PSObject.Properties['NetCacheStale']) { $config.PSObject.Properties.Remove('NetCacheStale') }

        $json = $config | ConvertTo-Json -Depth 5
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

function Draw-UI ($NetInfo, $Targets, $ClearScreen = $true) {
    Write-DebugLog "Draw-UI: Targets count=$($Targets.Count), ClearScreen=$ClearScreen"
    Update-ConsoleSize
    if ($ClearScreen) { [Console]::Clear() }
    
    Out-Str 1 1 ' ██╗   ██╗████████╗    ██████╗ ██████╗ ██╗' 'Green'
    Out-Str 1 2 ' ╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║' 'Green'
    Out-Str 1 3 '  ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║' 'Green'
    Out-Str 1 4 '   ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║' 'Green'
    Out-Str 1 5 '    ██║      ██║       ██████║ ██║     ██║' 'Green'
    Out-Str 1 6 '    ╚═╝      ╚═╝       ╚═════╝ ╚═╝     ╚═╝' 'Green'

    # Правая панель
    Out-Str 45 1 '██████╗    ██╗' 'Gray'
    Out-Str 45 2 '╚════██╗  ███║' 'Gray'
    Out-Str 45 3 ' █████╔╝  ╚██║' 'Gray'
    Out-Str 45 4 '██╔═══╝    ██║' 'Gray'
    Out-Str 45 5 '███████╗██╗██║' 'Gray'
    Out-Str 45 6 '╚══════╝╚═╝╚═╝' 'Gray'

    # Правая панель информации 
    Out-Str 65 1 "> SYS STATUS: [ ONLINE ]" "Green"
    Out-Str 65 2 "> ENGINE: Barebuh Pro v1.7.6" "Red"
    Out-Str 65 3 ("> LOCAL DNS: " + $NetInfo.DNS).PadRight(50) "Cyan"
    Out-Str 65 4 ("> CDN NODE: " + $NetInfo.CDN).PadRight(50) "Yellow"
    Out-Str 65 5 "> AUTHOR: github.com/Shiperoid" "Green"
    
    $dispIsp = $NetInfo.ISP
    if ($dispIsp.Length -gt 35) { 
        $dispIsp = $dispIsp.Substring(0, 32) + "..." 
    }
    $dispLoc = $NetInfo.LOC
    if ($dispLoc.Length -gt 30) { 
        $dispLoc = $dispLoc.Substring(0, 27) + "..." 
    }
    $ispStr = "> ISP / LOC: $dispIsp ($dispLoc)"
    Out-Str 65 6 ($ispStr.PadRight(80).Substring(0, 80)) "Magenta"
    
    $proxyStatus = if ($global:ProxyConfig.Enabled) { "> PROXY: $($global:ProxyConfig.Type) $($global:ProxyConfig.Host):$($global:ProxyConfig.Port) Connected" } else { "> PROXY: [ OFF ]" }
    Out-Str 65 7 ($proxyStatus.PadRight(58)) "DarkYellow"
    Out-Str 65 8 "> TG: t.me/YT_DPI | VERSION: $scriptVersion" "Green"
        
    # Таблица
    $y = 9
    $width = [Console]::WindowWidth
    
    # Верхняя граница таблицы
    Out-Str 0 $y ("=" * $width) "DarkCyan"
    
    # Заголовки (с новой колонкой #)
    Out-Str $CONST.UI.Num ($y+1) "#" "White"
    Out-Str $CONST.UI.Dom ($y+1) "TARGET DOMAIN" "White"
    Out-Str $CONST.UI.IP  ($y+1) "IP ADDRESS" "White"
    Out-Str $CONST.UI.HTTP ($y+1) "HTTP" "White"
    Out-Str $CONST.UI.T12 ($y+1) "TLS 1.2" "White"
    Out-Str $CONST.UI.T13 ($y+1) "TLS 1.3" "White"
    Out-Str $CONST.UI.Lat ($y+1) "LAT" "White"
    Out-Str $CONST.UI.Ver ($y+1) "RESULT" "White"
    
    # Разделитель под заголовками
    Out-Str 0 ($y+2) ("=" * $width) "DarkCyan"
    
    # Строки результатов (пустые)
    for($i=0; $i -lt $Targets.Count; $i++) {
        $currentRow = $y + 3 + $i
        $num = $i + 1
        $numStr = $num.ToString().PadRight(4)
        
        $numStr = ($i + 1).ToString().PadRight(4)
        Out-Str $CONST.UI.Num $currentRow $numStr "Cyan"
        Out-Str $CONST.UI.Dom $currentRow ($Targets[$i].PadRight(42).Substring(0, 42)) "Gray"
        Out-Str $CONST.UI.IP  $currentRow ("---.---.---.---".PadRight(16).Substring(0, 16)) "DarkGray"
        Out-Str $CONST.UI.HTTP $currentRow ("--".PadRight(6).Substring(0, 6)) "DarkGray"
        Out-Str $CONST.UI.T12  $currentRow ("--".PadRight(8).Substring(0, 8)) "DarkGray"
        Out-Str $CONST.UI.T13  $currentRow ("--".PadRight(8).Substring(0, 8)) "DarkGray"
        Out-Str $CONST.UI.Lat  $currentRow ("----".PadRight(6).Substring(0, 6)) "DarkGray"
        Out-Str $CONST.UI.Ver  $currentRow ("IDLE".PadRight(30).Substring(0, 30)) "DarkGray"
    }
    
    # Нижняя граница таблицы
    Out-Str 0 ($y + 3 + $Targets.Count) ("=" * $width) "DarkCyan"
}

function Get-ScanAnim($f, $row) {
    $frames = "[=   ]", "[ =  ]", "[  = ]", "[   =]", "[  = ]", "[ =  ]"
    return $frames[($f + $row) % $frames.Length]
}

function Write-ResultLine($row, $result) {
    if ($row -lt 0 -or $row -ge [Console]::BufferHeight) { return }
    
    # Подготовка строк
    $numStr = if ($result.Number) { $result.Number.ToString().PadRight(4) } else { "    " }
    $ipStr  = if ($result.IP) { [string]$result.IP } else { "---" }
    $htStr  = if ($result.HTTP) { [string]$result.HTTP } else { "---" }
    $t12Str = if ($result.T12) { [string]$result.T12 } else { "---" }
    $t13Str = if ($result.T13) { [string]$result.T13 } else { "---" }
    $latStr = if ($result.Lat) { [string]$result.Lat } else { "---" }
    $v      = if ($result.Verdict) { [string]$result.Verdict } else { "UNKNOWN" }
    
    if ($ipStr.Length -gt 15) { 
    # Сокращаем IPv6 для таблицы: "2a00:14...:c0f"
    $ipStr = $ipStr.Substring(0,9) + ".." + $ipStr.Substring($ipStr.Length-4) 
    }
    
    # ВЫВОД ДАННЫХ ПО КОЛОНКАМ (без предварительной очистки всей строки)
    Out-Str $CONST.UI.Num $row $numStr "Cyan"
    Out-Str $CONST.UI.Dom $row ($result.Target.PadRight(42).Substring(0, 42)) "Gray"
    Out-Str $CONST.UI.IP  $row ($ipStr.PadRight(16).Substring(0, 16)) "DarkGray"
    
    $hCol = if($htStr -eq "OK") {"Green"} elseif($htStr -eq "---") {"DarkGray"} else {"Red"}
    Out-Str $CONST.UI.HTTP $row ($htStr.PadRight(6)) $hCol
    
    $t12Col = if($t12Str -eq "OK") {"Green"} elseif($t12Str -eq "---") {"DarkGray"} else {"Red"}
    Out-Str $CONST.UI.T12 $row ($t12Str.PadRight(8)) $t12Col
    
    $t13Col = if($t13Str -eq "OK") {"Green"} elseif($t13Str -eq "N/A" -or $t13Str -eq "---") {"DarkGray"} else {"Red"}
    Out-Str $CONST.UI.T13 $row ($t13Str.PadRight(8)) $t13Col
    
    $latCol = if($latStr -eq "---") {"DarkGray"} else {"Cyan"}
    Out-Str $CONST.UI.Lat $row ($latStr.PadRight(6)) $latCol
    
    # Последняя колонка затирает всё, что было раньше (анимацию SCANNING)
    Out-Str $CONST.UI.Ver $row ($v.PadRight(30)) $result.Color
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
        [int]$TimeoutSec = 5
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
    return Invoke-TcpTracerouteCombined -Target $Target -Port $Port -MaxHops $MaxHops -TimeoutSec $TimeoutSec
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
        [int]$TimeoutSec
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
    } catch {
        Write-DebugLog "Не удалось разрешить целевой IP: $_"
    }
    
    foreach ($hop in $icmpHops) {
        Write-DebugLog "Проверка хопа $($hop.Hop): $($hop.IP)"
        
        # 1. TCP проверка
        $tcpResult = Test-TcpPort -TargetIp $hop.IP -Port $Port -TimeoutSec 2
        
        # 2. TLS проверка (если TCP успешен)
        $tlsStatus = "N/A"
        if ($tcpResult.Status -eq "SYNACK") {
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
        Start-Sleep -Seconds 2
    }
    elseif ($res -eq "DEV_VERSION") {
        Draw-StatusBar -Message "[ UPDATE ] Your version ($scriptVersion) is newer than GitHub release ($res)." -Fg "Black" -Bg "Magenta"
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
                    Write-DebugLog "SOCKS5 подключение, аутентификация..."
                    # Методы
                    $methods = @(0x00)
                    if ($ProxyConfig.User -and $ProxyConfig.Pass) { $methods += 0x02 }
                    $stream.Write([byte[]](@(0x05, $methods.Length) + $methods), 0, $methods.Length + 2)
                    # Чтение ответа на метод
                    $resp = New-Object byte[] 2
                    if (-not (Read-StreamWithTimeout $stream $resp 2 $Timeout)) {
                        throw "SOCKS5 no response to method request"
                    }
                    if ($resp[1] -eq 0x02) {
                        # Аутентификация
                        $u = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.User)
                        $p = [Text.Encoding]::UTF8.GetBytes($ProxyConfig.Pass)
                        $auth = [byte[]](@(0x01, $u.Length) + $u + @($p.Length) + $p)
                        $stream.Write($auth, 0, $auth.Length)
                        $resp = New-Object byte[] 2
                        if (-not (Read-StreamWithTimeout $stream $resp 2 $Timeout) -or $resp[1] -ne 0x00) {
                            throw "SOCKS5 authentication failed"
                        }
                    }
                    # Запрос на маршрутизацию
                    $ipObj = $null
                    if ([System.Net.IPAddress]::TryParse($TargetHost, [ref]$ipObj)) {
                        if ($ipObj.AddressFamily -eq 'InterNetworkV6') {
                            $req = [byte[]](@(0x05, 0x01, 0x00, 0x04) + $ipObj.GetAddressBytes())
                        } else {
                            $req = [byte[]](@(0x05, 0x01, 0x00, 0x01) + $ipObj.GetAddressBytes())
                        }
                    } else {
                        $h = [Text.Encoding]::UTF8.GetBytes($TargetHost)
                        $req = [byte[]](@(0x05, 0x01, 0x00, 0x03, $h.Length) + $h)
                    }
                    $req += [byte[]](@([math]::Floor($TargetPort/256), ($TargetPort%256)))
                    $stream.Write($req, 0, $req.Length)
                    # Чтение ответа (минимум 4 байта)
                    $buf = New-Object byte[] 10
                    $read = Read-StreamWithTimeout $stream $buf 10 $Timeout
                    if (-not $read -or $read -lt 4 -or $buf[1] -ne 0x00) {
                        throw "SOCKS5 route failed"
                    }
                    Write-DebugLog "SOCKS5 маршрутизация успешна"
                    return @{ Tcp = $tcp; Stream = $stream }
                }
                else {
                    Write-DebugLog "HTTP CONNECT запрос"
                    $auth = ""
                    if ($ProxyConfig.User -and $ProxyConfig.Pass) {
                        $auth = "Proxy-Authorization: Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)")) + "`r`n"
                    }
                    $hostHeader = if ($TargetHost -match ':') { "[$TargetHost]" } else { $TargetHost }
                    $req = "CONNECT $hostHeader`:$TargetPort HTTP/1.1`r`nHost: $hostHeader`:$TargetPort`r`n${auth}Proxy-Connection: Keep-Alive`r`n`r`n"
                    $reqBytes = [Text.Encoding]::ASCII.GetBytes($req)
                    $stream.Write($reqBytes, 0, $reqBytes.Length)
                    # Читаем ответ до \r\n\r\n
                    $response = Read-HttpResponse $stream $Timeout
                    if ($response -match "HTTP/1.[01]\s+200") {
                        Write-DebugLog "HTTP CONNECT успешен"
                        return @{ Tcp = $tcp; Stream = $stream }
                    } else {
                        throw "HTTP proxy refused: $response"
                    }
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
    Write-DebugLog "Invoke-WebRequestViaProxy: $Method $Url, ProxyEnabled=$($global:ProxyConfig.Enabled)"
    $uri = [System.Uri]$Url
    if (-not $global:ProxyConfig.Enabled -or $global:ProxyConfig.Type -in @("HTTP", "HTTPS")) {
        try {
            $req = [System.Net.WebRequest]::Create($uri)
            $req.Timeout = $Timeout
            $req.UserAgent = $script:UserAgent
            $req.KeepAlive = $false
            if ($global:ProxyConfig.Enabled) {
                $wp = New-Object System.Net.WebProxy($global:ProxyConfig.Host, $global:ProxyConfig.Port)
                if ($global:ProxyConfig.User) { $wp.Credentials = New-Object System.Net.NetworkCredential($global:ProxyConfig.User, $global:ProxyConfig.Pass) }
                $req.Proxy = $wp
            } else { $req.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy() }
            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $content = $reader.ReadToEnd()
            $resp.Close()
            Write-DebugLog "Invoke-WebRequestViaProxy успешно, длина ответа: $($content.Length)"
            return $content
        } catch { 
            Write-DebugLog "Invoke-WebRequestViaProxy ошибка: $_"
            return "" 
        }
    } else {
        Write-DebugLog "Invoke-WebRequestViaProxy через SOCKS"
        try {
            $conn = Connect-ThroughProxy $uri.Host $uri.Port $global:ProxyConfig $Timeout
            $request = "$Method $($uri.PathAndQuery) HTTP/1.0`r`nHost: $($uri.Host)`r`nUser-Agent: $script:UserAgent`r`nConnection: close`r`n`r`n"
            $reqBytes = [Text.Encoding]::ASCII.GetBytes($request)
            $conn.Stream.Write($reqBytes, 0, $reqBytes.Length)
            $buf = New-Object byte[] 4096
            $respBytes = New-Object System.Collections.Generic.List[byte]
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt $Timeout) {
                if ($conn.Stream.DataAvailable) {
                    $read = $conn.Stream.Read($buf, 0, 4096)
                    if ($read -gt 0) { for ($i=0; $i -lt $read; $i++) { $respBytes.Add($buf[$i]) } } else { break }
                } elseif ($respBytes.Count -gt 0) { break }
                else { Start-Sleep -Milliseconds 50 }
            }
            $conn.Tcp.Close()
            $parts = ([Text.Encoding]::UTF8.GetString($respBytes.ToArray())) -split "`r`n`r`n", 2
            if ($parts.Length -eq 2) { 
                Write-DebugLog "Invoke-WebRequestViaProxy (SOCKS) успешно, длина тела: $($parts[1].Length)"
                return $parts[1] 
            }
        } catch {
            Write-DebugLog "Invoke-WebRequestViaProxy (SOCKS) ошибка: $_"
        }
        return ""
    }
}

function Get-NetworkInfo {
    Write-DebugLog "Get-NetworkInfo: начало"
    
    # 1. Получаем DNS
    $dns = "UNKNOWN"
    try {
        $wmi = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | 
               Where-Object { $_.DNSServerSearchOrder -ne $null } | Select-Object -First 1
        if ($wmi) { $dns = $wmi.DNSServerSearchOrder[0] }
        Write-DebugLog "DNS: $dns" "INFO"
    } catch { Write-DebugLog "Ошибка получения DNS: $_" }

    # 2. Определяем CDN узел
    $rnd = [guid]::NewGuid().ToString().Substring(0,8)
    $cdn = "manifest.googlevideo.com"
    $geoResponse = Invoke-WebRequestViaProxy "http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd"
    if ($geoResponse -match "=>\s+([\w-]+)") { 
        $cdn = "r1.$($matches[1]).googlevideo.com"
        Write-DebugLog "CDN определён: $cdn"
    } else {
        Write-DebugLog "CDN не определён, оставляем по умолчанию"
    }

    # 3. Получаем ISP и Локацию
    $isp = "UNKNOWN"; $loc = "UNKNOWN"
    for ($i = 1; $i -le 2; $i++) {
        $rawGeo = Invoke-WebRequestViaProxy "http://ip-api.com/json/?fields=status,countryCode,city,isp"
        if ($rawGeo -match "(?s)(\{.*\})") {
            try {
                $geo = $matches[1] | ConvertFrom-Json
                if ($geo.status -eq "success") {
                    $isp = $geo.isp -replace '(?i)\s*(LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC)', ''
                    if ($isp.Length -gt 25) { $isp = $isp.Substring(0, 22) + '...' }
                    $loc = "$($geo.city), $($geo.countryCode)"
                    Write-DebugLog "Гео: $isp, $loc" "INFO"
                    break
                }
            } catch { Write-DebugLog "Ошибка парсинга гео: $_" }
        }
        if ($i -eq 1) { Start-Sleep -Milliseconds 500 }
    }

    # 4. Проверяем наличие IPv6 интернета
        # Внутри Get-NetworkInfo:
    $hasV6 = $false
    try {
        # Используем .NET класс, который работает везде от XP до Win11
        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
        foreach ($int in $interfaces) {
            if ($int.OperationalStatus -eq 'Up') {
                $props = $int.GetIPProperties()
                foreach ($addr in $props.UnicastAddresses) {
                    # Ищем глобальный IPv6 (не fe80 и не петлю)
                    if ($addr.Address.AddressFamily -eq 'InterNetworkV6' -and 
                        -not $addr.Address.IsIPv6LinkLocal -and 
                        $addr.Address.ToString() -ne '::1') {
                        $hasV6 = $true
                        break
                    }
                }
            }
            if ($hasV6) { break }
        }
        if ($hasV6) { Write-DebugLog "IPv6 стек активен." "INFO" }
    } catch { Write-DebugLog "Ошибка проверки IPv6: $_" }

    # 5. ФОРМИРУЕМ ЕДИНЫЙ ОБЪЕКТ И ВОЗВРАЩАЕМ ЕГО
    $info = @{ 
        DNS            = $dns
        CDN            = $cdn
        ISP            = $isp
        LOC            = $loc
        TimestampTicks = (Get-Date).Ticks
        HasIPv6        = $hasV6 
    }
    
    return $info
}

function Test-ProxyConnection {
    Write-DebugLog "Test-ProxyConnection: Запуск расширенного теста..."
    [Console]::Clear()
    
    $w = [Console]::WindowWidth
    if ($w -gt 80) { $w = 80 }
    $line = "═" * $w
    $dash = "─" * $w

    # Заголовок
    Write-Host "`n $line" -ForegroundColor Gray
    Write-Host (Get-PaddedCenter "ДИАГНОСТИКА ПРОКСИ-СОЕДИНЕНИЯ" $w) -ForegroundColor Cyan
    Write-Host " $line" -ForegroundColor Gray

    if (-not $global:ProxyConfig.Enabled) {
        Write-Host "`n  [!] ОШИБКА: Прокси не включен." -ForegroundColor Red
        Write-Host "  Сначала настройте его кнопкой [P]." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        return
    }

    Write-Host "`n  КОНФИГУРАЦИЯ:" -ForegroundColor White
    Write-Host "  > АДРЕС:  $($global:ProxyConfig.Host):$($global:ProxyConfig.Port)" -ForegroundColor Gray
    Write-Host "  > ТИП:    $($global:ProxyConfig.Type)" -ForegroundColor Gray
    Write-Host "`n $dash" -ForegroundColor Gray

    $steps = @(
        "Подключение к прокси-хосту    ",
        "Проверка порта и рукопожатие  ",
        "Туннель до google.com:80      ",
        "Получение HTTP ответа         "
    )

    # Локальная функция форматирования статуса
    function Format-Status($s) {
        $width = 6
        $spaces = $width - $s.Length
        if ($spaces -le 0) { return $s }
        $left = [Math]::Floor($spaces / 2)
        $right = $spaces - $left
        return (" " * $left) + $s + (" " * $right)
    }

    # Сохраняем позиции строк для каждого шага
    $stepRows = @()
    for($i=0; $i -lt $steps.Count; $i++) {
        $stepRows += [Console]::CursorTop
        Write-Host "  [ " -NoNewline -ForegroundColor Gray
        Write-Host (Format-Status "WAIT") -ForegroundColor Yellow -NoNewline
        Write-Host " ] $($steps[$i])" -ForegroundColor White
    }
    $afterStepsRow = [Console]::CursorTop

    # Функция обновления статуса (перерисовывает всю строку)
    function Update-ProxyStep($idx, $status, $color) {
        $row = $stepRows[$idx]
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write(" " * [Console]::WindowWidth)  # Очищаем строку
        [Console]::SetCursorPosition(0, $row)
        # Полностью перерисовываем строку
        Write-Host "  [ " -NoNewline -ForegroundColor Gray
        Write-Host (Format-Status $status) -ForegroundColor $color -NoNewline
        Write-Host " ] $($steps[$idx])" -ForegroundColor White
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $success = $false
    $errDetail = "Неизвестная ошибка"
    $latency = $null

    try {
        # Шаг 1: TCP Connect
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $tcp.BeginConnect($global:ProxyConfig.Host, $global:ProxyConfig.Port, $null, $null)
        if (-not $asyn.AsyncWaitHandle.WaitOne(3000)) { 
            Update-ProxyStep 0 "FAIL" "Red"
            throw "Прокси-сервер не отвечает (Timeout)" 
        }
        $tcp.EndConnect($asyn)
        Update-ProxyStep 0 " OK " "Green"

        # Шаг 2: Handshake (проверка прокси)
        Update-ProxyStep 1 "WAIT" "Yellow"
        $conn = Connect-ThroughProxy "google.com" 80 $global:ProxyConfig 4000
        Update-ProxyStep 1 " OK " "Green"
        
        # Шаг 3: Туннель установлен (автоматически OK)
        Update-ProxyStep 2 " OK " "Green"

        # Шаг 4: HTTP Request
        Update-ProxyStep 3 "WAIT" "Yellow"
        $req = [Text.Encoding]::ASCII.GetBytes("HEAD / HTTP/1.1`r`nHost: google.com`r`nConnection: close`r`n`r`n")
        $conn.Stream.Write($req, 0, $req.Length)
        
        $buf = New-Object byte[] 128
        if ($conn.Stream.Read($buf, 0, 128) -gt 0) {
            $latency = $sw.ElapsedMilliseconds
            Update-ProxyStep 3 " OK " "Green"
            $success = $true
        } else { throw "Сервер Google не ответил через прокси" }

        $conn.Tcp.Close()
    } catch {
        $errDetail = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-DebugLog "Proxy Test Error: $errDetail"
    }

    # Перемещаем курсор на строку после всех шагов и очищаем её
    [Console]::SetCursorPosition(0, $afterStepsRow)
    [Console]::Write(" " * [Console]::WindowWidth)
    [Console]::SetCursorPosition(0, $afterStepsRow)

    # Итоговый блок
    Write-Host " $dash" -ForegroundColor Gray
    if ($success) {
        Write-Host "  РЕЗУЛЬТАТ: " -NoNewline -ForegroundColor White
        Write-Host "ПРОКСИ РАБОТАЕТ" -ForegroundColor Green
        Write-Host "  ЗАДЕРЖКА:  " -NoNewline -ForegroundColor White
        Write-Host "$($latency) ms" -ForegroundColor Cyan
    } else {
        Write-Host "  РЕЗУЛЬТАТ: " -NoNewline -ForegroundColor White
        Write-Host "ОШИБКА СОЕДИНЕНИЯ" -ForegroundColor Red
        if ($errDetail.Length -gt $w - 15) { $errDetail = $errDetail.Substring(0, $w - 18) + "..." }
        Write-Host "  ДЕТАЛИ:    " -NoNewline -ForegroundColor White
        Write-Host $errDetail -ForegroundColor Gray
    }
    Write-Host " $line" -ForegroundColor Gray

    Write-Host "`n  Нажмите любую клавишу для возврата..." -ForegroundColor Gray
    Clear-KeyBuffer
    $null = [Console]::ReadKey($true)
}

# Универсальная функция для отрисовки блока
function Draw-Block {
    param(
        [int]$X,
        [int]$Y,
        [string]$Title,
        [array]$Content,
        [int]$Width = 78,
        [string]$TitleColor = "Yellow",
        [string]$BorderColor = "DarkYellow"
    )
    
    $line = "═" * ($Width - 2)
    $dash = "─" * ($Width - 2)
    $currentY = $Y
    
    # Верхняя граница
    Out-Str $X $currentY ("╔" + $line + "╗") $BorderColor
    $currentY++
    
    # Заголовок (если есть)
    if ($Title -and $Title -ne "") {
        $titleLine = "║" + " " * 3 + $Title + " " * ($Width - 2 - 3 - $Title.Length) + "║"
        Out-Str $X $currentY $titleLine $TitleColor
        $currentY++
        Out-Str $X $currentY ("├" + $dash + "┤") $BorderColor
        $currentY++
    } else {
        Out-Str $X $currentY ("║" + " " * ($Width - 2) + "║") $BorderColor
        $currentY++
    }
    
    # Содержимое
    foreach ($item in $Content) {
        $text = $item
        if ($text.GetType().Name -eq "Hashtable") {
            $text = $item.Text
            $color = $item.Color
        } else {
            $color = "White"
        }
        $contentLine = "║" + $text.PadRight($Width - 2) + "║"
        Out-Str $X $currentY $contentLine $color
        $currentY++
    }
    
    # Нижняя граница
    Out-Str $X $currentY ("└" + $dash + "┘") $BorderColor
    $currentY++
    
    return $currentY
}

function Parse-ProxyString {
    param([string]$input)
    
    Write-DebugLog "Parse-ProxyString: Входная строка = '$input'"
    
    $result = @{
        Valid = $false
        Type = "AUTO"
        Host = ""
        Port = 0
        User = ""
        Pass = ""
    }
    
    # Удаляем пробелы
    $input = $input.Trim()
    if ([string]::IsNullOrEmpty($input)) {
        Write-DebugLog "Parse-ProxyString: Пустая строка, возвращаем невалидный результат"
        return $result
    }
    
    Write-DebugLog "Parse-ProxyString: После Trim = '$input'"
    
    # Проверяем наличие протокола
    $protocol = ""
    $rest = $input
    
    if ($input -match '^(?i)(http|socks5)://(.*)$') {
        $protocol = $matches[1].ToUpper()
        $rest = $matches[2]
        $result.Type = $protocol
        Write-DebugLog "Parse-ProxyString: Обнаружен протокол = '$protocol', остаток = '$rest'"
    } else {
        Write-DebugLog "Parse-ProxyString: Протокол не указан, тип = AUTO"
    }
    
    # Проверяем наличие аутентификации
    $userpass = ""
    $hostport = $rest
    
    if ($rest -match '^([^@]+)@(.+)$') {
        $userpass = $matches[1]
        $hostport = $matches[2]
        Write-DebugLog "Parse-ProxyString: Обнаружена аутентификация, userpass = '$userpass', hostport = '$hostport'"
        
        # Разбираем логин:пароль
        if ($userpass -match '^([^:]+):(.+)$') {
            $result.User = $matches[1]
            $result.Pass = $matches[2]
            Write-DebugLog "Parse-ProxyString: User = '$($result.User)', Pass = '***'"
        } else {
            Write-DebugLog "Parse-ProxyString: Ошибка формата аутентификации (ожидается user:pass)"
            return $result
        }
    } else {
        Write-DebugLog "Parse-ProxyString: Аутентификация не обнаружена"
    }
    
    # Разбираем хост:порт
    Write-DebugLog "Parse-ProxyString: Парсим hostport = '$hostport'"
    $lastColon = $hostport.LastIndexOf(':')
    Write-DebugLog "Parse-ProxyString: Последнее двоеточие на позиции $lastColon"
    
    if ($lastColon -gt 0) {
        $result.Host = $hostport.Substring(0, $lastColon)
        $portStr = $hostport.Substring($lastColon + 1)
        Write-DebugLog "Parse-ProxyString: Host = '$($result.Host)', PortStr = '$portStr'"
        
        if ([int]::TryParse($portStr, [ref]$result.Port)) {
            Write-DebugLog "Parse-ProxyString: Порт распарсен = $($result.Port)"
            if ($result.Port -ge 1 -and $result.Port -le 65535) {
                if ($result.Host.Length -gt 0) {
                    $result.Valid = $true
                    Write-DebugLog "Parse-ProxyString: УСПЕХ! Host='$($result.Host)', Port=$($result.Port), Type=$($result.Type), Valid=$($result.Valid)"
                } else {
                    Write-DebugLog "Parse-ProxyString: Ошибка - пустой хост"
                }
            } else {
                Write-DebugLog "Parse-ProxyString: Ошибка - порт вне диапазона 1-65535 (получен $($result.Port))"
            }
        } else {
            Write-DebugLog "Parse-ProxyString: Ошибка - не удалось распарсить порт из '$portStr'"
        }
    } else {
        Write-DebugLog "Parse-ProxyString: Ошибка - не найдено двоеточие в '$hostport'"
    }
    
    return $result
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
    
    # Инструкция
    Write-Host "`n $dash" -ForegroundColor Gray
    Write-Host "  ФОРМАТЫ ВВОДА:" -ForegroundColor Cyan
    Write-Host "    * host:port                 - HTTP (автоопределение)" -ForegroundColor Gray
    Write-Host "    * http://host:port          - HTTP явно" -ForegroundColor Gray
    Write-Host "    * socks5://host:port        - SOCKS5 явно" -ForegroundColor Gray
    Write-Host "    * user:pass@host:port       - с аутентификацией" -ForegroundColor Gray
    Write-Host "    * http://user:pass@host:port - HTTP с аутентификацией" -ForegroundColor Gray
    Write-Host "    * socks5://user:pass@host:port - SOCKS5 с аутентификацией" -ForegroundColor Gray
    Write-Host "    * OFF / 0 / пусто           - отключить прокси" -ForegroundColor Gray
    Write-Host "    * TEST                      - протестировать текущий прокси" -ForegroundColor Gray
    
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
    
    # --- ПАРСИНГ ---
    Write-DebugLog "Show-ProxyMenu: Начинаем парсинг '$userInput'"

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
    
    # Проверка, что прокси настроен
    if ([string]::IsNullOrEmpty($ProxyConfig.Host) -or $ProxyConfig.Port -le 0) {
        $result.Error = "Прокси не настроен (хост/порт пуст)"
        return $result
    }

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Пробуем установить туннель до тестового хоста
        $conn = Connect-ThroughProxy "google.com" 80 $ProxyConfig 5000
        
        if ($conn) {
            $result.Latency = $sw.ElapsedMilliseconds
            $result.Success = $true
            $conn.Tcp.Close()
        } else {
            $result.Error = "Не удалось установить туннель"
        }
    } catch {
        $result.Error = $_.Exception.Message
        if ($result.Error -match "таймаут|timeout") {
            $result.Error = "Таймаут подключения"
        } elseif ($result.Error -match "отказано|refused") {
            $result.Error = "Соединение отклонено"
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
    Write-Host "   P (Proxy)      " -ForegroundColor Yellow -NoNewline; Write-Host "- Настроить прокси (формат IP:ПОРТ, например 127.0.0.1:1080)" -ForegroundColor Gray
    Write-Host "   S (Save)       " -ForegroundColor Yellow -NoNewline; Write-Host "- Сохранить результаты в файл YT-DPI_Report.txt" -ForegroundColor Gray
    Write-Host "   Q / ESC        " -ForegroundColor Yellow -NoNewline; Write-Host "- Выйти из программы" -ForegroundColor Gray

    # Статусы
    Write-Host "`n [ ЧТО ЗНАЧАТ ЦВЕТА ]" -ForegroundColor White
    Write-Host "   AVAILABLE      " -ForegroundColor Green -NoNewline; Write-Host "- Всё хорошо, домен доступен." -ForegroundColor Gray
    Write-Host "   DPI BLOCK/RESET" -ForegroundColor Red -NoNewline; Write-Host "- Блокировка провайдером (нужен обход SNI)." -ForegroundColor Gray
    Write-Host "   IP BLOCK       " -ForegroundColor Red -NoNewline; Write-Host "- Сервер недоступен (заблокирован сам адрес)." -ForegroundColor Gray

    # Решение проблем
    Write-Host "`n [ ЕСЛИ ТЕСТ ЗЕЛЕНЫЙ, НО ВИДЕО НЕ ГРУЗИТСЯ ]" -ForegroundColor White
    Write-Host "   1. Отключите QUIC в браузере: откройте " -ForegroundColor Gray -NoNewline
    Write-Host "chrome://flags/#enable-quic" -ForegroundColor Cyan -NoNewline
    Write-Host " -> Disabled" -ForegroundColor Gray
    
    Write-Host "   2. Отключите Kyber: откройте " -ForegroundColor Gray -NoNewline
    Write-Host "chrome://flags/#enable-tls13-kyber" -ForegroundColor Cyan -NoNewline
    Write-Host " -> Disabled" -ForegroundColor Gray
    
    Write-Host "   3. Если Deep Trace не работает, запустите программу от имени Администратора." -ForegroundColor Gray

    # Футер
    Write-Host "`n $($line)" -ForegroundColor Gray
    Write-Host (Get-PaddedCenter "Нажмите любую клавишу, чтобы вернуться назад" $w) -ForegroundColor Gray
    Write-Host " $($line)" -ForegroundColor Gray

    Clear-KeyBuffer
    $null = [Console]::ReadKey($true)
    
    try { [Console]::BufferHeight = $oldBufH } catch {}
}

# ====================================================================================
# РАБОЧИЙ ПОТОК
# ====================================================================================
$Worker = {
    param($Target, $ProxyConfig, $CanTls13, $CONST, $DebugLogFile, $DEBUG_ENABLED, $DnsCache, $DnsCacheLock, $NetInfo)

    # Внутренняя функция логирования для воркера
    function Write-DebugLog($msg, $level = "DEBUG") {
        if (-not $DEBUG_ENABLED) { return }
        $line = "[$(Get-Date -Format 'HH:mm:ss.fff')] [Worker $($Target)] [$($level)] $($msg)`r`n"
        try { [System.IO.File]::AppendAllText($DebugLogFile, $line, [System.Text.Encoding]::UTF8) } catch {}
    }

    # --- ВНУТРЕННИЕ ФУНКЦИИ ---
    function Connect-ThroughProxy {
        param($TargetHost, $TargetPort, $ProxyConfig, [int]$Timeout = $CONST.ProxyTimeout)
        # Проверка корректности конфигурации прокси
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
                $stream.Write([byte[]]@(0x05, 0x01, 0x00), 0, 3)
                $resp = New-Object byte[] 2; [void]$stream.Read($resp, 0, 2)
                $h = [Text.Encoding]::UTF8.GetBytes($TargetHost)
                $req = [byte[]](@(0x05, 0x01, 0x00, 0x03, $h.Length) + $h + @([math]::Floor($TargetPort/256), ($TargetPort%256)))
                $stream.Write($req, 0, $req.Length)
                $buf = New-Object byte[] 10; [void]$stream.Read($buf, 0, 10)
                Write-DebugLog "SOCKS5: Маршрут установлен."
                return @{ Tcp = $tcp; Stream = $stream }
            } else {
                $auth = if ($ProxyConfig.User) { "Proxy-Authorization: Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($ProxyConfig.User):$($ProxyConfig.Pass)")) + "`r`n" } else { "" }
                $req = "CONNECT $($TargetHost):$($TargetPort) HTTP/1.1`r`nHost: $($TargetHost):$($TargetPort)`r`n$($auth)`r`n"
                $reqB = [Text.Encoding]::ASCII.GetBytes($req); $stream.Write($reqB, 0, $reqB.Length)
                $buf = New-Object byte[] 1024; $r = $stream.Read($buf, 0, 1024)
                if ([Text.Encoding]::ASCII.GetString($buf, 0, $r) -match "200") {
                    Write-DebugLog "HTTP Proxy: CONNECT успешен."
                    return @{ Tcp = $tcp; Stream = $stream }
                }
                throw "Прокси отказал (CONNECT failed)"
            }
        } catch { 
            if($tcp){$tcp.Close()}
            Write-DebugLog "Ошибка прокси: $($_.Exception.Message)" "WARN"
            throw $_ 
        }
    }

    $Result = [PSCustomObject]@{ IP="FAILED"; HTTP="---"; T12="---"; T13="---"; Lat="---"; Verdict="UNKNOWN"; Color="White"; Target=$Target }
    $TO = if ($ProxyConfig.Enabled) { $CONST.ProxyTimeout } else { $CONST.TimeoutMs }

    Write-DebugLog "--- НАЧАЛО ПРОВЕРКИ ---"

    # 1. DNS
    if (-not $ProxyConfig.Enabled) {
        $ipStr = $null
        try {
            if ($DnsCacheLock.WaitOne(1000)) {
                if ($DnsCache.ContainsKey($Target)) { 
                    $ipStr = $DnsCache[$Target]
                    Write-DebugLog "DNS: Кэш HIT -> $($ipStr)"
                }
                [void]$DnsCacheLock.ReleaseMutex()
            }
            if (-not $ipStr) {
                Write-DebugLog "DNS: Кэш MISS. Резолвинг..."
                $ips = [System.Net.Dns]::GetHostAddresses($Target)
                $v6 = $ips | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' } | Select-Object -First 1
                $v4 = $ips | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                if ($v6 -and $NetInfo.HasIPv6) { 
                    $ipStr = $v6.IPAddressToString
                    Write-DebugLog "DNS: Выбран IPv6 -> $($ipStr)"
                } else { 
                    $ipStr = $v4.IPAddressToString 
                    Write-DebugLog "DNS: Выбран IPv4 -> $($ipStr)"
                }
                if ($DnsCacheLock.WaitOne(1000)) { $DnsCache[$Target] = $ipStr; [void]$DnsCacheLock.ReleaseMutex() }
            }
        } catch { 
            $ipStr = "DNS_ERR"
            Write-DebugLog "DNS: Ошибка - $($_.Exception.Message)" "ERROR"
        }
        $Result.IP = $ipStr
        if ($ipStr -eq "DNS_ERR") { $Result.Verdict = "DNS FAIL"; $Result.Color = "Red"; return $Result }
    } else { 
        $Result.IP = "[ PROXIED ]"
        Write-DebugLog "DNS: Пропущен (Proxy Mode)."
    }

    # 2. HTTP Проверка
    Write-DebugLog "HTTP: Тест порта 80..."
    $conn = $null
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        if ($ProxyConfig.Enabled) { $conn = Connect-ThroughProxy $Target 80 $ProxyConfig $TO }
        else {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $ar = $tcp.BeginConnect($Result.IP, 80, $null, $null)
            if (-not $ar.AsyncWaitHandle.WaitOne($TO)) { throw "Таймаут" }
            $tcp.EndConnect($ar); $conn = @{ Tcp = $tcp; Stream = $tcp.GetStream() }
        }
        $Result.Lat = "$($sw.ElapsedMilliseconds)ms"
        $Result.HTTP = "OK"
        Write-DebugLog "HTTP: OK (Ping: $($Result.Lat))"
    } catch { 
        $Result.HTTP = "ERR"
        Write-DebugLog "HTTP: Ошибка -> $($_.Exception.Message)" "WARN"
    } finally { if ($conn) { $conn.Tcp.Close() } }

    # 3. TLS Проверки (ПОСЛЕДОВАТЕЛЬНО)
    $tlsTO = 3500  #3500 для стабильности
    foreach ($ver in @("T12", "T13")) {
        if ($ver -eq "T13" -and -not $CanTls13) { 
            $Result.T13 = "N/A"
            Write-DebugLog "TLS 1.3: Пропуск (не поддерживается ОС)."
            continue 
        }
        
        Write-DebugLog "TLS $($ver): Запуск хендшейка..."
        $conn = $null
        $ssl = $null
        try {
            # 3.1. Установление TCP соединения
            if ($ProxyConfig.Enabled) { 
                $conn = Connect-ThroughProxy $Target 443 $ProxyConfig $tlsTO 
            } else {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $ar = $tcp.BeginConnect($Result.IP, 443, $null, $null)
                if (-not $ar.AsyncWaitHandle.WaitOne($tlsTO)) { throw "Таймаут сокета" }
                $tcp.EndConnect($ar)
                $conn = @{ Tcp = $tcp; Stream = $tcp.GetStream() }
            }

            # 3.2. Инициализация SSL (БЕЗ колбэка, чтобы избежать ошибки Runspace на Win7)
            $ssl = New-Object System.Net.Security.SslStream($conn.Stream, $false)
            $proto = if ($ver -eq "T12") { [System.Security.Authentication.SslProtocols]::Tls12 } else { 12288 }
            
            # 3.3. Запуск аутентификации
            $authAr = $ssl.BeginAuthenticateAsClient($Target, $null, $proto, $false, $null, $null)
            if ($authAr.AsyncWaitHandle.WaitOne($tlsTO)) {
                $ssl.EndAuthenticateAsClient($authAr)
                if ($ver -eq "T12") { $Result.T12 = "OK" } else { $Result.T13 = "OK" }
                Write-DebugLog "TLS $($ver): УСПЕШНО"
            } else { 
                # Если рукопожатие зависло - это "тихий" дроп пакетов (DPI)
                if ($ver -eq "T12") { $Result.T12 = "DRP" } else { $Result.T13 = "DRP" }
                Write-DebugLog "TLS $($ver): ТАЙМАУТ (DROPPED)" "WARN"
            }
        } catch {
            # 3.4. Анализ исключений
            $m = $_.Exception.Message + $_.Exception.InnerException.Message
            Write-DebugLog "TLS $($ver): Перехвачено исключение -> $($m)"
            
            if ($m -match "reset|сброс|forcibly|closed|разорвано") {
                # Если получили жесткий обрыв связи
                $res = "RST"
            } else {
                # Ошибки сертификатов, Runspace и прочие возникают только ПРИ ОТВЕТЕ сервера.
                # Это значит, что пакеты прошли фильтр SNI. Статус - OK.
                $res = "OK"
            }
            
            if ($ver -eq "T12") { $Result.T12 = $res } else { $Result.T13 = $res }
            Write-DebugLog "TLS $($ver): Финал (через catch) -> $($res)"
        } finally {
            # Обязательная очистка ресурсов
            if ($ssl) { $ssl.Close() }
            if ($conn) { $conn.Tcp.Close() }
        }
    }

    # 4. Вердикт
    if ($Result.T12 -eq "OK" -or $Result.T13 -eq "OK") { $Result.Verdict = "AVAILABLE"; $Result.Color = "Green" }
    elseif ($Result.T12 -eq "RST" -or $Result.T13 -eq "RST") { $Result.Verdict = "DPI RESET"; $Result.Color = "Red" }
    elseif ($Result.HTTP -eq "OK") { $Result.Verdict = "DPI BLOCK"; $Result.Color = "Yellow" }
    else { $Result.Verdict = "IP BLOCK"; $Result.Color = "Red" }

    Write-DebugLog "--- ЗАВЕРШЕНО: $($Result.Verdict) ---"
    return $Result
}

# ====================================================================================
# АСИНХРОННОЕ СКАНИРОВАНИЕ
# ====================================================================================
function Start-ScanWithAnimation($Targets, $ProxyConfig, $Tls13Supported) {
    Write-DebugLog "Start-ScanWithAnimation: Режим Ultra-Smooth Waterfall..."
    
    $cpuCount = [Environment]::ProcessorCount
    $maxThreads = [Math]::Min($Targets.Count, $cpuCount * 4)
    if ($maxThreads -lt 1) { $maxThreads = 1 }
    
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()
    $jobs = @()
    $results = New-Object 'object[]' $Targets.Count
    $completedTasks = 0
    $animationBuffer = @{}
    
    $waveChars = @("─     ", "──    ", "───   ", "────  ", "───── ", "──────", "───── ", "────  ", "───   ", "──    ")
    
    for ($i=0; $i -lt $Targets.Count; $i++) {
        $ps = [PowerShell]::Create().AddScript($Worker).AddArgument($Targets[$i]).AddArgument($ProxyConfig).AddArgument($Tls13Supported).AddArgument($CONST).AddArgument($DebugLogFile).AddArgument($DEBUG_ENABLED).AddArgument($script:DnsCache).AddArgument($script:DnsCacheLock).AddArgument($script:NetInfo)
        $ps.RunspacePool = $pool
        $jobs += [PSCustomObject]@{
            PowerShell = $ps; Handle = $ps.BeginInvoke(); Index = $i; Number = $i + 1
            Target = $Targets[$i]; DoneInBg = $false; Row = 12 + $i; Result = $null; Revealed = $false
        }
    }
    
    $aborted = $false
    $frameCounter = 0
    $revealIndex = -1 # Индекс строки, которую пора "раскрыть"
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

        # 3. Логика "Водопада": если ВСЕ готово, начинаем раскрывать по одной строке
        if ($completedTasks -eq $Targets.Count -and $revealIndex -lt ($Targets.Count - 1)) {
            # Раскрываем следующую строку каждые 40мс - 30мс 
            if ($lastRevealTime.ElapsedMilliseconds -gt 30) {
                $revealIndex++
                $lastRevealTime.Restart()
            }
        }

        # 4. ОТРИСОВКА КАДРА (Оптимизированный "один проход")
        for ($i = 0; $i -lt $Targets.Count; $i++) {
            $j = $jobs[$i]
            if ($j.Revealed) { continue }

            if ($i -le $revealIndex) {
                $res = $j.Result
                if ($null -eq $res) { $res = [PSCustomObject]@{ Target=$j.Target; Number=$j.Number; IP="ERR"; HTTP="---"; T12="---"; T13="---"; Lat="---"; Verdict="TIMEOUT"; Color="Red" } }
                
                Write-ResultLine $j.Row $res
                $j.Revealed = $true
                
            } 
            else {
                # Формируем ОДНУ строку для всей правой части таблицы (LAT + VERDICT)
                $rowChar = Get-ScanAnim $frameCounter $j.Row
                $statusText = " SCANNING $($rowChar)".PadRight(30)
                $latWave = $waveChars[($frameCounter + $j.Row) % $waveChars.Length].PadRight(7)
                
                # Склеиваем данные в один блок, чтобы минимизировать прыжки курсора
                $combinedFrame = "$($latWave)$($statusText)"
                
                $cacheKey = "R$($j.Row)"
                if ($animationBuffer[$cacheKey] -ne $combinedFrame) {
                    # Рисуем всё за один раз, начиная с колонки LAT
                    Out-Str $CONST.UI.Lat $j.Row $combinedFrame "Cyan"
                    $animationBuffer[$cacheKey] = $combinedFrame
                }
            }
        }

        # Выход, если всё раскрыто
        if ($revealIndex -eq ($Targets.Count - 1)) { break }

        # Тайминг кадра
        Start-Sleep -Milliseconds 30
    }
    
    $pool.Close(); $pool.Dispose()
    foreach ($j in $jobs) { try { $j.PowerShell.Dispose() } catch {} }
    return [PSCustomObject]@{ Results = $results; Aborted = $aborted }
}

# ====================================================================================
# ПРОВЕРКА ПОДДЕРЖКИ TLS 1.3
# ====================================================================================
function Test-Tls13Support {
    Write-DebugLog "Проверка поддержки TLS 1.3"
    try {
        $testTcp = New-Object System.Net.Sockets.TcpClient
        $asyn = $testTcp.BeginConnect("google.com", 443, $null, $null)
        if ($asyn.AsyncWaitHandle.WaitOne(1500)) {
            $testTcp.EndConnect($asyn)
            $testSsl = New-Object System.Net.Security.SslStream($testTcp.GetStream(), $false)
            $testSsl.AuthenticateAsClient("google.com", $null, $CONST.Tls13Proto, $false)
            $testSsl.Close()
        }
        $testTcp.Close()
        Write-DebugLog "TLS 1.3 поддерживается"
        return $true
    } catch {
        Write-DebugLog "TLS 1.3 НЕ поддерживается: $_" "WARNING"
        if ($_.Exception.Message -match "not supported|algorithm|поддерживается|алгоритм") {
            return $false
        }
        return $true
    }
}

# ====================================================================================
# ГЛАВНЫЙ ЦИКЛ ПРОГРАММЫ (ENGINE START)
# ====================================================================================
# 1. Загрузка конфигурации (Один раз)
$script:Config = Load-Config
$global:ProxyConfig = $script:Config.Proxy
#---
# Если нужно сбрасывать состояние прокси при каждом запуске
# $global:ProxyConfig.Enabled = $false
#---
$script:Config.RunCount++

# 2. Восстановление системных параметров
if ($null -ne $script:Config.Tls13Supported) {
    $global:Tls13Supported = $script:Config.Tls13Supported
    Write-DebugLog "TLS 1.3: Используем кэшированное значение ($global:Tls13Supported)"
} else {
    $global:Tls13Supported = Test-Tls13Support
    $script:Config.Tls13Supported = $global:Tls13Supported
}

# 3. Синхронизация DNS кэша (Потокобезопасная)
$script:DnsCache = [hashtable]::Synchronized(@{})
if ($script:Config.DnsCache -and $script:Config.DnsCache.PSObject) {
    foreach ($prop in $script:Config.DnsCache.PSObject.Properties) {
        # Игнорируем системные свойства самого объекта
        if ($prop.MemberType -eq "NoteProperty") {
            $script:DnsCache[$prop.Name] = $prop.Value
        }
    }
}
Write-DebugLog "DNS Кэш инициализирован: $($script:DnsCache.Count) записей."

# 4. Применяем настройки прокси из конфига
$global:ProxyConfig = $script:Config.Proxy
$script:CurrentWindowWidth = 0
$script:CurrentWindowHeight = 0

# 5. Проверка обновлений (Раз в 5 запусков)
$shouldPrompt = ($script:Config.RunCount - $script:Config.LastPromptRun) -ge 5
if ($shouldPrompt) {
    Write-DebugLog "--- ПЛАНОВАЯ ПРОВЕРКА ОБНОВЛЕНИЙ ---" "INFO"
    $newVer = Check-UpdateVersion -Repo "Shiperoid/YT-DPI" -LastCheckedVersion $script:Config.LastCheckedVersion
    if ($newVer) {
        [Console]::Clear()
        Write-Host "`n  === ДОСТУПНО ОБНОВЛЕНИЕ ===" -ForegroundColor Cyan
        Write-Host "  Версия: $newVer (текущая $scriptVersion)" -ForegroundColor Yellow
        Write-Host "  Обновить сейчас? (Y/N)" -ForegroundColor White
        $key = [Console]::ReadKey($true).KeyChar
        if ($key -eq 'y' -or $key -eq 'Y') {
            Write-DebugLog "Обновление подтверждено: $newVer"
            $currentFile = $script:OriginalFilePath
            $downloadUrl = "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.bat"
            Start-Updater $currentFile $downloadUrl
            exit
        } else {
            $script:Config.LastCheckedVersion = $newVer
        }
    }
    $script:Config.LastPromptRun = $script:Config.RunCount
    Save-Config $script:Config # Фиксируем напоминание
}

# 6. Инициализация сети (Кэш или Живой поиск)
$script:NetInfo = $script:Config.NetCache
if ($script:Config.NetCacheStale -or $script:Config.RunCount -eq 1 -or $script:NetInfo.ISP -eq "Loading...") {
    Write-DebugLog "Обновление сетевого статуса..." "INFO"
    $script:NetInfo = Get-NetworkInfo
    # КРИТИЧЕСКИ ВАЖНО: записываем новые данные обратно в объект конфига для сохранения
    $script:Config.NetCache = $script:NetInfo
}

# 7. Подготовка целей и отрисовка UI (ЕДИНСТВЕННЫЙ РАЗ)
$script:Targets = Get-Targets -NetInfo $script:NetInfo
[Console]::Clear()
Draw-UI $script:NetInfo $script:Targets $false
Draw-StatusBar -Message $CONST.NavStr

# 8. Сброс временных флагов
$FirstRun = $false
Clear-KeyBuffer
Write-DebugLog "--- СИСТЕМА ГОТОВА ---" "INFO"

while ($true) {
    if ($FirstRun) {
        Write-DebugLog "Первый запуск: получение сетевой информации"
        $script:NetInfo = Get-NetworkInfo
        $script:Targets = Get-Targets -NetInfo $script:NetInfo
        Write-DebugLog "Целей: $($script:Targets.Count)"
        Draw-UI $script:NetInfo $script:Targets $true
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
                $trace = Trace-TcpRoute -Target $target -Port 443 -MaxHops 15 -TimeoutSec 5
                
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
            $scanResult = Start-ScanWithAnimation $script:Targets $global:ProxyConfig $global:Tls13Supported
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