using YT_DPI.Core.Trace;

namespace YT_DPI.Core.Tests;

/// <summary>No ICMP dependency: fast local helpers only. Full hop tests belong outside CI.</summary>
public class TracerouteStableTests
{
    [Fact]
    public void NetworkInfoFast_GetCachedInfo_returns_usable_dictionary()
    {
        dynamic info = AdvancedTraceroute.NetworkInfoFast.GetCachedInfo();
        Assert.NotNull(info);
        Assert.True(info.ContainsKey("DNS"));
        Assert.True(info.ContainsKey("TimestampTicks"));
    }

    [Fact]
    public void SynchronousProgress_invokes_handler_inline()
    {
        string? last = null;
        var p = new SynchronousProgress(s => last = s);
        p.Report("x");
        Assert.Equal("x", last);
    }
}
