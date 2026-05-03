using System.Net;
using System.Net.Sockets;
using YT_DPI.Core.Config;

namespace YT_DPI.Core.Scan;

/// <summary>Resolve hostname to connect IP: <c>DnsCache</c> first, then DNS with <c>IpPreference</c> / <c>NetCache.HasIPv6</c> — aligned with YT-DPI.ps1 scan connect path (~4612+).</summary>
public static class DnsConnectIpResolver
{
    /// <param name="resolveAddresses">Optional override for tests; default uses <see cref="Dns.GetHostAddresses"/>.</param>
    public static string Resolve(string host, YtDpiUserConfig cfg, Func<string, IPAddress[]>? resolveAddresses = null)
    {
        if (cfg.DnsCache.TryGetValue(host, out var cached) && !string.IsNullOrWhiteSpace(cached))
        {
            if (cached.Contains(':', StringComparison.Ordinal) || IPAddress.TryParse(cached, out _))
                return cached;
        }

        try
        {
            var addrs = resolveAddresses is not null ? resolveAddresses(host) : Dns.GetHostAddresses(host);
            if (addrs.Length == 0)
                return "---";

            var preferV6 = string.Equals(cfg.IpPreference, "IPv6", StringComparison.OrdinalIgnoreCase);
            if (preferV6 && cfg.NetCache.HasIPv6)
            {
                var v6 = addrs.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetworkV6);
                if (v6 is not null)
                    return v6.ToString();
            }

            var v4 = addrs.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork);
            if (v4 is not null)
                return v4.ToString();

            return addrs[0].ToString();
        }
        catch
        {
            return "DNS_ERR";
        }
    }
}
