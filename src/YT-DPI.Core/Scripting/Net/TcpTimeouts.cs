#nullable disable
using System;
using System.Net;
using System.Net.Sockets;

namespace YtDpi
{
    /// <summary>TCP connect with explicit timeout (mirrors PS BeginConnect/WaitOne).</summary>
    public static class TcpTimeouts
    {
        /// <returns>Connected TcpClient (caller disposes).</returns>
        /// <exception cref="TimeoutException">connect wait exceeded</exception>
        public static TcpClient ConnectToIpPort(string ipString, int port, int timeoutMs)
        {
            if (string.IsNullOrWhiteSpace(ipString))
                throw new ArgumentException("ip", nameof(ipString));
            IPAddress ip = IPAddress.Parse(ipString.Trim());
            var tcp = new TcpClient(ip.AddressFamily);
            try
            {
                IAsyncResult ar = tcp.BeginConnect(ip, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeoutMs))
                {
                    try { tcp.Close(); } catch { }
                    throw new TimeoutException("Timeout");
                }
                tcp.EndConnect(ar);
                return tcp;
            }
            catch
            {
                try { tcp.Close(); } catch { }
                throw;
            }
        }
    }
}
