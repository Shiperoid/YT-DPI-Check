using System.Collections.ObjectModel;
using Terminal.Gui.App;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using YT_DPI.Core.Config;

namespace YT_DPI.App;

/// <summary>Modal edit of key config fields + save via <see cref="UserConfigSaver"/> (Terminal.Gui v2 controls).</summary>
internal static class ConfigEditDialog
{
    private static readonly string[] TlsChoices = ["Auto", "TLS12", "TLS13"];
    private static readonly string[] ProxyTypes = ["HTTP", "SOCKS5", "AUTO"];

    /// <returns><c>true</c> if config was saved and reloaded into <paramref name="holder"/>.</returns>
    public static bool RunModal(IApplication app, ConfigHolder holder, Label status)
    {
        var cfg = holder.Cfg;
        var dlg = new Dialog
        {
            Title = "Конфиг (фрагмент)",
            Width = Dim.Percent(88),
            Height = Dim.Auto(),
        };

        var y = 0;
        dlg.Add(new Label { Text = "IP-предпочтение:", X = 0, Y = y });
        var ipV4 = new CheckBox { Text = "IPv4", X = 18, Y = y, RadioStyle = true };
        var ipV6 = new CheckBox { Text = "IPv6", X = 28, Y = y, RadioStyle = true };
        ApplyIpPreference(cfg.IpPreference, ipV4, ipV6);
        WireMutuallyExclusiveRadios(ipV4, ipV6);
        dlg.Add(ipV4, ipV6);
        y++;

        dlg.Add(new Label { Text = "Режим TLS:", X = 0, Y = y });
        var tlsDd = new DropDownList
        {
            X = 18,
            Y = y,
            Width = Dim.Fill(2),
            ReadOnly = true,
            Source = new ListWrapper<string>(new ObservableCollection<string>(TlsChoices)),
        };
        tlsDd.Text = NormalizeTlsChoice(cfg.TlsMode);
        dlg.Add(tlsDd);
        y += 2;

        const int proxyFrameHeight = 11;
        var proxyFrame = new FrameView
        {
            Title = "Прокси",
            X = 0,
            Y = y,
            Width = Dim.Fill(2),
            Height = proxyFrameHeight,
        };
        var py = 0;
        var proxyOn = new CheckBox
        {
            Text = "_Включить прокси",
            X = 0,
            Y = py,
            Value = cfg.Proxy.Enabled ? CheckState.Checked : CheckState.UnChecked,
        };
        proxyFrame.Add(proxyOn);
        py++;

        proxyFrame.Add(new Label { Text = "Тип:", X = 0, Y = py });
        var proxyTypeDd = new DropDownList
        {
            X = 8,
            Y = py,
            Width = Dim.Fill(2),
            ReadOnly = true,
            Source = new ListWrapper<string>(new ObservableCollection<string>(ProxyTypes)),
        };
        proxyTypeDd.Text = NormalizeProxyTypeChoice(cfg.Proxy.Type);
        proxyFrame.Add(proxyTypeDd);
        py++;

        proxyFrame.Add(new Label { Text = "Хост:", X = 0, Y = py });
        var hostField = new TextField { Text = cfg.Proxy.Host, X = 8, Y = py, Width = Dim.Fill(2) };
        proxyFrame.Add(hostField);
        py++;

        proxyFrame.Add(new Label { Text = "Порт:", X = 0, Y = py });
        var portField = new TextField
        {
            Text = cfg.Proxy.Port == 0 ? "" : cfg.Proxy.Port.ToString(),
            X = 8,
            Y = py,
            Width = 12,
        };
        proxyFrame.Add(portField);
        py++;

        proxyFrame.Add(new Label { Text = "Пользователь:", X = 0, Y = py });
        var userField = new TextField { Text = cfg.Proxy.User, X = 15, Y = py, Width = Dim.Fill(2) };
        proxyFrame.Add(userField);
        py++;

        proxyFrame.Add(new Label { Text = "Пароль:", X = 0, Y = py });
        var passField = new TextField
        {
            Text = cfg.Proxy.Pass,
            X = 10,
            Y = py,
            Width = Dim.Fill(2),
            Secret = true,
        };
        proxyFrame.Add(passField);

        dlg.Add(proxyFrame);
        y += proxyFrameHeight;

        dlg.Add(new Label { Text = $"SchemaVersion (только чтение): {cfg.SchemaVersion}", X = 0, Y = y });
        y++;

        dlg.Add(new Label
        {
            Text = "Сохранение в JSON как в PowerShell.",
            X = 0,
            Y = y,
            Width = Dim.Fill(2),
            Height = 2,
        });

        dlg.AddButton(new Button { Title = "_Отмена" });
        dlg.AddButton(new Button { Title = "_Сохранить" });

        app.Run(dlg);
        if (dlg.Result != 1)
            return false;

        cfg.IpPreference = ipV4.Value == CheckState.Checked ? "IPv4" : "IPv6";
        cfg.TlsMode = CanonicalTls(tlsDd.Text.ToString());
        cfg.Proxy.Enabled = proxyOn.Value == CheckState.Checked;
        cfg.Proxy.Type = CanonicalProxyType(proxyTypeDd.Text.ToString());
        cfg.Proxy.Host = hostField.Text.ToString()?.Trim() ?? "";
        if (int.TryParse(portField.Text.ToString(), out var pp))
            cfg.Proxy.Port = pp;
        cfg.Proxy.User = userField.Text.ToString() ?? "";
        cfg.Proxy.Pass = passField.Text.ToString() ?? "";

        if (cfg.SchemaVersion < 1)
            cfg.SchemaVersion = 1;

        var (saveOk, saveErr) = UserConfigSaver.TrySaveUserConfig(cfg);
        if (!saveOk)
        {
            status.Text = "Сохранение не удалось: " + saveErr;
            return false;
        }

        status.Text = "Конфиг сохранён.";
        return true;
    }

    private static void ApplyIpPreference(string? pref, CheckBox ipV4, CheckBox ipV6)
    {
        if (string.Equals(pref, "IPv4", StringComparison.OrdinalIgnoreCase))
        {
            ipV4.Value = CheckState.Checked;
            ipV6.Value = CheckState.UnChecked;
        }
        else
        {
            ipV6.Value = CheckState.Checked;
            ipV4.Value = CheckState.UnChecked;
        }
    }

    private static void WireMutuallyExclusiveRadios(CheckBox a, CheckBox b)
    {
        a.ValueChanged += (_, _) => ExclusiveRadioSync(a, b);
        b.ValueChanged += (_, _) => ExclusiveRadioSync(b, a);
    }

    private static void ExclusiveRadioSync(CheckBox changed, CheckBox other)
    {
        if (changed.Value == CheckState.Checked)
        {
            other.Value = CheckState.UnChecked;
            return;
        }

        if (other.Value != CheckState.Checked)
            changed.Value = CheckState.Checked;
    }

    private static string NormalizeTlsChoice(string? raw)
    {
        var s = (raw ?? "Auto").Trim();
        if (s.Equals("TLS12", StringComparison.OrdinalIgnoreCase) || s.Equals("TLS1.2", StringComparison.OrdinalIgnoreCase))
            return "TLS12";
        if (s.Equals("TLS13", StringComparison.OrdinalIgnoreCase) || s.Equals("TLS1.3", StringComparison.OrdinalIgnoreCase))
            return "TLS13";
        return "Auto";
    }

    private static string CanonicalTls(string? displayed) =>
        NormalizeTlsChoice(displayed);

    private static string NormalizeProxyTypeChoice(string? raw)
    {
        var s = (raw ?? "HTTP").Trim();
        if (s.Equals("SOCKS5", StringComparison.OrdinalIgnoreCase) || s.Equals("socks5", StringComparison.Ordinal))
            return "SOCKS5";
        if (s.Equals("AUTO", StringComparison.OrdinalIgnoreCase))
            return "AUTO";
        return "HTTP";
    }

    private static string CanonicalProxyType(string? displayed) =>
        NormalizeProxyTypeChoice(displayed);
}

internal sealed class ConfigHolder
{
    public required YtDpiUserConfig Cfg { get; set; }
}
