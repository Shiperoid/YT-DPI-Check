using System.Net;
using System.Net.Sockets;
using YT_DPI.Core.Config;
using YT_DPI.Core.Tls;

namespace YT_DPI.Core.Scan;

/// <summary>Background-friendly TLS 1.3-only preview scan (HTTP/T12/LAT left as placeholders).</summary>
public static class PreviewScanRunner
{
    public static async Task<IReadOnlyList<ScanRow>> RunTls13PreviewAsync(
        IReadOnlyList<string> targetDomains,
        YtDpiUserConfig cfg,
        IProgress<string>? status,
        IProgress<(int Index, ScanRow Row)>? rowProgress,
        CancellationToken cancellationToken)
    {
        var fast = TlsTimeouts.FastMs(cfg);
        var retry = TlsTimeouts.RetryMs(cfg);
        var pHost = cfg.Proxy.Enabled ? cfg.Proxy.Host : "";
        var pPort = cfg.Proxy.Port;
        var pUser = cfg.Proxy.User;
        var pPass = cfg.Proxy.Pass;

        var rows = new List<ScanRow>(targetDomains.Count);
        var n = targetDomains.Count;
        for (var i = 0; i < n; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var domain = targetDomains[i];
            status?.Report($"[{i + 1}/{n}] {domain}");

            var row = await Task.Run(
                    () => ScanOneRow(i + 1, domain, cfg.IpPreference, pHost, pPort, pUser, pPass, fast, retry, cancellationToken),
                    cancellationToken)
                .ConfigureAwait(false);

            rows.Add(row);
            rowProgress?.Report((i, row));
            await Task.Yield();
        }

        status?.Report("Done");
        return rows;
    }

    private static ScanRow ScanOneRow(
        int number,
        string domain,
        string ipPreference,
        string pHost,
        int pPort,
        string pUser,
        string pPass,
        int fastMs,
        int retryMs,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var ip = ResolveConnectIp(domain, ipPreference);
        cancellationToken.ThrowIfCancellationRequested();

        string t13;
        if (ip == "---")
        {
            t13 = "---";
        }
        else
        {
            t13 = TlsScanner.TestT13(ip, domain, pHost, pPort, pUser, pPass, fastMs);
            if (t13 is "DRP" or "RST")
            {
                cancellationToken.ThrowIfCancellationRequested();
                var retryVal = TlsScanner.TestT13(ip, domain, pHost, pPort, pUser, pPass, retryMs);
                if (retryVal != t13)
                    t13 = retryVal;
            }
        }

        cancellationToken.ThrowIfCancellationRequested();
        return new ScanRow
        {
            Number = number,
            Target = domain,
            IP = ip,
            HTTP = "---",
            T12 = "---",
            T13 = t13,
            Lat = "---",
            Verdict = VerdictFromTls(t13),
        };
    }

    private static string VerdictFromTls(string t13) =>
        t13 switch
        {
            "OK" => "OK",
            "---" => "NO_IP",
            _ => "CHECK",
        };

    private static string ResolveConnectIp(string host, string ipPreference)
    {
        try
        {
            var addrs = Dns.GetHostAddresses(host);
            if (addrs.Length == 0)
                return "---";

            var preferV6 = string.Equals(ipPreference, "IPv6", StringComparison.OrdinalIgnoreCase);
            if (preferV6)
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
            return "---";
        }
    }
}
