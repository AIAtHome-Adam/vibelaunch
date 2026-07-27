using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Markdig;

namespace VibeLaunchGui;

/// <summary>
/// Renders shipped Markdown help/runbook files to HTML for the in-app WebView and default browser.
/// Relative links to sibling Markdown (and other local files) are rewritten so they still resolve
/// after the HTML is written under %TEMP%\VibeLaunch\help — without this, Help → Open runbook
/// showed dead links such as HERMES_ACP_CLIENT.md next to the temp HTML.
/// </summary>
public static class HelpContentRenderer
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    private static readonly Regex HrefRegex = new(
        @"href\s*=\s*""([^""]+)""",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static string GetHelpOutputDirectory()
    {
        var dir = Path.Combine(Path.GetTempPath(), "VibeLaunch", "help");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string MarkdownToHtmlDocument(string markdown, string title, bool darkTheme)
    {
        var body = Markdown.ToHtml(markdown, Pipeline);
        return WrapHtml(body, title, darkTheme);
    }

    public static string MarkdownFileToHtmlDocument(string filePath, string title, bool darkTheme)
    {
        var md = File.ReadAllText(filePath);
        var sourceDir = Path.GetDirectoryName(Path.GetFullPath(filePath)) ?? ".";
        var outputDir = GetHelpOutputDirectory();
        var body = Markdown.ToHtml(md, Pipeline);
        body = RewriteLocalLinks(body, sourceDir, outputDir, darkTheme, new HashSet<string>(StringComparer.OrdinalIgnoreCase));
        return WrapHtml(body, title, darkTheme);
    }

    /// <summary>
    /// Renders <paramref name="markdownPath"/> (and reachable local .md links) into the help temp
    /// directory and returns the primary HTML file path.
    /// </summary>
    public static string RenderMarkdownFileToHtmlFile(string markdownPath, string title, bool darkTheme)
    {
        var outputDir = GetHelpOutputDirectory();
        var fullMd = Path.GetFullPath(markdownPath);
        var htmlPath = Path.Combine(outputDir, Path.GetFileNameWithoutExtension(fullMd) + ".html");
        var html = MarkdownFileToHtmlDocument(fullMd, title, darkTheme);
        File.WriteAllText(htmlPath, html, Encoding.UTF8);
        return htmlPath;
    }

    public static string OpenMarkdownInDefaultBrowser(string markdownPath, string title, bool darkTheme)
    {
        var htmlPath = RenderMarkdownFileToHtmlFile(markdownPath, title, darkTheme);
        Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true });
        return htmlPath;
    }

    private static string RewriteLocalLinks(
        string htmlBody,
        string sourceDirectory,
        string outputDirectory,
        bool darkTheme,
        HashSet<string> renderingStack)
    {
        return HrefRegex.Replace(htmlBody, match =>
        {
            var href = WebUtilityHtmlDecode(match.Groups[1].Value.Trim());
            if (IsNonLocalHref(href))
                return match.Value;

            var hash = string.Empty;
            var pathPart = href;
            var hashIdx = href.IndexOf('#');
            if (hashIdx >= 0)
            {
                pathPart = href[..hashIdx];
                hash = href[hashIdx..];
            }

            // Pure fragment stays as-is.
            if (string.IsNullOrEmpty(pathPart))
                return match.Value;

            string targetFull;
            try
            {
                targetFull = Path.GetFullPath(Path.Combine(sourceDirectory, Uri.UnescapeDataString(pathPart)));
            }
            catch
            {
                return match.Value;
            }

            if (Directory.Exists(targetFull))
            {
                var dirUri = new Uri(AppendDirectorySlash(targetFull));
                return $"href=\"{dirUri.AbsoluteUri.TrimEnd('/')}{hash}\"";
            }

            if (!File.Exists(targetFull))
                return match.Value;

            if (targetFull.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
            {
                var outPath = Path.Combine(outputDirectory, Path.GetFileNameWithoutExtension(targetFull) + ".html");
                if (renderingStack.Add(targetFull))
                {
                    try
                    {
                        var linkedMd = File.ReadAllText(targetFull);
                        var linkedBody = Markdown.ToHtml(linkedMd, Pipeline);
                        var linkedDir = Path.GetDirectoryName(targetFull) ?? sourceDirectory;
                        linkedBody = RewriteLocalLinks(linkedBody, linkedDir, outputDirectory, darkTheme, renderingStack);
                        var linkedTitle = Path.GetFileNameWithoutExtension(targetFull);
                        File.WriteAllText(outPath, WrapHtml(linkedBody, linkedTitle, darkTheme), Encoding.UTF8);
                    }
                    catch
                    {
                        var mdUri = new Uri(targetFull);
                        return $"href=\"{mdUri.AbsoluteUri}{hash}\"";
                    }
                }

                return $"href=\"{new Uri(outPath).AbsoluteUri}{hash}\"";
            }

            return $"href=\"{new Uri(targetFull).AbsoluteUri}{hash}\"";
        });
    }

    private static bool IsNonLocalHref(string href)
    {
        if (string.IsNullOrWhiteSpace(href))
            return true;
        if (href.StartsWith('#') ||
            href.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            href.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
            href.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase) ||
            href.StartsWith("file:", StringComparison.OrdinalIgnoreCase) ||
            href.StartsWith("data:", StringComparison.OrdinalIgnoreCase) ||
            href.StartsWith("javascript:", StringComparison.OrdinalIgnoreCase) ||
            href.StartsWith("about:", StringComparison.OrdinalIgnoreCase))
            return true;
        return false;
    }

    private static string AppendDirectorySlash(string path)
    {
        if (path.EndsWith(Path.DirectorySeparatorChar) || path.EndsWith(Path.AltDirectorySeparatorChar))
            return path;
        return path + Path.DirectorySeparatorChar;
    }

    // Avoid taking a dependency on System.Net.WebUtility just for rare entities in hrefs.
    private static string WebUtilityHtmlDecode(string value) =>
        value.Replace("&amp;", "&", StringComparison.Ordinal)
             .Replace("&quot;", "\"", StringComparison.Ordinal)
             .Replace("&#39;", "'", StringComparison.Ordinal);

    private static string WrapHtml(string body, string title, bool darkTheme)
    {
        var bg = darkTheme ? "#1e1e1e" : "#ffffff";
        var fg = darkTheme ? "#e8e8e8" : "#1a1a1a";
        var codeBg = darkTheme ? "#2d2d30" : "#f4f4f4";
        var border = darkTheme ? "#555" : "#ccc";
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>" +
            System.Net.WebUtility.HtmlEncode(title) +
            "</title><style>" +
            "body { font-family: Segoe UI, sans-serif; margin: 24px 32px; line-height: 1.55; background: " + bg + "; color: " + fg + "; max-width: 920px; }" +
            "h1,h2,h3 { margin-top: 1.2em; }" +
            "code { background: " + codeBg + "; padding: 2px 6px; border-radius: 4px; font-size: 0.95em; }" +
            "pre { background: " + codeBg + "; padding: 12px; overflow-x: auto; border-radius: 4px; }" +
            "pre code { background: transparent; padding: 0; }" +
            "a { color: #4a9eff; }" +
            "table { border-collapse: collapse; margin: 12px 0; }" +
            "th, td { border: 1px solid " + border + "; padding: 6px 10px; text-align: left; }" +
            "blockquote { border-left: 4px solid " + border + "; margin-left: 0; padding-left: 12px; opacity: 0.9; }" +
            "</style></head><body>" + body + "</body></html>";
    }
}
