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

Окно превью: заголовок **YT-DPI Preview**; выход — **Esc** (как в шаблоне Terminal.Gui).

## CI

Сборка превью: workflow [`.github/workflows/terminal-gui-build.yml`](../.github/workflows/terminal-gui-build.yml) (артефакт publish для Windows при push/PR по затронутым путям).

## Атрибуция

См. [third-party/Terminal.Gui.md](third-party/Terminal.Gui.md).

## Связь с `YT-DPI.sh`

Превью **desktop-only** (.NET + Terminal.Gui). Скрипт **`YT-DPI.sh`** для Linux/роутеров остаётся отдельной линией; перенос логики скана в общую библиотеку — см. [src/YT-DPI.Core/README.md](../src/YT-DPI.Core/README.md).
