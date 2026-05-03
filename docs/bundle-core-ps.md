# Поставка `YT-DPI.ps1` + `YT-DPI.Core.dll` (гибрид)

Скрипт **[`tools/bundle-core-ps.ps1`](../tools/bundle-core-ps.ps1)** собирает проект **`src/YT-DPI.Core/YT-DPI.Core.csproj`** (Release) и копирует в **`artifacts/yt-dpi-core-ps/`**:

- `YT-DPI.ps1`, `YT-DPI.bat`
- `lib/net472/YT-DPI.Core.dll` — для Windows PowerShell 5.1
- `lib/net8.0/YT-DPI.Core.dll` — для PowerShell Core (`pwsh`)

Workflow **[`.github/workflows/core-ps-bundle.yml`](../.github/workflows/core-ps-bundle.yml)** выкладывает эту папку как артефакт **`yt-dpi-core-ps`**.

Переопределение пути к одной DLL: переменная окружения **`YT_DPI_CORE_DLL`** (полный путь к `YT-DPI.Core.dll`).

## Связь с `YT-DPI.ps1`

Скрипт грузит типы **`YtDpi.*`** через **`Add-Type -Path`** после резолва пути (см. блок «YT-DPI.Core.dll» в начале `YT-DPI.ps1`). Кроме **`TlsScanner`** и **`AdvancedTraceroute`**, для основного скана используются **`TcpTimeouts`**, **`ProxyThrough`**, **`HttpPortProbe`**, **`Tls12Scripting`** (сетевой слой и TLS 1.2 в Core; в PS остаются DNS-кэш, mutex, выбор IP и оркестрация вердиктов). **PowerShell 6.x** не поддерживается для этой DLL (**net8.0**); используйте **Windows PowerShell 5.1** или **pwsh 7+**.
