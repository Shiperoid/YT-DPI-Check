using YT_DPI.Core.Config;

namespace YT_DPI.Core.Scan;

/// <summary>TLS timeouts aligned with YT-DPI.ps1 (~4548–4549).</summary>
public static class TlsTimeouts
{
    public static int FastMs(YtDpiUserConfig cfg) => cfg.Proxy.Enabled ? 2200 : 1600;

    public static int RetryMs(YtDpiUserConfig cfg) => cfg.Proxy.Enabled ? Math.Max(2600, 2600) : 2600;
}
