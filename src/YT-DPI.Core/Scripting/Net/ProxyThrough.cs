#nullable disable
using System;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace YtDpi
{
    /// <summary>SOCKS5 and HTTP CONNECT tunnel (ported from YT-DPI.ps1 Connect-ThroughProxy).</summary>
    public static class ProxyThrough
    {
        const int MaxAttempts = 3;
        const int BaseDelayMs = 500;

        public static ProxyTunnelConnection Establish(
            string proxyHost,
            int proxyPort,
            string proxyType,
            string targetHost,
            int targetPort,
            string proxyUser,
            string proxyPass,
            int timeoutMs)
        {
            if (string.IsNullOrWhiteSpace(proxyHost) || proxyPort <= 0)
                throw new InvalidOperationException("Некорректная конфигурация прокси: хост/порт");

            string kind = (proxyType ?? "").Trim().ToUpperInvariant();
            if (kind == "AUTO")
                throw new InvalidOperationException("Неподдерживаемый тип прокси для туннеля: AUTO (выберите SOCKS5 или HTTP)");

            Exception last = null;
            for (int attempt = 1; attempt <= MaxAttempts; attempt++)
            {
                TcpClient tcp = null;
                NetworkStream stream = null;
                try
                {
                    tcp = new TcpClient();
                    IAsyncResult ar = tcp.BeginConnect(proxyHost.Trim(), proxyPort, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(timeoutMs))
                        throw new TimeoutException("Proxy connection timeout");
                    tcp.EndConnect(ar);
                    stream = tcp.GetStream();
                    stream.ReadTimeout = timeoutMs;
                    stream.WriteTimeout = timeoutMs;
                    Socket sock = tcp.Client;

                    if (kind == "SOCKS5")
                    {
                        DoSocks5(stream, sock, targetHost, targetPort, proxyUser, proxyPass, timeoutMs);
                        return new ProxyTunnelConnection(tcp, stream);
                    }
                    if (kind == "HTTP")
                    {
                        DoHttpConnect(stream, sock, targetHost, targetPort, proxyUser, proxyPass, timeoutMs);
                        return new ProxyTunnelConnection(tcp, stream);
                    }

                    throw new InvalidOperationException("Неподдерживаемый тип прокси для туннеля: " + proxyType);
                }
                catch (Exception ex)
                {
                    last = ex;
                    try { stream?.Dispose(); } catch { }
                    try { tcp?.Close(); } catch { }
                    if (attempt == MaxAttempts)
                        throw last;
                    int sleep = (int)(BaseDelayMs * Math.Pow(2, attempt - 1));
                    Thread.Sleep(sleep);
                }
            }

            throw last ?? new InvalidOperationException("proxy connect failed");
        }

        static void DoSocks5(NetworkStream stream, Socket sock, string targetHost, int targetPort, string user, string pass, int timeoutMs)
        {
            byte[] methods;
            if (!string.IsNullOrEmpty(user) && !string.IsNullOrEmpty(pass))
                methods = new byte[] { 0x05, 0x02, 0x02, 0x00 };
            else
                methods = new byte[] { 0x05, 0x01, 0x00 };

            stream.Write(methods, 0, methods.Length);
            var methResp = new byte[2];
            SocketIo.ReadExact(stream, sock, methResp, timeoutMs);
            if (methResp[0] != 0x05)
                throw new InvalidOperationException("SOCKS5: неверная версия ответа на метод");

            byte method = methResp[1];
            if (method == 0x00) { }
            else if (method == 0x02)
            {
                if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(pass))
                    throw new InvalidOperationException("SOCKS5: сервер требует логин/пароль");
                byte[] ub = Encoding.UTF8.GetBytes(user);
                byte[] pb = Encoding.UTF8.GetBytes(pass);
                if (ub.Length > 255 || pb.Length > 255)
                    throw new InvalidOperationException("SOCKS5: credentials too long");
                var auth = new byte[3 + ub.Length + pb.Length];
                auth[0] = 0x01;
                auth[1] = (byte)ub.Length;
                Buffer.BlockCopy(ub, 0, auth, 2, ub.Length);
                auth[2 + ub.Length] = (byte)pb.Length;
                Buffer.BlockCopy(pb, 0, auth, 3 + ub.Length, pb.Length);
                stream.Write(auth, 0, auth.Length);
                var authResp = new byte[2];
                SocketIo.ReadExact(stream, sock, authResp, timeoutMs);
                if (authResp[0] != 0x01 || authResp[1] != 0x00)
                    throw new InvalidOperationException("SOCKS5: неверный логин/пароль (код " + authResp[1] + ")");
            }
            else if (method == 0xFF)
                throw new InvalidOperationException("SOCKS5: сервер отверг методы (0xFF)");
            else
                throw new InvalidOperationException("SOCKS5: неподдерживаемый метод 0x" + method.ToString("X2"));

            byte[] hostBytes = Encoding.UTF8.GetBytes(targetHost);
            if (hostBytes.Length > 255)
                throw new InvalidOperationException("SOCKS5: host name too long");

            var req = new List<byte>(9 + hostBytes.Length);
            req.AddRange(new byte[] { 0x05, 0x01, 0x00, 0x03, (byte)hostBytes.Length });
            req.AddRange(hostBytes);
            req.Add((byte)(targetPort >> 8));
            req.Add((byte)(targetPort & 0xFF));
            byte[] reqArr = req.ToArray();
            stream.Write(reqArr, 0, reqArr.Length);

            var hdr = new byte[4];
            SocketIo.ReadExact(stream, sock, hdr, timeoutMs);
            if (hdr[0] != 0x05)
                throw new InvalidOperationException("SOCKS5: неверная версия в ответе на подключение");
            if (hdr[1] != 0x00)
                throw MapSocksRep(hdr[1]);

            byte atyp = hdr[3];
            int tail = atyp == 0x01 ? 4 + 2 : atyp == 0x03 ? (SocketIo.ReadByte(stream, sock, timeoutMs) + 2) : atyp == 0x04 ? 16 + 2 : throw new InvalidOperationException("SOCKS5: address type not supported");
            SocketIo.SkipExact(stream, sock, tail, timeoutMs);
        }

        static Exception MapSocksRep(byte code)
        {
            string txt = code switch
            {
                0x01 => "general failure",
                0x02 => "connection not allowed",
                0x03 => "network unreachable",
                0x04 => "host unreachable",
                0x05 => "connection refused",
                0x06 => "TTL expired",
                0x07 => "command not supported",
                0x08 => "address type not supported",
                _ => "unknown error 0x" + code.ToString("X2")
            };
            return new InvalidOperationException("SOCKS5: сервер вернул ошибку - " + txt);
        }

        static void DoHttpConnect(NetworkStream stream, Socket sock, string targetHost, int targetPort, string user, string pass, int timeoutMs)
        {
            var hdr = new StringBuilder();
            hdr.Append("CONNECT ").Append(targetHost).Append(':').Append(targetPort).Append(" HTTP/1.1\r\nHost: ").Append(targetHost).Append(':').Append(targetPort).Append("\r\n");
            if (!string.IsNullOrEmpty(user) && !string.IsNullOrEmpty(pass))
            {
                string pair = user + ":" + pass;
                string b64 = Convert.ToBase64String(Encoding.ASCII.GetBytes(pair));
                hdr.Append("Proxy-Authorization: Basic ").Append(b64).Append("\r\n");
            }
            hdr.Append("\r\n");
            byte[] reqBytes = Encoding.ASCII.GetBytes(hdr.ToString());
            stream.Write(reqBytes, 0, reqBytes.Length);

            var sb = new StringBuilder();
            var buf = new byte[1024];
            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                if (!SocketIo.WaitCanRead(sock, Math.Min(250, timeoutMs - (int)sw.ElapsedMilliseconds)))
                    continue;
                int r = stream.Read(buf, 0, buf.Length);
                if (r <= 0) break;
                sb.Append(Encoding.ASCII.GetString(buf, 0, r));
                string acc = sb.ToString();
                if (acc.IndexOf("\r\n\r\n", StringComparison.Ordinal) >= 0)
                    break;
                Thread.Sleep(5);
            }

            string response = sb.ToString();
            if (response.IndexOf("\r\n\r\n", StringComparison.Ordinal) < 0)
                throw new InvalidOperationException("HTTP CONNECT: incomplete response");

            if (!LooksLikeHttp200(response))
            {
                string snip = response.Length > 160 ? response.Substring(0, 160) + "..." : response;
                throw new InvalidOperationException("HTTP CONNECT не 200: " + snip);
            }
        }

        static bool LooksLikeHttp200(string response)
        {
            foreach (string line in response.Split(new[] { "\r\n" }, StringSplitOptions.None))
            {
                if (string.IsNullOrEmpty(line)) continue;
                string u = line.TrimStart().ToUpperInvariant();
                if (u.StartsWith("HTTP/1.", StringComparison.Ordinal))
                {
                    return u.IndexOf(" 200", StringComparison.Ordinal) >= 0;
                }
            }
            return false;
        }
    }
}
