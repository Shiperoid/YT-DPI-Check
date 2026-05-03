using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;

namespace YT_DPI.Core.Scan;

internal static class Tls12Probe
{
    public static string Handshake(string ip, string sniHost, int timeoutMs)
    {
        TcpClient? tcp = null;
        try
        {
            tcp = new TcpClient();
            var ar = tcp.BeginConnect(ip, 443, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(Math.Max(1, timeoutMs)))
                return "DRP";
            tcp.EndConnect(ar);

            var stream = tcp.GetStream();
            return HandshakeOverStream(stream, sniHost, timeoutMs, leaveInnerStreamOpen: false);
        }
        catch (Exception ex)
        {
            return MapTls12Exception(ex);
        }
        finally
        {
            try
            {
                tcp?.Close();
            }
            catch
            {
                /* ignore */
            }
        }
    }

    /// <summary>TLS 1.2 client handshake over an existing stream (e.g. SOCKS/HTTP tunnel). Does not dispose <paramref name="stream"/> when <paramref name="leaveInnerStreamOpen"/> is true.</summary>
    internal static string HandshakeOverStream(Stream stream, string sniHost, int timeoutMs, bool leaveInnerStreamOpen)
    {
        try
        {
            if (stream is NetworkStream ns)
            {
                ns.ReadTimeout = timeoutMs;
                ns.WriteTimeout = timeoutMs;
            }

            using var ssl = new SslStream(stream, leaveInnerStreamOpen);
            var auth = ssl.AuthenticateAsClientAsync(sniHost, null, SslProtocols.Tls12, false);
            if (!auth.Wait(Math.Max(1, timeoutMs)))
                return "DRP";
            auth.GetAwaiter().GetResult();
            return ssl.IsAuthenticated ? "OK" : "DRP";
        }
        catch (Exception ex)
        {
            return MapTls12Exception(ex);
        }
    }

    private static string MapTls12Exception(Exception ex)
    {
        var m = ex.Message.ToLowerInvariant();
        if (m.Contains("reset") || m.Contains("сброс") || m.Contains("forcibly") || m.Contains("closed"))
            return "RST";
        if (m.Contains("certificate") || m.Contains("remote") || m.Contains("success"))
            return "OK";
        return "DRP";
    }
}
