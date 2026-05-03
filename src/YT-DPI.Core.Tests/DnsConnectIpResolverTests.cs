using System.Net;
using System.Net.Sockets;
using YT_DPI.Core.Config;
using YT_DPI.Core.Scan;

namespace YT_DPI.Core.Tests;

public sealed class DnsConnectIpResolverTests
{
    [Fact]
    public void Resolve_returns_cached_ipv4_without_lookup()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.DnsCache["example.test"] = "203.0.113.1";
        var ip = DnsConnectIpResolver.Resolve("example.test", cfg, _ => throw new InvalidOperationException("DNS should not be called"));
        Assert.Equal("203.0.113.1", ip);
    }

    [Fact]
    public void Resolve_returns_cached_ipv6_string_without_lookup()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.DnsCache["v6.test"] = "2001:db8::1";
        var ip = DnsConnectIpResolver.Resolve("v6.test", cfg, _ => throw new InvalidOperationException("DNS should not be called"));
        Assert.Equal("2001:db8::1", ip);
    }

    [Fact]
    public void Resolve_prefers_ipv6_when_preference_ipv6_and_net_has_ipv6()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.IpPreference = "IPv6";
        cfg.NetCache.HasIPv6 = true;
        var v4 = IPAddress.Parse("198.51.100.2");
        var v6 = IPAddress.Parse("2001:db8::2");
        var ip = DnsConnectIpResolver.Resolve("multi.test", cfg, _ => [v4, v6]);
        Assert.Equal("2001:db8::2", ip);
    }

    [Fact]
    public void Resolve_falls_back_to_ipv4_when_preference_ipv6_but_net_has_no_ipv6_flag()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.IpPreference = "IPv6";
        cfg.NetCache.HasIPv6 = false;
        var v4 = IPAddress.Parse("198.51.100.3");
        var v6 = IPAddress.Parse("2001:db8::3");
        var ip = DnsConnectIpResolver.Resolve("multi.test", cfg, _ => [v4, v6]);
        Assert.Equal("198.51.100.3", ip);
    }

    [Fact]
    public void Resolve_prefers_ipv4_when_preference_not_ipv6()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.IpPreference = "IPv4";
        cfg.NetCache.HasIPv6 = true;
        var v4 = IPAddress.Parse("198.51.100.4");
        var v6 = IPAddress.Parse("2001:db8::4");
        var ip = DnsConnectIpResolver.Resolve("multi.test", cfg, _ => [v6, v4]);
        Assert.Equal("198.51.100.4", ip);
    }

    [Fact]
    public void Resolve_returns_first_when_no_v4_or_v6_match()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.IpPreference = "IPv4";
        cfg.NetCache.HasIPv6 = false;
        var unusual = IPAddress.Loopback; // InterNetwork — still IPv4
        var ip = DnsConnectIpResolver.Resolve("only.test", cfg, _ => [unusual]);
        Assert.Equal("127.0.0.1", ip);
    }

    [Fact]
    public void Resolve_returns_DNS_ERR_on_lookup_exception()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        var ip = DnsConnectIpResolver.Resolve("fail.test", cfg, _ => throw new SocketException());
        Assert.Equal("DNS_ERR", ip);
    }

    [Fact]
    public void Resolve_returns_triple_dash_on_empty_addresses()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        var ip = DnsConnectIpResolver.Resolve("empty.test", cfg, _ => []);
        Assert.Equal("---", ip);
    }
}
