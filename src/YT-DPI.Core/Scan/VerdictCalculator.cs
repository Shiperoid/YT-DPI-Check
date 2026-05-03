namespace YT_DPI.Core.Scan;

/// <summary>Verdict rules aligned with YT-DPI.ps1 (~4830–4871) for Auto / TLS12-only / TLS13-only.</summary>
public static class VerdictCalculator
{
    public static string Compute(string tlsMode, string http, string t12, string t13)
    {
        var mode = (tlsMode ?? "Auto").Trim();
        var consider13 = !string.Equals(mode, "TLS12", StringComparison.OrdinalIgnoreCase);
        var consider12 = !string.Equals(mode, "TLS13", StringComparison.OrdinalIgnoreCase);

        if (http == "ERR")
            return "IP BLOCK";

        if (!consider13)
        {
            if (t12 == "OK")
                return "AVAILABLE";
            if (t12 == "RST")
                return "DPI RESET";
            if (t12 == "DRP")
                return "DPI BLOCK";
            return "IP BLOCK";
        }

        if (!consider12)
        {
            if (t13 == "OK")
                return "AVAILABLE";
            if (t13 == "RST")
                return "DPI RESET";
            if (t13 == "DRP")
                return "DPI BLOCK";
            return "IP BLOCK";
        }

        var t12Ok = t12 == "OK";
        var t13Ok = t13 == "OK";
        var t12Blocked = t12 is "RST" or "DRP";
        var t13Blocked = t13 is "RST" or "DRP";

        if (t12Ok && t13Ok)
            return "AVAILABLE";
        if (t12Ok || t13Ok)
        {
            if (t12Blocked || t13Blocked)
                return "THROTTLED";
            return "AVAILABLE";
        }

        if (t12 == "RST" || t13 == "RST")
            return "DPI RESET";
        if (t12 == "DRP" || t13 == "DRP")
            return "DPI BLOCK";
        return "IP BLOCK";
    }
}
