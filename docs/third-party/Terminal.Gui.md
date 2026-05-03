# Terminal.Gui (third-party)

Превью-ветка **Terminal.Gui** в этом репозитории использует библиотеку **Terminal.Gui** — кроссплатформенный UI toolkit для .NET (TUI).

## Проект и авторы

- **Репозиторий:** [gui-cs/Terminal.Gui](https://github.com/gui-cs/Terminal.Gui)
- **Документация:** [Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/)
- **Организация на GitHub:** [gui-cs](https://github.com/gui-cs)

Список участников и историю коммитов см. в репозитории проекта выше.

## Лицензия

Лицензия распространения пакета **Terminal.Gui** указана в репозитории (файл `LICENSE` / `LICENSE.md`) и на странице пакета NuGet для версии, зафиксированной в [`src/YT-DPI.App/YT-DPI.App.csproj`](../../src/YT-DPI.App/YT-DPI.App.csproj) (`PackageReference`). При обновлении версии пакета сверяйте актуальную лицензию на NuGet и в upstream-репозитории.

## Использование в YT-DPI

Используется только **превью-приложение** в каталоге `src/YT-DPI.App/` (целевая платформа **net10.0**, пакет **Terminal.Gui** версии из `PackageReference` в csproj). UI превью опирается на идиомы v2 (**MenuBar**, **FrameView**, **TableStyle**, **StatusBar** / **Shortcut**). Основная поставка для пользователей по-прежнему **`YT-DPI.bat`** + **`YT-DPI.ps1`** (ветка `master` / релизы).
