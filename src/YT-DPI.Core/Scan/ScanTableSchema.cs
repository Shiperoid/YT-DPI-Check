using System.Data;

namespace YT_DPI.Core.Scan;

/// <summary>Column headers matching YT-DPI.ps1 Draw-UI (~2106–2113).</summary>
public static class ScanTableSchema
{
    public const string ColNumber = "#";
    public const string ColTarget = "TARGET DOMAIN";
    public const string ColIp = "IP ADDRESS";
    public const string ColHttp = "HTTP";
    public const string ColT12 = "TLS 1.2";
    public const string ColT13 = "TLS 1.3";
    public const string ColLat = "LAT (ms)";
    public const string ColVerdict = "RESULT";

    public static DataTable CreateTable()
    {
        var dt = new DataTable();
        dt.Columns.Add(ColNumber, typeof(int));
        dt.Columns.Add(ColTarget, typeof(string));
        dt.Columns.Add(ColIp, typeof(string));
        dt.Columns.Add(ColHttp, typeof(string));
        dt.Columns.Add(ColT12, typeof(string));
        dt.Columns.Add(ColT13, typeof(string));
        dt.Columns.Add(ColLat, typeof(string));
        dt.Columns.Add(ColVerdict, typeof(string));
        return dt;
    }

    public static void AppendRow(DataTable dt, ScanRow r)
    {
        dt.Rows.Add(r.Number, r.Target, r.IP, r.HTTP, r.T12, r.T13, r.Lat, r.Verdict);
    }

    public static void FillFromRows(DataTable dt, IReadOnlyList<ScanRow> rows)
    {
        dt.Rows.Clear();
        foreach (var r in rows)
            AppendRow(dt, r);
    }
}
