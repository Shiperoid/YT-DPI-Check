// Ported from YT-DPI.ps1 embedded C# (here-string lines 376-513).

namespace YT_DPI.Core.Tls;

using System;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Linq;
using System.Security.Cryptography;

public class TlsScanner {
    private static void FillRandomBytes(byte[] buffer) {
        using (var rng = RandomNumberGenerator.Create()) {
            rng.GetBytes(buffer);
        }
    }
    public static string TestT13(string targetIp, string host, string proxyHost, int proxyPort, string user, string pass, int timeout) {
        try {
            using (TcpClient tcp = new TcpClient()) {
                string connectHost = string.IsNullOrEmpty(proxyHost) ? targetIp : proxyHost;
                int connectPort = string.IsNullOrEmpty(proxyHost) ? 443 : proxyPort;

                var ar = tcp.BeginConnect(connectHost, connectPort, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeout)) return "DRP";
                tcp.EndConnect(ar);

                NetworkStream stream = tcp.GetStream();
                stream.ReadTimeout = timeout;
                stream.WriteTimeout = timeout;

                if (!string.IsNullOrEmpty(proxyHost)) {
                    byte[] greeting = new byte[] { 0x05, 0x01, 0x00 };
                    stream.Write(greeting, 0, greeting.Length);
                    byte[] authResp = new byte[2];
                    stream.Read(authResp, 0, 2);

                    byte[] connectReq = BuildSocksConnect(host, 443);
                    stream.Write(connectReq, 0, connectReq.Length);
                    byte[] connResp = new byte[10];
                    stream.Read(connResp, 0, 10);
                    if (connResp[1] != 0x00) return "PRX_ERR";
                }

                // Шлем исправленный пакет
                byte[] hello = BuildModernHello(host);
                stream.Write(hello, 0, hello.Length);

                byte[] header = new byte[5];
                int read = 0;
                try {
                    read = stream.Read(header, 0, 5);
                } catch (System.IO.IOException ex) {
                    string m = ex.Message.ToLower();
                    if (m.Contains("reset") || m.Contains("сброс")) return "RST";
                    return "DRP";
                }

                if (read < 5) return "DRP";

                // 0x16 = Handshake (Server Hello) - Успех
                if (header[0] == 0x16) return "OK";

                // 0x15 = TLS Alert. Если сервер прислал это, значит пакет валиден,
                // но серверу что-то не нравится. Для теста доступности это "OK" (сервер ответил).
                if (header[0] == 0x15) return "OK";

                return "DRP";
            }
        } catch (Exception ex) {
            string m = ex.Message.ToLower();
            if (m.Contains("reset") || m.Contains("closed")) return "RST";
            return "DRP";
        }
    }

    private static byte[] BuildSocksConnect(string host, int port) {
        List<byte> req = new List<byte> { 0x05, 0x01, 0x00, 0x03 };
        byte[] h = Encoding.ASCII.GetBytes(host);
        req.Add((byte)h.Length);
        req.AddRange(h);
        req.Add((byte)(port >> 8));
        req.Add((byte)(port & 0xFF));
        return req.ToArray();
    }

    private static byte[] BuildModernHello(string host) {
        List<byte> body = new List<byte>();
        body.AddRange(new byte[] { 0x03, 0x03 }); // TLS 1.2 (for compatibility header)

        byte[] random = new byte[32];
        FillRandomBytes(random);
        body.AddRange(random);

        body.Add(0x00); // Session ID len
        body.AddRange(new byte[] { 0x00, 0x06, 0x13, 0x01, 0x13, 0x02, 0x13, 0x03 }); // Ciphers: TLS_AES_128_GCM_SHA256 и др.
        body.Add(0x20); // Length 32
        byte[] sessId = new byte[32]; FillRandomBytes(sessId);
        body.AddRange(sessId);

        List<byte> exts = new List<byte>();

        // 1. SNI
        byte[] h = Encoding.ASCII.GetBytes(host);
        exts.AddRange(new byte[] { 0x00, 0x00 }); // Type SNI
        int sniLen = h.Length + 5;
        exts.Add((byte)(sniLen >> 8)); exts.Add((byte)(sniLen & 0xFF));
        exts.Add((byte)((h.Length + 3) >> 8)); exts.Add((byte)((h.Length + 3) & 0xFF));
        exts.Add(0x00); // Name type: host_name
        exts.Add((byte)(h.Length >> 8)); exts.Add((byte)(h.Length & 0xFF));
        exts.AddRange(h);

        // 2. Extended Master Secret (0x0017)
        exts.AddRange(new byte[] { 0x00, 0x17, 0x00, 0x00 });

        // 3. Supported Groups (0x000a) - x25519
        exts.AddRange(new byte[] { 0x00, 0x0a, 0x00, 0x04, 0x00, 0x02, 0x00, 0x1d });

        // 4. Signature Algorithms (0x000d) - КРИТИЧНО ДЛЯ GOOGLE
        // ecdsa_secp256r1_sha256, rsa_pss_rsae_sha256, rsa_pkcs1_sha256
        exts.AddRange(new byte[] { 0x00, 0x0d, 0x00, 0x08, 0x00, 0x06, 0x04, 0x03, 0x08, 0x04, 0x04, 0x01 });

        // 5. Supported Versions (0x002b) - TLS 1.3
        exts.AddRange(new byte[] { 0x00, 0x2b, 0x00, 0x03, 0x02, 0x03, 0x04 });

        // 6. PSK Key Exchange Modes (0x002d) - КРИТИЧНО ДЛЯ TLS 1.3
        exts.AddRange(new byte[] { 0x00, 0x2d, 0x00, 0x02, 0x01, 0x01 });

        // 7. Key Share (0x0033)
        exts.AddRange(new byte[] { 0x00, 0x33, 0x00, 0x26, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20 });
        byte[] key = new byte[32]; FillRandomBytes(key);
        exts.AddRange(key);

        body.Add((byte)(exts.Count >> 8)); body.Add((byte)(exts.Count & 0xFF));
        body.AddRange(exts);

        List<byte> pkt = new List<byte> { 0x16, 0x03, 0x01 }; // Record Header
        pkt.Add((byte)(body.Count >> 8)); pkt.Add((byte)(body.Count & 0xFF));
        pkt.AddRange(body);
        return pkt.ToArray();
    }
}

