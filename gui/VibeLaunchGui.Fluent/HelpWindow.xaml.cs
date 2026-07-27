using System.IO;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using VibeLaunchGui;

namespace VibeLaunchGui.Fluent;

public partial class HelpWindow : Wpf.Ui.Controls.FluentWindow
{
    private readonly string _markdownPath;
    private readonly string _pageTitle;
    private readonly CoreWebView2Environment? _environment;
    private readonly bool _darkTheme;

    public HelpWindow(string markdownPath, string pageTitle, CoreWebView2Environment? environment, bool darkTheme)
    {
        _markdownPath = markdownPath;
        _pageTitle = pageTitle;
        _environment = environment;
        _darkTheme = darkTheme;
        InitializeComponent();
        Title = pageTitle;
        HelpTitleBar.Title = pageTitle;
        Loaded += HelpWindow_Loaded;
    }

    private async void HelpWindow_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!File.Exists(_markdownPath))
            {
                LoadingText.Text = "File not found.";
                return;
            }

            await HelpWebView.EnsureCoreWebView2Async(_environment);
            // Prefer file:// HTML so rewritten relative links (sibling .md → .html) navigate cleanly.
            var htmlPath = HelpContentRenderer.RenderMarkdownFileToHtmlFile(_markdownPath, _pageTitle, _darkTheme);
            HelpWebView.CoreWebView2.Navigate(new Uri(htmlPath).AbsoluteUri);
            LoadingText.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            LoadingText.Text = $"Failed to load: {ex.Message}";
            MessageBox.Show(
                this,
                $"In-app help failed: {ex.Message}\n\nTry Help → Open runbook in browser.",
                "Help",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }
}
