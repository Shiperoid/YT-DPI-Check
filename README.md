# YT-DPI Check v1.0.2
![GitHub Release](https://img.shields.io/badge/release-1.0.1-red)
![License](https://img.shields.io/badge/license-MIT-blue)

[[Русский язык](README_ru.md)]

### Overview
**YT-DPI Check** is a lightweight, zero-dependency diagnostic utility designed to identify how YouTube and Google services are being restricted. It goes beyond simple pings by performing deep protocol analysis (TLS SNI Handshakes and QUIC probes) to distinguish between server issues, IP blocks, and active Deep Packet Inspection (DPI/TSPU) interference.

### Key Features
*   **QUIC/UDP Analysis:** Probes UDP port 443 to see if modern high-speed protocols are being throttled or blocked.
*   **SNI Handshake Test:** Specifically tests the "Server Name Indication" field to detect filters that trigger only when they "see" you visiting YouTube.
*   **Active Reset Detection:** Identifies if a middlebox (TSPU) is actively sending `TCP RST` packets to kill your connection.
*   **CDN Discovery:** Automatically locates your nearest Google Global Cache (GGC) node for precise video-stream testing.
*   **Comprehensive Coverage:** Tests main UI, video servers (googlevideo), and essential APIs (googleapis).

### How to Use
1.  Download **`YT-DPI-Check.bat`** from the [latest release](../../releases/latest).
2.  Double-click to run. No installation or Administrator rights required.
3.  Review the table and the final **DIAGNOSIS** summary.

---

### Comprehensive Status Guide

#### Column: TCP / TLS
*   **OK**: Success. The connection was established and the handshake completed.
*   **FL (Failed)**: The port is closed or the server is completely unreachable at the network level.
*   **DR (Dropped)**: **[DPI Alert]** The packet was sent, but the server "disappeared." This happens when DPI identifies the SNI and silently discards your packets.
*   **RS (Reset)**: **[Active DPI Alert]** The connection was established, but as soon as the SNI was sent, a "Connection Reset" was forcibly injected by a middlebox.
*   **--**: Skipped because a previous mandatory step (like DNS) failed.

#### Column: UDP
*   **OK**: The port is open, and a QUIC probe suggests the protocol is allowed.
*   **BK (Blocked)**: The ISP is explicitly rejecting UDP traffic on port 443 (often used to throttle YouTube to 1080p or lower).
*   **??**: State unknown or test timed out.

#### Column: RESULT (Verdict)
| Verdict | Meaning |
| :--- | :--- |
| **AVAILABLE** | The service is working normally. |
| **DPI BLOCK** | Active filtering detected. Connection is blocked based on the site name (SNI). |
| **IP BLOCK** | The IP address itself is unreachable (IP-level blacklist). |
| **DNS ERROR** | Your DNS provider is giving incorrect data or failing to resolve the domain. |

---

### Contributing
Contributions are accepted through GitHub pull requests. Whether it's adding new target domains or improving protocol detection, feel free to help!

### Credits
This tool is built upon the collective research of the DPI-bypass community:
*   [youtubeUnblock](https://github.com/Waujito/youtubeUnblock) - C-based DPI bypass research.
*   [B4](https://github.com/DanielLavrushin/b4) - Network packet processor with a friendly UI.
*   [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) - The industry standard for Windows DPI circumvention.
*   [zapret](https://github.com/bol-van/zapret) - Advanced multi-platform DPI bypass techniques.
*   [dpi-detector](https://github.com/Runnin4ik/dpi-detector) - Foundational DPI/TSPU detection techniques.

---
*Disclaimer: This tool is for diagnostic and educational purposes only.*
