using System.Data;
using Terminal.Gui.Drawing;
using Terminal.Gui.Views;
using YT_DPI.Core.Scan;

namespace YT_DPI.App;

/// <summary>Row coloring for <see cref="TableView"/> by RESULT column (verdict strings from PS/Core).</summary>
internal static class ScanTableVerdictSchemes
{
    private static readonly Lazy<Scheme> Available = new(() =>
        new Scheme(new Terminal.Gui.Drawing.Attribute(ColorName16.Green, ColorName16.Black)));

    private static readonly Lazy<Scheme> BlockOrReset = new(() =>
        new Scheme(new Terminal.Gui.Drawing.Attribute(ColorName16.BrightRed, ColorName16.Black)));

    private static readonly Lazy<Scheme> Warning = new(() =>
        new Scheme(new Terminal.Gui.Drawing.Attribute(ColorName16.BrightYellow, ColorName16.Black)));

    internal static Scheme? RowColorGetter(DataTable table, RowColorGetterArgs args)
    {
        if (table is null || args.RowIndex < 0 || args.RowIndex >= table.Rows.Count)
            return null;

        if (!table.Columns.Contains(ScanTableSchema.ColVerdict))
            return null;

        var verdict = table.Rows[args.RowIndex][ScanTableSchema.ColVerdict]?.ToString()?.Trim() ?? "";
        if (string.IsNullOrEmpty(verdict) || verdict == "---")
            return null;

        if (verdict.Contains("AVAILABLE", StringComparison.OrdinalIgnoreCase))
            return Available.Value;

        if (verdict.Contains("THROTTLED", StringComparison.OrdinalIgnoreCase)
            || verdict.Contains("PARTIAL", StringComparison.OrdinalIgnoreCase))
            return Warning.Value;

        if (verdict.Contains("BLOCK", StringComparison.OrdinalIgnoreCase)
            || verdict.Contains("RESET", StringComparison.OrdinalIgnoreCase)
            || verdict.Contains("IP BLOCK", StringComparison.OrdinalIgnoreCase))
            return BlockOrReset.Value;

        return null;
    }
}
