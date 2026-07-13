using System.Windows;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace VibeLaunchGui.Fluent;

public static class FluentThemeHelper
{
    public const string Light = "light";
    public const string Dark = "dark";
    public const string System = "system";

    public static void Apply(string? theme, Window? window = null)
    {
        if (string.Equals(theme, Light, StringComparison.OrdinalIgnoreCase))
            ApplicationThemeManager.Apply(ApplicationTheme.Light, WindowBackdropType.Mica, true);
        else if (string.Equals(theme, Dark, StringComparison.OrdinalIgnoreCase))
            ApplicationThemeManager.Apply(ApplicationTheme.Dark, WindowBackdropType.Mica, true);
        else
            ApplicationThemeManager.Apply(ApplicationTheme.Unknown, WindowBackdropType.Mica, true);

        if (window != null)
            WindowBackdrop.ApplyBackdrop(window, WindowBackdropType.Mica);
    }

    public static bool IsDark(string? theme)
    {
        if (string.Equals(theme, Dark, StringComparison.OrdinalIgnoreCase)) return true;
        if (string.Equals(theme, Light, StringComparison.OrdinalIgnoreCase)) return false;
        return ApplicationThemeManager.GetAppTheme() == ApplicationTheme.Dark;
    }
}
