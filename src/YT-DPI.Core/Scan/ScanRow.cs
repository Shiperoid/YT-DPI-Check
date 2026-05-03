namespace YT_DPI.Core.Scan;

/// <summary>One scan row aligned with YT-DPI.ps1 Draw-UI / New-PlaceholderResultRow.</summary>
public sealed class ScanRow
{
    public int Number { get; init; }
    public string Target { get; init; } = "";
    public string IP { get; init; } = "---";
    public string HTTP { get; init; } = "---";
    public string T12 { get; init; } = "---";
    public string T13 { get; init; } = "---";
    public string Lat { get; init; } = "---";
    public string Verdict { get; init; } = "IDLE";

    public static ScanRow Placeholder(int number, string target) =>
        new()
        {
            Number = number,
            Target = target,
            IP = "---",
            HTTP = "---",
            T12 = "---",
            T13 = "---",
            Lat = "---",
            Verdict = "IDLE",
        };
}
