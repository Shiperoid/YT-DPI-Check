# YT-DPI
![GitHub Release](https://img.shields.io/badge/release-2.0-red)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)

[[Русский](README_ru.md)]

### Overview
**YT-DPI** — Is an advanced, multi-threaded diagnostic utility designed to identify how YouTube and Google services are being restricted by your ISP. It goes beyond simple pings by performing deep protocol analysis across Cleartext HTTP, TLS 1.2, and TLS 1.3 to accurately distinguish between hard IP bans, silent packet drops, and active Deep Packet Inspection (DPI/TSPU) interference.
![[preview](https://raw.githubusercontent.com/Shiperoid/YT-DPI-Check/refs/heads/master/img/preview-yt-dpi-2.0.png)](https://raw.githubusercontent.com/Shiperoid/YT-DPI-Check/refs/heads/master/img/preview-yt-dpi-2.0.png)
### System Requirements
*   **OS:** Windows 10 or Windows 11 (recommended).
*   **Legacy OS:** Windows 7 / 8.1 are supported but require **PowerShell 5.1** and **.NET Framework 4.5+** installed.
*   **Environment:** PowerShell 5.1 or higher. No external dependencies.

### Key Features
*   **Active RST & DRP Detection:** Monitors for forged `TCP RST` (Reset) packets actively injected by middleboxes (TSPU/DPI), as well as silent `DRP` (Drops/Blackholes) where the connection simply times out during the TLS handshake upon detecting restricted SNI.
*   **IP Blacklist vs. Deep Inspection:** Compares Cleartext HTTP (Port 80) reachability against TLS (Port 443) to definitively separate hard IP routing bans (blackholes) from surgical DPI traffic filtering.
*   **Granular Protocol Testing:** Separately tests Port 443 across different encryption standards (TLS 1.2 & TLS 1.3), as modern DPI algorithms often apply different filtering rules based on the protocol version.
*   **Network Intelligence & Localization:** Auto-detects your active DNS, ISP name, City, and dynamically resolves the nearest Google Global Cache (CDN) node for precise, localized video-stream testing.
*   **Multi-Threaded Engine:** Utilizes PowerShell `RunspacePools` for lightning-fast, concurrent scanning of multiple domains without blocking the main execution thread.
*   **Smart OS Detection:** Automatically detects if your OS lacks native TLS 1.3 support (e.g., Windows 7/older Win10) to prevent false-positive block reports.
*   **Live Telemetry & Cyberpunk UI:** Interactive console with dynamic hex-decoding animations, real-time ping tracking, RAM usage, live packet-drop counters, and instant abort capabilities.

### How to Use
1.  Download the latest `.bat` file from the [Releases](../../releases/latest) page.
2.  Double-click to run. **No Administrator rights required.**
3.  Press `[ENTER]` to start the scan.
4.  Press `[H]` at any time to open the built-in mini-guide and legend.
5.  Press `[Q]` or `[ESC]` to instantly abort the scan or exit the tool.

---

### Comprehensive Status Guide

#### The Columns
*   **HTTP (Port 80):** Sends a cleartext baseline request. Used to check if the IP is reachable at all.
*   **TLS 1.2 (Port 443):** The most common secure protocol for YouTube. Tests if the ISP drops or resets the connection after seeing the SNI (Server Name Indication).
*   **TLS 1.3 (Port 443):** Modern, more secure protocol. Harder for some DPIs to parse, but heavily targeted by modern TSPU filters.
*   **LAT (Latency):** Real TCP handshake latency (ping) to the server.

#### Status Codes
*   **OK**: Success. The connection was established and the handshake completed without interference.
*   **RST**: Connection Reset. The DPI/TSPU explicitly intercepted the packet and injected a TCP Reset to kill your connection.
*   **DRP**: Connection Dropped. The packet was silently discarded (blackholed) by the DPI or firewall, causing the TLS handshake to time out.
*   **N/A**: Not Available. Your operating system does not support this protocol natively (usually seen in the TLS 1.3 column on Windows 7/10).
*   **FAIL**: Connection timed out completely or a general socket/routing error occurred before the handshake could even begin.

#### RESULT (Verdict)
| Verdict | Meaning |
| :--- | :--- |
| **AVAILABLE** | TLS handshake passed. YouTube should work fine on this domain. |
| **DPI BLOCK** | HTTP works (the server is reachable), but the secure TLS connection is actively blocked or dropped by the provider (Typical DPI behavior). |
| **IP BLOCK** | Both HTTP and TLS are unreachable. The IP address itself is blacklisted or routed to a blackhole. |
| **DNS_ERR** | Your DNS provider is giving incorrect data or failing to resolve the domain entirely. |

---

### Important Notes
*   **Antivirus:** Some AV software may flag the script as a "Generic Downloader" or "Network Tool" because it performs manual TCP socket connections. The script is open-source; you can inspect the code in any text editor.
*   **VPN/Proxies & Bypassers:** If you have a VPN or DPI-bypass software (like GoodbyeDPI or Zapret) running, the script will show "AVAILABLE (CLEAN)" because the traffic is successfully circumventing the ISP filter. Turn them off for an accurate "raw" ISP test.

### Contributing
Contributions are accepted through GitHub pull requests. Whether it's adding new target domains, optimizing the Runspace pool, or improving protocol detection, feel free to help!

### Credits
This tool is built upon the collective research of the DPI-bypass community:
*   [youtubeUnblock](https://github.com/Waujito/youtubeUnblock) - C-based DPI bypass research.
*   [B4](https://github.com/DanielLavrushin/b4) - Network packet processor with a friendly UI.
*   [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) - The industry standard for Windows DPI circumvention.
*   [zapret](https://github.com/bol-van/zapret) - Advanced multi-platform DPI bypass techniques.
*   [dpi-detector](https://github.com/Runnin4ik/dpi-detector) - Foundational DPI/TSPU detection techniques.

---
*Disclaimer: This tool is for diagnostic and educational purposes only.*
