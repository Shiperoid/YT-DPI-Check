# YT-DPI.Core

Библиотека переноса логики из **`YT-DPI.ps1`**: сеть, TLS, трассировка, чтение конфига — **без** Terminal.Gui.

## Структура

| Путь | Назначение |
|------|------------|
| [`Config/`](Config/) | Путь к `%LocalAppData%\YT-DPI\YT-DPI_config.json`, DTO, `UserConfigLoader.TryLoadUserConfig` (read-only, совместимо с `Load-Config`). |
| [`Tls/TlsScanner.cs`](Tls/TlsScanner.cs) | TLS 1.3 probe; через прокси — [`Net/ProxyTunnel.cs`](Net/ProxyTunnel.cs) (SOCKS5 с auth, HTTP CONNECT). |
| [`Net/ProxyTunnel.cs`](Net/ProxyTunnel.cs) | Туннель SOCKS5 / HTTP CONNECT к `host:port` как в `YT-DPI.ps1` ~2980–3120. |
| [`Trace/TraceroutePorted.cs`](Trace/TraceroutePorted.cs) | Порт here-string **строки 544–1073** `YT-DPI.ps1` (`SynchronousProgress`, `AdvancedTraceroute`, …). |
| [`Preview/PreviewEngine.cs`](Preview/PreviewEngine.cs) | Тонкие входные точки для превью UI и unit-тестов. |
| [`Scan/`](Scan/) | `ScanTargetsBuilder` (`Get-Targets`), `DnsConnectIpResolver` (кэш DNS + выбор IP), `TargetRowScanner` (одна строка таблицы, логика как в PS ~4612–4872), `PreviewScanRunner` (оркестрация цикла), `VerdictCalculator`, `Tls12Probe`, `PortConnectivity`, таймауты. |
| [`Config/UserConfigSaver.cs`](Config/UserConfigSaver.cs) | Запись JSON (PascalCase, совместимо с `ConvertTo-Json` / `Save-Config`). |

## Тесты

Проект [`../YT-DPI.Core.Tests/`](../YT-DPI.Core.Tests/) (xUnit).

## Связь с Bash

`YT-DPI.sh` эту DLL не использует; общие спецификации — только документация или JSON, не бинарник.
