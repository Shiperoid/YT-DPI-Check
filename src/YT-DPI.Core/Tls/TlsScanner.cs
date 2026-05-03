// Ported from YT-DPI.ps1 embedded C# (here-string lines 376-513).
// SOCKS5 / HTTP CONNECT through proxy: YT-DPI.Core.Net.ProxyTunnel (PS ~2980–3120).

namespace YT_DPI.Core.Tls;

using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using YT_DPI.Core.Config;
using YT_DPI.Core.Net;

public class TlsScanner
{
    private static int ReadBlocking(NetworkStream stream, byte[] buffer, int offset, int count)
    {
        var total = 0;
        while (total < count)
        {
            var n = stream.Read(buffer, offset + total, count - total);
            if (n == 0)
                return total;
            total += n;
        }

        return total;
    }

    private static void FillRandomBytes(byte[] buffer)
    {
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(buffer);
    }

    /// <param name="proxyType">When using a proxy: <c>SOCKS5</c> or <c>HTTP</c> (same as config JSON). Default <c>SOCKS5</c>.</param>
    public static string TestT13(
        string targetIp,
        string host,
        string proxyHost,
        int proxyPort,
        string user,
        string pass,
        int timeout,
        string proxyType = "SOCKS5")
    {
        try
        {
            if (string.IsNullOrEmpty(proxyHost))
            {
                using var tcp = new TcpClient();
                var ar = tcp.BeginConnect(targetIp, 443, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeout))
                    return "DRP";
                tcp.EndConnect(ar);

                using var stream = tcp.GetStream();
                stream.ReadTimeout = timeout;
                stream.WriteTimeout = timeout;
                return RunTls13RecordProbe(stream, host, timeout);
            }

            var proxy = new ProxySection
            {
                Enabled = true,
                Type = string.IsNullOrWhiteSpace(proxyType) ? "SOCKS5" : proxyType,
                Host = proxyHost,
                Port = proxyPort,
                User = user ?? "",
                Pass = pass ?? "",
            };

            if (!ProxyTunnel.TryOpen(proxy, host, 443, timeout, out var tunnel, out _, out _))
                return "DRP";

            using (tunnel)
            {
                var stream = tunnel.Stream;
                stream.ReadTimeout = timeout;
                stream.WriteTimeout = timeout;
                return RunTls13RecordProbe(stream, host, timeout);
            }
        }
        catch (Exception ex)
        {
            var m = ex.Message.ToLower();
            if (m.Contains("reset") || m.Contains("closed"))
                return "RST";
            return "DRP";
        }
    }

    private static string RunTls13RecordProbe(NetworkStream stream, string host, int timeout)
    {
        var hello = BuildModernHello(host);
        stream.Write(hello, 0, hello.Length);

        var header = new byte[5];
        int read;
        try
        {
            read = ReadBlocking(stream, header, 0, 5);
        }
        catch (IOException ex)
        {
            var m = ex.Message.ToLower();
            if (m.Contains("reset") || m.Contains("сброс"))
                return "RST";
            return "DRP";
        }

        if (read < 5)
            return "DRP";

        if (header[0] == 0x16)
            return "OK";

        if (header[0] == 0x15)
            return "OK";

        return "DRP";
    }

    private static byte[] BuildModernHello(string host)
    {
        var body = new List<byte>();
        body.AddRange(new byte[] { 0x03, 0x03 });

        var random = new byte[32];
        FillRandomBytes(random);
        body.AddRange(random);

        body.Add(0x00);
        body.AddRange(new byte[] { 0x00, 0x06, 0x13, 0x01, 0x13, 0x02, 0x13, 0x03 });
        body.Add(0x20);
        var sessId = new byte[32];
        FillRandomBytes(sessId);
        body.AddRange(sessId);

        var exts = new List<byte>();

        var h = Encoding.ASCII.GetBytes(host);
        exts.AddRange(new byte[] { 0x00, 0x00 });
        var sniLen = h.Length + 5;
        exts.Add((byte)(sniLen >> 8));
        exts.Add((byte)(sniLen & 0xFF));
        exts.Add((byte)((h.Length + 3) >> 8));
        exts.Add((byte)((h.Length + 3) & 0xFF));
        exts.Add(0x00);
        exts.Add((byte)(h.Length >> 8));
        exts.Add((byte)(h.Length & 0xFF));
        exts.AddRange(h);

        exts.AddRange(new byte[] { 0x00, 0x17, 0x00, 0x00 });

        exts.AddRange(new byte[] { 0x00, 0x0a, 0x00, 0x04, 0x00, 0x02, 0x00, 0x1d });

        exts.AddRange(new byte[] { 0x00, 0x0d, 0x00, 0x08, 0x00, 0x06, 0x04, 0x03, 0x08, 0x04, 0x04, 0x01 });

        exts.AddRange(new byte[] { 0x00, 0x2b, 0x00, 0x03, 0x02, 0x03, 0x04 });

        exts.AddRange(new byte[] { 0x00, 0x2d, 0x00, 0x02, 0x01, 0x01 });

        exts.AddRange(new byte[] { 0x00, 0x33, 0x00, 0x26, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20 });
        var key = new byte[32];
        FillRandomBytes(key);
        exts.AddRange(key);

        body.Add((byte)(exts.Count >> 8));
        body.Add((byte)(exts.Count & 0xFF));
        body.AddRange(exts);

        var pkt = new List<byte> { 0x16, 0x03, 0x01 };
        pkt.Add((byte)(body.Count >> 8));
        pkt.Add((byte)(body.Count & 0xFF));
        pkt.AddRange(body);
        return pkt.ToArray();
    }
}
