using System.Diagnostics;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using YT_DPI.Core.Config;

namespace YT_DPI.Core.Net;

/// <summary>SOCKS5 (RFC 1928 + auth) and HTTP CONNECT tunnel to <c>targetHost:targetPort</c>, aligned with <c>YT-DPI.ps1</c> ~2980–3120.</summary>
public static class ProxyTunnel
{
    private static readonly Regex HttpConnectOk = new(@"HTTP/1\.\d\s+200", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>Opens a tunnel through <paramref name="proxy"/> (must have <c>Enabled</c>, <c>Host</c>, <c>Port</c>). Retries up to 3 times with backoff like PS.</summary>
    public static bool TryOpen(
        ProxySection proxy,
        string targetHost,
        int targetPort,
        int timeoutMs,
        [System.Diagnostics.CodeAnalysis.NotNullWhen(true)] out ProxyTunnelConnection? connection,
        out int elapsedMs,
        out string? error)
    {
        elapsedMs = 0;
        error = null;
        connection = null;
        var sw = Stopwatch.StartNew();
        const int maxAttempts = 3;
        const int delayMs = 500;
        string? lastErr = null;

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            if (TryOpenOnce(proxy, targetHost, targetPort, timeoutMs, out connection, out var err))
            {
                elapsedMs = (int)Math.Min(int.MaxValue, sw.ElapsedMilliseconds);
                return true;
            }

            lastErr = err;
            if (attempt < maxAttempts)
                Thread.Sleep(delayMs * (int)Math.Pow(2, attempt - 1));
        }

        error = lastErr ?? "Proxy tunnel failed";
        return false;
    }

    private static bool TryOpenOnce(
        ProxySection proxy,
        string targetHost,
        int targetPort,
        int timeoutMs,
        [System.Diagnostics.CodeAnalysis.NotNullWhen(true)] out ProxyTunnelConnection? connection,
        out string? error)
    {
        connection = null;
        error = null;
        TcpClient? tcp = null;
        try
        {
            tcp = new TcpClient();
            var ar = tcp.BeginConnect(proxy.Host, proxy.Port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(Math.Max(1, timeoutMs)))
            {
                error = "Proxy connection timeout";
                tcp.Dispose();
                return false;
            }

            tcp.EndConnect(ar);
            var stream = tcp.GetStream();
            stream.ReadTimeout = timeoutMs;
            stream.WriteTimeout = timeoutMs;

            var kind = NormalizeProxyType(proxy.Type);
            if (kind == ProxyKind.Socks5)
            {
                if (!EstablishSocks5(stream, proxy, targetHost, targetPort, timeoutMs, out error))
                {
                    stream.Dispose();
                    tcp.Dispose();
                    return false;
                }
            }
            else if (kind == ProxyKind.Http)
            {
                if (!EstablishHttpConnect(stream, proxy, targetHost, targetPort, timeoutMs, out error))
                {
                    stream.Dispose();
                    tcp.Dispose();
                    return false;
                }
            }
            else
            {
                error = $"Unsupported proxy type: {proxy.Type}";
                stream.Dispose();
                tcp.Dispose();
                return false;
            }

            connection = new ProxyTunnelConnection(tcp, stream);
            tcp = null;
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            tcp?.Dispose();
            return false;
        }
    }

    private static ProxyKind NormalizeProxyType(string type)
    {
        if (string.IsNullOrWhiteSpace(type))
            return ProxyKind.Socks5;
        var t = type.Trim();
        if (t.Equals("AUTO", StringComparison.OrdinalIgnoreCase))
            return ProxyKind.Socks5;
        if (t.Equals("SOCKS5", StringComparison.OrdinalIgnoreCase) || t.Equals("socks5", StringComparison.Ordinal))
            return ProxyKind.Socks5;
        if (t.Equals("HTTP", StringComparison.OrdinalIgnoreCase))
            return ProxyKind.Http;
        return ProxyKind.Unknown;
    }

    private enum ProxyKind
    {
        Unknown,
        Socks5,
        Http,
    }

    private static bool EstablishSocks5(NetworkStream stream, ProxySection proxy, string targetHost, int targetPort, int timeoutMs, out string? error)
    {
        error = null;
        try
        {
            var hasUser = !string.IsNullOrEmpty(proxy.User) && !string.IsNullOrEmpty(proxy.Pass);
            byte[] greeting;
            if (hasUser)
                greeting = new byte[] { 0x05, 0x02, 0x02, 0x00 };
            else
                greeting = new byte[] { 0x05, 0x01, 0x00 };

            stream.Write(greeting, 0, greeting.Length);
            var methodPick = new byte[2];
            if (ReadBlocking(stream, methodPick, 0, 2, timeoutMs) < 2)
            {
                error = "SOCKS5: no method response";
                return false;
            }

            if (methodPick[0] != 0x05)
            {
                error = "SOCKS5: bad version in method response";
                return false;
            }

            var method = methodPick[1];
            if (method == 0xFF)
            {
                error = "SOCKS5: no acceptable auth method";
                return false;
            }

            if (method == 0x02)
            {
                if (!hasUser)
                {
                    error = "SOCKS5: server requires password but credentials missing";
                    return false;
                }

                var u = Encoding.UTF8.GetBytes(proxy.User);
                var p = Encoding.UTF8.GetBytes(proxy.Pass);
                if (u.Length > 255 || p.Length > 255)
                {
                    error = "SOCKS5: username or password too long";
                    return false;
                }

                var authMsg = new List<byte> { 0x01, (byte)u.Length };
                authMsg.AddRange(u);
                authMsg.Add((byte)p.Length);
                authMsg.AddRange(p);
                var authBytes = authMsg.ToArray();
                stream.Write(authBytes, 0, authBytes.Length);
                var authResp = new byte[2];
                if (ReadBlocking(stream, authResp, 0, 2, timeoutMs) < 2)
                {
                    error = "SOCKS5: no auth response";
                    return false;
                }

                if (authResp[0] != 0x01 || authResp[1] != 0x00)
                {
                    error = "SOCKS5: authentication failed";
                    return false;
                }
            }
            else if (method != 0x00)
            {
                error = $"SOCKS5: unsupported auth method 0x{method:X2}";
                return false;
            }

            var hostBytes = Encoding.UTF8.GetBytes(targetHost);
            if (hostBytes.Length > 255)
            {
                error = "SOCKS5: target hostname too long";
                return false;
            }

            var connectReq = new List<byte> { 0x05, 0x01, 0x00, 0x03, (byte)hostBytes.Length };
            connectReq.AddRange(hostBytes);
            connectReq.Add((byte)(targetPort >> 8));
            connectReq.Add((byte)(targetPort & 0xFF));
            var req = connectReq.ToArray();
            stream.Write(req, 0, req.Length);

            var head = new byte[4];
            if (ReadBlocking(stream, head, 0, 4, timeoutMs) < 4)
            {
                error = "SOCKS5: incomplete connect reply";
                return false;
            }

            if (head[0] != 0x05 || head[1] != 0x00)
            {
                error = $"SOCKS5: connect failed (rep=0x{head[1]:X2})";
                return false;
            }

            var atyp = head[3];
            if (atyp == 0x01)
            {
                var buf = new byte[6];
                if (ReadBlocking(stream, buf, 0, 6, timeoutMs) < 6)
                {
                    error = "SOCKS5: incomplete IPv4 bind";
                    return false;
                }
            }
            else if (atyp == 0x04)
            {
                var buf = new byte[18];
                if (ReadBlocking(stream, buf, 0, 18, timeoutMs) < 18)
                {
                    error = "SOCKS5: incomplete IPv6 bind";
                    return false;
                }
            }
            else if (atyp == 0x03)
            {
                var lenB = new byte[1];
                if (ReadBlocking(stream, lenB, 0, 1, timeoutMs) < 1)
                {
                    error = "SOCKS5: missing domain length in bind";
                    return false;
                }

                var dn = lenB[0];
                var rest = new byte[dn + 2];
                if (ReadBlocking(stream, rest, 0, dn + 2, timeoutMs) < dn + 2)
                {
                    error = "SOCKS5: incomplete domain bind";
                    return false;
                }
            }
            else
            {
                error = $"SOCKS5: unsupported ATYP 0x{atyp:X2} in reply";
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private static bool EstablishHttpConnect(NetworkStream stream, ProxySection proxy, string targetHost, int targetPort, int timeoutMs, out string? error)
    {
        error = null;
        try
        {
            var hdr = new StringBuilder();
            hdr.Append("CONNECT ").Append(targetHost).Append(':').Append(targetPort).Append(" HTTP/1.1\r\nHost: ").Append(targetHost).Append(':').Append(targetPort).Append("\r\n");
            if (!string.IsNullOrEmpty(proxy.User) && !string.IsNullOrEmpty(proxy.Pass))
            {
                var token = Convert.ToBase64String(Encoding.ASCII.GetBytes(proxy.User + ":" + proxy.Pass));
                hdr.Append("Proxy-Authorization: Basic ").Append(token).Append("\r\n");
            }

            hdr.Append("\r\n");
            var reqBytes = Encoding.ASCII.GetBytes(hdr.ToString());
            stream.Write(reqBytes, 0, reqBytes.Length);

            var response = new StringBuilder();
            var buf = new byte[1024];
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                if (stream.DataAvailable)
                {
                    var r = stream.Read(buf, 0, buf.Length);
                    if (r <= 0)
                        break;
                    response.Append(Encoding.ASCII.GetString(buf, 0, r));
                    if (response.ToString().Contains("\r\n\r\n", StringComparison.Ordinal))
                        break;
                }
                else
                    Thread.Sleep(20);
            }

            var text = response.ToString();
            if (HttpConnectOk.IsMatch(text))
                return true;

            var snip = text.Length > 160 ? text[..160] + "..." : text;
            error = "HTTP CONNECT not 200: " + snip;
            return false;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private static int ReadBlocking(NetworkStream stream, byte[] buffer, int offset, int count, int timeoutMs)
    {
        var sw = Stopwatch.StartNew();
        var total = 0;
        while (total < count)
        {
            if (sw.ElapsedMilliseconds > timeoutMs)
                return total;
            try
            {
                var n = stream.Read(buffer, offset + total, count - total);
                if (n == 0)
                    return total;
                total += n;
            }
            catch
            {
                return total;
            }
        }

        return total;
    }
}

/// <summary>Established TCP stream through proxy; dispose to close.</summary>
public sealed class ProxyTunnelConnection : IDisposable
{
    private TcpClient? _tcp;
    private NetworkStream? _stream;

    internal ProxyTunnelConnection(TcpClient tcp, NetworkStream stream)
    {
        _tcp = tcp;
        _stream = stream;
    }

    public NetworkStream Stream => _stream ?? throw new ObjectDisposedException(nameof(ProxyTunnelConnection));

    public void Dispose()
    {
        try
        {
            _stream?.Dispose();
        }
        catch
        {
            /* ignore */
        }

        try
        {
            _tcp?.Dispose();
        }
        catch
        {
            /* ignore */
        }

        _stream = null;
        _tcp = null;
    }
}
