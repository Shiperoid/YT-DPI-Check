using System.Data;
using Terminal.Gui.App;
using Terminal.Gui.Drawing;
using Terminal.Gui.Drivers;
using Terminal.Gui.Input;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using YT_DPI.Core.Config;
using YT_DPI.Core.Preview;
using YT_DPI.Core.Scan;

namespace YT_DPI.App;

/// <summary>Main preview window: MenuBar, FrameViews, TableView styles, StatusBar, scan coordination.</summary>
internal sealed class PreviewMainShell
{
    /// <summary>
    /// Read-only <see cref="TextView"/> uses VisualRole ReadOnly → Editable derived from Normal (dimmed fg as bg).
    /// Inherited window schemes can make that unreadable (gray slab). Force plain text colors for summary.
    /// </summary>
    private static readonly Scheme SummaryTextScheme = CreateSummaryTextScheme();

    private static Scheme CreateSummaryTextScheme()
    {
        var plain = new Terminal.Gui.Drawing.Attribute(ColorName16.White, ColorName16.Black);
        return new Scheme(plain)
        {
            Editable = plain,
            ReadOnly = plain,
            Focus = new Terminal.Gui.Drawing.Attribute(ColorName16.Black, ColorName16.White),
        };
    }

    private const int MenuBarHeight = 1;
    private const int SummaryFrameHeight = 8;
    private const int ActivityLabelHeight = 1;
    private const int StatusBarHeight = 1;

    private readonly IApplication _app;
    private readonly PreviewScanUiCoordinator _scanCoord = new();
    private readonly ConfigHolder _holder;
    private readonly string _cfgPath;

    private readonly TextView _summary;
    private readonly TableView _tableView;
    private readonly DataTable _table;
    private readonly Label _activityStatus;
    private readonly Window _window;

    private PreviewMainShell(
        IApplication app,
        bool configOk,
        YtDpiUserConfig cfg,
        string cfgPath,
        string? loadErr,
        IReadOnlyList<string> initialTargets)
    {
        _app = app;
        _cfgPath = cfgPath;
        _holder = new ConfigHolder { Cfg = cfg };

        var summaryText = BuildHeaderSummary(configOk, _holder.Cfg, _cfgPath, loadErr, initialTargets.Count);

        _summary = new TextView
        {
            Text = summaryText,
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
            Multiline = true,
            ReadOnly = true,
        };
        _summary.SetScheme(SummaryTextScheme);

        _table = BuildPlaceholderTable(initialTargets);
        _tableView = new TableView(new DataTableSource(_table))
        {
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
        };

        _tableView.Style ??= new TableStyle();
        _tableView.Style.ShowHorizontalHeaderUnderline = true;
        _tableView.Style.ExpandLastColumn = true;
        _tableView.Style.RowColorGetter = args => ScanTableVerdictSchemes.RowColorGetter(_table, args);

        var frameSummary = new FrameView
        {
            Title = "Конфигурация",
            X = 0,
            Y = MenuBarHeight,
            Width = Dim.Fill(),
            Height = SummaryFrameHeight,
        };
        frameSummary.Add(_summary);

        var frameScan = new FrameView
        {
            Title = "Результаты скана",
            X = 0,
            Y = MenuBarHeight + SummaryFrameHeight,
            Width = Dim.Fill(),
            Height = Dim.Fill() - (MenuBarHeight + SummaryFrameHeight + ActivityLabelHeight + StatusBarHeight),
        };
        frameScan.Add(_tableView);

        _activityStatus = new Label
        {
            Text = "Готово | TLS quick: " + PreviewEngine.TlsQuickLocalTimeout(),
            X = 0,
            Y = Pos.AnchorEnd(ActivityLabelHeight + StatusBarHeight),
            Width = Dim.Fill(),
            Height = ActivityLabelHeight,
        };

        var statusBar = new StatusBar(BuildStatusShortcuts());

        _window = new Window
        {
            Title = "YT-DPI Preview",
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
        };

        var menu = BuildMenuBar();
        _window.Add(menu, frameSummary, frameScan, _activityStatus, statusBar);

        WireKeyboardShortcuts();
    }

    internal static Window CreateAndWire(
        IApplication app,
        bool configOk,
        YtDpiUserConfig cfg,
        string cfgPath,
        string? loadErr,
        IReadOnlyList<string> initialTargets,
        out PreviewMainShell shell)
    {
        shell = new PreviewMainShell(app, configOk, cfg, cfgPath, loadErr, initialTargets);
        return shell._window;
    }

    internal void StartInitialScan(IReadOnlyList<string> targets) =>
        _scanCoord.StartBackgroundScan(_app, _table, _tableView, _activityStatus, _holder.Cfg, targets);

    private MenuBar BuildMenuBar()
    {
        MenuItem[] scanItems =
        {
            new MenuItem("_Пересканировать", new Key(KeyCode.F5), OnRescanRequested),
            new MenuItem("_Отменить скан", new Key(KeyCode.C).WithCtrl, OnCancelScanRequested),
        };

        MenuItem[] configItems =
        {
            new MenuItem("_Править конфиг (F3)", new Key(KeyCode.F3), OnConfigRequested),
        };

        MenuItem[] fileItems =
        {
            new MenuItem("_Выход", "", () => _app.RequestStop()),
        };

        return new MenuBar(
        [
            new MenuBarItem("_Скан", scanItems),
            new MenuBarItem("_Конфиг", configItems),
            new MenuBarItem("_Файл", fileItems),
        ]);
    }

    private IEnumerable<Shortcut> BuildStatusShortcuts()
    {
        yield return new Shortcut(new Key(KeyCode.F5), "Скан", OnRescanRequested, "Пересканировать");
        yield return new Shortcut(new Key(KeyCode.F3), "Конфиг", OnConfigRequested, "Править JSON");
        yield return new Shortcut(new Key(KeyCode.C).WithCtrl, "Стоп", OnCancelScanRequested, "Отменить скан");
        yield return new Shortcut(Key.Empty, "Esc", () => _app.RequestStop(), "Выход");
    }

    private void WireKeyboardShortcuts()
    {
        var cancelScanKey = new Key(KeyCode.C).WithCtrl;
        var rescanKey = new Key(KeyCode.F5);
        var configKey = new Key(KeyCode.F3);

        _app.Keyboard.KeyDown += (_, key) =>
        {
            if (key == cancelScanKey)
            {
                if (_scanCoord.TryCancelScan(_activityStatus))
                    key.Handled = true;
                return;
            }

            if (key == configKey)
            {
                if (_scanCoord.IsScanRunning)
                {
                    _activityStatus.Text = "Остановите скан (Ctrl+C), затем откройте конфиг.";
                    key.Handled = true;
                    return;
                }

                if (ConfigEditDialog.RunModal(_app, _holder, _activityStatus))
                {
                    var (ok2, cfg2, err2) = UserConfigLoader.TryLoadUserConfig();
                    _holder.Cfg = cfg2;
                    var t = GetTargetsForRun(_holder.Cfg);
                    RebuildTablePlaceholders(_table, _tableView, t);
                    _summary.Text = BuildHeaderSummary(ok2, _holder.Cfg, _cfgPath, err2, t.Count);
                    _summary.SetNeedsDraw();
                }

                key.Handled = true;
                return;
            }

            if (key == rescanKey)
            {
                if (_scanCoord.IsScanRunning)
                {
                    _activityStatus.Text = "Скан уже выполняется — подождите или Ctrl+C.";
                    key.Handled = true;
                    return;
                }

                var t = GetTargetsForRun(_holder.Cfg);
                RebuildTablePlaceholders(_table, _tableView, t);
                _scanCoord.StartBackgroundScan(_app, _table, _tableView, _activityStatus, _holder.Cfg, t);
                key.Handled = true;
            }
        };
    }

    private void OnRescanRequested()
    {
        if (_scanCoord.IsScanRunning)
        {
            _activityStatus.Text = "Скан уже выполняется.";
            return;
        }

        var t = GetTargetsForRun(_holder.Cfg);
        RebuildTablePlaceholders(_table, _tableView, t);
        _scanCoord.StartBackgroundScan(_app, _table, _tableView, _activityStatus, _holder.Cfg, t);
    }

    private void OnCancelScanRequested()
    {
        _scanCoord.TryCancelScan(_activityStatus);
    }

    private void OnConfigRequested()
    {
        if (_scanCoord.IsScanRunning)
        {
            _activityStatus.Text = "Остановите скан (Ctrl+C), затем откройте конфиг.";
            return;
        }

        if (!ConfigEditDialog.RunModal(_app, _holder, _activityStatus))
            return;

        var (ok2, cfg2, err2) = UserConfigLoader.TryLoadUserConfig();
        _holder.Cfg = cfg2;
        var t = GetTargetsForRun(_holder.Cfg);
        RebuildTablePlaceholders(_table, _tableView, t);
        _summary.Text = BuildHeaderSummary(ok2, _holder.Cfg, _cfgPath, err2, t.Count);
        _summary.SetNeedsDraw();
    }

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

    private static string BuildHeaderSummary(bool ok, YtDpiUserConfig cfg, string cfgPath, string? err, int targetCount) =>
        $"Файл: {cfgPath}\n"
        + $"Загрузка: {(ok ? "OK" : "ERR")}   SchemaVersion={cfg.SchemaVersion}   IpPreference={cfg.IpPreference}   TlsMode={cfg.TlsMode}\n"
        + $"Proxy: {(cfg.Proxy.Enabled ? "ON" : "OFF")} ({cfg.Proxy.Type})   CDN: {cfg.NetCache.CDN}\n"
        + $"Целей в скане: {targetCount}"
        + (err is null ? "" : $"\nПримечание: {err}")
        + "\n\nПодсказка: меню сверху, F5 / F3 / Ctrl+C — как в статус-строке. YT_DPI_PREVIEW_MAX_TARGETS=N — ограничить число целей.";

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
