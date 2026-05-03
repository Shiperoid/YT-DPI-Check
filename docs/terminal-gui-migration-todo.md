# Terminal.Gui — миграция: полный TODO

Ветка **`feature/terminal-gui`**. Исходный план переноса (без правок самого плана): см. обсуждение в репо / Cursor. Этот файл — **единый чеклист** от инфраструктуры до финала; отмечайте пункты по мере выполнения.

Требования: [.NET 10 SDK](https://dotnet.microsoft.com/download); основная поставка **`YT-DPI.bat` + `YT-DPI.ps1`** пока не заменяется.

---

## Сделано

- [x] Инфраструктура: `YT-DPI.sln`, `src/YT-DPI.App`, `src/YT-DPI.Core` (**net10.0**), CI [`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml) (build, `dotnet test`, publish / артефакт).
- [x] **Этап 1 — конфиг (только чтение):** путь `%LocalAppData%\YT-DPI\YT-DPI_config.json`, DTO, `UserConfigLoader.TryLoadUserConfig` (дефолты в духе `Load-Config`, санитизация `DnsCache`, без записи на диск).
- [x] **Этап 2 — порт C# из `YT-DPI.ps1`:** here-string `$tlsCode` → [`src/YT-DPI.Core/Tls/TlsScanner.cs`](../src/YT-DPI.Core/Tls/TlsScanner.cs) (в файле — ссылка на строки PS).
- [x] **Этап 2 — trace:** here-string `$traceCode` → [`src/YT-DPI.Core/Trace/TraceroutePorted.cs`](../src/YT-DPI.Core/Trace/TraceroutePorted.cs).
- [x] Точки входа для превью/тестов: [`src/YT-DPI.Core/Preview/PreviewEngine.cs`](../src/YT-DPI.Core/Preview/PreviewEngine.cs).
- [x] Тесты: [`src/YT-DPI.Core.Tests/`](../src/YT-DPI.Core.Tests/) (xUnit), smoke; в workflow после build вызывается `dotnet test`.
- [x] **Этап 3 (UI):** `TextView` с дампом конфига, `TableView` с колонками как **Draw-UI** в PS, фоновый TLS 1.3-скан (`PreviewScanRunner`), статус через `IProgress` + `IApplication.Invoke`, отмена **Ctrl+C**, старт скана после первого кадра ([`src/YT-DPI.App/Program.cs`](../src/YT-DPI.App/Program.cs)).
- [x] **App — фон и прогресс:** `Task.Run` + `IProgress` / `CancellationToken`, маршалинг на UI-поток через **`app.Invoke`**, **Ctrl+C** отменяет скан.
- [x] **App — таблица как в PS:** [`ScanTableSchema`](../src/YT-DPI.Core/Scan/ScanTableSchema.cs) + [`PreviewScanRunner`](../src/YT-DPI.Core/Scan/PreviewScanRunner.cs); цели — [`ScanTargetsBuilder`](../src/YT-DPI.Core/Scan/ScanTargetsBuilder.cs) (базовый список + CDN из кэша, F5, `YT_DPI_PREVIEW_MAX_TARGETS`).
- [x] **Core.Tests — trace:** [`TracerouteStableTests`](../src/YT-DPI.Core.Tests/TracerouteStableTests.cs) без ICMP (локальные helper + `SynchronousProgress`).
- [x] **DnsCache JSON:** коэрция нестроковых значений в строку при чтении ([`UserConfigLoader`](../src/YT-DPI.Core/Config/UserConfigLoader.cs)); тесты [`DnsCacheJsonTests`](../src/YT-DPI.Core.Tests/DnsCacheJsonTests.cs).
- [x] **Запись конфига + round-trip:** [`UserConfigSaver`](../src/YT-DPI.Core/Config/UserConfigSaver.cs), тест [`UserConfigRoundTripTests`](../src/YT-DPI.Core.Tests/UserConfigRoundTripTests.cs).
- [x] **Качество:** CA2022 в TLS (`ReadBlocking`); `#nullable disable` в порте trace.
- [x] **Корневые доки:** [`README.md`](../README.md), [`CHANGELOG_ru.md`](../CHANGELOG_ru.md), [`docs/terminal-gui-preview.md`](terminal-gui-preview.md), [`docs/terminal-gui-merge-policy.md`](terminal-gui-merge-policy.md).
- [x] **HTTP / TLS 1.2 / LAT** в превью-скане (рядом с TLS 1.3): [`TargetRowScanner`](../src/YT-DPI.Core/Scan/TargetRowScanner.cs), [`VerdictCalculator`](../src/YT-DPI.Core/Scan/VerdictCalculator.cs); при прокси — [`ProxyTunnel`](../src/YT-DPI.Core/Net/ProxyTunnel.cs).
- [x] **`SchemaVersion`** в [`YtDpiUserConfig`](../src/YT-DPI.Core/Config/YtDpiUserConfig.cs) + merge в [`UserConfigLoader`](../src/YT-DPI.Core/Config/UserConfigLoader.cs); round-trip в тестах; TUI по-прежнему только читает конфиг (запись — [`UserConfigSaver`](../src/YT-DPI.Core/Config/UserConfigSaver.cs) для других сценариев).
- [x] **Артефакт CI превью:** workflow публикует папку + `yt-dpi-gui-preview-win-x64.zip` (см. [`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml)).
- [x] **Поставка превью:** [`tools/Run-YT-DPI-Preview.ps1`](../tools/Run-YT-DPI-Preview.ps1), [`tools/Run-YT-DPI-Preview.bat`](../tools/Run-YT-DPI-Preview.bat); CI превью — [`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml) (только ветка `feature/terminal-gui`). **`release-gate`** на этой ветке не запускается (`branches-ignore` в workflow).
- [x] **PS + DLL:** `YT-DPI.ps1` — `Try-LoadYtDpiCoreDll`, вызовы типов с полными именами `YT_DPI.Core.*`; при отсутствии DLL — прежний `Add-Type` here-string.
- [x] **Прокси в Core:** [`Net/ProxyTunnel.cs`](../src/YT-DPI.Core/Net/ProxyTunnel.cs), скан через туннель + `TlsScanner` с типом прокси (`Invoke-YtDpiTlsTest13` / прямой вызов DLL в PS обновлены).
- [x] **TUI сохранение конфига (F3):** [`ConfigEditDialog.cs`](../src/YT-DPI.App/ConfigEditDialog.cs) — v2-контролы: **RadioStyle** `CheckBox` для IP, **DropDownList** для TLS и `Proxy.Type`, **FrameView** «Прокси», пароль **`TextField.Secret`**, разметка **`Dim.Auto` / `Dim.Percent`**; запись и `SchemaVersion` ≥ 1 как раньше.
- [x] **Артефакт `core-ps-bundle`:** [`.github/workflows/core-ps-bundle.yml`](../.github/workflows/core-ps-bundle.yml), [`bundle-core-ps.md`](bundle-core-ps.md).

## В работу / дальше

- [x] **Прокси + HTTP/T12 на 80/443:** [`Net/ProxyTunnel.cs`](../src/YT-DPI.Core/Net/ProxyTunnel.cs) (SOCKS5 + auth, HTTP CONNECT); [`TargetRowScanner`](../src/YT-DPI.Core/Scan/TargetRowScanner.cs); [`TlsScanner`](../src/YT-DPI.Core/Tls/TlsScanner.cs) с типом прокси; тесты [`ProxyTunnelTests`](../src/YT-DPI.Core.Tests/ProxyTunnelTests.cs).
- [x] **Опциональный zip основной линии:** [`.github/workflows/core-ps-bundle.yml`](../.github/workflows/core-ps-bundle.yml), [`docs/bundle-core-ps.md`](bundle-core-ps.md).

- [ ] **Дальше по желанию:** миграции JSON по `SchemaVersion` при расширении полей диалога; для **`Proxy.Type=AUTO`** — определение HTTP vs SOCKS как в PS (`Detect-ProxyType`), сейчас в туннеле **AUTO → SOCKS5**.

---

## Заметки

- В `YT-DPI.ps1` крупные встроенные C# блоки — в основном **`$tlsCode`** и **`$traceCode`**; остальная оркестрация Runspace/UI остаётся в PS до отдельного переноса.
- **YT-DPI.sh** и Linux-линия не используют эту DLL; общее — спецификации и JSON, не бинарник (см. `src/YT-DPI.Core/README.md`).
