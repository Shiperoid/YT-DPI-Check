namespace YT_DPI.Core.Config;

public static class UserConfigPaths
{
    public const string ConfigDirName = "YT-DPI";
    public const string ConfigFileName = "YT-DPI_config.json";

    /// <summary>Same as Join-Path $env:LOCALAPPDATA "YT-DPI" in YT-DPI.ps1.</summary>
    public static string GetConfigDirectory()
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), ConfigDirName);

    public static string GetConfigFilePath()
        => Path.Combine(GetConfigDirectory(), ConfigFileName);
}
