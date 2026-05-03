using Terminal.Gui.App;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

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

            var title = new Label
            {
                Text =
                    "YT-DPI — превью TUI (ветка feature/terminal-gui)\n\n"
                    + "Основная поставка: YT-DPI.bat + YT-DPI.ps1\n\n"
                    + "Esc — выход",
                X = Pos.Center(),
                Y = Pos.Center(),
                TextAlignment = Alignment.Center,
            };

            win.Add(title);
            app.Run(win);
        }
    }
}
