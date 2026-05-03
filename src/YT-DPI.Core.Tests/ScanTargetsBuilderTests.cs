using YT_DPI.Core.Config;
using YT_DPI.Core.Scan;

namespace YT_DPI.Core.Tests;

public class ScanTargetsBuilderTests
{
    [Fact]
    public void BuildTargets_includes_cdn_sorted_by_length()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        cfg.NetCache.CDN = "zz.example.cdn";
        var list = ScanTargetsBuilder.BuildTargets(cfg);
        Assert.Contains("zz.example.cdn", list);
        Assert.Equal(list.Count, list.OrderBy(s => s.Length).Count());
        for (var i = 1; i < list.Count; i++)
            Assert.True(list[i].Length >= list[i - 1].Length, "should be sorted by length ascending");
    }

    [Fact]
    public void BuildTargetsSubset_respects_cap()
    {
        var cfg = YtDpiUserConfig.CreateDefaults();
        var all = ScanTargetsBuilder.BuildTargets(cfg);
        var sub = ScanTargetsBuilder.BuildTargetsSubset(cfg, 3);
        Assert.Equal(3, sub.Count);
        Assert.True(all.Take(3).SequenceEqual(sub));
    }
}
