# Сборка «Core DLL + YT-DPI.ps1»

Артефакт **`yt-dpi-core-ps-bundle`** (workflow **`core-ps-bundle`**) содержит:

- **`YT-DPI.Core.dll`** — опубликованная библиотека из `src/YT-DPI.Core`;
- **`YT-DPI.ps1`** — скрипт из корня репозитория;
- **`README-bundle.md`** — эта заметка.

Положите **`YT-DPI.Core.dll`** в тот же каталог, что и **`YT-DPI.ps1`**, чтобы скрипт подхватил типы из DLL (см. логику `Try-LoadYtDpiCoreDll` в скрипте). Нужен **.NET 10 runtime** на машине, если вы не публикуете self-contained.

Этот zip **не** заменяет артефакт превью Terminal.Gui (`terminal-gui-build` на ветке `feature/terminal-gui`).
