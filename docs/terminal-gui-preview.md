# Превью: YT-DPI на Terminal.Gui

Экспериментальная линия в ветке **`feature/terminal-gui`**: **.NET** + TUI на **[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/)**.

## Сборка

Требуется [.NET 10 SDK](https://dotnet.microsoft.com/download) (см. `TargetFramework` в [`src/YT-DPI.App/YT-DPI.App.csproj`](../src/YT-DPI.App/YT-DPI.App.csproj)).

```powershell
dotnet run --project src/YT-DPI.App/YT-DPI.App.csproj
```

## Поведение

- Главное окно следует паттернам **Terminal.Gui v2**: **MenuBar** (Скан / Конфиг / Файл), две **FrameView** — «Конфигурация» (краткий текст) и «Результаты скана» (**TableView**), внизу **StatusBar** с подсказками по клавишам (**Shortcut**).
- **Esc** — выход. **Ctrl+C** — отмена фонового скана. **F5** — пересканировать. **F3** — модальный диалог правки ключевых полей конфига ([`ConfigEditDialog`](../src/YT-DPI.App/ConfigEditDialog.cs)): **CheckBox** в стиле радио для IPv4/IPv6, **DropDownList** для режима TLS и типа прокси, **FrameView** «Прокси», пароль в **TextField** с **`Secret`**, размер диалога **`Dim.Percent` / `Dim.Auto`**. Сохранение через [`UserConfigSaver`](../src/YT-DPI.Core/Config/UserConfigSaver.cs) (не во время активного скана). После сохранения конфиг перечитывается с диска. Те же действия доступны из меню и дублируются глобальными сочетаниями клавиш.
- Строки таблицы по колонке **RESULT** подсвечиваются разными схемами (доступность / предупреждение / блокировка и т.п.) через **`TableView.Style.RowColorGetter`** (см. [`ScanTableVerdictSchemes`](../src/YT-DPI.App/ScanTableVerdictSchemes.cs)).
- Конфиг: `%LocalAppData%\YT-DPI\YT-DPI_config.json` — чтение через [`UserConfigLoader`](../src/YT-DPI.Core/Config/UserConfigLoader.cs) (дефолты и миграции полей как в `Load-Config` в референс-скрипте репозитория).
- В JSON поддерживается поле **`SchemaVersion`** (0 = старые файлы без поля; новые дефолты в Core — `1`). При сохранении из превью, если значение меньше **1**, выставляется **1** (расширяйте политику версий при добавлении полей).
- Таблица: колонки как **Draw-UI** (**#**, **TARGET DOMAIN**, **IP ADDRESS**, **HTTP**, **TLS 1.2**, **TLS 1.3**, **LAT (ms)**, **RESULT**). Скан: DNS (в т.ч. `DnsCache` из конфига), TCP:80 + LAT, TLS 1.2 и 1.3, вердикт по правилам как в скан-строке PS. При **включённом прокси** используется [`ProxyTunnel`](../src/YT-DPI.Core/Net/ProxyTunnel.cs) (**SOCKS5** с логином/паролем по необходимости, **HTTP** CONNECT + Basic) для **80** и **443**; тип прокси — из **`Proxy.Type`** (`AUTO` в Core трактуется как **SOCKS5** для туннеля).
- Список целей: как **`Get-Targets`** — базовый список + `NetCache.CDN`, сортировка по длине строки ([`ScanTargetsBuilder`](../src/YT-DPI.Core/Scan/ScanTargetsBuilder.cs)). Для коротких прогонов: переменная окружения **`YT_DPI_PREVIEW_MAX_TARGETS=N`**.

### Тесты

```powershell
dotnet test YT-DPI.sln -c Release
```

## CI

[`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml) запускается только для ветки **`feature/terminal-gui`** (push/PR при изменениях в `src/**`, `YT-DPI.sln` или самом workflow): `dotnet build`, **`dotnet test`**, `dotnet publish` для **win-x64** (framework-dependent), артефакты — папка publish и **ZIP**. Workflow **`release-gate`** на этой ветке не настроен (см. `branches-ignore` в репозитории).

Для основной линии (ветка **`master`**): опциональный артефакт **DLL + `YT-DPI.ps1`** — [`.github/workflows/core-ps-bundle.yml`](../.github/workflows/core-ps-bundle.yml), описание [`bundle-core-ps.md`](bundle-core-ps.md).

## Атрибуция

См. [third-party/Terminal.Gui.md](third-party/Terminal.Gui.md).
