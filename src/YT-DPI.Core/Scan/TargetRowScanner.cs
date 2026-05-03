using YT_DPI.Core.Config;
using YT_DPI.Core.Net;
using YT_DPI.Core.Tls;

namespace YT_DPI.Core.Scan;

/// <summary>Single-target scan row: proxy/DNS, HTTP:80 + LAT, TLS 1.2/1.3, verdict — logic from YT-DPI.ps1 (~4612–4872). Orchestration stays in <see cref="PreviewScanRunner"/>.</summary>
internal static class TargetRowScanner
{
    internal static ScanRow ScanOneRow(int number, string domain, YtDpiUserConfig cfg, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var proxyOn = cfg.Proxy.Enabled;
        var pHost = proxyOn ? cfg.Proxy.Host : "";
        var pPort = cfg.Proxy.Port;
        var pUser = proxyOn ? cfg.Proxy.User : "";
        var pPass = proxyOn ? cfg.Proxy.Pass : "";
        var proxyType = proxyOn ? (cfg.Proxy.Type ?? "SOCKS5") : "SOCKS5";

        string ip;
        if (proxyOn)
            ip = PreviewScanRunner.ProxiedIpMarker;
        else
            ip = DnsConnectIpResolver.Resolve(domain, cfg);

        cancellationToken.ThrowIfCancellationRequested();

        var http = "---";
        var lat = "---";
        var t12 = "---";
        var t13 = "---";

        if (!proxyOn)
        {
            if (ip is "---" or "DNS_ERR")
            {
                return Row(number, domain, ip, "ERR", "---", "---", "---", VerdictCalculator.Compute(cfg.TlsMode ?? "Auto", "ERR", "---", "---"));
            }

            var httpMs = ScanTimeouts.HttpFastMs(cfg);
            if (PortConnectivity.TryTcpConnect(ip, 80, httpMs, out var latMs))
            {
                http = "OK";
                lat = latMs.ToString();
            }
            else
            {
                http = "ERR";
                return Row(number, domain, ip, http, "---", "---", "---", VerdictCalculator.Compute(cfg.TlsMode ?? "Auto", http, "---", "---"));
            }
        }
        else
        {
            var httpMs = ScanTimeouts.HttpFastMs(cfg);
            if (ProxyTunnel.TryOpen(cfg.Proxy, domain, 80, httpMs, out var tun80, out var latMs, out _))
            {
                http = "OK";
                lat = latMs.ToString();
                tun80.Dispose();
            }
            else
            {
                http = "ERR";
                return Row(number, domain, ip, http, "---", "---", "---", VerdictCalculator.Compute(cfg.TlsMode ?? "Auto", http, "---", "---"));
            }
        }

        cancellationToken.ThrowIfCancellationRequested();

        var tlsFast = ScanTimeouts.Tls13FastMs(cfg);
        var tlsRetry = ScanTimeouts.Tls13RetryMs(cfg);
        var t12Fast = ScanTimeouts.Tls12HandshakeMs(cfg);
        var t12Retry = ScanTimeouts.Tls12RetryMs(cfg);

        var mode = cfg.TlsMode ?? "Auto";
        var consider13 = !string.Equals(mode, "TLS12", StringComparison.OrdinalIgnoreCase);
        var consider12 = !string.Equals(mode, "TLS13", StringComparison.OrdinalIgnoreCase);

        if (consider13)
        {
            if (proxyOn)
            {
                t13 = TlsScanner.TestT13(ip, domain, pHost, pPort, pUser, pPass, tlsFast, proxyType);
                if (t13 is "DRP" or "RST")
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var retryVal = TlsScanner.TestT13(ip, domain, pHost, pPort, pUser, pPass, tlsRetry, proxyType);
                    if (retryVal != t13)
                        t13 = retryVal;
                }
            }
            else
            {
                t13 = TlsScanner.TestT13(ip, domain, "", 0, "", "", tlsFast);
                if (t13 is "DRP" or "RST")
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var retryVal = TlsScanner.TestT13(ip, domain, "", 0, "", "", tlsRetry);
                    if (retryVal != t13)
                        t13 = retryVal;
                }
            }
        }
        else
        {
            t13 = "N/A";
        }

        cancellationToken.ThrowIfCancellationRequested();

        if (consider12 && proxyOn)
        {
            if (ProxyTunnel.TryOpen(cfg.Proxy, domain, 443, t12Fast, out var tun443, out _, out _))
            {
                using (tun443)
                {
                    t12 = Tls12Probe.HandshakeOverStream(tun443.Stream, domain, t12Fast, leaveInnerStreamOpen: true);
                    var t12TimedOut = t12 == "DRP";
                    var doRetry = t12TimedOut && ((consider13 && t13 == "OK") || !consider13);
                    if (doRetry)
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        if (ProxyTunnel.TryOpen(cfg.Proxy, domain, 443, t12Retry, out var tun443b, out _, out _))
                        {
                            using (tun443b)
                                t12 = Tls12Probe.HandshakeOverStream(tun443b.Stream, domain, t12Retry, leaveInnerStreamOpen: true);
                        }
                    }
                }
            }
            else
                t12 = "DRP";
        }
        else if (consider12 && !proxyOn)
        {
            t12 = Tls12Probe.Handshake(ip, domain, t12Fast);
            var t12TimedOut = t12 == "DRP";
            var doRetry = consider12 && t12TimedOut && ((consider13 && t13 == "OK") || !consider13);
            if (doRetry)
            {
                cancellationToken.ThrowIfCancellationRequested();
                t12 = Tls12Probe.Handshake(ip, domain, t12Retry);
            }
        }
        else if (!consider12)
        {
            t12 = "N/A";
        }

        var verdict = VerdictCalculator.Compute(cfg.TlsMode ?? "Auto", http, t12, t13);
        return Row(number, domain, ip, http, t12, t13, lat, verdict);
    }

    private static ScanRow Row(int number, string target, string ip, string http, string t12, string t13, string lat, string verdict) =>
        new()
        {
            Number = number,
            Target = target,
            IP = ip,
            HTTP = http,
            T12 = t12,
            T13 = t13,
            Lat = lat,
            Verdict = verdict,
        };
}
