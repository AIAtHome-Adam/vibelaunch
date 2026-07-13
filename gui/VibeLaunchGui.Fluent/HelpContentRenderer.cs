using System.Diagnostics;
using System.IO;
using System.Text;
using Markdig;

namespace VibeLaunchGui;

public static class HelpContentRenderer
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    public static string MarkdownToHtmlDocument(string markdown, string title, bool darkTheme)
    {
        var body = Markdown.ToHtml(markdown, Pipeline);
        return WrapHtml(body, title, darkTheme);
    }

    public static string MarkdownFileToHtmlDocument(string filePath, string title, bool darkTheme)
    {
        var md = File.ReadAllText(filePath);
        return MarkdownToHtmlDocument(md, title, darkTheme);
    }

    public static string OpenMarkdownInDefaultBrowser(string markdownPath, string title, bool darkTheme)
    {
        var html = MarkdownFileToHtmlDocument(markdownPath, title, darkTheme);
        var dir = Path.Combine(Path.GetTempPath(), "VibeLaunch", "help");
        Directory.CreateDirectory(dir);
        var safeName = Path.GetFileNameWithoutExtension(markdownPath) + ".html";
        var htmlPath = Path.Combine(dir, safeName);
        File.WriteAllText(htmlPath, html, Encoding.UTF8);
        Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true });
        return htmlPath;
    }

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
