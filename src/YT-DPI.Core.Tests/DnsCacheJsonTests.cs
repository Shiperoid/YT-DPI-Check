using YT_DPI.Core.Config;

namespace YT_DPI.Core.Tests;

public class DnsCacheJsonTests
{
    [Fact]
    public void Load_numeric_dns_value_stringifies_then_sanitize_may_drop()
    {
        var path = Path.Combine(Path.GetTempPath(), "yt_dpi_dnsnum_" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            File.WriteAllText(
                path,
                """
                {
                  "RunCount": 0,
                  "LastPromptRun": 0,
                  "LastCheckedVersion": "",
                  "IpPreference": "IPv6",
                  "TlsMode": "Auto",
                  "Proxy": { "Enabled": false, "Type": "HTTP", "Host": "", "Port": 0, "User": "", "Pass": "" },
                  "ProxyHistory": [],
                  "NetCache": {
                    "ISP": "Loading...",
                    "LOC": "Unknown",
                    "DNS": "8.8.8.8",
                    "CDN": "manifest.googlevideo.com",
                    "TimestampTicks": 0,
                    "HasIPv6": false
                  },
                  "DnsCache": { "x.test": 12345 },
                  "DebugLogEnabled": false,
                  "DebugLogFullIdentifiers": false
                }
                """);

            var (ok, cfg, err) = UserConfigLoader.TryLoadUserConfig(path);
            Assert.True(ok, err);
            // "12345" does not pass PS DnsCache sanitize; entry should be dropped.
            Assert.False(cfg.DnsCache.ContainsKey("x.test"));
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

    [Fact]
    public void Load_ipv4_string_dns_survives_sanitize()
    {
        var path = Path.Combine(Path.GetTempPath(), "yt_dpi_dnsip_" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            File.WriteAllText(
                path,
                """
                {
                  "RunCount": 0,
                  "LastPromptRun": 0,
                  "LastCheckedVersion": "",
                  "IpPreference": "IPv6",
                  "TlsMode": "Auto",
                  "Proxy": { "Enabled": false, "Type": "HTTP", "Host": "", "Port": 0, "User": "", "Pass": "" },
                  "ProxyHistory": [],
                  "NetCache": {
                    "ISP": "Loading...",
                    "LOC": "Unknown",
                    "DNS": "8.8.8.8",
                    "CDN": "manifest.googlevideo.com",
                    "TimestampTicks": 0,
                    "HasIPv6": false
                  },
                  "DnsCache": { "h.example": "10.0.0.1" },
                  "DebugLogEnabled": false,
                  "DebugLogFullIdentifiers": false
                }
                """);

            var (ok, cfg, err) = UserConfigLoader.TryLoadUserConfig(path);
            Assert.True(ok, err);
            Assert.Equal("10.0.0.1", cfg.DnsCache["h.example"]);
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
