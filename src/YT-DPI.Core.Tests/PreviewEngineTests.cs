using YT_DPI.Core.Config;
using YT_DPI.Core.Preview;
using YT_DPI.Core.Trace;

namespace YT_DPI.Core.Tests;

public class PreviewEngineTests
{
    [Fact]
    public void Tls_quick_local_1ms_returns_DRP()
    {
        var r = PreviewEngine.TlsQuickLocalTimeout();
        Assert.Equal("DRP", r);
    }

    [Fact]
    public void Load_config_missing_file_returns_defaults()
    {
        var path = Path.Combine(Path.GetTempPath(), "yt_dpi_no_config_" + Guid.NewGuid().ToString("N") + ".json");
        var (ok, cfg, err) = UserConfigLoader.TryLoadUserConfig(path);
        Assert.True(ok);
        Assert.Null(err);
        Assert.Equal("IPv6", cfg.IpPreference);
        Assert.Equal("Auto", cfg.TlsMode);
        Assert.False(cfg.Proxy.Enabled);
    }

    [Fact]
    public void Traceroute_ported_type_loads()
    {
        Assert.NotNull(typeof(AdvancedTraceroute));
    }
}
