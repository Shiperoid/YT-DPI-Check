# Превью: YT-DPI на Terminal.Gui

Экспериментальная линия разработки в ветке **`feature/terminal-gui`**: настольное **.NET**-приложение с TUI на **[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/)**.

## Зачем

Отдельная ветка позволяет исследовать богатый консольный UI (layout, двойная буферизация, виджеты) без риска для текущей стабильной поставки **`YT-DPI.ps1`** + **`YT-DPI.bat`**.

## Сборка локально

Требуется [.NET 10 SDK](https://dotnet.microsoft.com/download) (см. `TargetFramework` в [`src/YT-DPI.App/YT-DPI.App.csproj`](../src/YT-DPI.App/YT-DPI.App.csproj)). Пакет **Terminal.Gui 2.0.x** на NuGet ориентирован на **net10.0**.

```powershell
cd src/YT-DPI.App
dotnet run
```

Из корня репозитория:

```powershell
dotnet run --project src/YT-DPI.App/YT-DPI.App.csproj
```

Окно превью: заголовок **YT-DPI Preview**; выход — **Esc**; во время скана **Ctrl+C** отменяет фоновый TLS 1.3-проход. Таблица повторяет колонки консольного **Draw-UI** в `YT-DPI.ps1` (**#**, **TARGET DOMAIN**, **IP ADDRESS**, **HTTP**, **TLS 1.2**, **TLS 1.3**, **LAT (ms)**, **RESULT**); HTTP / TLS 1.2 / LAT в превью пока заглушки **`---`**.

Превью **только читает** `%LocalAppData%\YT-DPI\YT-DPI_config.json` (тот же путь и правила дефолтов/миграции, что в `Load-Config` в `YT-DPI.ps1`) и показывает поля в шапке; **запись конфига из .NET не выполняется** — настройки по-прежнему сохраняет PowerShell-версия.

### Тесты

```powershell
dotnet test YT-DPI.sln -c Release
```

## CI

Сборка превью: workflow [`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml) — `dotnet build`, **`dotnet test`**, затем publish и артефакт для Windows при push/PR по затронутым путям.

## Запись конфига из превью (отложено)

Редактирование и сохранение `YT-DPI_config.json` из .NET не реализовано: нужны согласованная схема с `Save-Config` в PowerShell и round-trip тесты. До стабилизации чтения и переноса движка не начинать.

## Атрибуция

См. [third-party/Terminal.Gui.md](third-party/Terminal.Gui.md).

## Связь с `YT-DPI.sh`

Превью **desktop-only** (.NET + Terminal.Gui). Скрипт **`YT-DPI.sh`** для Linux/роутеров остаётся отдельной линией; перенос логики скана в общую библиотеку — см. [src/YT-DPI.Core/README.md](../src/YT-DPI.Core/README.md).
