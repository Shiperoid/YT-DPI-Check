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

- Читает тот же файл конфигурации, что и основная линия продукта: `%LocalAppData%\YT-DPI\YT-DPI_config.json` (см. `docs/terminal-gui-preview.md`).
- Таблица скана повторяет набор колонок консольного **Draw-UI**; в превью по шагам заполняется в первую очередь **TLS 1.3**, остальные колонки могут оставаться заглушками до следующих итераций.
- **Esc** — выход из приложения.
- **Ctrl+C** — отмена фонового скана.

## CI

Workflow **[`.github/workflows/terminal-gui-build.yml`](.github/workflows/terminal-gui-build.yml)**: сборка решения, `dotnet test`, publish и артефакт для Windows при изменениях по заданным путям.

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
