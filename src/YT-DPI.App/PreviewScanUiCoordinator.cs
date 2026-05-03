using System.Data;
using Terminal.Gui.App;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using YT_DPI.Core.Config;
using YT_DPI.Core.Scan;

namespace YT_DPI.App;

/// <summary>Background preview scan: CTS, marshals progress to UI thread, updates <see cref="ScanTableSchema"/> rows.</summary>
internal sealed class PreviewScanUiCoordinator
{
    private CancellationTokenSource? _scanCts;
    private volatile bool _scanRunning;

    public bool IsScanRunning => _scanRunning;

    /// <returns><c>true</c> if a running scan was cancelled (caller should set <c>key.Handled</c>).</returns>
    public bool TryCancelScan(Label status)
    {
        if (_scanCts is null || _scanCts.IsCancellationRequested || !_scanRunning)
            return false;
        _scanCts.Cancel();
        status.Text = "status: cancelling scan (Ctrl+C)…";
        return true;
    }

    public void StartBackgroundScan(
        IApplication app,
        DataTable table,
        TableView tableView,
        Label status,
        YtDpiUserConfig cfg,
        IReadOnlyList<string> targets)
    {
        if (_scanRunning)
            return;

        _scanCts?.Dispose();
        _scanCts = new CancellationTokenSource();
        var ct = _scanCts.Token;
        _scanRunning = true;
        status.Text = "status: starting preview scan…";

        var progress = new Progress<string>(msg => app.Invoke(() => status.Text = "status: " + msg));
        var rowProgress = new Progress<(int Index, ScanRow Row)>(p =>
        {
            app.Invoke(() =>
            {
                if (p.Index < 0 || p.Index >= table.Rows.Count)
                    return;
                var r = p.Row;
                var row = table.Rows[p.Index];
                row[ScanTableSchema.ColIp] = r.IP;
                row[ScanTableSchema.ColHttp] = r.HTTP;
                row[ScanTableSchema.ColT12] = r.T12;
                row[ScanTableSchema.ColT13] = r.T13;
                row[ScanTableSchema.ColLat] = r.Lat;
                row[ScanTableSchema.ColVerdict] = r.Verdict;
                tableView.SetNeedsDraw();
            });
        });

        _ = Task.Run(async () =>
        {
            try
            {
                var result = await PreviewScanRunner.RunFullPreviewScanAsync(
                        targets,
                        cfg,
                        progress,
                        rowProgress,
                        ct)
                    .ConfigureAwait(false);

                app.Invoke(() =>
                {
                    ScanTableSchema.FillFromRows(table, result);
                    tableView.SetNeedsDraw();
                    status.Text = ct.IsCancellationRequested
                        ? "status: scan cancelled"
                        : "status: scan finished";
                });
            }
            catch (OperationCanceledException)
            {
                app.Invoke(() => status.Text = "status: scan cancelled");
            }
            catch (Exception ex)
            {
                app.Invoke(() => status.Text = "status: error — " + ex.Message);
            }
            finally
            {
                _scanRunning = false;
            }
        }, ct);
    }
}
