#nullable disable
using System;
using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;

namespace YtDpi
{
    public sealed class Tls12Result
    {
        public string Cell { get; internal set; }
        /// <summary>True when handshake WaitOne timed out (PS retry logic).</summary>
        public bool HandshakeTimedOut { get; internal set; }
    }

    /// <summary>TLS 1.2 client handshake with timeout (ported from YT-DPI.ps1 scan worker).</summary>
    public static class Tls12Scripting
    {
        /// <summary>Direct TCP to IP:443 then TLS 1.2 handshake.</summary>
        public static Tls12Result HandshakeDirectDetailed(string ipString, int port, string sniHost, int timeoutMs)
        {
            TcpClient tcp = null;
            try
            {
                tcp = TcpTimeouts.ConnectToIpPort(ipString, port, timeoutMs);
                NetworkStream ns = tcp.GetStream();
                return HandshakeOnStreamDetailed(ns, sniHost, timeoutMs, leaveInnerStreamOpen: false);
            }
            catch (Exception ex)
            {
                return new Tls12Result { Cell = ClassifyTls12Error(ex), HandshakeTimedOut = false };
            }
            finally
            {
                try { tcp?.Close(); } catch { }
            }
        }

        /// <summary>TLS 1.2 over an established tunnel stream (e.g. after HTTP CONNECT / SOCKS5).</summary>
        public static Tls12Result HandshakeOverStreamDetailed(Stream tunnelStream, string sniHost, int timeoutMs)
        {
            try
            {
                return HandshakeOnStreamDetailed(tunnelStream, sniHost, timeoutMs, leaveInnerStreamOpen: false);
            }
            catch (Exception ex)
            {
                return new Tls12Result { Cell = ClassifyTls12Error(ex), HandshakeTimedOut = false };
            }
        }

        static Tls12Result HandshakeOnStreamDetailed(Stream stream, string sniHost, int timeoutMs, bool leaveInnerStreamOpen)
        {
            SslStream ssl = null;
            try
            {
                ssl = new SslStream(stream, leaveInnerStreamOpen);
                IAsyncResult ar = ssl.BeginAuthenticateAsClient(sniHost, null, SslProtocols.Tls12, false, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeoutMs))
                {
                    try { ssl.Close(); } catch { }
                    return new Tls12Result { Cell = "DRP", HandshakeTimedOut = true };
                }
                ssl.EndAuthenticateAsClient(ar);
                return new Tls12Result { Cell = ssl.IsAuthenticated ? "OK" : "DRP", HandshakeTimedOut = false };
            }
            catch (Exception ex)
            {
                return new Tls12Result { Cell = ClassifyTls12Error(ex), HandshakeTimedOut = false };
            }
            finally
            {
                try { ssl?.Dispose(); } catch { }
            }
        }

        static string ClassifyTls12Error(Exception ex)
        {
            string m = ex.Message ?? "";
            if (ex.InnerException != null)
                m += " | Inner: " + ex.InnerException.Message;
            string ml = m.ToLowerInvariant();
            if (ml.Contains("reset") || ml.Contains("сброс") || ml.Contains("forcibly") || ml.Contains("closed") || ml.Contains("разорвано") || ml.Contains("failed"))
                return "RST";
            if (ml.Contains("certificate") || ml.Contains("сертификат") || ml.Contains("remote") || ml.Contains("success"))
                return "OK";
            return "DRP";
        }
    }
}
