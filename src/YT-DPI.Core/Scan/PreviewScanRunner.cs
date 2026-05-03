using YT_DPI.Core.Config;

namespace YT_DPI.Core.Scan;

/// <summary>Preview scan orchestration: sequential targets, progress, cancellation. Per-row logic: <see cref="TargetRowScanner"/>; DNS: <see cref="DnsConnectIpResolver"/>.</summary>
public static class PreviewScanRunner
{
    public const string ProxiedIpMarker = "[ PROXIED ]";

    /// <summary>Legacy entry: TLS 1.3 only (kept for callers/tests).</summary>
    public static Task<IReadOnlyList<ScanRow>> RunTls13PreviewAsync(
        IReadOnlyList<string> targetDomains,
        YtDpiUserConfig cfg,
        IProgress<string>? status,
        IProgress<(int Index, ScanRow Row)>? rowProgress,
        CancellationToken cancellationToken)
        => RunFullPreviewScanAsync(targetDomains, cfg, status, rowProgress, cancellationToken);

    public static async Task<IReadOnlyList<ScanRow>> RunFullPreviewScanAsync(
        IReadOnlyList<string> targetDomains,
        YtDpiUserConfig cfg,
        IProgress<string>? status,
        IProgress<(int Index, ScanRow Row)>? rowProgress,
        CancellationToken cancellationToken)
    {
        var rows = new List<ScanRow>(targetDomains.Count);
        var n = targetDomains.Count;
        for (var i = 0; i < n; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var domain = targetDomains[i];
            status?.Report($"[{i + 1}/{n}] {domain}");

            var row = await Task.Run(
                    () => TargetRowScanner.ScanOneRow(i + 1, domain, cfg, cancellationToken),
                    cancellationToken)
                .ConfigureAwait(false);

            rows.Add(row);
            rowProgress?.Report((i, row));
            await Task.Yield();
        }

        status?.Report("Done");
        return rows;
    }
}
