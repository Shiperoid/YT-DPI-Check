using Terminal.Gui.App;
using Terminal.Gui.Drivers;
using YT_DPI.Core.Config;

namespace YT_DPI.App;

internal static class Program
{
    private static void Main()
    {
        using var app = Application.Create().Init();

        var cfgPath = UserConfigPaths.GetConfigFilePath();
        var (ok, loadedCfg, err) = UserConfigLoader.TryLoadUserConfig();
        var targetsPreview = GetTargetsForRun(loadedCfg);

        var win = PreviewMainShell.CreateAndWire(app, ok, loadedCfg, cfgPath, err, targetsPreview, out var shell);

        app.AddTimeout(TimeSpan.Zero, () =>
        {
            shell.StartInitialScan(targetsPreview);
            return false;
        });

        app.Run(win);
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
        return YT_DPI.Core.Scan.ScanTargetsBuilder.BuildTargetsSubset(cfg, cap);
    }
}
