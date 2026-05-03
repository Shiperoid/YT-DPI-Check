# Превью: YT-DPI на Terminal.Gui

Экспериментальная линия в ветке **`feature/terminal-gui`**: **.NET** + TUI на **[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/)**.

## Сборка

Требуется [.NET 10 SDK](https://dotnet.microsoft.com/download) (см. `TargetFramework` в [`src/YT-DPI.App/YT-DPI.App.csproj`](../src/YT-DPI.App/YT-DPI.App.csproj)).

```powershell
dotnet run --project src/YT-DPI.App/YT-DPI.App.csproj
```

## Поведение

- **Esc** — выход. **Ctrl+C** — отмена фонового скана. **F5** — пересканировать.
- Конфиг: `%LocalAppData%\YT-DPI\YT-DPI_config.json` — чтение через [`UserConfigLoader`](../src/YT-DPI.Core/Config/UserConfigLoader.cs) (дефолты и миграции полей как в `Load-Config` в референс-скрипте репозитория).
- В JSON поддерживается поле **`SchemaVersion`** (0 = старые файлы без поля; новые дефолты в Core — `1`). Сериализация/запись: [`UserConfigSaver`](../src/YT-DPI.Core/Config/UserConfigSaver.cs); в превью **TUI пока не вызывает сохранение** на диск (только отображение и скан).
- Таблица: колонки как **Draw-UI** (**#**, **TARGET DOMAIN**, **IP ADDRESS**, **HTTP**, **TLS 1.2**, **TLS 1.3**, **LAT (ms)**, **RESULT**). Скан: DNS (в т.ч. `DnsCache` из конфига), TCP:80 + LAT, TLS 1.2 и 1.3, вердикт по правилам как в скан-строке PS. При **включённом прокси** TLS 1.3 идёт через существующий [`TlsScanner`](../src/YT-DPI.Core/Tls/TlsScanner.cs); колонки **HTTP** / **TLS 1.2** остаются **`---`** до порта SOCKS/HTTP CONNECT для 80/443 в Core.
- Список целей: как **`Get-Targets`** — базовый список + `NetCache.CDN`, сортировка по длине строки ([`ScanTargetsBuilder`](../src/YT-DPI.Core/Scan/ScanTargetsBuilder.cs)). Для коротких прогонов: переменная окружения **`YT_DPI_PREVIEW_MAX_TARGETS=N`**.

### Тесты

```powershell
dotnet test YT-DPI.sln -c Release
```

## CI

[`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml): `dotnet build`, **`dotnet test`**, `dotnet publish` для **win-x64** (framework-dependent), загрузка папки publish и **ZIP**-архива как отдельный артефакт.

## Атрибуция

См. [third-party/Terminal.Gui.md](third-party/Terminal.Gui.md).
