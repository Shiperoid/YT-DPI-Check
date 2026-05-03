using System.Text.Json.Serialization;

namespace YT_DPI.Core.Config;

public sealed class ProxySection
{
    public bool Enabled { get; set; }
    public string Type { get; set; } = "HTTP";
    public string Host { get; set; } = "";
    public int Port { get; set; }
    public string User { get; set; } = "";
    public string Pass { get; set; } = "";
}

public sealed class NetCacheSection
{
    public string ISP { get; set; } = "Loading...";
    public string LOC { get; set; } = "Unknown";
    public string DNS { get; set; } = "8.8.8.8";
    public string CDN { get; set; } = "manifest.googlevideo.com";
    public long TimestampTicks { get; set; }
    public bool HasIPv6 { get; set; }

    /// <summary>Matches PS Load-Config NetCacheStale (6 hours).</summary>
    [JsonIgnore]
    public bool NetCacheStale { get; set; }
}

/// <summary>Subset of YT-DPI.ps1 New-ConfigObject / Load-Config JSON (read-only in Core).</summary>
public sealed class YtDpiUserConfig
{
    /// <summary>Optional JSON schema version for forward-compatible saves from .NET preview (0 = legacy / unset).</summary>
    public int SchemaVersion { get; set; }

    public int RunCount { get; set; }
    public int LastPromptRun { get; set; }
    public string LastCheckedVersion { get; set; } = "";
    public string IpPreference { get; set; } = "IPv6";
    public string TlsMode { get; set; } = "Auto";
    public ProxySection Proxy { get; set; } = new();
    public List<string> ProxyHistory { get; set; } = new();
    public NetCacheSection NetCache { get; set; } = new();
    public Dictionary<string, string> DnsCache { get; set; } = new();
    public bool DebugLogEnabled { get; set; }
    public bool DebugLogFullIdentifiers { get; set; }

    public static YtDpiUserConfig CreateDefaults()
    {
        var staleTicks = DateTime.Now.AddDays(-1).Ticks;
        return new YtDpiUserConfig
        {
            SchemaVersion = 1,
            RunCount = 0,
            LastPromptRun = 0,
            LastCheckedVersion = "",
            IpPreference = "IPv6",
            TlsMode = "Auto",
            Proxy = new ProxySection(),
            ProxyHistory = new List<string>(),
            NetCache = new NetCacheSection
            {
                ISP = "Loading...",
                LOC = "Unknown",
                DNS = "8.8.8.8",
                CDN = "manifest.googlevideo.com",
                TimestampTicks = staleTicks,
                HasIPv6 = false,
            },
            DnsCache = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase),
            DebugLogEnabled = false,
            DebugLogFullIdentifiers = false,
        };
    }
}
