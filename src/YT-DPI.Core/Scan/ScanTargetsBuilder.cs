using YT_DPI.Core.Config;

namespace YT_DPI.Core.Scan;

/// <summary>Same rules as YT-DPI.ps1 Get-Targets (~1567–1575): $BaseTargets + NetInfo.CDN, sort by length, unique.</summary>
public static class ScanTargetsBuilder
{
    /// <summary>Must match <c>$BaseTargets</c> in YT-DPI.ps1 (~1538–1564).</summary>
    public static readonly string[] BaseTargets =
    [
        "youtu.be",
        "youtube.com",
        "i.ytimg.com",
        "s.ytimg.com",
        "yt3.ggpht.com",
        "yt4.ggpht.com",
        "s.youtube.com",
        "m.youtube.com",
        "googleapis.com",
        "tv.youtube.com",
        "googlevideo.com",
        "www.youtube.com",
        "play.google.com",
        "youtubekids.com",
        "video.google.com",
        "music.youtube.com",
        "accounts.google.com",
        "clients6.google.com",
        "studio.youtube.com",
        "manifest.googlevideo.com",
        "youtubei.googleapis.com",
        "www.youtube-nocookie.com",
        "signaler-pa.youtube.com",
        "redirector.googlevideo.com",
        "youtubeembeddedplayer.googleapis.com",
    ];

    /// <summary>Build ordered target list from config NetCache (CDN) like PS <c>Get-Targets $NetInfo</c>.</summary>
    public static IReadOnlyList<string> BuildTargets(YtDpiUserConfig cfg)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var t in BaseTargets)
            set.Add(t);

        var cdn = (cfg.NetCache.CDN ?? "").Trim();
        if (cdn.Length > 0 && !set.Contains(cdn))
            set.Add(cdn);

        return set.OrderBy(s => s.Length).ToList();
    }

    /// <summary>First N targets for fast local runs / tests (deterministic subset).</summary>
    public static IReadOnlyList<string> BuildTargetsSubset(YtDpiUserConfig cfg, int maxCount)
    {
        var all = BuildTargets(cfg);
        if (maxCount <= 0 || maxCount >= all.Count)
            return all;
        return all.Take(maxCount).ToList();
    }
}
