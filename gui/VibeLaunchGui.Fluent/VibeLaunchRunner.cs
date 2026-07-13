using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace VibeLaunchGui;

public sealed class VibeLaunchRunner
{
    private readonly string _root;
    private readonly string _scriptPath;

    public VibeLaunchRunner(string root)
    {
        _root = root;
        _scriptPath = Path.Combine(root, "vibelaunch.ps1");
    }

    public static string ResolveVibeLaunchRoot()
    {
        var dir = AppContext.BaseDirectory.TrimEnd('\\', '/');
        while (!string.IsNullOrEmpty(dir))
        {
            if (File.Exists(Path.Combine(dir, "vibelaunch.ps1")))
                return dir;
            var parent = Directory.GetParent(dir)?.FullName;
            if (parent == dir) break;
            dir = parent ?? string.Empty;
        }

        const string installed = @"C:\Program Files\VibeLaunch";
        if (File.Exists(Path.Combine(installed, "vibelaunch.ps1")))
            return installed;

        throw new InvalidOperationException("VibeLaunch root not found.");
    }

    public async Task<RunResult> RunAsync(IEnumerable<string> args, CancellationToken cancellationToken = default)
    {
        var argList = args.ToList();
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = BuildArguments(argList),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        using var proc = new Process { StartInfo = psi };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        proc.OutputDataReceived += (_, e) => { if (e.Data != null) stdout.AppendLine(e.Data); };
        proc.ErrorDataReceived += (_, e) => { if (e.Data != null) stderr.AppendLine(e.Data); };

        proc.Start();
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        await proc.WaitForExitAsync(cancellationToken);

        return new RunResult(proc.ExitCode, stdout.ToString(), stderr.ToString());
    }

    public async Task<T?> RunJsonAsync<T>(IEnumerable<string> args, CancellationToken cancellationToken = default)
    {
        var result = await RunAsync(args, cancellationToken);
        if (result.ExitCode != 0)
            throw new InvalidOperationException(result.Stderr.Trim().Length > 0 ? result.Stderr : result.Stdout);

        var text = result.Stdout.Trim();
        if (text.Length == 0) return default;
        return JsonSerializer.Deserialize<T>(text, JsonOptions);
    }

    private string BuildArguments(IReadOnlyList<string> args)
    {
        var sb = new StringBuilder();
        sb.Append("-NoProfile -ExecutionPolicy Bypass -File \"");
        sb.Append(_scriptPath);
        sb.Append('"');
        foreach (var arg in args)
        {
            sb.Append(' ');
            sb.Append(EscapeArg(arg));
        }
        return sb.ToString();
    }

    private static string EscapeArg(string arg)
    {
        if (arg.Contains('"'))
            return $"\"{arg.Replace("\"", "\\\"")}\"";
        if (arg.Contains(' '))
            return $"\"{arg}\"";
        return arg;
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };
}

public sealed record RunResult(int ExitCode, string Stdout, string Stderr);

public sealed class StatusDto
{
    public string? Profile { get; set; }
    public int Port { get; set; }
    public string? Preset { get; set; }
    public int? Pid { get; set; }
    public bool Listening { get; set; }
    public string[]? BindAddrs { get; set; }
    public string? KeypadUrl { get; set; }
    public string? WebUrl { get; set; }
    public string? SetupUrl { get; set; }
    public KeypadReadinessDto? KeypadReadiness { get; set; }
}

public sealed class KeypadReadinessDto
{
    public string? Level { get; set; }
    public string? Summary { get; set; }
    public bool Listening { get; set; }
    public string? KeypadHost { get; set; }
    public string? KeypadUrl { get; set; }
    public string[]? LocalAddresses { get; set; }
    public bool HostOnThisMachine { get; set; }
    public string[]? Messages { get; set; }
}

public sealed class PathsDto
{
    public string? Root { get; set; }
    public string? ConfigDir { get; set; }
    public string? Presets { get; set; }
    public string? PresetsLocal { get; set; }
    public string? ProfilesDir { get; set; }
    public string? UserDefaults { get; set; }
    public string? UserConfigDir { get; set; }
    public string? PtySizePresets { get; set; }
    public string? PtySizePresetsLocal { get; set; }
    public string? GuiLocal { get; set; }
    public string? State { get; set; }
}

public sealed class GuiConfigDto
{
    public bool HideVibettyConsole { get; set; } = true;
    public int DefaultCols { get; set; } = 35;
    public int DefaultRows { get; set; } = 10;
    public int Cols { get; set; } = 35;
    public int Rows { get; set; } = 10;
    public string? SizePresetLabel { get; set; }
    public string? Theme { get; set; } = "system";
    public List<SizePresetDto>? SizePresets { get; set; }
}

public sealed class SizePresetDto
{
    public string? Label { get; set; }
    public int Cols { get; set; }
    public int Rows { get; set; }
}

public sealed class PresetFileDto : Dictionary<string, PresetDto> { }

public sealed class PresetDto
{
    public string? Label { get; set; }
    public List<string>? Tokens { get; set; }
    public List<string>? Tags { get; set; }
    public List<string>? Spawn { get; set; }
    public string? Cwd { get; set; }
    public string? Notes { get; set; }
}

public sealed class StateDto
{
    public string? Preset { get; set; }
}

public sealed class GuiLinksDto
{
    public string? Github { get; set; }
    public string? Youtube { get; set; }
    public string? Twitter { get; set; }
    public string? BuyMeACoffee { get; set; }
    public string? Linkedin { get; set; }
    public string? VibekeysRemoteDocs { get; set; }
    public string? VibekeysFirmware { get; set; }
    public string? VibekeysConfigurator { get; set; }
    public string? RunbookPath { get; set; }
}
