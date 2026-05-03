using System.Net;
using System.Net.Sockets;
using System.Text;
using YT_DPI.Core.Config;
using YT_DPI.Core.Net;

namespace YT_DPI.Core.Tests;

public sealed class ProxyTunnelTests
{
    [Fact]
    public async Task TryOpen_socks5_no_auth_tunnel_to_port_succeeds()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;

        var server = Task.Run(() =>
        {
            using var client = listener.AcceptTcpClient();
            using var s = client.GetStream();
            var buf = new byte[512];

            var n = ReadAtLeast(s, buf, 0, 2, 5000);
            Assert.Equal(2, n);
            Assert.Equal(0x05, buf[0]);
            var nmeth = buf[1];
            Assert.Equal(nmeth, ReadAtLeast(s, buf, 0, nmeth, 5000));
            s.Write(new byte[] { 0x05, 0x00 }, 0, 2);

            n = ReadAtLeast(s, buf, 0, 5, 5000);
            Assert.True(n >= 5);
            Assert.Equal(0x05, buf[0]);
            Assert.Equal(0x01, buf[1]);
            Assert.Equal(0x03, buf[3]);
            var hostLen = buf[4];
            Assert.Equal(hostLen + 2, ReadAtLeast(s, buf, 0, hostLen + 2, 5000));

            var reply = new byte[] { 0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0 };
            s.Write(reply, 0, reply.Length);
        });

        var proxy = new ProxySection
        {
            Enabled = true,
            Type = "SOCKS5",
            Host = "127.0.0.1",
            Port = port,
        };

        var ok = ProxyTunnel.TryOpen(proxy, "example.test", 80, 8000, out var conn, out _, out var err);
        Assert.True(ok, err ?? "");
        Assert.NotNull(conn);
        conn!.Dispose();
        await server;
    }

    [Fact]
    public async Task TryOpen_http_connect_200_succeeds()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;

        var server = Task.Run(() =>
        {
            using var client = listener.AcceptTcpClient();
            using var s = client.GetStream();
            var buf = new byte[2048];
            var total = 0;
            while (total < 2048)
            {
                var n = s.Read(buf, total, buf.Length - total);
                if (n <= 0)
                    break;
                total += n;
                var text = Encoding.ASCII.GetString(buf, 0, total);
                if (text.Contains("\r\n\r\n", StringComparison.Ordinal))
                    break;
            }

            var resp = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
            s.Write(resp, 0, resp.Length);
        });

        var proxy = new ProxySection
        {
            Enabled = true,
            Type = "HTTP",
            Host = "127.0.0.1",
            Port = port,
        };

        var ok = ProxyTunnel.TryOpen(proxy, "example.test", 443, 8000, out var conn, out _, out var err);
        Assert.True(ok, err ?? "");
        conn!.Dispose();
        await server;
    }

    private static int ReadAtLeast(NetworkStream s, byte[] buf, int offset, int count, int timeoutMs)
    {
        s.ReadTimeout = timeoutMs;
        var got = 0;
        while (got < count)
        {
            var r = s.Read(buf, offset + got, count - got);
            if (r == 0)
                return got;
            got += r;
        }

        return got;
    }
}

