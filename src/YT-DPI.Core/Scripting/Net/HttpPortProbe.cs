#nullable disable
using System;
using System.Diagnostics;

namespace YtDpi
{
    /// <summary>TCP reachability + latency (YT-DPI HTTP column — по сути TCP до порта, обычно 80).</summary>
    public sealed class HttpPortProbe
    {
        public bool Ok { get; private set; }
        /// <summary>Elapsed ms from start of connect attempt through success.</summary>
        public int LatencyMs { get; private set; }

        /// <summary>Direct connect to resolved IP (no proxy).</summary>
        public static HttpPortProbe QuickDirect(string ipString, int port, int timeoutMs)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                using (var tcp = TcpTimeouts.ConnectToIpPort(ipString, port, timeoutMs))
                {
                    sw.Stop();
                    return new HttpPortProbe { Ok = true, LatencyMs = (int)sw.ElapsedMilliseconds };
                }
            }
            catch
            {
                sw.Stop();
                return new HttpPortProbe { Ok = false, LatencyMs = (int)sw.ElapsedMilliseconds };
            }
        }

        /// <summary>Through SOCKS5 / HTTP CONNECT tunnel to target host:port.</summary>
        public static HttpPortProbe QuickViaProxy(string targetHost, int port, string proxyHost, int proxyPort, string proxyType, string proxyUser, string proxyPass, int timeoutMs)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                using (ProxyTunnelConnection tunnel = ProxyThrough.Establish(proxyHost, proxyPort, proxyType, targetHost, port, proxyUser, proxyPass, timeoutMs))
                {
                    sw.Stop();
                    return new HttpPortProbe { Ok = true, LatencyMs = (int)sw.ElapsedMilliseconds };
                }
            }
            catch
            {
                sw.Stop();
                return new HttpPortProbe { Ok = false, LatencyMs = (int)sw.ElapsedMilliseconds };
            }
        }
    }
}
