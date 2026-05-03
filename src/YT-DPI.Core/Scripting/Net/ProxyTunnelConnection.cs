#nullable disable
using System;
using System.Net.Sockets;

namespace YtDpi
{
    /// <summary>TCP stream after SOCKS5 / HTTP CONNECT tunnel (PS: @{ Tcp; Stream }).</summary>
    public sealed class ProxyTunnelConnection : IDisposable
    {
        public TcpClient Tcp { get; }
        public NetworkStream Stream { get; }

        private bool _disposed;

        internal ProxyTunnelConnection(TcpClient tcp, NetworkStream stream)
        {
            Tcp = tcp ?? throw new ArgumentNullException(nameof(tcp));
            Stream = stream ?? throw new ArgumentNullException(nameof(stream));
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { Stream.Dispose(); } catch { }
            try { Tcp.Close(); } catch { }
        }
    }
}
