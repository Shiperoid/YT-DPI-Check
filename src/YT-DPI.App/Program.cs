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
    private static int GetPreviewMaxTargets()
    {
        var v = Environment.GetEnvironmentVariable("YT_DPI_PREVIEW_MAX_TARGETS");
        if (string.IsNullOrWhiteSpace(v) || !int.TryParse(v, out var n) || n <= 0)
            return int.MaxValue;
        return n;
    }

    private static IReadOnlyList<string> GetTargetsForRun(YtDpiUserConfig cfg)
    {
        var cap = GetPreviewMaxTargets();
        return ScanTargetsBuilder.BuildTargetsSubset(cfg, cap);
    }

    private static void Main()
    {
        using var app = Application.Create().Init();
        var scanCoord = new PreviewScanUiCoordinator();

        var cfgPath = UserConfigPaths.GetConfigFilePath();
        var (ok, cfg, err) = UserConfigLoader.TryLoadUserConfig();
        var targetsPreview = GetTargetsForRun(cfg);
        var cfgSummary =
            $"Config: {(ok ? "OK" : "ERR")}  file: {cfgPath}\n"
            + $"SchemaVersion={cfg.SchemaVersion}  IpPreference={cfg.IpPreference}  TlsMode={cfg.TlsMode}  Proxy.Enabled={cfg.Proxy.Enabled}\n"
            + $"NetCache.CDN={cfg.NetCache.CDN}  targets={targetsPreview.Count}"
            + (err is null ? "" : $"\nNote: {err}");

        var header = new TextView
        {
            Text = cfgSummary
                   + "\n\nEsc — выход. Ctrl+C — отменить скан. F5 — пересканировать.\n"
                   + "Список целей как Get-Targets в PS (BaseTargets + CDN). Опционально: YT_DPI_PREVIEW_MAX_TARGETS=N.",
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = 7,
            ReadOnly = true,
        };

        var table = BuildPlaceholderTable(targetsPreview);
        var tableView = new TableView(new DataTableSource(table))
        {
            X = 0,
            Y = 7,
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
        var rescanKey = new Key(KeyCode.F5);
        app.Keyboard.KeyDown += (_, key) =>
        {
            if (key == cancelScanKey)
            {
                if (scanCoord.TryCancelScan(status))
                    key.Handled = true;
                return;
            }

            if (key == rescanKey)
            {
                if (scanCoord.IsScanRunning)
                {
                    status.Text = "status: scan already running — wait or Ctrl+C";
                    key.Handled = true;
                    return;
                }

                var t = GetTargetsForRun(cfg);
                RebuildTablePlaceholders(table, tableView, t);
                scanCoord.StartBackgroundScan(app, table, tableView, status, cfg, t);
                key.Handled = true;
            }
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
            scanCoord.StartBackgroundScan(app, table, tableView, status, cfg, targetsPreview);
            return false;
        });

        app.Run(win);
    }

    private static DataTable BuildPlaceholderTable(IReadOnlyList<string> targets)
    {
        var dt = ScanTableSchema.CreateTable();
        for (var i = 0; i < targets.Count; i++)
            ScanTableSchema.AppendRow(dt, ScanRow.Placeholder(i + 1, targets[i]));
        return dt;
    }

    private static void RebuildTablePlaceholders(DataTable table, TableView tableView, IReadOnlyList<string> targets)
    {
        table.Rows.Clear();
        for (var i = 0; i < targets.Count; i++)
            ScanTableSchema.AppendRow(table, ScanRow.Placeholder(i + 1, targets[i]));
        tableView.SetNeedsDraw();
    }
}
