namespace YT_DPI.Core.Scan;

/// <summary>Static preview targets (v1); later replace with Get-Targets port or config-driven list.</summary>
public static class PreviewTargetList
{
    public static IReadOnlyList<string> DefaultDomains { get; } =
    [
        "preview.youtube.com",
        "preview.googlevideo.com",
        "www.google.com",
    ];
}
