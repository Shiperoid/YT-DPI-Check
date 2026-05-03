using YT_DPI.Core.Config;
using YT_DPI.Core.Tls;

namespace YT_DPI.Core.Preview;

/// <summary>Thin entry points for the GUI preview and tests (ported TLS/trace from YT-DPI.ps1).</summary>
public static class PreviewEngine
{
    /// <summary>Quick TLS probe with 1 ms timeout to localhost — expect DRP, no crash.</summary>
    public static string TlsQuickLocalTimeout()
        => TlsScanner.TestT13("127.0.0.1", "example.com", "", 0, "", "", 1);

    public static (bool Ok, YtDpiUserConfig Config, string? Error) LoadUserConfigReadOnly()
        => UserConfigLoader.TryLoadUserConfig();
}
