# YT-DPI Diagnostic Tool

[[Русский язык](readme_ru.md)]


### Overview
**YT-DPI Diagnostic Tool** is a lightweight PowerShell utility designed to identify the exact cause of YouTube accessibility issues. It performs a multi-layered network analysis to distinguish between simple connection failures and sophisticated DPI (Deep Packet Inspection) filtering.

### Key Features
*   **DNS Integrity Check:** Detects DNS hijacking or spoofing (e.g., when a domain resolves to `127.0.0.1`).
*   **TCP Connectivity Check:** Verifies if Google/YouTube IP addresses are reachable on port 443.
*   **SNI Handshake Test:** Simulates a secure connection to detect DPI interference (TSPU).
*   **CDN Node Discovery:** Automatically finds and tests your local Google Global Cache (GGC) node.
*   **Legacy Support:** Fully compatible with Windows 7, 10, and 11 (handles TLS 1.2/1.3 differences).
*   **Retry Logic:** Built-in attempts to prevent false positives caused by temporary network jitter.

### How to Use
1.  Download the `YT-DPI-Test.ps1` script.
2.  Right-click the file and select **"Run with PowerShell"**.
3.  *Optional:* If you encounter execution policy errors, run this in the terminal:
    ```powershell
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\YT-DPI-Test.ps1
    ```

### Understanding Results
| Result | Meaning |
| :--- | :--- |
| **AVAILABLE** | Connection is fully functional. |
| **DPI BLOCK (SNI)** | The ISP sees the "youtube.com" name in the packet and drops it. Typical DPI behavior. |
| **IP BLOCK** | The IP address is completely unreachable. The ISP has blacklisted the IP. |
| **DNS SPOOFED** | Your DNS provider is returning fake IP addresses (e.g., 127.0.0.1). |
| **ERROR** | General network error or timeout. |

---
*Disclaimer: This tool is for diagnostic and educational purposes only.*