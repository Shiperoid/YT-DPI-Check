# YT-DPI.Core

Библиотека переноса логики из **`YT-DPI.ps1`**: сеть, TLS, трассировка, чтение конфига — **без** Terminal.Gui.

## Структура

| Путь | Назначение |
|------|------------|
| [`Config/`](Config/) | Путь к `%LocalAppData%\YT-DPI\YT-DPI_config.json`, DTO, `UserConfigLoader.TryLoadUserConfig` (read-only, совместимо с `Load-Config`). |
| [`Tls/TlsScanner.cs`](Tls/TlsScanner.cs) | Порт встроенного C# из PS (here-string **строки 376–513** `YT-DPI.ps1`). |
| [`Trace/TraceroutePorted.cs`](Trace/TraceroutePorted.cs) | Порт here-string **строки 544–1073** `YT-DPI.ps1` (`SynchronousProgress`, `AdvancedTraceroute`, …). |
| [`Preview/PreviewEngine.cs`](Preview/PreviewEngine.cs) | Тонкие входные точки для превью UI и unit-тестов. |

## Тесты

Проект [`../YT-DPI.Core.Tests/`](../YT-DPI.Core.Tests/) (xUnit).

## Связь с Bash

`YT-DPI.sh` эту DLL не использует; общие спецификации — только документация или JSON, не бинарник.
