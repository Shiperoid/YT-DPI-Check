using System.Text.Json;
using System.Text.RegularExpressions;

namespace YT_DPI.Core.Config;

public static class UserConfigLoader
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    /// <summary>
    /// Read-only load aligned with YT-DPI.ps1 Load-Config (defaults, missing keys, DnsCache sanitize, NetCacheStale).
    /// Does not write to disk.
    /// </summary>
    public static (bool Ok, YtDpiUserConfig Config, string? Error) TryLoadUserConfig(string? pathOverride = null)
    {
        var path = pathOverride ?? UserConfigPaths.GetConfigFilePath();
        var cfg = YtDpiUserConfig.CreateDefaults();

        if (!File.Exists(path))
            return (true, cfg, null);

        try
        {
            var raw = File.ReadAllText(path);
            if (string.IsNullOrWhiteSpace(raw))
                return (true, cfg, null);

            using var doc = JsonDocument.Parse(raw, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip });
            if (doc.RootElement.ValueKind != JsonValueKind.Object)
                return (true, cfg, "Root JSON is not an object; using defaults.");

            MergeFromJson(cfg, doc.RootElement);
            ApplyDnsSanitize(cfg);
            ApplyNetCacheStale(cfg);
            return (true, cfg, null);
        }
        catch (Exception ex)
        {
            return (false, YtDpiUserConfig.CreateDefaults(), ex.Message);
        }
    }

    private static void MergeFromJson(YtDpiUserConfig cfg, JsonElement root)
    {
        var def = YtDpiUserConfig.CreateDefaults();
        cfg.RunCount = ReadInt(root, nameof(YtDpiUserConfig.RunCount), def.RunCount);
        cfg.LastPromptRun = ReadInt(root, nameof(YtDpiUserConfig.LastPromptRun), def.LastPromptRun);
        cfg.LastCheckedVersion = ReadString(root, nameof(YtDpiUserConfig.LastCheckedVersion), def.LastCheckedVersion);
        cfg.IpPreference = ReadString(root, nameof(YtDpiUserConfig.IpPreference), def.IpPreference);
        cfg.TlsMode = ReadString(root, nameof(YtDpiUserConfig.TlsMode), def.TlsMode);
        cfg.DebugLogEnabled = ReadBool(root, nameof(YtDpiUserConfig.DebugLogEnabled), def.DebugLogEnabled);
        cfg.DebugLogFullIdentifiers = ReadBool(root, nameof(YtDpiUserConfig.DebugLogFullIdentifiers), def.DebugLogFullIdentifiers);

        if (root.TryGetProperty(nameof(YtDpiUserConfig.Proxy), out var px) && px.ValueKind == JsonValueKind.Object)
        {
            cfg.Proxy.Enabled = ReadBool(px, nameof(ProxySection.Enabled), def.Proxy.Enabled);
            cfg.Proxy.Type = ReadString(px, nameof(ProxySection.Type), def.Proxy.Type);
            cfg.Proxy.Host = ReadString(px, nameof(ProxySection.Host), def.Proxy.Host);
            cfg.Proxy.Port = ReadInt(px, nameof(ProxySection.Port), def.Proxy.Port);
            cfg.Proxy.User = ReadString(px, nameof(ProxySection.User), def.Proxy.User);
            cfg.Proxy.Pass = ReadString(px, nameof(ProxySection.Pass), def.Proxy.Pass);
        }

        if (root.TryGetProperty(nameof(YtDpiUserConfig.ProxyHistory), out var ph) && ph.ValueKind == JsonValueKind.Array)
        {
            cfg.ProxyHistory.Clear();
            foreach (var el in ph.EnumerateArray())
            {
                if (el.ValueKind == JsonValueKind.String)
                {
                    var s = el.GetString();
                    if (!string.IsNullOrEmpty(s))
                        cfg.ProxyHistory.Add(s);
                }
            }
        }

        if (root.TryGetProperty(nameof(YtDpiUserConfig.NetCache), out var nc) && nc.ValueKind == JsonValueKind.Object)
        {
            cfg.NetCache.ISP = ReadString(nc, nameof(NetCacheSection.ISP), def.NetCache.ISP);
            cfg.NetCache.LOC = ReadString(nc, nameof(NetCacheSection.LOC), def.NetCache.LOC);
            cfg.NetCache.DNS = ReadString(nc, nameof(NetCacheSection.DNS), def.NetCache.DNS);
            cfg.NetCache.CDN = ReadString(nc, nameof(NetCacheSection.CDN), def.NetCache.CDN);
            cfg.NetCache.TimestampTicks = ReadInt64(nc, nameof(NetCacheSection.TimestampTicks), def.NetCache.TimestampTicks);
            cfg.NetCache.HasIPv6 = ReadBool(nc, nameof(NetCacheSection.HasIPv6), def.NetCache.HasIPv6);
        }

        if (root.TryGetProperty(nameof(YtDpiUserConfig.DnsCache), out var dns) && dns.ValueKind == JsonValueKind.Object)
        {
            cfg.DnsCache.Clear();
            foreach (var p in dns.EnumerateObject())
            {
                if (p.Value.ValueKind == JsonValueKind.String)
                {
                    var v = p.Value.GetString() ?? "";
                    cfg.DnsCache[p.Name] = v;
                }
            }
        }
    }

    /// <summary>PS: value -match '\..*\.' -or value -match ':'</summary>
    private static void ApplyDnsSanitize(YtDpiUserConfig cfg)
    {
        if (cfg.DnsCache.Count == 0)
            return;
        var dotPattern = new Regex(@"\..*\.");
        var cleaned = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in cfg.DnsCache)
        {
            if (dotPattern.IsMatch(kv.Value) || kv.Value.Contains(':'))
                cleaned[kv.Key] = kv.Value;
        }
        cfg.DnsCache = cleaned;
    }

    private static void ApplyNetCacheStale(YtDpiUserConfig cfg)
    {
        var last = cfg.NetCache.TimestampTicks;
        var stale = DateTime.Now.Ticks - last > TimeSpan.FromHours(6).Ticks;
        cfg.NetCache.NetCacheStale = stale;
    }

    private static int ReadInt(JsonElement parent, string name, int fallback)
    {
        if (!parent.TryGetProperty(name, out var el))
            return fallback;
        return el.ValueKind switch
        {
            JsonValueKind.Number when el.TryGetInt32(out var i) => i,
            JsonValueKind.String when int.TryParse(el.GetString(), out var j) => j,
            _ => fallback,
        };
    }

    private static long ReadInt64(JsonElement parent, string name, long fallback)
    {
        if (!parent.TryGetProperty(name, out var el))
            return fallback;
        return el.ValueKind switch
        {
            JsonValueKind.Number when el.TryGetInt64(out var i) => i,
            JsonValueKind.String when long.TryParse(el.GetString(), out var j) => j,
            _ => fallback,
        };
    }

    private static bool ReadBool(JsonElement parent, string name, bool fallback)
    {
        if (!parent.TryGetProperty(name, out var el))
            return fallback;
        return el.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Number when el.TryGetInt32(out var n) => n != 0,
            JsonValueKind.String when bool.TryParse(el.GetString(), out var b) => b,
            _ => fallback,
        };
    }

    private static string ReadString(JsonElement parent, string name, string fallback)
    {
        if (!parent.TryGetProperty(name, out var el))
            return fallback;
        return el.ValueKind == JsonValueKind.String ? el.GetString() ?? fallback : fallback;
    }
}
