using YT_DPI.Core.Config;

namespace YT_DPI.Core.Scan;

/// <summary>Timeouts aligned with YT-DPI.ps1 $CONST and scan worker (~4613–4616).</summary>
public static class ScanTimeouts
{
    public const int MainTimeoutMs = 1500;
    public const int ProxyTimeoutMs = 2500;

    public static int HttpFastMs(YtDpiUserConfig cfg) =>
        cfg.Proxy.Enabled ? ProxyTimeoutMs : Math.Min(MainTimeoutMs, 1200);

    public static int MainToMs(YtDpiUserConfig cfg) =>
        cfg.Proxy.Enabled ? ProxyTimeoutMs : MainTimeoutMs;

    /// <summary>TLS 1.3 fast / retry — same as <see cref="TlsTimeouts"/>.</summary>
    public static int Tls13FastMs(YtDpiUserConfig cfg) => TlsTimeouts.FastMs(cfg);

    public static int Tls13RetryMs(YtDpiUserConfig cfg) => TlsTimeouts.RetryMs(cfg);

    public static int Tls12HandshakeMs(YtDpiUserConfig cfg) => TlsTimeouts.FastMs(cfg);

    public static int Tls12RetryMs(YtDpiUserConfig cfg) => TlsTimeouts.RetryMs(cfg);
}
