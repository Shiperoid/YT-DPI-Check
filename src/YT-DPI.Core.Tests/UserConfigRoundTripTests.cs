using System.Text.Json;
using YT_DPI.Core.Config;

namespace YT_DPI.Core.Tests;

public class UserConfigRoundTripTests
{
    [Fact]
    public void Save_load_roundtrip_preserves_scalars_and_dns_numeric_string()
    {
        var path = Path.Combine(Path.GetTempPath(), "yt_dpi_rt_" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            var cfg = YtDpiUserConfig.CreateDefaults();
            cfg.RunCount = 7;
            cfg.IpPreference = "IPv4";
            cfg.TlsMode = "TLS13";
            cfg.Proxy.Enabled = true;
            cfg.Proxy.Host = "127.0.0.1";
            cfg.Proxy.Port = 8080;
            cfg.DnsCache["example.com"] = "1.2.3.4";
            cfg.SchemaVersion = 2;

            var (okSave, errSave) = UserConfigSaver.TrySaveUserConfig(cfg, path);
            Assert.True(okSave, errSave);

            var raw = File.ReadAllText(path);
            using var doc = JsonDocument.Parse(raw);
            Assert.Equal(JsonValueKind.Number, doc.RootElement.GetProperty("RunCount").ValueKind);
            Assert.Equal(7, doc.RootElement.GetProperty("RunCount").GetInt32());

            var (okLoad, loaded, errLoad) = UserConfigLoader.TryLoadUserConfig(path);
            Assert.True(okLoad, errLoad);
            Assert.Equal(7, loaded.RunCount);
            Assert.Equal("IPv4", loaded.IpPreference);
            Assert.Equal("TLS13", loaded.TlsMode);
            Assert.True(loaded.Proxy.Enabled);
            Assert.Equal("127.0.0.1", loaded.Proxy.Host);
            Assert.Equal(8080, loaded.Proxy.Port);
            Assert.Equal("1.2.3.4", loaded.DnsCache["example.com"]);
            Assert.Equal(2, loaded.SchemaVersion);
        }
        finally
        {
            try
            {
                File.Delete(path);
            }
            catch
            {
                /* ignore */
            }
        }
    }
}
