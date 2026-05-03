using System.Diagnostics;
using System.Net.Sockets;

namespace YT_DPI.Core.Scan;

internal static class PortConnectivity
{
    /// <summary>TCP connect to <paramref name="hostOrIp"/>:<paramref name="port"/>; returns whether handshake completed within timeout.</summary>
    public static bool TryTcpConnect(string hostOrIp, int port, int timeoutMs, out int elapsedMs)
    {
        elapsedMs = 0;
        var sw = Stopwatch.StartNew();
        try
        {
            using var tcp = new TcpClient();
            var ar = tcp.BeginConnect(hostOrIp, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(Math.Max(1, timeoutMs)))
                return false;
            tcp.EndConnect(ar);
            elapsedMs = (int)sw.ElapsedMilliseconds;
            return true;
        }
        catch
        {
            return false;
        }
    }
}
