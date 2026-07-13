using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;

using VibeLaunchGui;

namespace VibeLaunchGui.Fluent;

public partial class MainWindow : Wpf.Ui.Controls.FluentWindow
{
    private readonly string _root;
    private readonly VibeLaunchRunner _runner;
    private string _presetsPath;
    private string _presetsLocalPath;
    private readonly string _statePath;

    private Dictionary<string, PresetDto> _presets = new();
    private GuiConfigDto _guiConfig = new();
    private GuiLinksDto _guiLinks = new();
    private PathsDto _paths = new();
    private StatusDto? _status;
    private bool _suppressSizeEvents;
    private bool _webViewReady;
    private CoreWebView2Environment? _webViewEnvironment;
    private bool _launchInProgress;
    private bool _forcePreviewReload;
    private string? _lastPresetName;
    private string? _previewUrl;

    // vibetty web UI uses xterm FitAddon to fill the browser; that stretches a
    // small PTY (e.g. 40x12) across the WebView and scrambles the layout.
    // Lock cols/rows to the launched geometry and center a fixed-size terminal.
    private static string BuildEmbedChromeScript(int cols, int rows)
    {
        if (cols < 20) cols = 35;
        if (rows < 5) rows = 10;
        return $$"""
        (function() {
          const COLS = {{cols}};
          const ROWS = {{rows}};

          let style = document.getElementById('vibelaunch-embed-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'vibelaunch-embed-style';
            document.head.appendChild(style);
          }
          style.textContent = `
            header, footer, nav, .navbar { display: none !important; }
            body { overflow: hidden !important; background: #1e1e1e !important; }
            .container, body > div { padding: 0 !important; margin: 0 !important; max-width: none !important; height: 100vh !important; }
            #terminal {
              width: fit-content !important;
              max-width: 100% !important;
              height: fit-content !important;
              margin: 12px auto !important;
              overflow: hidden !important;
            }
            .xterm, .xterm-viewport, .xterm-screen { width: auto !important; }
            button { visibility: hidden !important; }
            [role="toolbar"] { display: none !important; }
            .badge, #connection-status, [class*="Connected"], [class*="connected"] {
              visibility: visible !important;
            }
          `;

          document.querySelectorAll('button').forEach(b => {
            const t = (b.textContent || '').toLowerCase();
            if (t.includes('interrupt') || t.includes('ctrl')) {
              b.style.visibility = 'visible';
              return;
            }
            const r = b.getBoundingClientRect();
            if (r.top < 100 || r.bottom > window.innerHeight - 80) {
              b.style.display = 'none';
            }
          });

          function lockSize() {
            const wt = window.webTerminal;
            const term = (wt && wt.terminal) || window.terminal;
            if (!term || typeof term.resize !== 'function') return false;
            try {
              if (wt && wt.fitAddon) {
                wt.fitAddon.fit = function() { /* disabled for embed */ };
              }
              if (term.cols !== COLS || term.rows !== ROWS) {
                term.resize(COLS, ROWS);
              }
              const el = document.getElementById('terminal');
              if (el) {
                el.style.width = 'fit-content';
                el.style.marginLeft = 'auto';
                el.style.marginRight = 'auto';
              }
              return true;
            } catch (e) { return false; }
          }

          if (!lockSize()) {
            let n = 0;
            const t = setInterval(() => {
              if (lockSize() || ++n > 40) clearInterval(t);
            }, 100);
          }
        })();
        """;
    }

    private string CurrentEmbedScript() =>
        BuildEmbedChromeScript((int)ColsSlider.Value, (int)RowsSlider.Value);

    public MainWindow()
    {
        InitializeComponent();
        _root = VibeLaunchRunner.ResolveVibeLaunchRoot();
        _runner = new VibeLaunchRunner(_root);
        _presetsPath = Path.Combine(_root, "config", "presets.json");
        _presetsLocalPath = Path.Combine(_root, "config", "presets.local.json");
        _statePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VibeLaunch", "state.json");

        Loaded += MainWindow_Loaded;
        ContentRendered += MainWindow_ContentRendered;
    }

    private Task? _webViewInitTask;

    private async void MainWindow_ContentRendered(object? sender, EventArgs e)
    {
        ContentRendered -= MainWindow_ContentRendered;
        await InitWebViewAsync();
        if (_status?.Listening == true && !string.IsNullOrWhiteSpace(_status.WebUrl))
            await NavigatePreviewAsync(_status.WebUrl, force: _forcePreviewReload);
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        FluentThemeHelper.Apply(FluentThemeHelper.System, this);
        BuildMenus();
        await ReloadAllAsync();
    }

    private Task InitWebViewAsync() => _webViewInitTask ??= InitWebViewCoreAsync();

    private async Task InitWebViewCoreAsync()
    {
        if (_webViewReady) return;
        try
        {
            await TerminalWebView.EnsureCoreWebView2Async();
            _webViewReady = true;
            _webViewEnvironment = TerminalWebView.CoreWebView2?.Environment;
            var core = TerminalWebView.CoreWebView2;
            if (core == null) throw new InvalidOperationException("WebView2 core unavailable");
            core.Settings.AreDevToolsEnabled = false;

            core.PermissionRequested += (_, args) =>
            {
                if (args.PermissionKind is CoreWebView2PermissionKind.Microphone
                    or CoreWebView2PermissionKind.Camera)
                {
                    args.State = CoreWebView2PermissionState.Deny;
                }
            };

            core.NewWindowRequested += (_, args) =>
            {
                args.Handled = true;
                var uri = args.Uri ?? "";
                if (uri.StartsWith("http://localhost", StringComparison.OrdinalIgnoreCase)
                    || uri.StartsWith("http://127.0.0.1", StringComparison.OrdinalIgnoreCase))
                {
                    core.Navigate(uri);
                }
            };

            core.NavigationCompleted += async (_, _) =>
            {
                if (!_webViewReady) return;
                try
                {
                    await core.ExecuteScriptAsync(CurrentEmbedScript());
                }
                catch { /* upstream DOM may change */ }
            };
        }
        catch (Exception ex)
        {
            AppendOutput($"WebView2 init failed: {ex.Message}\nInstall WebView2 Runtime if missing.");
            PreviewPlaceholder.Text = "WebView2 unavailable — use Open in browser from WinForms fallback.";
        }
    }

    private void BuildMenus()
    {
        MainMenu.Items.Clear();

        var hardware = new System.Windows.Controls.MenuItem { Header = "VibeKeys Hardware" };
        hardware.Items.Add(MakeMenuItem("Keypad setup (/setup)", () => OpenSetupUrl()));
        hardware.Items.Add(MakeMenuItem("Remote mode docs", () => OpenUrl(_guiLinks.VibekeysRemoteDocs)));
        hardware.Items.Add(MakeMenuItem("Firmware update instructions", () => OpenUrl(_guiLinks.VibekeysFirmware)));
        hardware.Items.Add(MakeMenuItem("Open VibeKeys folder", () => OpenFolder(_guiLinks.VibekeysConfigurator),
            string.IsNullOrWhiteSpace(_guiLinks.VibekeysConfigurator) || !Directory.Exists(_guiLinks.VibekeysConfigurator)));
        MainMenu.Items.Add(hardware);

        var settings = new System.Windows.Controls.MenuItem { Header = "Settings" };
        settings.Items.Add(MakeMenuItem("Open VibeLaunch folder", () => OpenFolder(_paths.Root)));
        settings.Items.Add(MakeMenuItem("Open presets folder", () => OpenFolder(_paths.ConfigDir)));
        settings.Items.Add(MakeMenuItem("Open user config folder", () => OpenFolder(_paths.UserConfigDir)));
        settings.Items.Add(MakeMenuItem("Profile help", () => ShowProfileHelp()));
        settings.Items.Add(MakeMenuItem("PTY size presets help", () => ShowPtySizePresetsHelp()));
        settings.Items.Add(MakeMenuItem("Keypad scrollback help", () => ShowKeypadScrollbackHelp()));
        settings.Items.Add(MakeMenuItem("PTY defaults summary", () => ShowPtyDefaults()));

        var themeMenu = new System.Windows.Controls.MenuItem { Header = "Theme" };
        themeMenu.Items.Add(MakeMenuItem("Light", () => _ = SaveThemeAsync(FluentThemeHelper.Light)));
        themeMenu.Items.Add(MakeMenuItem("Dark", () => _ = SaveThemeAsync(FluentThemeHelper.Dark)));
        themeMenu.Items.Add(MakeMenuItem("Follow system", () => _ = SaveThemeAsync(FluentThemeHelper.System)));
        settings.Items.Add(themeMenu);

        MainMenu.Items.Add(settings);

        var connect = new System.Windows.Controls.MenuItem { Header = "Connect" };
        connect.Items.Add(MakeMenuItem("GitHub", () => OpenUrl(_guiLinks.Github), string.IsNullOrWhiteSpace(_guiLinks.Github)));
        connect.Items.Add(MakeMenuItem("YouTube", () => OpenUrl(_guiLinks.Youtube), string.IsNullOrWhiteSpace(_guiLinks.Youtube)));
        connect.Items.Add(MakeMenuItem("X (Twitter)", () => OpenUrl(_guiLinks.Twitter), string.IsNullOrWhiteSpace(_guiLinks.Twitter)));
        connect.Items.Add(MakeMenuItem("Buy Me a Coffee", () => OpenUrl(_guiLinks.BuyMeACoffee), string.IsNullOrWhiteSpace(_guiLinks.BuyMeACoffee)));
        connect.Items.Add(MakeMenuItem("LinkedIn", () => OpenUrl(_guiLinks.Linkedin), string.IsNullOrWhiteSpace(_guiLinks.Linkedin)));
        MainMenu.Items.Add(connect);

        var help = new System.Windows.Controls.MenuItem { Header = "Help" };
        help.Items.Add(MakeMenuItem("Open runbook", OpenRunbookInAppAsync));
        help.Items.Add(MakeMenuItem("Open runbook in browser", OpenRunbookInBrowserAsync));
        help.Items.Add(MakeMenuItem("About VibeLaunch", () => ShowAbout()));
        MainMenu.Items.Add(help);
    }

    private static System.Windows.Controls.MenuItem MakeMenuItem(string header, Action action, bool disabled = false)
    {
        var item = new System.Windows.Controls.MenuItem { Header = header, IsEnabled = !disabled };
        item.Click += (_, _) => action();
        return item;
    }

    private static System.Windows.Controls.MenuItem MakeMenuItem(string header, Func<Task> action, bool disabled = false)
    {
        var item = new System.Windows.Controls.MenuItem { Header = header, IsEnabled = !disabled };
        item.Click += async (_, _) =>
        {
            try { await action(); }
            catch (Exception ex) { MessageBox.Show(ex.Message, header, MessageBoxButton.OK, MessageBoxImage.Error); }
        };
        return item;
    }

    private async Task ReloadAllAsync()
    {
        LoadPresetsFromDisk();
        _paths = await _runner.RunJsonAsync<PathsDto>(new[] { "paths", "--json" }) ?? new PathsDto();
        if (!string.IsNullOrWhiteSpace(_paths.Presets))
            _presetsPath = _paths.Presets;
        if (!string.IsNullOrWhiteSpace(_paths.PresetsLocal))
            _presetsLocalPath = _paths.PresetsLocal;
        _guiConfig = await _runner.RunJsonAsync<GuiConfigDto>(new[] { "gui-config" }) ?? new GuiConfigDto();
        _guiLinks = await _runner.RunJsonAsync<GuiLinksDto>(new[] { "gui-links" }) ?? new GuiLinksDto();
        FluentThemeHelper.Apply(_guiConfig.Theme ?? FluentThemeHelper.System, this);
        BuildMenus();
        ApplyGuiConfigToControls();
        RefreshPresetList();
        await RefreshStatusAsync(navigate: !_launchInProgress);
        SelectLastPreset();
    }

    private void LoadPresetsFromDisk()
    {
        _presets = new Dictionary<string, PresetDto>();
        MergePresetFile(_presetsPath);
        MergePresetFile(_presetsLocalPath);
    }

    private void MergePresetFile(string path)
    {
        if (!File.Exists(path)) return;
        var json = File.ReadAllText(path);
        var doc = JsonSerializer.Deserialize<Dictionary<string, PresetDto>>(json, JsonOpts());
        if (doc == null) return;
        foreach (var kv in doc)
            _presets[kv.Key] = kv.Value;
    }

    private void ApplyGuiConfigToControls()
    {
        _suppressSizeEvents = true;
        SizePresetBox.Items.Clear();
        foreach (var preset in _guiConfig.SizePresets ?? new List<SizePresetDto>())
            SizePresetBox.Items.Add(preset);
        SizePresetBox.DisplayMemberPath = "Label";

        ColsSlider.Value = _guiConfig.Cols > 0 ? _guiConfig.Cols : 35;
        RowsSlider.Value = _guiConfig.Rows > 0 ? _guiConfig.Rows : 200;
        HideConsoleBox.IsChecked = _guiConfig.HideVibettyConsole;
        UpdateSizeLabels();

        var label = _guiConfig.SizePresetLabel;
        if (!string.IsNullOrWhiteSpace(label))
        {
            foreach (SizePresetDto item in SizePresetBox.Items)
            {
                if (item.Label == label)
                {
                    SizePresetBox.SelectedItem = item;
                    break;
                }
            }
        }
        if (SizePresetBox.SelectedItem == null && SizePresetBox.Items.Count > 0)
            SizePresetBox.SelectedIndex = 0;

        _suppressSizeEvents = false;
    }

    private void RefreshPresetList()
    {
        var filter = TagFilterBox.SelectedItem as string;
        var items = _presets
            .OrderBy(p => p.Key)
            .Where(p => filter == null || filter == "(all)" || (p.Value.Tags?.Contains(filter) ?? false))
            .Select(p => new PresetListItem(p.Key, p.Value))
            .ToList();

        PresetList.ItemsSource = items;
    }

    private void SelectLastPreset()
    {
        string? last = null;
        if (File.Exists(_statePath))
        {
            try
            {
                var state = JsonSerializer.Deserialize<StateDto>(File.ReadAllText(_statePath), JsonOpts());
                last = state?.Preset;
            }
            catch { /* ignore */ }
        }

        if (string.IsNullOrWhiteSpace(last)) return;
        foreach (PresetListItem item in PresetList.Items)
        {
            if (item.Name == last)
            {
                PresetList.SelectedItem = item;
                break;
            }
        }
    }

    private void ShowPresetDetails(string name)
    {
        if (!_presets.TryGetValue(name, out var preset)) return;
        _lastPresetName = name;
        PresetTitleText.Text = $"{name} — {preset.Label}";
        SpawnBox.Text = preset.Spawn != null ? string.Join(" ", preset.Spawn) : "";
        NotesBox.Text = preset.Notes ?? "";
    }

    private async Task RefreshStatusAsync(bool navigate = true)
    {
        try
        {
            _status = await _runner.RunJsonAsync<StatusDto>(new[] { "status", "--json" });
            UpdateStatusBar();
            if (!navigate || _launchInProgress) return;

            if (_status?.Listening == true && !string.IsNullOrWhiteSpace(_status.WebUrl))
            {
                if (_forcePreviewReload || !string.Equals(_previewUrl, _status.WebUrl, StringComparison.OrdinalIgnoreCase))
                    await NavigatePreviewAsync(_status.WebUrl, force: _forcePreviewReload);
                _forcePreviewReload = false;
            }
            else if (!_launchInProgress)
            {
                ShowPreviewPlaceholder();
            }
        }
        catch (Exception ex)
        {
            StatusBarText.Text = $"Status error: {ex.Message}";
        }
    }

    private void UpdateStatusBar()
    {
        if (_status == null)
        {
            StatusBarText.Text = "No status";
            return;
        }

        var bind = _status.BindAddrs is { Length: > 0 } ? string.Join(", ", _status.BindAddrs) : "not listening";
        var geom = $"{(int)ColsSlider.Value}x{(int)RowsSlider.Value}";
        var keypad = _status.KeypadReadiness?.Summary ?? (_status.Listening ? "ready" : "no session");
        StatusBarText.Text =
            $"profile: {_status.Profile}  |  port: {_status.Port}  |  preset: {_status.Preset ?? "-"}  |  pid: {_status.Pid?.ToString() ?? "-"}  |  geom: {geom}  |  keypad: {keypad}  |  bind: {bind}  |  {_status.KeypadUrl}";
    }

    private async Task NavigatePreviewAsync(string url, bool force = false)
    {
        if (!_webViewReady)
        {
            await InitWebViewAsync();
            if (!_webViewReady) return;
        }

        PreviewPlaceholder.Visibility = Visibility.Collapsed;
        TerminalWebView.Visibility = Visibility.Visible;

        var core = TerminalWebView.CoreWebView2;
        var current = core?.Source ?? TerminalWebView.Source?.AbsoluteUri;
        if (!force && string.Equals(current, url, StringComparison.OrdinalIgnoreCase))
            return;

        if (core != null)
        {
            core.Navigate(url);
            try { await core.ExecuteScriptAsync(CurrentEmbedScript()); } catch { /* page may still be loading */ }
        }
        else
            TerminalWebView.Source = new Uri(url);

        _previewUrl = url;
        await Task.CompletedTask;
    }

    private void ShowPreviewPlaceholder(string? message = null)
    {
        PreviewPlaceholder.Text = message ?? "Launch a preset to show the vibetty terminal preview.";
        PreviewPlaceholder.Visibility = Visibility.Visible;
        TerminalWebView.Visibility = Visibility.Collapsed;
        if (_webViewReady)
        {
            try { TerminalWebView.CoreWebView2.Navigate("about:blank"); } catch { /* ignore */ }
        }
        _previewUrl = null;
    }

    private async Task SaveThemeAsync(string theme)
    {
        var label = (SizePresetBox.SelectedItem as SizePresetDto)?.Label ?? "Custom";
        var hide = HideConsoleBox.IsChecked == true;
        await _runner.RunAsync(new[]
        {
            "gui-save",
            "--cols", ((int)ColsSlider.Value).ToString(),
            "--rows", ((int)RowsSlider.Value).ToString(),
            "--label", label,
            "--theme", theme,
            hide ? "--hide-console" : "--show-console",
        });
        _guiConfig.Theme = theme;
        FluentThemeHelper.Apply(theme, this);
        BuildMenus();
        UpdateStatusBar();
    }

    private async Task SaveGuiSettingsAsync()
    {
        var label = (SizePresetBox.SelectedItem as SizePresetDto)?.Label ?? "Custom";
        var hide = HideConsoleBox.IsChecked == true;
        var cols = (int)ColsSlider.Value;
        var rows = (int)RowsSlider.Value;
        await _runner.RunAsync(new[]
        {
            "gui-save",
            "--cols", cols.ToString(),
            "--rows", rows.ToString(),
            "--label", label,
            hide ? "--hide-console" : "--show-console",
        });
        UpdateStatusBar();
    }

    private async Task RunCommandAsync(string heading, IEnumerable<string> args)
    {
        try
        {
            AppendOutput($"> {heading}");
            var result = await _runner.RunAsync(args);
            if (!string.IsNullOrWhiteSpace(result.Stdout))
                AppendOutput(result.Stdout.TrimEnd());
            if (!string.IsNullOrWhiteSpace(result.Stderr))
                AppendOutput(result.Stderr.TrimEnd());
            AppendOutput($"(exit {result.ExitCode})");
        }
        catch (Exception ex)
        {
            AppendOutput($"ERROR: {ex.Message}");
        }
    }

    private void AppendOutput(string text)
    {
        OutputBox.AppendText(text + Environment.NewLine);
        OutputBox.ScrollToEnd();
    }

    private string? SelectedPresetName()
    {
        return (PresetList.SelectedItem as PresetListItem)?.Name ?? _lastPresetName;
    }

    private async Task LaunchSelectedAsync()
    {
        var name = SelectedPresetName();
        if (string.IsNullOrWhiteSpace(name))
        {
            MessageBox.Show("Select a preset first.");
            return;
        }

        _launchInProgress = true;
        ShowPreviewPlaceholder("Starting session…");

        try
        {
            await SaveGuiSettingsAsync();

            var hideFlag = HideConsoleBox.IsChecked == true ? "--hide-console" : "--show-console";
            await RunCommandAsync($"launch {name}", new[]
            {
                name, "--force", "--gui",
                "--cols", ((int)ColsSlider.Value).ToString(),
                "--rows", ((int)RowsSlider.Value).ToString(),
                hideFlag,
            });

            var webUrl = await WaitForListenerAsync();
            if (!string.IsNullOrWhiteSpace(webUrl))
            {
                _status = await _runner.RunJsonAsync<StatusDto>(new[] { "status", "--json" });
                UpdateStatusBar();
                await NavigatePreviewAsync(webUrl, force: true);
            }
        }
        finally
        {
            _launchInProgress = false;
        }
    }

    private async Task<string?> WaitForListenerAsync()
    {
        for (var i = 0; i < 20; i++)
        {
            await Task.Delay(500);
            var status = await _runner.RunJsonAsync<StatusDto>(new[] { "status", "--json" });
            if (status?.Listening == true && !string.IsNullOrWhiteSpace(status.WebUrl))
                return status.WebUrl;
        }
        return null;
    }

    private void UpdateSizeLabels()
    {
        if (ColsValueText == null || RowsValueText == null) return;
        ColsValueText.Text = ((int)ColsSlider.Value).ToString();
        RowsValueText.Text = ((int)RowsSlider.Value).ToString();
        UpdateStatusBar();
    }

    private static JsonSerializerOptions JsonOpts() => new() { PropertyNameCaseInsensitive = true };

    private void PresetList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var name = SelectedPresetName();
        if (name != null) ShowPresetDetails(name);
    }

    private async void PresetList_MouseDoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        await LaunchSelectedAsync();
    }

    private void TagFilterBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded) return;
        RefreshPresetList();
    }

    private void SizePresetBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSizeEvents) return;
        if (SizePresetBox.SelectedItem is not SizePresetDto preset) return;
        _suppressSizeEvents = true;
        ColsSlider.Value = preset.Cols;
        RowsSlider.Value = preset.Rows;
        UpdateSizeLabels();
        _suppressSizeEvents = false;
    }

    private void SizeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_suppressSizeEvents || !IsLoaded) return;
        UpdateSizeLabels();
        SizePresetBox.SelectedItem = null;
    }

    private async void HideConsoleBox_Changed(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded) return;
        await SaveGuiSettingsAsync();
    }

    private async void LaunchBtn_Click(object sender, RoutedEventArgs e) => await LaunchSelectedAsync();

    private async void StopBtn_Click(object sender, RoutedEventArgs e)
    {
        ShowPreviewPlaceholder("Stopping session…");
        await RunCommandAsync("stop", new[] { "stop", "--force" });
        await RefreshStatusAsync(navigate: false);
    }

    private async void PreflightBtn_Click(object sender, RoutedEventArgs e)
    {
        await RunCommandAsync("preflight", new[] { "preflight" });
    }

    private async void RefreshStatusBtn_Click(object sender, RoutedEventArgs e)
    {
        _forcePreviewReload = true;
        _guiConfig = await _runner.RunJsonAsync<GuiConfigDto>(new[] { "gui-config" }) ?? _guiConfig;
        ApplyGuiConfigToControls();
        await RefreshStatusAsync(navigate: true);
    }

    private void CopyUrlBtn_Click(object sender, RoutedEventArgs e)
    {
        var url = _status?.KeypadUrl;
        if (string.IsNullOrWhiteSpace(url))
        {
            MessageBox.Show("No keypad URL — launch a preset first.");
            return;
        }

        var readiness = _status?.KeypadReadiness;
        if (readiness is { HostOnThisMachine: false })
        {
            var msg = string.Join("\n", readiness.Messages ?? Array.Empty<string>());
            var result = MessageBox.Show(
                $"The configured keypadHost may not match this PC.\n\n{msg}\n\nCopy URL anyway?",
                "Keypad host warning",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (result != MessageBoxResult.Yes) return;
        }

        Clipboard.SetText(url);
        AppendOutput($"Copied keypad URL: {url}");
    }

    private void SetupBtn_Click(object sender, RoutedEventArgs e) => OpenSetupUrl();

    private void OpenSetupUrl()
    {
        if (_status?.Listening != true)
        {
            var port = _status?.Port.ToString() ?? "?";
            var result = MessageBox.Show(
                $"Setup needs vibetty running on port {port}.\n\nLaunch a preset first, then open /setup in your browser.",
                "No active session",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Information);
            if (result == MessageBoxResult.OK && !string.IsNullOrWhiteSpace(_guiLinks.VibekeysRemoteDocs))
                OpenUrl(_guiLinks.VibekeysRemoteDocs);
            return;
        }

        var url = _status.SetupUrl;
        if (string.IsNullOrWhiteSpace(url))
            url = $"http://localhost:{_status.Port}/setup";
        OpenUrl(url);
    }

    private void OpenUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            MessageBox.Show("Link not configured. Add gui-links.local.json under %LOCALAPPDATA%\\VibeLaunch\\");
            return;
        }
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private static void OpenFolder(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
        {
            MessageBox.Show($"Folder not found: {path ?? "(null)"}");
            return;
        }
        Process.Start(new ProcessStartInfo("explorer.exe", path) { UseShellExecute = true });
    }

    private string? ResolveRunbookPath()
    {
        var path = _guiLinks.RunbookPath;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            var fallback = Path.Combine(_paths.Root ?? _root, "docs", "VIBEKEYS_REMOTE.md");
            if (File.Exists(fallback))
                path = Path.GetFullPath(fallback);
        }
        return path is { Length: > 0 } p && File.Exists(p) ? p : null;
    }

    private async Task OpenRunbookInAppAsync()
    {
        var path = ResolveRunbookPath();
        if (path == null)
        {
            MessageBox.Show(
                "Runbook not found relative to your VibeLaunch install.\n\nExpected: docs/VIBEKEYS_REMOTE.md",
                "Runbook",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var dark = FluentThemeHelper.IsDark(_guiConfig.Theme ?? FluentThemeHelper.System);
        try
        {
            var win = new HelpWindow(path, "VIBEKEYS_REMOTE", _webViewEnvironment, dark) { Owner = this };
            win.Show();
            win.Activate();
        }
        catch (Exception ex)
        {
            var openBrowser = MessageBox.Show(
                $"Could not open in-app help: {ex.Message}\n\nOpen in your default browser instead?",
                "Runbook",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);
            if (openBrowser == MessageBoxResult.Yes)
                await OpenRunbookInBrowserAsync();
        }

        await Task.CompletedTask;
    }

    private Task OpenRunbookInBrowserAsync()
    {
        var path = ResolveRunbookPath();
        if (path == null)
        {
            MessageBox.Show(
                "Runbook not found relative to your VibeLaunch install.\n\nExpected: docs/VIBEKEYS_REMOTE.md",
                "Runbook",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return Task.CompletedTask;
        }

        var dark = FluentThemeHelper.IsDark(_guiConfig.Theme ?? FluentThemeHelper.System);
        var htmlPath = HelpContentRenderer.OpenMarkdownInDefaultBrowser(path, "VIBEKEYS_REMOTE", dark);
        AppendOutput($"Opened runbook in browser: {htmlPath}");
        return Task.CompletedTask;
    }

    private void ShowProfileHelp()
    {
        var profile = _status?.Profile ?? "standalone";
        var port = _status?.Port.ToString() ?? "?";
        var keypadHost = _status?.KeypadReadiness?.KeypadHost ?? "?";
        var wsl = string.Equals(profile, "wsl-remote", StringComparison.OrdinalIgnoreCase);

        var body = profile switch
        {
            "wsl-remote" =>
                "Profile: wsl-remote (example split-stack setup)\n\n" +
                "1. Run setup-wsl-remote.ps1 from the VibeLaunch folder, or\n" +
                "2. Copy config/defaults.local.json.example to\n" +
                "   %LOCALAPPDATA%\\VibeLaunch\\defaults.local.json\n\n" +
                $"Current port: {port}\n" +
                $"keypadHost: {keypadHost}\n" +
                "WSL enabled for Hermes/OpenClaw presets.",
            _ =>
                "Profile: standalone (default)\n\n" +
                "1. Copy config/defaults.local.json.example to\n" +
                "   %LOCALAPPDATA%\\VibeLaunch\\defaults.local.json\n" +
                "2. Set keypadHost to your PC's LAN IP if using VibeKeys over Wi-Fi.\n\n" +
                $"Current port: {port}\n" +
                $"keypadHost: {keypadHost}\n" +
                (wsl ? "WSL: enabled\n" : "WSL: disabled\n") +
                "\nSee VibeKeys remote mode docs for keypad setup."
        };

        MessageBox.Show(body, "Profile help", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void ShowPtySizePresetsHelp()
    {
        MessageBox.Show(
            "PTY size presets are loaded from JSON files:\n\n" +
            $"Shipped:  {_paths.PtySizePresets}\n" +
            $"Override: {_paths.PtySizePresetsLocal}\n\n" +
            "Copy config/pty-size-presets.local.json.example to the override path.\n" +
            "Each entry: { \"label\": \"...\", \"cols\": N, \"rows\": N }\n\n" +
            "Default shipped preset: VibeKeys (35x200) — 35 cols, 200 rows.\n" +
            "See Settings → Keypad scrollback help for why cols vs rows matters.\n\n" +
            "Click Refresh after editing. Sliders apply on next Launch and affect\n" +
            "the VibeKeys display + embedded preview.",
            "PTY size presets",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ShowKeypadScrollbackHelp()
    {
        MessageBox.Show(
            GuiHelpText.KeypadScrollbackBody,
            GuiHelpText.KeypadScrollbackTitle,
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ShowPtyDefaults()
    {
        MessageBox.Show(
            $"PTY defaults (applied on Launch):\n\n" +
            $"Cols: {(int)ColsSlider.Value}\n" +
            $"Rows: {(int)RowsSlider.Value}\n" +
            $"Hide vibetty console: {HideConsoleBox.IsChecked == true}\n\n" +
            "Cols ≈35 for OLED legibility. Rows = scroll depth (default 200).\n" +
            "Slider changes take effect on the next Launch (not live).\n" +
            "Affects the VibeKeys display + embedded preview.\n\n" +
            "Settings → Keypad scrollback help for the full explanation.",
            "PTY defaults",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ShowAbout()
    {
        MessageBox.Show(
            "VibeLaunch — VibeKeys session manager\n\n" +
            "Embedded preview is display-only. Voice uses the VibeKeys keypad +\n" +
            "the vibetty server's configured ASR provider (e.g. Groq Whisper),\n" +
            "not the browser microphone.\n\n" +
            "Web UI theme controls do not affect the VibeKeys OLED\n" +
            "(upstream feature request).\n\n" +
            "Future idea: background session juggling without full restart.",
            "About VibeLaunch",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void SaveLocalBtn_Click(object sender, RoutedEventArgs e)
    {
        var name = SelectedPresetName();
        if (string.IsNullOrWhiteSpace(name) || !_presets.TryGetValue(name, out var preset))
        {
            MessageBox.Show("Select a preset to save.");
            return;
        }

        var merged = new Dictionary<string, object?>();
        if (File.Exists(_presetsLocalPath))
        {
            var existing = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(_presetsLocalPath));
            if (existing != null)
            {
                foreach (var kv in existing)
                    merged[kv.Key] = JsonSerializer.Deserialize<object>(kv.Value.GetRawText());
            }
        }

        merged[name] = new Dictionary<string, object?>
        {
            ["label"] = preset.Label,
            ["tokens"] = preset.Tokens ?? new List<string>(),
            ["spawn"] = preset.Spawn ?? new List<string>(),
            ["cwd"] = preset.Cwd,
            ["notes"] = preset.Notes,
        };

        var json = JsonSerializer.Serialize(merged, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_presetsLocalPath, json);
        AppendOutput($"Saved preset override: {name}");
        LoadPresetsFromDisk();
        RefreshPresetList();
    }

    protected override void OnContentRendered(EventArgs e)
    {
        base.OnContentRendered(e);
        if (TagFilterBox.Items.Count == 0)
        {
            TagFilterBox.Items.Add("(all)");
            foreach (var tag in _presets.Values.SelectMany(p => p.Tags ?? new List<string>()).Distinct().OrderBy(t => t))
                TagFilterBox.Items.Add(tag);
            TagFilterBox.SelectedIndex = 0;
        }
    }
}

internal sealed class PresetListItem
{
    public PresetListItem(string name, PresetDto preset)
    {
        Name = name;
        Display = string.IsNullOrWhiteSpace(preset.Label) ? name : $"{name} — {preset.Label}";
    }

    public string Name { get; }
    public string Display { get; }
    public override string ToString() => Display;
}
