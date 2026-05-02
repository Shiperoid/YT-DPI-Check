# Machine-readable API (NDJSON over stdout)

Windows PowerShell script **`YT-DPI.ps1`** can emit **one UTF-8 JSON object per line** (NDJSON / JSON Lines) so any host (Go, Rust, Python, Node, C#, …) can spawn `pwsh` and parse stdout line by line.

## Launch

```powershell
pwsh -NoProfile -File .\YT-DPI.ps1 -JsonStream
```

`-Headless` is an **alias** for the same behaviour (either switch enables the stream).

Interactive UI is **not** used; no keyboard handling during the scan.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Scan finished normally |
| `1` | No connectivity to `8.8.8.8` (quick ping/TCP check) |
| `2` | Scan aborted (reserved; interactive abort is not used in stream mode) |

## Schema

Every object includes a `type` field. The first full session object uses:

- `schema`: **`yt-dpi.ndjson/v1`** (on `session_start`)

## Event types

### `progress`

Optional human-oriented phase marker (safe to ignore for logic).

- `phase` — string, e.g. `network_lookup`
- `message` — string

### `session_start`

Emitted once targets are built.

- `schema`, `version`, `ps_edition`, `ps_version`
- `os_caption`, `os_version`, `is_admin`, `culture`
- `target_count`, `proxy_enabled`

### `target_result`

One line per target, in scan order.

- `index` — 0-based row index in this run
- `row_number` — 1-based label (same as UI row number)
- `host`, `ip`, `http`, `tls12`, `tls13`, `latency`, `verdict`

`latency` is a string as measured in the script (e.g. `42ms`). `verdict` values match the console tool (e.g. `AVAILABLE`, `THROTTLED`, `DPI BLOCK`, …).

### `error`

- `code` — e.g. `no_internet`
- `message` — string

### `session_end`

- `ok` — boolean
- `aborted` — boolean
- `summary` — object with `target_count`, `results`, `by_verdict` (counts per verdict string)

## Example (first lines)

```json
{"type":"progress","phase":"network_lookup","message":"Get-NetworkInfo (ISP/DNS/CDN); may take a short while."}
{"type":"session_start","schema":"yt-dpi.ndjson/v1","version":"2.2.3","target_count":25,"proxy_enabled":false}
{"type":"target_result","index":0,"host":"youtu.be","ip":"…","http":"OK","tls12":"DRP","tls13":"OK","latency":"208ms","verdict":"THROTTLED","row_number":1}
```

## Notes

- Use **`Write-Output` / success stream** semantics: redirect with `pwsh … > file.ndjson` works line-by-line.
- Proxy and DNS cache behaviour is the same as the interactive script (`%LOCALAPPDATA%\YT-DPI\YT-DPI_config.json`).
