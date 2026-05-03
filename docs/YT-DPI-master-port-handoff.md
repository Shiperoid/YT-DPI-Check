# Handoff: перенос изменений `YT-DPI.ps1` на ветку master

Самодостаточный чеклист для другого агента: воспроизвести те же правки в upstream без истории чата. Файл эталона — текущий [`YT-DPI.ps1`](../YT-DPI.ps1) в этом репозитории.

---

## 1. Краткое резюме для агента

**Переносить**

- Вынесенные таймауты и лимиты в `$SCRIPT:CONST` **до** любого `Write-DebugLog` и `Start-Job` (см. комментарий у строки ~49 в эталоне).
- Оптимизации UI скана: `UiScan.RevealAnimFps`, уменьшенные `StatusBarThrottleCollectMs` / `StatusBarThrottleRevealMs`.
- Конфиг: `ScanParallelTlsFirstPass = $false` по умолчанию + миграция `Initialize-DisableBrokenParallelTlsTasks` и вызов из `Initialize-AppState`.
- Воркер скана: опциональный параллельный первый проход TLS с проверкой `parallelOk` и откатом на последовательный путь; функция `Set-Verdict-DualTlsCells`; вспомогательные пробы T13/T12 для режимов TLS12-only / TLS13-only при DRP/RST основной колонки (вердикт двухпротокольный, отображаемая «неактивная» колонка остаётся `N/A`).
- Тексты пункта 3 и 6 в меню настроек (`Show-SettingsMenu`).

**Не переносить**

- Любую старую NDJSON-инструментализацию или отладочные хвосты из прошлых итераций — в эталонном скрипте их нет; в master не добавлять.

**Зависимости**

- Только `YT-DPI.ps1` и существующий **YtDpi.\*** из Core; новых правок в `.cs` в этом сценарии не требуется.

---

## 2. Размещение `$SCRIPT:CONST`

Требование: блок `$SCRIPT:CONST = @{ ... }` и строка `$CONST = $SCRIPT:CONST` должны идти **сразу после** инициализации mutex для лога и **до** первых вызовов `Write-DebugLog` / фоновых джобов, иначе ранний код может обратиться к несуществующему `$CONST`.

На master искать верх файла около mutex и секции отладки; вставить таблицу **целиком** (или смержить ключи, сохранив числа и комментарии `# Снижено с …` как подсказки для поиска/замены).

---

## 3. Полный снимок `$SCRIPT:CONST` (эталон для копирования)

Ниже — **полная** актуальная hashtable из эталона (строки ~50–119).

```powershell
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
        # FPS только для этапа «раскрытия» таблицы после сбора (не влияет на сетевые проверки)
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
```

**Подсказки поиска на master**, если структура CONST другая: искать старые числа из комментариев (`1500`, `2500`, `240`, `280`, и т.д.) или имена вложенных таблиц (`Scan`, `NetInfo`, `Traceroute`, `ProxySelfTest`, `UiScan`, `Internet`, `HttpMisc`).

---

## 4. Оптимизация сканирования (UI, не сеть)

### 4.1 `UiScan.RevealAnimFps`

- Новое поле в `UiScan`: **`RevealAnimFps = 48`** (только анимация «раскрытия» таблицы после сбора).

### 4.2 `Start-ScanWithAnimation`

На этапе 2 («раскрытие»), перед циклом по строкам:

- По умолчанию `$revealFps = [double]$CONST.AnimFps`.
- Если задано `$CONST.UiScan.RevealAnimFps` и это положительное целое — подставить в `$revealFps`.
- Затем **`$animTargetMs = 1000.0 / $revealFps`**.

В эталоне это ~4248–4253.

### 4.3 Троттлинг статус-бара

В `CONST.UiScan`:

- **`StatusBarThrottleCollectMs = 90`** (было типично ~240).
- **`StatusBarThrottleRevealMs = 110`** (было типично ~280).

Использование: условия перерисовки статус-бара на этапе сбора (~4209) и на этапе раскрытия (~4266).

---

## 5. Конфиг и миграция

### 5.1 `New-ConfigObject`

Добавить (или выставить дефолт) свойство:

- **`ScanParallelTlsFirstPass = $false`**

Комментарий в эталоне (~613–614): первый проход T13+T12 через ThreadPool Tasks в воркере нестабилен; по умолчанию выключено.

### 5.2 Функция `Initialize-DisableBrokenParallelTlsTasks`

Логика (~709–717):

- Если нет `$script:Config` — выход.
- Если у конфига уже есть свойство **`ParallelTlsTasksDisabled032026`** — выход (миграция одноразовая).
- Иначе: добавить **`ParallelTlsTasksDisabled032026 = $true`**, принудительно **`$script:Config.ScanParallelTlsFirstPass = $false`**, запись в лог (`INFO`), **`Save-Config $script:Config`**.

### 5.3 `Initialize-AppState`

Сразу после **`Sync-DnsCacheFromConfig`** вызвать **`Initialize-DisableBrokenParallelTlsTasks`** (~4958–4960).

Убедиться, что в меню настроек при переключении параллельного TLS свойство `ScanParallelTlsFirstPass` по-прежнему сохраняется в конфиг (в эталоне пункт меню ~2880).

---

## 6. Воркер скана (`$Worker`): параллельный первый проход TLS

Условия включения параллели:

- Флаг **`ParallelTlsFirstPass`** из аргументов джоба (`$true` только если в конфиге включено).
- Режим **Auto** по двум столбцам: **`$consider13`** и **`$consider12`** оба истинны.

Реализация (~3934–3991):

- `$didParallelTls = ($consider13 -and $consider12 -and $ParallelTlsFirstPass)`.
- Снимок состояния в **`[PSCustomObject]$tlsSnap`** с полями для IP, хоста, прокси, таймаутов, **`T13`**, **`H12`** (результат детального handshake T12).
- Два делегата **`Task.Factory.StartNew`** для `TestT13` и `HandshakeDirectDetailed` / прокси-ветки → **`WaitAll`**.
- После ожидания вычислить **`$parallelOk`**: обе задачи не **`IsFaulted`**, и **`$null -ne $tlsSnap.T13`**, **`$null -ne $tlsSnap.H12`**.
- Если **`$parallelOk`**: заполнить **`$Result.T13`**, **`$Result.T12`** из ячейки handshake, **`$t12TimedOut`**, **`$parallelTlsHandled = $true`**, при **`T13 -eq "DRP"`** — retry с **`TlsTimeoutRetry`** как в последовательном пути.
- Если не ok — **`WARN`** в лог, **`$parallelTlsHandled`** остаётся `$false`.

Основной последовательный путь — блок **`if (-not $parallelTlsHandled)`** (~3993+): как раньше T13 → T12 с retry DRP для T13.

Параметр воркера для параллели — последний из **`AddArgument`** (~4165): **`[bool]($script:Config.ScanParallelTlsFirstPass -eq $true)`**.

---

## 7. Воркер: вердикты TLS12 / TLS13 / Auto

### 7.1 `Set-Verdict-DualTlsCells`

Внутри `$Worker`, перед созданием **`$Result`** (~3803–3821). Параметры: **`Cell12`**, **`Cell13`** (строки статусов).

Матрица:

- Оба **OK** → **AVAILABLE** / Green.
- Хотя бы один **OK**; если другой **RST** или **DRP** → **THROTTLED** / Yellow; иначе при одном OK → **AVAILABLE** / Green.
- Иначе при наличии **RST** → **DPI RESET** / Red.
- Иначе при наличии **DRP** → **DPI BLOCK** / Red.
- Иначе → **IP BLOCK** / Red.

### 7.2 Вспомогательные пробы (после retry T12, перед секцией «4. Логика вердикта»)

~4045–4087:

- Переменные **`$auxVerdictT13`**, **`$auxVerdictT12`** = `$null`.
- **TLS12-only** (`-not $consider13`): если **`Result.T12`** — **`DRP`** или **`RST`**, выполнить **`TestT13`** с теми же таймаутами; при **`DRP`** на aux — retry с **`TlsTimeoutRetry`**. Результат только в **`$auxVerdictT13`**. Колонку **`Result.T13`** для отображения **не менять** (остаётся **`N/A`** в этой ветке конфигурации режима).
- **TLS13-only** (`-not $consider12`): симметрично handshake T12 (direct или через прокси); при timeout — повтор с **`TlsTimeoutRetry`**. Результат в **`$auxVerdictT12`**. **`Result.T12`** для отображения **не подставлять** из aux (**`N/A`**).

### 7.3 Секция вердикта (~4089+)

- **TLS12-only**: если **`$auxVerdictT13`** не `$null` → **`Set-Verdict-DualTlsCells -Cell12 $Result.T12 -Cell13 $auxVerdictT13`**; иначе прежняя одноколоночная логика по **`Result.T12`**.
- **TLS13-only**: если **`$auxVerdictT12`** не `$null` → **`Set-Verdict-DualTlsCells -Cell12 $auxVerdictT12 -Cell13 $Result.T13`**; иначе по **`Result.T13`**.
- **Auto** (оба столбца): один вызов **`Set-Verdict-DualTlsCells -Cell12 $Result.T12 -Cell13 $Result.T13`**.

---

## 8. Меню настроек (`Show-SettingsMenu`)

### Пункт 3 — режим TLS (~2745–2747)

Текст помощи (смысл сохранить дословно по возможности):

- Auto — колонки T12 и T13 (как по умолчанию).
- TLS12 — в таблице осмысленен столбец T12 (T13 остаётся N/A); при DRP/RST тихо проверяется T13 только для вердикта.
- TLS13 — наоборот: столбец T13 основной (T12 N/A); при DRP/RST тихо проверяется T12 для вердикта.

### Пункт 6 — параллельный TLS (~2784–2790)

- Заголовок: параллельный первый проход TLS (Auto, T13+T12).
- Если ВКЛ: эксперимент, параллельные Tasks; при сбое — последовательный TLS без ложного IP BLOCK.
- Если ВЫКЛ: последовательно T13 → T12 (медленнее строка скана).

---

## 9. Чеклист порядка правок на master

1. **`$SCRIPT:CONST`** — вставить/смержить полный блок и **`$CONST = $SCRIPT:CONST`** в правильное место (до раннего логирования и джобов).
2. **`Initialize-DisableBrokenParallelTlsTasks`** — добавить функцию после загрузки конфига (рядом с другими миграциями).
3. **`Initialize-AppState`** — вызов сразу после **`Sync-DnsCacheFromConfig`**.
4. **`New-ConfigObject`** — **`ScanParallelTlsFirstPass = $false`** и комментарий про нестабильность Tasks.
5. **`$Worker`** (скриптблок, создающийся для скана):
   - параметр **`$ParallelTlsFirstPass`** (или эквивалент из аргументов);
   - блок параллельного первого прохода + **`$parallelOk`** + fallback;
   - **`Set-Verdict-DualTlsCells`**;
   - блок **`$auxVerdictT13` / `$auxVerdictT12`** и ветки вердикта.
6. **`Start-ScanWithAnimation`** — **`RevealAnimFps`** и **`$animTargetMs = 1000.0 / $revealFps`** на этапе раскрытия; проверить использование **`UiScan.StatusBarThrottleCollectMs`** / **`StatusBarThrottleRevealMs`**.
7. **`Show-SettingsMenu`** — строки пункта 3 и 6.
8. **`AddArgument` при создании джобов скана**: в эталоне **ровно 11** аргументов; **нет** лишнего пути NDJSON или иной отладочной «хвостной» передачи — сверить сигнатуру начала воркера с количеством **`AddArgument`**.

После переноса: прогон скана в Auto, TLS12-only и TLS13-only; при включённом параллельном TLS убедиться, что при сбое Tasks результат не деградирует в ложный **IP BLOCK**, а повторяется последовательный путь.
