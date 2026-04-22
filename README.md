# YT-DPI v2.1.4
![GitHub Release](https://img.shields.io/badge/release-2.1.4-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)
[![Telegram Channel](https://img.shields.io/badge/Telegram-blue)](https://t.me/YT_DPI)

[[Русский](README_ru.md)] | [[Telegram](https://t.me/YT_DPI)]

**YT-DPI** is a professional forensic network diagnostic framework designed to dissect and identify Deep Packet Inspection (DPI) and TSPU interference. While standard tools just "ping", YT-DPI simulates browser-level TLS handshakes and performs L4-layer analysis to pinpoint exactly where and how your traffic is being manipulated.

![Preview](https://raw.githubusercontent.com/Shiperoid/YT-DPI/refs/heads/master/img/YT-DPI-v2.1.3.png)

## 🚀 Key Features (v2.1+)

*   **Persistent Analytics Core:** Stores network state, ISP metadata, and high-speed DNS mappings in `%LOCALAPPDATA%`. Launch time is reduced to <1s.
*   **Multi-Protocol Engine:** Independent testing of Port 80 (HTTP), Port 443 (TLS 1.2), and Port 443 (TLS 1.3) to find the specific layer of censorship.
*   **Smart Dual-Stack:** Native IPv6 diagnostic support. Automatically detects global IPv6 availability and prioritizes it to find "holes" in IPv4-only ISP filters.
*   **Forensic Deep Trace:** Custom L4 TCP Traceroute. Unlike standard ICMP trace, this tool identifies the specific network hop where the DPI middlebox injects RST packets or drops traffic.
*   **Universal Proxy Tunneling:** Full SOCKS5/HTTP support with auto-negotiation. Validate your bypass tools (GoodbyeDPI, Zapret, etc.) with objective TLS metrics.

## 🧠 The Knowledge Base: Why YouTube Lags?

| Problem | Technical Explanation | Solution |
| :--- | :--- | :--- |
| **SNI Filtering** | ISP "reads" the hostname (youtube.com) in cleartext before encryption starts. | Use [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) or [Zapret](https://github.com/bol-van/zapret). |
| **QUIC Blocking** | ISPs often block UDP Port 443 entirely. Browsers use QUIC by default. | Disable QUIC in `chrome://flags/#enable-quic`. |
| **Kyber Algorithm** | Modern TLS 1.3 use large Post-Quantum packets that break old DPI parsers. | Disable Kyber in `chrome://flags/#enable-tls13-kyber`. |
| **GGC Throttling** | Artificial speed limits applied to local Google Global Cache nodes. | Use a Proxy/VPN or advanced fragmentation. |

## 🛠 Usage & Hotkeys

1.  **Run `YT-DPI.bat`** (No installation required).
2.  **[ENTER]** — Start global multi-threaded scan.
3.  **[D]** — Deep Trace: Pinpoint the censorship node by domain index.
4.  **[P]** — Configure Proxy (`127.0.0.1:1080`). Auto-detects protocol.
5.  **[T]** — Proxy Health Check (Latency & Header validation).
6.  **[S]** — Export forensic report to `YT-DPI_Report.txt`.

## 🔗 Community & Credits
This project stands on the shoulders of giants in the DPI-circumvention scene:
*   [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) — The definitive Windows bypasser by ValdikSS.
*   [Zapret](https://github.com/bol-van/zapret) — Powerful multi-platform bypass engine by bol-van.
*   [B4](https://github.com/DanielLavrushin/b4) — Advanced network diagnostic tool by Daniel Lavrushin.
*   [dpi-detector](https://github.com/Runnin4ik/dpi-detector) — Research on TSPU/DPI detection.
*   [youtubeUnblock](https://github.com/Waujito/youtubeUnblock) — C-based bypass techniques.

## ⚖️ License & Disclaimer
Licensed under **MIT**. This tool is for **diagnostic and educational purposes only**. It does not provide bypass capabilities but helps you configure them correctly.

---
*Developed with ❤️ for the open internet.*