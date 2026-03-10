## Initial Stable Release (v1.0.0)

YT-DPI Check is a lightweight diagnostic utility designed to identify YouTube connection issues caused by DPI (Deep Packet Inspection) or IP-level blocking.

### Key Features:
- **Single-File Execution:** Runs via a `.bat` wrapper with a simple double-click. No manual PowerShell execution policy configuration is required.
- **Smart Diagnosis:** Distinguishes between DPI interference (SNI dropping), IP-level blocks, and DNS issues.
- **Modern & Legacy OS Support:** Fully compatible with Windows 7, 10, and 11 (TLS 1.2/1.3).
- **Optimized UI:** Compact table layout designed for standard 80-column console windows.

### How to use:
1. Download the **`YT-DPI-Check.bat`** file from the Assets below.
2. Run the file by double-clicking it.
3. Review the diagnostic table and the final summary.

---
*Disclaimer: This tool is intended for diagnostic and educational purposes only.*

## Hotfix 1.0.1
Fix cdn detection bug
**Full Changelog**: https://github.com/Shiperoid/YT-DPI-Check/commits/1.0.1

# YT-DPI Check Release v1.1.1

This major update transforms YT-DPI Check from a simple one-time scanner into a powerful interactive diagnostic tool. It is now optimized for real-time testing of DPI bypass solutions like GoodbyeDPI, Zapret, or ByeDPI.

### New Features

*   Interactive Loop Mode: No need to restart the script! After the analysis, simply press any key to refresh results or Q/Esc to exit. This allows you to toggle your bypass tools and see changes instantly.
*   QUIC (UDP 443) Probing: Added detection for UDP-based blocking. The tool now probes for QUIC protocol availability, identifying if your ISP is throttling YouTube by dropping UDP packets.
*   Deep TLS Handshake Analysis: Improved logic to distinguish between different DPI behaviors:
    *   DR (Dropped): Silent packet loss after SNI detection.
    *   RS (Reset): Active connection termination via injected TCP RST packets.
*   Dynamic CDN Detection: Automatically identifies and tests your nearest Google Global Cache (GGC) node for more accurate video-streaming diagnostics.
*   Expanded Target Ecosystem: Added critical endpoints including mobile versions (m.youtube.com), signaling servers, and diverse static content hosts (ytimg, ggpht).

### Improvements & Fixes

*   Smart Navigation: Enhanced user input handling to prevent accidental script termination.
*   Legacy OS Support: Refined compatibility for Windows 7 (requires PowerShell 5.1). Note: Win7 lacks native TLS 1.3 support, which may affect result accuracy.
*   Refined Console UI: Improved auto-resizing and alphabetical organization of targets for a cleaner look.

### Status Guide

| Status | Meaning |
| :--- | :--- |
| OK | Connection successful (Handshake passed). |
| DR (Dropped) | Packet sent, but no response (DPI Filter/Silent Drop). |
| RS (Reset) | Connection forcibly closed by a middlebox (Active DPI Reset). |
| BK (Blocked) | UDP/QUIC traffic is explicitly rejected (Throttling indicator). |
| FL (Failed) | Basic TCP connection failed (IP block or port closed). |

---

### Installation
1. Download the YT-DPI-Check.bat from the assets below.
2. Run the file (No Administrator rights required).
3. Follow the on-screen prompts to re-run or exit.

---
*Disclaimer: This tool is for diagnostic purposes only. It helps identify blocking methods but does not provide bypass capabilities itself.*



# YT-DPI Check v2.0

In version 2.0, the utility has been completely rewritten. The tool transitioned from sequential scanning to a multi-threaded architecture and features an entirely new interactive console interface. The update heavily focuses on execution speed, detailed protocol testing, and real-time network analysis.

### Major New Features

* **Multi-threaded Engine (RunspacePools):** Scanning is no longer sequential. The utility now runs up to 20 independent background threads concurrently, reducing the total scan time for all domains from ~30 seconds to just 2-3 seconds.
* **Detailed Protocol Separation:** Instead of grouping all TLS traffic into a single result, the tool now separately tests **Cleartext HTTP (Port 80)**, **TLS 1.2 (Port 443)**, and **TLS 1.3 (Port 443)**. This allows for precise identification of the encryption level at which the TSPU/DPI interrupts the connection.
* **DRP (Drop) Detection:** Added specific detection for silent packet drops (`DRP`). The tool now accurately identifies when a DPI system or firewall blackholes the connection, causing the TLS handshake to time out, distinguishing it from active TCP Resets (`RST`).
* **New Interactive UI:** A static dashboard with absolute cursor positioning (no console scrolling). During operation, it displays dynamic scanning effects: iterative IP octet formatting, Hex-byte cycling on tested ports, and live ping updates.
* **Live Telemetry Panel:** A real-time telemetry panel has been added to the top right corner. During the scan, it updates the active thread count (JOBS), RAM usage, and counters for blocked domains (BLOCKS), reset packets (RST), and successful connections (CLEAN).
* **Advanced Network Analytics:** Before each scan, the utility automatically detects and displays your current active **DNS**, **ISP name**, **Country/City**, and the nearest **Google CDN node**.

### Improvements & Fixes

* **Instant Scan Cancellation:** Pressing `Q` or `ESC` now utilizes asynchronous thread stopping (`BeginStop`). The interface unlocks instantly without waiting for the network timeouts of hanging connections.
* **Console Freeze Protection:** Upon launch, the utility uses a C# API call to automatically disable "QuickEdit Mode" in Windows. Accidental mouse clicks/selections in the console will no longer pause the script's execution.
* **Smart OS Detection for TLS 1.3:** Windows 7 and older Windows 10 builds do not support TLS 1.3 natively. The utility now recognizes this OS limitation and outputs an `N/A` (Not Available) status instead of a false-positive `RST` (Block).
* **Built-in Help Menu:** Added an `[H]` hotkey that opens a mini-guide explaining status codes (OK, RST, DRP, N/A, FAIL) and verdicts directly inside the app, without needing to open a browser.
* **Screen Flicker Eliminated:** The UI rendering mechanism has been optimized. Data is now overwritten on top of old values without fully clearing the console (`Clear-Host`), removing the annoying flicker during repeated scans.

### Status Code Legend
* **OK:** Connection established, TLS handshake completed successfully.
* **RST:** Connection forcefully terminated (TCP Reset) by DPI/TSPU equipment.
* **DRP:** Connection silently dropped (Blackholed), resulting in a TLS handshake timeout.
* **N/A:** Protocol is not supported by your OS natively (e.g., TLS 1.3 on Windows 7).
* **--** / **FAIL:** Socket error or complete unreachability of the IP address before the handshake.

---

### Installation and Usage
1. Download the **`YT-DPI-Check.bat`** file from the Assets section below.
2. Run the file (Administrator privileges are not required).
3. Press `[ENTER]` to start scanning or `[H]` to read the help menu.

*Disclaimer: This tool is intended exclusively for diagnostic and educational purposes. It helps identify blocking methods but is not a bypass tool in itself.*