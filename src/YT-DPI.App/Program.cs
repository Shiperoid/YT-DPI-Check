using System.Data;
using Terminal.Gui.App;
using Terminal.Gui.Drivers;
using Terminal.Gui.Input;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using YT_DPI.Core.Config;
using YT_DPI.Core.Preview;
using YT_DPI.Core.Scan;

namespace YT_DPI.App;

internal static class Program
{
    private static CancellationTokenSource? s_scanCts;
    private static volatile bool s_scanRunning;

    private static void Main()
    {
        using var app = Application.Create().Init();

        var cfgPath = UserConfigPaths.GetConfigFilePath();
        var (ok, cfg, err) = UserConfigLoader.TryLoadUserConfig();
        var cfgSummary =
            $"Config: {(ok ? "OK" : "ERR")}  file: {cfgPath}\n"
            + $"IpPreference={cfg.IpPreference}  TlsMode={cfg.TlsMode}  Proxy.Enabled={cfg.Proxy.Enabled}\n"
            + $"NetCache.Stale={cfg.NetCache.NetCacheStale}  DnsCache.Count={cfg.DnsCache.Count}"
            + (err is null ? "" : $"\nNote: {err}");

        var header = new TextView
        {
            Text = cfgSummary
                   + "\n\nEsc — выход. Ctrl+C — отменить скан. Скан TLS 1.3 в фоне; таблица как в PS (Draw-UI).",
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = 6,
            ReadOnly = true,
        };

        var table = BuildInitialPlaceholderTable();
        var tableView = new TableView(new DataTableSource(table))
        {
            X = 0,
            Y = 6,
            Width = Dim.Fill(),
            Height = Dim.Fill() - 1,
        };

        var status = new Label
        {
            Text = "status: idle | " + PreviewEngine.TlsQuickLocalTimeout() + " (TLS quick localhost 1ms)",
            X = 0,
            Y = Pos.AnchorEnd(1),
            Width = Dim.Fill(),
        };

        var cancelScanKey = new Key(KeyCode.C).WithCtrl;
        app.Keyboard.KeyDown += (_, key) =>
        {
            if (key != cancelScanKey)
                return;
            if (s_scanCts is null || s_scanCts.IsCancellationRequested || !s_scanRunning)
                return;
            s_scanCts.Cancel();
            status.Text = "status: cancelling scan (Ctrl+C)…";
            key.Handled = true;
        };

        var win = new Window
        {
            Title = "YT-DPI Preview (Terminal.Gui v2)",
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
        };
        win.Add(header, tableView, status);

        app.AddTimeout(TimeSpan.Zero, () =>
        {
            StartBackgroundScan(app, table, tableView, status, cfg);
            return false;
        });

        app.Run(win);
    }

    private static DataTable BuildInitialPlaceholderTable()
    {
        var dt = ScanTableSchema.CreateTable();
        var targets = PreviewTargetList.DefaultDomains;
        for (var i = 0; i < targets.Count; i++)
            ScanTableSchema.AppendRow(dt, ScanRow.Placeholder(i + 1, targets[i]));
        return dt;
    }

    private static void StartBackgroundScan(
        IApplication app,
        DataTable table,
        TableView tableView,
        Label status,
        YtDpiUserConfig cfg)
    {
        if (s_scanRunning)
            return;

        s_scanCts?.Dispose();
        s_scanCts = new CancellationTokenSource();
        var ct = s_scanCts.Token;
        s_scanRunning = true;
        status.Text = "status: starting TLS 1.3 preview scan…";

        var targets = PreviewTargetList.DefaultDomains;
        var progress = new Progress<string>(msg => app.Invoke(() => status.Text = "status: " + msg));
        var rowProgress = new Progress<(int Index, ScanRow Row)>(p =>
        {
            app.Invoke(() =>
            {
                if (p.Index < 0 || p.Index >= table.Rows.Count)
                    return;
                var r = p.Row;
                table.Rows[p.Index][ScanTableSchema.ColIp] = r.IP;
                table.Rows[p.Index][ScanTableSchema.ColT13] = r.T13;
                table.Rows[p.Index][ScanTableSchema.ColVerdict] = r.Verdict;
                tableView.SetNeedsDraw();
            });
        });

        _ = Task.Run(async () =>
        {
            try
            {
                var result = await PreviewScanRunner.RunTls13PreviewAsync(
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
                s_scanRunning = false;
            }
        }, ct);
    }
}
