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

            using var stream = tcp.GetStream();
            stream.ReadTimeout = timeoutMs;
            stream.WriteTimeout = timeoutMs;
            using var ssl = new SslStream(stream, false);
            var auth = ssl.AuthenticateAsClientAsync(sniHost, null, SslProtocols.Tls12, false);
            if (!auth.Wait(Math.Max(1, timeoutMs)))
                return "DRP";
            auth.GetAwaiter().GetResult();
            return ssl.IsAuthenticated ? "OK" : "DRP";
        }
        catch (Exception ex)
        {
            var m = ex.Message.ToLowerInvariant();
            if (m.Contains("reset") || m.Contains("сброс") || m.Contains("forcibly") || m.Contains("closed"))
                return "RST";
            if (m.Contains("certificate") || m.Contains("remote") || m.Contains("success"))
                return "OK";
            return "DRP";
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
}
