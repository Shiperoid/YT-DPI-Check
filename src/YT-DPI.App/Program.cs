using System.Data;
using Terminal.Gui.App;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using YT_DPI.Core.Config;
using YT_DPI.Core.Preview;
using YT_DPI.Core.Tls;

namespace YT_DPI.App;

internal static class Program
{
    private static void Main()
    {
        using (var app = Application.Create().Init())
        {
            var win = new Window
            {
                Title = "YT-DPI Preview (Terminal.Gui v2)",
                X = 0,
                Y = 0,
                Width = Dim.Fill(),
                Height = Dim.Fill(),
            };

            var cfgPath = UserConfigPaths.GetConfigFilePath();
            var (ok, cfg, err) = UserConfigLoader.TryLoadUserConfig();
            var cfgSummary =
                $"Config: {(ok ? "OK" : "ERR")}  file: {cfgPath}\n"
                + $"IpPreference={cfg.IpPreference}  TlsMode={cfg.TlsMode}  Proxy.Enabled={cfg.Proxy.Enabled}\n"
                + $"NetCache.Stale={cfg.NetCache.NetCacheStale}  DnsCache.Count={cfg.DnsCache.Count}"
                + (err is null ? "" : $"\nNote: {err}");

            var header = new TextView
            {
                Text = cfgSummary + "\n\nEsc — выход. Таблица — заглушка скана; статус обновляется таймером.",
                X = 0,
                Y = 0,
                Width = Dim.Fill(),
                Height = 5,
                ReadOnly = true,
            };

            var table = BuildPlaceholderTable();
            var tableView = new TableView(new DataTableSource(table))
            {
                X = 0,
                Y = 5,
                Width = Dim.Fill(),
                Height = Dim.Fill() - 1,
            };

            var status = new Label
            {
                Text = "status: idle | TLS quick (127.0.0.1:1ms) = " + PreviewEngine.TlsQuickLocalTimeout(),
                X = 0,
                Y = Pos.AnchorEnd(1),
                Width = Dim.Fill(),
            };

            var tick = 0;
            app.AddTimeout(TimeSpan.FromSeconds(1), () =>
            {
                tick++;
                status.Text = $"status: tick={tick} | {DateTime.Now:HH:mm:ss}";
                return true;
            });

            win.Add(header, tableView, status);
            app.Run(win);
        }
    }

    private static DataTable BuildPlaceholderTable()
    {
        var dt = new DataTable();
        dt.Columns.Add("#", typeof(int));
        dt.Columns.Add("Target", typeof(string));
        dt.Columns.Add("Verdict", typeof(string));
        dt.Rows.Add(1, "preview.youtube.com", "PLACEHOLDER");
        dt.Rows.Add(2, "preview.googlevideo.com", "PLACEHOLDER");
        dt.Rows.Add(3, "TlsScanner.TestT13 sample", TlsScanner.TestT13("127.0.0.1", "example.com", "", 0, "", "", 1));
        return dt;
    }
}
