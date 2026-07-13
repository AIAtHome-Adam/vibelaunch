namespace VibeLaunchGui;

/// <summary>User-facing help strings for PTY geometry and keypad scrollback.</summary>
internal static class GuiHelpText
{
    internal const string PtySizeHint =
        "PTY size — cols ≈35 for OLED legibility; rows = scroll depth (default 200). Applied on Launch.";

    internal const string KeypadScrollbackTitle = "Keypad scrollback";

    internal const string KeypadScrollbackBody =
        "The VibeKeys keypad shows a small window into the terminal grid. Scroll keys move through that grid.\n\n" +
        "Cols (width): primary control — keep near 35 so text stays legible on the OLED. " +
        "While the keypad is connected, vibetty Sync also clamps width to ≤35. Adjust if your font/layout needs a tweak.\n\n" +
        "Rows (height): scroll depth, not visible keypad lines. Too few rows (e.g. 10–20) leave little history to scroll " +
        "on the PC preview; the default 200 gives a full session on both keypad and PC. Extra rows are not blank space — " +
        "the keypad still shows a small crop.\n\n" +
        "Presets:\n" +
        "• VibeKeys (35x200) — default for agents and CLIs\n" +
        "• Keypad focus (35x20) — keypad-first when the PC preview does not matter\n" +
        "• cmd scroll test — diagnostic preset\n\n" +
        "Troubleshooting: uncheck Hide vibetty console and resize the window — vibetty re-syncs geometry.\n\n" +
        "Slider changes apply on the next Launch (via mode con), not live.";
}
