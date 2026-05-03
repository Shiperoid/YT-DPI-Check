// Ported from YT-DPI.ps1 embedded C# (here-string lines 544-1073).

namespace YT_DPI.Core.Trace;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// Не использовать System.Progress: в pw7 без SynchronizationContext колбэки идут в ThreadPool,
/// а обновление консоли из фонового потока приводит к аварийному завершению процесса.
/// </summary>
public sealed class SynchronousProgress : IProgress<string>
{
    private readonly Action<string> _handler;
    public SynchronousProgress(Action<string> handler) { _handler = handler; }
    public void Report(string value) { if (_handler != null) { _handler.Invoke(value); } }
}

public class AdvancedTraceroute
{
    private static readonly object s_synRngLock = new object();
    private static readonly Random s_synRng = new Random();

    private static int NextBoundedInt(int minInclusive, int maxExclusive)
    {
        lock (s_synRngLock) { return s_synRng.Next(minInclusive, maxExclusive); }
    }

    // ========== ПУБЛИЧНЫЕ МЕТОДЫ ==========

    /// <summary>
    /// Выполняет трассировку с автоопределением лучшего метода
    /// </summary>
    public static List<TraceHop> Trace(string target, int maxHops = 30, int timeoutMs = 3000,
                                       TraceMethod method = TraceMethod.Auto, IProgress<string> progress = null)
    {
        // Разрешаем DNS
        if (progress != null) { progress.Report(string.Format("[*] Разрешение DNS: {0}", target)); }
        var targetIp = ResolveTarget(target);
        if (targetIp == null)
        {
            if (progress != null) { progress.Report(string.Format("[!] Не удалось разрешить DNS: {0}", target)); }
            return new List<TraceHop>();
        }
        if (progress != null) { progress.Report(string.Format("[+] Целевой IP: {0}", targetIp)); }

        // Автоопределение метода
        if (method == TraceMethod.Auto)
        {
            method = DetectBestMethod(targetIp);
            if (progress != null) { progress.Report(string.Format("[*] Выбран метод: {0}", method)); }
        }

        // Выполняем трассировку
        switch (method)
        {
            case TraceMethod.Icmp:
                return TraceWithIcmp(targetIp, maxHops, timeoutMs, progress);
            case TraceMethod.TcpSyn:
                return TraceWithTcpSyn(targetIp, 443, maxHops, timeoutMs, progress);
            case TraceMethod.Udp:
                return TraceWithUdp(targetIp, 33434, maxHops, timeoutMs, progress);
            default:
                return TraceWithIcmp(targetIp, maxHops, timeoutMs, progress);
        }
    }

    /// <summary>
    /// Быстрая трассировка TCP SYN (обходит ICMP блокировки)
    /// </summary>
    public static List<TraceHop> QuickTcpTrace(string target, int port = 443, int maxHops = 15)
    {
        return TraceWithTcpSyn(ResolveTarget(target), port, maxHops, 2000, null);
    }

    // ========== ВНУТРЕННИЕ МЕТОДЫ ==========

    private static IPAddress ResolveTarget(string target)
    {
        try
        {
            var addresses = Dns.GetHostAddresses(target);
            return addresses.FirstOrDefault(ip => ip.AddressFamily == AddressFamily.InterNetwork)
                   ?? addresses.FirstOrDefault();
        }
        catch { return null; }
    }

    public class NetworkInfoFast {
    public static dynamic GetCachedInfo() {
        var result = new Dictionary<string, object>();

        // DNS (быстро)
        try {
            var hostName = Dns.GetHostName();
            var ips = Dns.GetHostAddresses(hostName);
            var dns = ips.FirstOrDefault(ip => ip.AddressFamily == AddressFamily.InterNetwork);
            result["DNS"] = (dns != null ? dns.ToString() : null) ?? "UNKNOWN";
        } catch { result["DNS"] = "UNKNOWN"; }

        // CDN через DNS (быстро, без HTTP)
        try {
            var cdnIps = Dns.GetHostAddresses("redirector.googlevideo.com");
            result["CDN"] = "redirector.googlevideo.com (DNS resolved)";
        } catch { result["CDN"] = "manifest.googlevideo.com"; }

        result["ISP"] = "Detected via C#";
        result["LOC"] = "Fast mode";
        result["HasIPv6"] = Socket.OSSupportsIPv6;
        result["TimestampTicks"] = DateTime.Now.Ticks;

        return result;
    }
}

    private static TraceMethod DetectBestMethod(IPAddress targetIp)
    {
        // Пробуем ICMP (быстрый тест)
        using (var ping = new Ping())
        {
            try
            {
                var reply = ping.Send(targetIp, 1000);
                if (reply != null && reply.Status == IPStatus.Success)
                    return TraceMethod.Icmp;
            }
            catch { }
        }

        // Если ICMP заблокирован, пробуем TCP
        using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.Tcp))
        {
            try
            {
                socket.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.IpTimeToLive, 1);
                return TraceMethod.TcpSyn;
            }
            catch (SocketException)
            {
                // Raw sockets требуют админских прав
                return TraceMethod.Udp; // UDP работает без админа
            }
        }
    }

    // SocketError.TtlExpired отсутствует в public enum .NET 5+ (см. System.Net.Sockets.SocketError) — только эвристика по тексту.
    private static bool LooksLikeTracerouteTtlExpired(SocketException ex)
    {
        if (ex == null) return false;
        string m = ex.Message ?? string.Empty;
        return m.IndexOf("TTL", StringComparison.OrdinalIgnoreCase) >= 0
            || m.IndexOf("time to live", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    // ========== ICMP TRACEROUTE (ТРЕБУЕТ АДМИНА) ==========

    private static List<TraceHop> TraceWithIcmp(IPAddress targetIp, int maxHops, int timeoutMs,
                                                 IProgress<string> progress)
    {
        var results = new List<TraceHop>();
        using (var ping = new Ping())
        {
            var options = new PingOptions(1, true);
            var buffer = new byte[32];

            for (int ttl = 1; ttl <= maxHops; ttl++)
            {
                if (progress != null) { progress.Report(string.Format("[TRACE] Hop {0}/{1} (ICMP)...", ttl, maxHops)); }
                options.Ttl = ttl;

                try
                {
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    var reply = ping.Send(targetIp, timeoutMs, buffer, options);
                    sw.Stop();

                    var hop = new TraceHop
                    {
                        HopNumber = ttl,
                        IP = (reply.Address != null ? reply.Address.ToString() : null) ?? "*",
                        RttMs = (int)sw.ElapsedMilliseconds,
                        Status = MapIcmpStatus(reply.Status)
                    };

                    results.Add(hop);
                    if (progress != null) { progress.Report(string.Format("[OK] Hop {0}: {1} - {2} ({3}ms)", ttl, hop.IP, hop.Status, hop.RttMs)); }

                    if (reply.Status == IPStatus.Success ||
                        (reply.Address != null && reply.Address.Equals(targetIp)))
                        break;
                }
                catch (PingException)
                {
                    results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "TIMEOUT" });
                    if (progress != null) { progress.Report(string.Format("[!] Hop {0}: TIMEOUT", ttl)); }
                }
                catch (Exception ex)
                {
                    if (progress != null) { progress.Report(string.Format("[ERROR] Hop {0}: {1}", ttl, ex.Message)); }
                }

                Thread.Sleep(20); // Небольшая задержка между хопами
            }
        }
        return results;
    }

    // ========== TCP SYN TRACEROUTE (ОБХОДИТ ICMP, ТРЕБУЕТ АДМИНА) ==========

    private static List<TraceHop> TraceWithTcpSyn(IPAddress targetIp, int port, int maxHops,
                                                   int timeoutMs, IProgress<string> progress)
    {
        var results = new List<TraceHop>();
        var localIp = GetLocalIpAddress();

        for (int ttl = 1; ttl <= maxHops; ttl++)
        {
            if (progress != null) { progress.Report(string.Format("[TRACE] Hop {0}/{1} (TCP SYN:{2})...", ttl, maxHops, port)); }

            using (var sender = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.IP))
            using (var receiver = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.IP))
            {
                try
                {
                    // Настройка сокетов
                    sender.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.HeaderIncluded, true);
                    sender.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.IpTimeToLive, ttl);

                    receiver.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.HeaderIncluded, true);
                    receiver.ReceiveTimeout = timeoutMs;
                    receiver.Bind(new IPEndPoint(IPAddress.Any, 0));

                    // Собираем TCP SYN пакет
                    var srcPort = NextBoundedInt(1024, 65535);
                    var seq = (uint)NextBoundedInt(1, int.MaxValue);

                    var tcpPacket = BuildTcpSynPacket(srcPort, port, seq);
                    var ipPacket = BuildIpPacket(localIp, targetIp, 6, tcpPacket);

                    // Отправляем
                    var endpoint = new IPEndPoint(targetIp, 0);
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    sender.SendTo(ipPacket, endpoint);

                    // Ждем ответ
                    var buffer = new byte[4096];
                    var remoteEp = (EndPoint)new IPEndPoint(IPAddress.Any, 0);

                    string responderIp = null;
                    string status = "TIMEOUT";
                    int rttMs = -1;

                    if (receiver.Poll(timeoutMs * 1000, SelectMode.SelectRead))
                    {
                        var bytes = receiver.ReceiveFrom(buffer, ref remoteEp);
                        sw.Stop();
                        rttMs = (int)sw.ElapsedMilliseconds;

                        responderIp = ((IPEndPoint)remoteEp).Address.ToString();
                        status = ParseIpResponse(buffer, bytes, targetIp, port);
                    }

                    var hop = new TraceHop
                    {
                        HopNumber = ttl,
                        IP = responderIp ?? "*",
                        TcpStatus = status,
                        RttMs = rttMs,
                        Status = status == "SYNACK" ? "RESPONDED" :
                                (status == "RST" ? "BLOCKED" : "TIMEOUT")
                    };

                    results.Add(hop);
                    if (progress != null) { progress.Report(string.Format("[OK] Hop {0}: {1} - {2} ({3}ms)", ttl, hop.IP, hop.Status, hop.RttMs)); }

                    if (status == "SYNACK" || (responderIp == targetIp.ToString()))
                        break;
                }
                catch (SocketException ex)
                {
                    if (progress != null) { progress.Report(string.Format("[!] Hop {0}: SOCKET ERROR - {1}", ttl, ex.Message)); }
                    results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "ERROR" });
                }
                catch (Exception ex)
                {
                    if (progress != null) { progress.Report(string.Format("[ERROR] Hop {0}: {1}", ttl, ex.Message)); }
                }
            }
            Thread.Sleep(20);
        }
        return results;
    }

    // ========== UDP TRACEROUTE (НЕ ТРЕБУЕТ АДМИНА, РАБОТАЕТ ВЕЗДЕ) ==========

    private static List<TraceHop> TraceWithUdp(IPAddress targetIp, int startPort, int maxHops,
                                                int timeoutMs, IProgress<string> progress)
    {
        var results = new List<TraceHop>();

        for (int ttl = 1; ttl <= maxHops; ttl++)
        {
            if (progress != null) { progress.Report(string.Format("[TRACE] Hop {0}/{1} (UDP)...", ttl, maxHops)); }

            using (var sender = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
            using (var receiver = new Socket(AddressFamily.InterNetwork, SocketType.Raw, ProtocolType.Icmp))
            {
                try
                {
                    sender.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.IpTimeToLive, ttl);
                    receiver.ReceiveTimeout = timeoutMs;
                    receiver.Bind(new IPEndPoint(IPAddress.Any, 0));

                    var sendPort = startPort + ttl;
                    var endpoint = new IPEndPoint(targetIp, sendPort);
                    var buffer = new byte[] { 0x00 };

                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    sender.SendTo(buffer, endpoint);

                    var responseBuffer = new byte[256];
                    var remoteEp = (EndPoint)new IPEndPoint(IPAddress.Any, 0);

                    string responderIp = null;
                    string status = "TIMEOUT";
                    int rttMs = -1;

                    if (receiver.Poll(timeoutMs * 1000, SelectMode.SelectRead))
                    {
                        var bytes = receiver.ReceiveFrom(responseBuffer, ref remoteEp);
                        sw.Stop();
                        rttMs = (int)sw.ElapsedMilliseconds;
                        responderIp = ((IPEndPoint)remoteEp).Address.ToString();
                        status = "RESPONDED";
                    }

                    var hop = new TraceHop
                    {
                        HopNumber = ttl,
                        IP = responderIp ?? "*",
                        RttMs = rttMs,
                        Status = status
                    };

                    results.Add(hop);
                    if (progress != null) { progress.Report(string.Format("[OK] Hop {0}: {1} - {2} ({3}ms)", ttl, hop.IP, hop.Status, hop.RttMs)); }

                    if (responderIp == targetIp.ToString())
                        break;
                }
                catch (SocketException ex)
                {
                    if (LooksLikeTracerouteTtlExpired(ex))
                    {
                        // TTL истек - это нормально для промежуточных хопов
                        if (progress != null) { progress.Report(string.Format("[*] Hop {0}: TTL expired", ttl)); }
                        results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "TTL_EXPIRED" });
                    }
                    else
                    {
                        if (progress != null) { progress.Report(string.Format("[!] Hop {0}: {1}", ttl, ex.Message)); }
                        results.Add(new TraceHop { HopNumber = ttl, IP = "*", Status = "ERROR" });
                    }
                }
            }
            Thread.Sleep(20);
        }
        return results;
    }

    // ========== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ==========

    private static IPAddress GetLocalIpAddress()
    {
        using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
        {
            socket.Connect("8.8.8.8", 53);
            var endPoint = socket.LocalEndPoint as IPEndPoint;
            return (endPoint == null) ? null : endPoint.Address;
        }
    }

    private static byte[] BuildTcpSynPacket(int srcPort, int dstPort, uint seq)
    {
        var tcp = new byte[20];

        // Source port
        tcp[0] = (byte)(srcPort >> 8);
        tcp[1] = (byte)(srcPort & 0xFF);
        // Destination port
        tcp[2] = (byte)(dstPort >> 8);
        tcp[3] = (byte)(dstPort & 0xFF);
        // Sequence number
        tcp[4] = (byte)(seq >> 24);
        tcp[5] = (byte)(seq >> 16);
        tcp[6] = (byte)(seq >> 8);
        tcp[7] = (byte)(seq & 0xFF);
        // Data offset (5 = 20 bytes header) + flags (SYN)
        tcp[12] = 0x50; // Data offset = 5 (20 bytes)
        tcp[13] = 0x02; // SYN flag
        // Window size
        tcp[14] = 0x20;
        tcp[15] = 0x00;

        return tcp;
    }

    private static byte[] BuildIpPacket(IPAddress source, IPAddress destination,
                                        byte protocol, byte[] payload)
    {
        var totalLen = 20 + payload.Length;
        var packet = new byte[totalLen];

        // IP version (4) + header length (5)
        packet[0] = 0x45;
        // Total length
        packet[2] = (byte)(totalLen >> 8);
        packet[3] = (byte)(totalLen & 0xFF);
        // TTL (64)
        packet[8] = 64;
        // Protocol
        packet[9] = protocol;
        // Source IP
        source.GetAddressBytes().CopyTo(packet, 12);
        // Destination IP
        destination.GetAddressBytes().CopyTo(packet, 16);

        // Calculate checksum
        // Контрольная сумма только по IPv4-заголовку (20 байт), не по TCP payload (RFC 791).
        var checksum = ComputeIpChecksum(packet, 20);
        packet[10] = (byte)(checksum >> 8);
        packet[11] = (byte)(checksum & 0xFF);

        // Payload
        payload.CopyTo(packet, 20);

        return packet;
    }

    private static ushort ComputeIpChecksum(byte[] packet, int ipHeaderLength)
    {
        uint sum = 0;
        for (int i = 0; i < ipHeaderLength; i += 2)
        {
            if (i + 1 < ipHeaderLength)
                sum += (uint)((packet[i] << 8) | packet[i + 1]);
            else
                sum += (uint)(packet[i] << 8);

            if ((sum & 0xFFFF0000) != 0)
            {
                sum = (sum & 0xFFFF) + (sum >> 16);
            }
        }

        return (ushort)~sum;
    }

    private static string ParseIpResponse(byte[] buffer, int bytes, IPAddress targetIp, int targetPort)
    {
        if (bytes < 20) return "UNKNOWN";

        var protocol = buffer[9];

        if (protocol == 1) // ICMP
        {
            var type = buffer[20];
            if (type == 11) return "TTL_EXPIRED";
            if (type == 3) return "PORT_UNREACHABLE";
            return string.Format("ICMP_{0}", type);
        }
        else if (protocol == 6) // TCP
        {
            var ipHeaderLen = (buffer[0] & 0x0F) * 4;
            if (bytes < ipHeaderLen + 20) return "UNKNOWN";

            var tcpOffset = ipHeaderLen;
            var flags = buffer[tcpOffset + 13];

            if ((flags & 0x12) == 0x12) return "SYNACK";
            if ((flags & 0x04) == 0x04) return "RST";
            return "TCP_OTHER";
        }

        return "UNKNOWN";
    }

    private static string MapIcmpStatus(IPStatus status)
    {
        switch (status)
        {
            case IPStatus.Success: return "RESPONDED";
            case IPStatus.TtlExpired: return "TTL_EXPIRED";
            case IPStatus.TimedOut: return "TIMEOUT";
            case IPStatus.DestinationUnreachable: return "UNREACHABLE";
            default: return status.ToString();
        }
    }
}

// ========== ВСПОМОГАТЕЛЬНЫЕ КЛАССЫ ==========

public enum TraceMethod
{
    Auto,
    Icmp,
    TcpSyn,
    Udp
}

public class TraceHop
{
    public int HopNumber { get; set; }
    public string IP { get; set; }
    public int RttMs { get; set; }
    public string Status { get; set; }
    public string TcpStatus { get; set; } // Для TCP метода (SYNACK/RST)

    public bool IsBlocking { get { return Status == "BLOCKED" || TcpStatus == "RST"; } }
    public bool IsTimeout { get { return Status == "TIMEOUT" || Status == "TTL_EXPIRED"; } }

    public override string ToString()
    {
        string rttPart = (RttMs > 0) ? string.Format("({0}ms)", RttMs) : "";
        return string.Format("Hop {0,2}: {1,-15} {2} {3}", HopNumber, IP == null ? "" : IP, Status == null ? "" : Status, rttPart);
    }
}

