using YT_DPI.Core.Scan;

namespace YT_DPI.Core.Tests;

public class VerdictCalculatorTests
{
    [Fact]
    public void Http_err_is_ip_block()
    {
        Assert.Equal("IP BLOCK", VerdictCalculator.Compute("Auto", "ERR", "OK", "OK"));
    }

    [Fact]
    public void Both_tls_ok_is_available()
    {
        Assert.Equal("AVAILABLE", VerdictCalculator.Compute("Auto", "OK", "OK", "OK"));
    }

    [Fact]
    public void One_ok_one_blocked_is_throttled()
    {
        Assert.Equal("THROTTLED", VerdictCalculator.Compute("Auto", "OK", "OK", "DRP"));
        Assert.Equal("THROTTLED", VerdictCalculator.Compute("Auto", "OK", "DRP", "OK"));
    }

    [Fact]
    public void Tls12_only_uses_t12()
    {
        Assert.Equal("AVAILABLE", VerdictCalculator.Compute("TLS12", "OK", "OK", "DRP"));
        Assert.Equal("DPI BLOCK", VerdictCalculator.Compute("TLS12", "OK", "DRP", "DRP"));
    }

    [Fact]
    public void Tls13_only_uses_t13()
    {
        Assert.Equal("AVAILABLE", VerdictCalculator.Compute("TLS13", "OK", "DRP", "OK"));
    }
}
