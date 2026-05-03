using System.Text.Json;
using System.Text.Json.Serialization;

namespace YT_DPI.Core.Config;

/// <summary>Write <c>YT-DPI_config.json</c> compatible with YT-DPI.ps1 Save-Config / ConvertTo-Json (PascalCase, compressed).</summary>
public static class UserConfigSaver
{
    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        PropertyNamingPolicy = null,
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static (bool Ok, string? Error) TrySaveUserConfig(YtDpiUserConfig config, string? pathOverride = null)
    {
        var path = pathOverride ?? UserConfigPaths.GetConfigFilePath();
        try
        {
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                Directory.CreateDirectory(dir);

            var json = JsonSerializer.Serialize(config, WriteOptions);
            File.WriteAllText(path, json, new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            return (true, null);
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }
}
