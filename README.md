# YT-DPI — Terminal.Gui preview (.NET)

[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Telegram Channel](https://img.shields.io/badge/Telegram-blue)](https://t.me/YT_DPI)

Ветка **`feature/terminal-gui`**: экспериментальный **TUI** на **[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/)** и общая логика в **`YT-DPI.Core`** (.NET 10, без Bash и без отдельного Windows-лаунчера в этом README).

## Состав репозитория

| Путь | Назначение |
|------|-------------|
| [`src/YT-DPI.App/`](src/YT-DPI.App/) | Исполняемое превью: окно, таблица скана, статус. |
| [`src/YT-DPI.Core/`](src/YT-DPI.Core/) | Конфиг (чтение/запись JSON), TLS, трассировка (порт из встроенного C#), оркестрация превью-скана. |
| [`src/YT-DPI.Core.Tests/`](src/YT-DPI.Core.Tests/) | xUnit, smoke и round-trip конфига. |
| [`docs/terminal-gui-preview.md`](docs/terminal-gui-preview.md) | Сборка, CI, ограничения превью. |
| [`docs/terminal-gui-migration-todo.md`](docs/terminal-gui-migration-todo.md) | Чеклист миграции. |
| [`docs/terminal-gui-merge-policy.md`](docs/terminal-gui-merge-policy.md) | Политика ветки и merge в `master`. |
| [`docs/third-party/Terminal.Gui.md`](docs/third-party/Terminal.Gui.md) | Атрибуция upstream Terminal.Gui. |

## Требования

- **[.NET 10 SDK](https://dotnet.microsoft.com/download)** (пакет Terminal.Gui 2.x ориентирован на `net10.0`).
- Терминал с нормальным размером окна (как минимум десятки строк и колонок), желательно **Windows Terminal**.

## Сборка и тесты

Из корня клонированного репозитория:

```powershell
dotnet build YT-DPI.sln -c Release
dotnet test YT-DPI.sln -c Release
```

## Запуск превью

```powershell
dotnet run --project src/YT-DPI.App/YT-DPI.App.csproj
```

Либо скрипты в **`tools/`**:

- [`tools/Run-YT-DPI-Preview.ps1`](tools/Run-YT-DPI-Preview.ps1)
- [`tools/Run-YT-DPI-Preview.bat`](tools/Run-YT-DPI-Preview.bat)

## Поведение UI (кратко)

Подробно: [`docs/terminal-gui-preview.md`](docs/terminal-gui-preview.md).

- Конфиг: `%LocalAppData%\YT-DPI\YT-DPI_config.json`, поле **`SchemaVersion`**, скан по списку целей как **Get-Targets** (базовые домены + CDN из кэша).
- Таблица: колонки **Draw-UI**; заполняются DNS, HTTP:80 + LAT, TLS 1.2 / 1.3 и вердикт (при прокси часть колонок см. док).
- **Esc** — выход. **Ctrl+C** — отмена скана. **F5** — пересканировать. **`YT_DPI_PREVIEW_MAX_TARGETS`** — ограничить число целей.

## CI и артефакты

Workflow **[`.github/workflows/terminal-gui-build.yml`](.github/workflows/terminal-gui-build.yml)** (push/PR по `src/**` и решению): `dotnet build`, **`dotnet test`**, **`dotnet publish`** (`win-x64`, framework-dependent).

В [Actions](https://github.com/Shiperoid/YT-DPI/actions) откройте последний запуск **terminal-gui-build** → **Artifacts** → **`yt-dpi-gui-preview-win-x64`**: внутри папка **`publish/`** и архив **`yt-dpi-gui-preview-win-x64.zip`**. Нужен установленный **.NET 10 runtime** (self-contained в этом workflow не используется). Запуск: распаковать и выполнить **`YT-DPI.App.exe`** из каталога publish.

Политика слияния с `master`: [`docs/terminal-gui-merge-policy.md`](docs/terminal-gui-merge-policy.md).

## Зачем отдельная ветка

Цель — развивать богатый консольный UI и перенос движка в **одну .NET-библиотеку** без смешения с другими линиями поставки в этом README.

## Благодарности и ссылки

Идеи и контекст сообщества по DPI:

- [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) — ValdikSS  
- [Zapret](https://github.com/bol-van/zapret) — bol-van  
- [B4](https://github.com/DanielLavrushin/b4) — Даниил Лаврушин  
- [dpi-detector](https://github.com/Runnin4ik/dpi-detector)

## Лицензия

Проект распространяется по лицензии **MIT**. Инструмент предназначен для **диагностики** сетевого доступа.
