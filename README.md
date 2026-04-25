# YT-DPI v2.2.0
![GitHub Release](https://img.shields.io/badge/release-2.2.0-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)
[![Telegram Channel](https://img.shields.io/badge/Telegram-blue)](https://t.me/YT_DPI)

[[Русский](README_ru.md)] | [[Telegram](https://t.me/YT_DPI)]

**YT-DPI** is a professional forensic network diagnostic framework designed to dissect and identify Deep Packet Inspection (DPI) and TSPU interference. Unlike standard tools that rely on high-level OS libraries, YT-DPI uses a low-level C# engine to simulate raw TLS handshakes, pinpointing exactly where and how your traffic is being manipulated.

![Preview](https://raw.githubusercontent.com/Shiperoid/YT-DPI/refs/heads/master/img/YT-DPI-v2.2.0.png)

## 🚀 Key Features (v2.2.0)

*   **Low-Level TLS Engine (C#):** Built-in "Barebuh Pro" engine that manually constructs `ClientHello` packets. This bypasses Windows Schannel limitations and identifies subtle DPI blocks that standard tools miss.
*   **Dynamic Responsive UI:** Automatically calculates table widths based on IP address lengths (IPv4/IPv6). Features an ultra-smooth real-time "Waterfall" results display.
*   **Multi-Protocol Depth:** Independent testing of Port 80 (HTTP), Port 443 (TLS 1.2), and Port 443 (TLS 1.3) with a new **THROTTLED** status detection.
*   **Dual-Stack Control:** Toggle between `IPv6 Priority` and `IPv4 Only` via the new Settings menu to find "holes" in ISP filtering.
*   **PowerShell 7 (Core) Optimized:** Auto-detects and runs on `pwsh.exe` for enhanced socket performance and faster execution.
*   **Universal Proxy Tunneling:** Full SOCKS5/HTTP support with improved SSL-over-Proxy handling for ISP/GEO metadata retrieval.
*   **Forensic Deep Trace:** Custom L4 TCP Traceroute to identify the specific network hop where the DPI middlebox injects RST packets.

## 🧠 The Knowledge Base: Why YouTube Lags?

| Problem | Technical Explanation | Solution |
| :--- | :--- | :--- |
| **SNI Filtering** | ISP "reads" the hostname in cleartext. YT-DPI will show **DPI RESET**. | Use [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) or [Zapret](https://github.com/bol-van/zapret). |
| **QUIC Blocking** | ISPs block UDP Port 443. YT-DPI identifies this via L4 timeouts. | Disable QUIC in `chrome://flags/#enable-quic`. |
| **Kyber Algorithm** | Post-Quantum packets break old DPI parsers. Causes **THROTTLED** status. | Disable Kyber in `chrome://flags/#enable-tls13-kyber`. |
| **IP/CDN Blocking** | Direct block of Google/CDN nodes. YT-DPI will show **IP BLOCK**. | Use a Proxy/VPN or advanced IP fragmentation. |

## 🛠 Usage & Hotkeys

1.  **Run `YT-DPI.bat`** (No installation required).
2.  **[ENTER]** — Start global multi-threaded scan.
3.  **[S]** — **Settings:** Change IP preference (v4/v6) or clear network cache.
4.  **[P]** — **Proxy:** Configure SOCKS5/HTTP tunnel with history support.
5.  **[D]** — **Deep Trace:** Pinpoint the censorship node by domain index.
6.  **[R]** — **Report:** Export forensic results to `YT-DPI_Report.txt`.
7.  **[U]** — **Update:** Check for the latest version on GitHub.

## 🔗 Community & Credits
This project stands on the shoulders of giants in the DPI-circumvention scene:
*   [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) — The definitive Windows bypasser by ValdikSS.
*   [Zapret](https://github.com/bol-van/zapret) — Powerful multi-platform bypass engine by bol-van.
*   [B4](https://github.com/DanielLavrushin/b4) — Advanced network diagnostic tool by Daniel Lavrushin.
*   [dpi-detector](https://github.com/Runnin4ik/dpi-detector) — Research on TSPU/DPI detection.

## ⚖️ License & Disclaimer
Licensed under **MIT**. This tool is for **diagnostic and educational purposes only**. It does not provide bypass capabilities but helps you verify and calibrate your circumvention tools.

---
*Developed with ❤️ for the open internet.*