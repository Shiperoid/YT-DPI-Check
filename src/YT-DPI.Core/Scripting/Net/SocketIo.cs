#nullable disable
using System;
using System.Net.Sockets;
using System.Threading;

namespace YtDpi
{
    internal static class SocketIo
    {
        [ThreadStatic]
        static byte[] t_scratch;

        static byte[] Scratch =>
            t_scratch ?? (t_scratch = new byte[256]);

        internal static bool WaitCanRead(Socket sock, int totalTimeoutMs)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < totalTimeoutMs)
            {
                int slice = (int)Math.Min(250, totalTimeoutMs - sw.ElapsedMilliseconds);
                if (slice <= 0) break;
                if (sock.Poll(slice * 1000, SelectMode.SelectRead))
                    return true;
                Thread.Sleep(5);
            }
            return false;
        }

        internal static int ReadSome(NetworkStream stream, Socket sock, byte[] buf, int off, int need, int totalTimeoutMs)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            int got = 0;
            while (got < need && sw.ElapsedMilliseconds < totalTimeoutMs)
            {
                int remainMs = totalTimeoutMs - (int)sw.ElapsedMilliseconds;
                if (remainMs <= 0) break;
                if (!WaitCanRead(sock, Math.Min(250, remainMs)))
                    continue;
                int r = stream.Read(buf, off + got, need - got);
                if (r == 0) break;
                got += r;
            }
            return got;
        }

        internal static void ReadExact(NetworkStream stream, Socket sock, byte[] buf, int totalTimeoutMs)
        {
            ReadExact(stream, sock, buf, 0, buf.Length, totalTimeoutMs);
        }

        internal static void ReadExact(NetworkStream stream, Socket sock, byte[] buf, int offset, int count, int totalTimeoutMs)
        {
            int n = ReadSome(stream, sock, buf, offset, count, totalTimeoutMs);
            if (n != count)
                throw new InvalidOperationException("unexpected EOF reading socket");
        }

        internal static byte ReadByte(NetworkStream stream, Socket sock, int totalTimeoutMs)
        {
            byte[] b = Scratch;
            ReadExact(stream, sock, b, 0, 1, totalTimeoutMs);
            return b[0];
        }

        internal static void SkipExact(NetworkStream stream, Socket sock, int len, int totalTimeoutMs)
        {
            byte[] buf = Scratch;
            int left = len;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (left > 0 && sw.ElapsedMilliseconds < totalTimeoutMs)
            {
                int chunk = Math.Min(buf.Length, left);
                int remainMs = totalTimeoutMs - (int)sw.ElapsedMilliseconds;
                if (remainMs <= 0) break;
                int r = ReadSome(stream, sock, buf, 0, chunk, remainMs);
                if (r == 0) throw new InvalidOperationException("unexpected EOF skipping SOCKS reply");
                left -= r;
            }
            if (left != 0)
                throw new TimeoutException("timeout skipping SOCKS reply tail");
        }
    }
}
