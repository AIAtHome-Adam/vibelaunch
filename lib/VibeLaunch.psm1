#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:VibeLaunchRoot = $null

if (-not ('VibeLaunch.ConsoleApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

namespace VibeLaunch {
    public static class ConsoleApi {
        const int STD_OUTPUT_HANDLE = -11;
        const int SWP_NOMOVE = 0x0002;
        const int SWP_NOZORDER = 0x0004;
        const int SWP_NOACTIVATE = 0x0010;

        [StructLayout(LayoutKind.Sequential)]
        public struct COORD {
            public short X;
            public short Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct SMALL_RECT {
            public short Left;
            public short Top;
            public short Right;
            public short Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_FONT_INFO {
            public int nFont;
            public COORD dwFontSize;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_SCREEN_BUFFER_INFO {
            public COORD dwSize;
            public COORD dwCursorPosition;
            public short wAttributes;
            public SMALL_RECT srWindow;
            public COORD dwMaximumWindowSize;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AttachConsole(uint dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool FreeConsole();

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetConsoleScreenBufferInfo(IntPtr hConsoleOutput, out CONSOLE_SCREEN_BUFFER_INFO lpConsoleScreenBufferInfo);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetConsoleScreenBufferSize(IntPtr hConsoleOutput, COORD dwSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetConsoleWindowInfo(IntPtr hConsoleOutput, bool bAbsolute, ref SMALL_RECT lpConsoleWindow);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetCurrentConsoleFont(IntPtr hConsoleOutput, bool bMaximumWindow, out CONSOLE_FONT_INFO lpConsoleCurrentFont);

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        // vibetty PTY size tracks the console *window* viewport. AttachConsole fails
        // if this process already owns a console (GUI-launched powershell), so FreeConsole first.
        // Shrink window before buffer; grow buffer before window.
        public static bool TryResizeProcessConsole(int processId, int cols, int rows) {
            if (cols < 20 || rows < 5) return false;

            FreeConsole();
            if (!AttachConsole((uint)processId)) return false;
            try {
                IntPtr handle = GetStdHandle(STD_OUTPUT_HANDLE);
                if (handle == IntPtr.Zero || handle == new IntPtr(-1)) return false;

                CONSOLE_SCREEN_BUFFER_INFO info;
                if (!GetConsoleScreenBufferInfo(handle, out info)) return false;

                int curCols = info.srWindow.Right - info.srWindow.Left + 1;
                int curRows = info.srWindow.Bottom - info.srWindow.Top + 1;
                bool shrinking = cols < curCols || rows < curRows;

                SMALL_RECT window = new SMALL_RECT {
                    Left = 0,
                    Top = 0,
                    Right = (short)(cols - 1),
                    Bottom = (short)(rows - 1)
                };
                COORD size = new COORD { X = (short)cols, Y = (short)rows };

                if (shrinking) {
                    if (!SetConsoleWindowInfo(handle, true, ref window)) return false;
                    if (!SetConsoleScreenBufferSize(handle, size)) return false;
                } else {
                    if (!SetConsoleScreenBufferSize(handle, size)) return false;
                    if (!SetConsoleWindowInfo(handle, true, ref window)) return false;
                }

                // Also size the Win32 window so ConPTY clients that follow HWND geometry update.
                try {
                    var proc = System.Diagnostics.Process.GetProcessById(processId);
                    proc.Refresh();
                    IntPtr hwnd = proc.MainWindowHandle;
                    if (hwnd != IntPtr.Zero) {
                        int fontW = 8;
                        int fontH = 16;
                        CONSOLE_FONT_INFO font;
                        if (GetCurrentConsoleFont(handle, false, out font) && font.dwFontSize.X > 0 && font.dwFontSize.Y > 0) {
                            fontW = font.dwFontSize.X;
                            fontH = font.dwFontSize.Y;
                        }

                        RECT client, outer;
                        if (GetClientRect(hwnd, out client) && GetWindowRect(hwnd, out outer)) {
                            int chromeX = (outer.Right - outer.Left) - (client.Right - client.Left);
                            int chromeY = (outer.Bottom - outer.Top) - (client.Bottom - client.Top);
                            int width = cols * fontW + chromeX;
                            int height = rows * fontH + chromeY;
                            if (width > 80 && height > 40)
                                SetWindowPos(hwnd, IntPtr.Zero, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
                        }
                    }
                } catch { /* window size is best-effort */ }

                return true;
            } finally {
                FreeConsole();
            }
        }
    }

    public static class ProcessWindowApi {
        const int SW_HIDE = 0;

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AttachConsole(uint dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool FreeConsole();

        [DllImport("kernel32.dll")]
        static extern IntPtr GetConsoleWindow();

        public static bool TryHideProcessMainWindow(int processId) {
            try {
                var proc = System.Diagnostics.Process.GetProcessById(processId);
                proc.Refresh();
                var hwnd = proc.MainWindowHandle;
                if (hwnd != IntPtr.Zero && ShowWindow(hwnd, SW_HIDE)) return true;

                // vibetty is a CUI app: MainWindowHandle is often 0; hide via AttachConsole.
                FreeConsole();
                if (!AttachConsole((uint)processId)) return false;
                try {
                    hwnd = GetConsoleWindow();
                    if (hwnd == IntPtr.Zero) return false;
                    return ShowWindow(hwnd, SW_HIDE);
                } finally {
                    FreeConsole();
                }
            } catch {
                return false;
            }
        }
    }
}
'@
}

function Get-VibeLaunchRoot {
    if ($script:VibeLaunchRoot) { return $script:VibeLaunchRoot }
    $here = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $here 'config\defaults.json')) {
        $script:VibeLaunchRoot = $here
        return $here
    }
    $installed = 'C:\Program Files\VibeLaunch'
    if (Test-Path -LiteralPath (Join-Path $installed 'config\defaults.json')) {
        $script:VibeLaunchRoot = $installed
        return $installed
    }
    throw 'VibeLaunch root not found (expected repo vibelaunch/ or C:\Program Files\VibeLaunch)'
}

function Get-VibeLaunchStatePath {
    $dir = Join-Path $env:LOCALAPPDATA 'VibeLaunch'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir 'state.json'
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Merge-Hashtable {
    param([hashtable]$Base, [hashtable]$Overlay)
    $out = @{}
    foreach ($k in $Base.Keys) { $out[$k] = $Base[$k] }
    foreach ($k in $Overlay.Keys) {
        if ($out[$k] -is [hashtable] -and $Overlay[$k] -is [hashtable]) {
            $out[$k] = Merge-Hashtable -Base $out[$k] -Overlay $Overlay[$k]
        } else {
            $out[$k] = $Overlay[$k]
        }
    }
    return $out
}

function ConvertTo-HashtableDeep {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string]) { return $InputObject }
    if ($InputObject -is [hashtable]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) {
            $h[$k] = ConvertTo-HashtableDeep -InputObject $InputObject[$k]
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) {
            $h[$k] = ConvertTo-HashtableDeep -InputObject $InputObject[$k]
        }
        return $h
    }
    if ($InputObject -is [ValueType]) { return $InputObject }
    if ($null -ne $InputObject -and $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Array]) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-HashtableDeep -InputObject $item)) | Out-Null
        }
        return $list.ToArray()
    }
    $props = @($InputObject.PSObject.Properties)
    if ($props.Count -gt 0 -and $InputObject -isnot [decimal] -and $InputObject -isnot [int] -and $InputObject -isnot [long] -and $InputObject -isnot [double] -and $InputObject -isnot [bool]) {
        $h = @{}
        foreach ($p in $props) {
            $h[$p.Name] = ConvertTo-HashtableDeep -InputObject $p.Value
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-HashtableDeep -InputObject $item)) | Out-Null
        }
        return $list.ToArray()
    }
    return $InputObject
}

function Get-VibeLaunchGuiLinksPath {
    Join-Path $env:LOCALAPPDATA 'VibeLaunch\gui-links.local.json'
}

function Get-VibeLaunchGuiLinks {
    $paths = Get-VibeLaunchConfigPaths
    $loaded = Get-VibeLaunchConfig
    $cfg = $loaded.Config
    $links = @{
        github               = ''
        youtube              = ''
        twitter              = ''
        buyMeACoffee         = ''
        linkedin             = ''
        vibekeysRemoteDocs   = 'https://vibekeys.dev/docs/remote-mode/'
        vibekeysFirmware     = 'https://vibekeys.dev/docs/flashing-firmware/'
        vibekeysConfigurator = ''
        runbookPath          = ''
    }

    $shipped = ConvertTo-HashtableDeep (Read-JsonFile (Join-Path $paths.Root 'config\gui-links.json'))
    if ($shipped) {
        foreach ($k in $shipped.Keys) { $links[$k] = $shipped[$k] }
    }

    $local = ConvertTo-HashtableDeep (Read-JsonFile (Get-VibeLaunchGuiLinksPath))
    if ($local) {
        foreach ($k in $local.Keys) {
            if (-not [string]::IsNullOrWhiteSpace([string]$local[$k])) {
                $links[$k] = $local[$k]
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$links['vibekeysConfigurator'])) {
        $links['vibekeysConfigurator'] = Resolve-VibeLaunchVibekeysInstallDir -Config $cfg
    }

    $runbook = Join-Path $paths.Root 'docs\VIBEKEYS_REMOTE.md'
    if (Test-Path -LiteralPath $runbook) {
        $links['runbookPath'] = (Resolve-Path -LiteralPath $runbook).Path
    }

    return $links
}

function Resolve-VibeLaunchVibekeysInstallDir {
    param([hashtable]$Config)
    $vibettyPath = Expand-VibeLaunchTemplate -Text ([string]$Config['vibettyPath']) -Config $Config
    if ($vibettyPath -and (Test-Path -LiteralPath $vibettyPath)) {
        return (Split-Path -Parent $vibettyPath)
    }
    foreach ($candidate in @(
        'C:\Program Files (x86)\Vibekeys'
        'C:\Program Files\Vibekeys'
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ''
}

function Get-VibeLaunchPtySizePresetsLocalPath {
    $dir = Join-Path $env:LOCALAPPDATA 'VibeLaunch'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir 'pty-size-presets.local.json'
}

function Normalize-VibeLaunchPtySizePreset {
    param($Item)
    if ($null -eq $Item) { return $null }
    $h = if ($Item -is [hashtable]) { $Item } else { ConvertTo-HashtableDeep $Item }
    if (-not $h) { return $null }
    $cols = [int]$h['cols']
    $rows = [int]$h['rows']
    $label = [string]$h['label']
    if ($cols -lt 20 -or $cols -gt 120) { return $null }
    if ($rows -lt 5 -or $rows -gt 500) { return $null }
    if ([string]::IsNullOrWhiteSpace($label)) { $label = "${cols}x${rows}" }
    @{ label = $label; cols = $cols; rows = $rows }
}

function Get-VibeLaunchPtySizePresets {
    $paths = Get-VibeLaunchConfigPaths
    $fallback = @(
        @{ label = 'VibeKeys (35x200)'; cols = 35; rows = 200 }
        @{ label = 'Keypad focus (35x20)'; cols = 35; rows = 20 }
        @{ label = 'Desktop (80x24)'; cols = 80; rows = 24 }
    )

    $local = Read-JsonFile (Get-VibeLaunchPtySizePresetsLocalPath)
    if ($local) {
        $out = New-Object System.Collections.Generic.List[hashtable]
        foreach ($item in @($local)) {
            $norm = Normalize-VibeLaunchPtySizePreset -Item $item
            if ($norm) { $out.Add($norm) | Out-Null }
        }
        if ($out.Count -gt 0) { return @($out) }
    }

    $shipped = Read-JsonFile (Join-Path $paths.Root 'config\pty-size-presets.json')
    if ($shipped) {
        $out = New-Object System.Collections.Generic.List[hashtable]
        foreach ($item in @($shipped)) {
            $norm = Normalize-VibeLaunchPtySizePreset -Item $item
            if ($norm) { $out.Add($norm) | Out-Null }
        }
        if ($out.Count -gt 0) { return @($out) }
    }

    return $fallback
}

function Get-VibeLaunchPathsObject {
    $p = Get-VibeLaunchConfigPaths
    $userDir = Join-Path $env:LOCALAPPDATA 'VibeLaunch'
    @{
        root               = $p.Root
        configDir          = Join-Path $p.Root 'config'
        presets            = $p.Presets
        presetsLocal       = $p.PresetsLocal
        profilesDir        = $p.ProfilesDir
        userDefaults       = $p.UserDefaults
        userConfigDir      = $userDir
        ptySizePresets     = Join-Path $p.Root 'config\pty-size-presets.json'
        ptySizePresetsLocal = Get-VibeLaunchPtySizePresetsLocalPath
        guiLocal           = Get-VibeLaunchGuiLocalPath
        state              = Get-VibeLaunchStatePath
    }
}

function Get-VibeLaunchLocalIPv4Addresses {
    $addrs = New-Object System.Collections.Generic.List[string]
    try {
        [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' } |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object {
                $_.Address.AddressFamily -eq 'InterNetwork' -and
                $_.Address.ToString() -ne '127.0.0.1'
            } |
            ForEach-Object {
                $ip = $_.Address.ToString()
                if (-not $addrs.Contains($ip)) { $addrs.Add($ip) | Out-Null }
            }
    } catch { }
    return @($addrs)
}

function Test-VibeLaunchKeypadReadiness {
    param([hashtable]$Config)

    $port = [int]$Config['port']
    $listeners = @(Get-VibeLaunchPortListener -Port $port)
    $listening = ($listeners.Count -gt 0)
    $keypadHost = [string]$Config['keypadHost']
    if ([string]::IsNullOrWhiteSpace($keypadHost)) { $keypadHost = 'localhost' }
    $localAddrs = @(Get-VibeLaunchLocalIPv4Addresses)
    $isLoopback = ($keypadHost -eq 'localhost' -or $keypadHost -eq '127.0.0.1')
    $hostOnMachine = $isLoopback -or ($localAddrs -contains $keypadHost)

    $messages = New-Object System.Collections.Generic.List[string]
    $level = 'ok'
    $summary = 'ready'

    if (-not $listening) {
        $level = 'fail'
        $summary = 'no session'
        $messages.Add('No vibetty session - launch a preset first.') | Out-Null
    }

    if (-not $isLoopback -and -not $hostOnMachine) {
        if ($level -eq 'ok') { $level = 'warn' }
        $summary = 'host mismatch'
        $localText = if ($localAddrs.Count -gt 0) { ($localAddrs -join ', ') } else { '(none detected)' }
        $messages.Add("keypadHost '$keypadHost' is not assigned to this PC (local: $localText).") | Out-Null
    }

    if ($isLoopback -and $listening) {
        if ($level -eq 'ok') { $level = 'warn'; $summary = 'localhost host' }
        $messages.Add('keypadHost is localhost - VibeKeys on Wi-Fi needs your PC LAN IP in defaults.local.json.') | Out-Null
    }

    @{
        level             = $level
        summary           = $summary
        listening         = $listening
        keypadHost        = $keypadHost
        keypadUrl         = Get-VibeLaunchKeypadUrl -Config $Config
        localAddresses    = $localAddrs
        hostOnThisMachine = $hostOnMachine
        messages          = @($messages)
    }
}

function Hide-VibeLaunchProcessWindow {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            if ([VibeLaunch.ProcessWindowApi]::TryHideProcessMainWindow($ProcessId)) {
                return $true
            }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Get-VibeLaunchGuiLocalPath {
    $dir = Join-Path $env:LOCALAPPDATA 'VibeLaunch'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir 'gui.local.json'
}

function Get-VibeLaunchMergedGuiSettings {
    param([hashtable]$Config)

    $gui = @{
        hideVibettyConsole = $true
        defaultCols        = 35
        defaultRows        = 200
        theme              = 'system'
        sizePresets        = @(Get-VibeLaunchPtySizePresets)
        cols               = 35
        rows               = 200
        sizePresetLabel    = 'VibeKeys (35x200)'
    }

    if ($Config['gui'] -is [hashtable]) {
        foreach ($k in $Config['gui'].Keys) {
            if ($k -eq 'sizePresets') { continue }
            $gui[$k] = $Config['gui'][$k]
        }
    }

    $gui['sizePresets'] = @(Get-VibeLaunchPtySizePresets)

    $local = ConvertTo-HashtableDeep (Read-JsonFile (Get-VibeLaunchGuiLocalPath))
    if ($local) {
        foreach ($k in $local.Keys) {
            if ($k -eq 'sizePresets') { continue }
            $gui[$k] = $local[$k]
        }
    }

    if (-not $gui['cols']) { $gui['cols'] = [int]$gui['defaultCols'] }
    if (-not $gui['rows']) { $gui['rows'] = [int]$gui['defaultRows'] }
    if ([string]::IsNullOrWhiteSpace([string]$gui['theme'])) { $gui['theme'] = 'system' }

    return $gui
}

function Set-VibeLaunchGuiLocalSettings {
    param(
        [int]$Cols,
        [int]$Rows,
        [string]$SizePresetLabel,
        [bool]$HideVibettyConsole,
        [string]$Theme
    )
    $path = Get-VibeLaunchGuiLocalPath
    $existing = ConvertTo-HashtableDeep (Read-JsonFile $path)
    if (-not $existing) { $existing = @{} }
    $existing['cols'] = $Cols
    $existing['rows'] = $Rows
    $existing['sizePresetLabel'] = $SizePresetLabel
    $existing['hideVibettyConsole'] = $HideVibettyConsole
    if (-not [string]::IsNullOrWhiteSpace($Theme)) {
        $existing['theme'] = $Theme
    }
    $existing | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-VibeLaunchWebUrl {
    param([hashtable]$Config)
    $port = [int]$Config['port']
    "http://localhost:$port/"
}

function Set-VibeLaunchConsoleGeometry {
    param(
        [int]$ProcessId,
        [int]$Cols,
        [int]$Rows
    )
    if ($ProcessId -le 0 -or $Cols -le 0 -or $Rows -le 0) { return $false }
    try {
        return [VibeLaunch.ConsoleApi]::TryResizeProcessConsole($ProcessId, $Cols, $Rows)
    } catch {
        Write-Warning "Console resize failed: $_"
        return $false
    }
}

# vibetty sizes its ConPTY from crossterm::terminal::size() minus TUI chrome
# (4 cols / 6 rows — header+footer borders). Post-launch AttachConsole cannot
# shrink the buffer (ERROR_INVALID_PARAMETER); size must be set BEFORE spawn.
# Keypad Sync also clamps width to 35 cols (upstream vibetty).
$script:VibeLaunchTuiColsPadding = 4
$script:VibeLaunchTuiRowsPadding = 6

function Get-VibeLaunchConsoleSizeForPty {
    param([int]$PtyCols, [int]$PtyRows)
    @{
        Cols = [Math]::Max(20, $PtyCols + $script:VibeLaunchTuiColsPadding)
        Rows = [Math]::Max(10, $PtyRows + $script:VibeLaunchTuiRowsPadding)
    }
}

function Format-VibeLaunchBatVibettyLine {
    param(
        [string]$VibettyPath,
        [string[]]$ArgumentList
    )

    $vibettyQuoted = '"{0}"' -f ($VibettyPath -replace '"', '')
    $dashDashIdx = [Array]::IndexOf($ArgumentList, '--')

    # WSL presets arrive as: ... -- cmd.exe /c wsl.exe -u USER bash -lic "command"
    # The tail after /c is already cmd-parseable; wrapping it in extra quotes
    # produces `"bash -lic "command""` and bash dies with unexpected EOF.
    if ($dashDashIdx -ge 0 `
            -and ($dashDashIdx + 3) -lt $ArgumentList.Count `
            -and [string]$ArgumentList[$dashDashIdx + 1] -eq 'cmd.exe' `
            -and [string]$ArgumentList[$dashDashIdx + 2] -eq '/c') {
        $before = @()
        if ($dashDashIdx -gt 0) { $before = $ArgumentList[0..($dashDashIdx - 1)] }
        $tail = ($ArgumentList[($dashDashIdx + 3)..($ArgumentList.Count - 1)] -join ' ')
        $beforeQuoted = ($before | ForEach-Object {
                if ($_ -match '\s') { '"{0}"' -f ($_ -replace '"', '""') } else { $_ }
            }) -join ' '
        $middle = if ($beforeQuoted) { "$beforeQuoted --" } else { '--' }
        return '{0} {1} cmd.exe /c {2}' -f $vibettyQuoted, $middle, $tail
    }

    $argLine = ($ArgumentList | ForEach-Object {
            if ($_ -match '\s') { '"{0}"' -f ($_ -replace '"', '""') } else { $_ }
        }) -join ' '
    return '{0} {1}' -f $vibettyQuoted, $argLine
}

function Start-VibeLaunchVibettyProcess {
    param(
        [string]$VibettyPath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [int]$ConsoleCols = 0,
        [int]$ConsoleRows = 0,
        [switch]$HideConsole
    )

    $needsGeometry = ($ConsoleCols -gt 0 -and $ConsoleRows -gt 0)
    if (-not $needsGeometry) {
        return Start-Process -FilePath $VibettyPath `
            -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory `
            -PassThru `
            -WindowStyle $(if ($HideConsole) { 'Hidden' } else { 'Normal' })
    }

    $console = Get-VibeLaunchConsoleSizeForPty -PtyCols $ConsoleCols -PtyRows $ConsoleRows
    $dir = Join-Path $env:TEMP 'VibeLaunch'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $bat = Join-Path $dir ("launch-{0}.cmd" -f [guid]::NewGuid().ToString('N'))

    $vibettyLine = Format-VibeLaunchBatVibettyLine -VibettyPath $VibettyPath -ArgumentList $ArgumentList
    $cwdQuoted = '"{0}"' -f ($WorkingDirectory -replace '"', '')
    @(
        '@echo off'
        'cd /d {0}' -f $cwdQuoted
        'mode con: cols={0} lines={1} >nul 2>&1' -f $console.Cols, $console.Rows
        $vibettyLine
    ) | Set-Content -LiteralPath $bat -Encoding ASCII

    # Same console as mode con — do not use `start` (new console loses geometry).
    $cmdProc = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList @('/c', "`"$bat`"") `
        -WorkingDirectory $WorkingDirectory `
        -PassThru `
        -WindowStyle Normal

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 150
        $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($cmdProc.Id)" -ErrorAction SilentlyContinue)
        $vibetty = $kids | Where-Object { $_.Name -match 'vibetty' } | Select-Object -First 1
        if ($vibetty) {
            try { return Get-Process -Id $vibetty.ProcessId -ErrorAction Stop } catch { }
        }
        if ($cmdProc.HasExited) { break }
    }
    return $cmdProc
}

function Set-VibeLaunchHermesGeometryEnv {
    # Despite the name (kept for call-site compatibility), this feeds PTY
    # geometry env vars to every WSL launch wrapper that reads them, not
    # just Hermes's. Add new wrapper var names here when new wrappers ship
    # so VibeLaunch GUI's cols/rows sliders reach them too.
    param(
        [int]$Cols,
        [int]$Rows
    )
    if ($Cols -gt 0) {
        $env:HERMES_VIBEKEYS_COLS = [string]$Cols
        $env:OPENCLAW_VIBEKEYS_COLS = [string]$Cols
    }
    if ($Rows -gt 0) {
        $env:HERMES_VIBEKEYS_ROWS = [string]$Rows
        $env:OPENCLAW_VIBEKEYS_ROWS = [string]$Rows
    }
}

function Clear-VibeLaunchHermesGeometryEnv {
    Remove-Item Env:HERMES_VIBEKEYS_COLS -ErrorAction SilentlyContinue
    Remove-Item Env:HERMES_VIBEKEYS_ROWS -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_VIBEKEYS_COLS -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_VIBEKEYS_ROWS -ErrorAction SilentlyContinue
}

function Split-VibeLaunchLaunchFlags {
    param([string[]]$Arguments)

    $result = @{
        Positionals  = New-Object System.Collections.Generic.List[string]
        Extra        = New-Object System.Collections.Generic.List[string]
        Force        = $false
        Wait         = $false
        DryRun       = $false
        Gui          = $false
        HideConsole  = $false
        ShowConsole  = $false
        Cols         = 0
        Rows         = 0
        Passthrough  = $false
    }

    if (-not $Arguments) { return $result }

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($result.Passthrough) {
            $result.Extra.Add($a) | Out-Null
            continue
        }
        switch -Regex ($a) {
            '^--force$' { $result.Force = $true; continue }
            '^--wait$' { $result.Wait = $true; continue }
            '^--dry-run$' { $result.DryRun = $true; continue }
            '^--gui$' { $result.Gui = $true; continue }
            '^--hide-console$' { $result.HideConsole = $true; continue }
            '^--show-console$' { $result.ShowConsole = $true; continue }
            '^--cols$' {
                $i++
                if ($i -ge $Arguments.Count) { throw '--cols requires a value' }
                $result.Cols = [int]$Arguments[$i]
                continue
            }
            '^--rows$' {
                $i++
                if ($i -ge $Arguments.Count) { throw '--rows requires a value' }
                $result.Rows = [int]$Arguments[$i]
                continue
            }
            '^--$' { $result.Passthrough = $true; continue }
            default {
                if ($a -match '^--cols=(.+)$') {
                    $result.Cols = [int]$Matches[1]
                    continue
                }
                if ($a -match '^--rows=(.+)$') {
                    $result.Rows = [int]$Matches[1]
                    continue
                }
                $result.Positionals.Add($a) | Out-Null
            }
        }
    }

    return $result
}

function Resolve-VibeLaunchLaunchOptions {
    param(
        [hashtable]$Flags,
        [hashtable]$Config
    )

    $gui = Get-VibeLaunchMergedGuiSettings -Config $Config
    $cols = [int]$Flags.Cols
    $rows = [int]$Flags.Rows
    $hide = $false

    if ($Flags.Gui) {
        if ($cols -le 0) { $cols = [int]$gui['cols'] }
        if ($rows -le 0) { $rows = [int]$gui['rows'] }
        if ($Flags.HideConsole) { $hide = $true }
        elseif ($Flags.ShowConsole) { $hide = $false }
        else { $hide = [bool]$gui['hideVibettyConsole'] }
    } else {
        if ($Flags.HideConsole) { $hide = $true }
        if ($Flags.ShowConsole) { $hide = $false }
        if ($cols -le 0 -and $rows -le 0) {
            $cols = 0
            $rows = 0
        } elseif ($cols -le 0) {
            $cols = [int]$gui['defaultCols']
        } elseif ($rows -le 0) {
            $rows = [int]$gui['defaultRows']
        }
    }

    return @{
        ConsoleCols = $cols
        ConsoleRows = $rows
        HideConsole = $hide
    }
}

function Get-VibeLaunchStatusObject {
    param([hashtable]$Config)

    $port = [int]$Config['port']
    $listeners = @(Get-VibeLaunchPortListener -Port $port)
    $state = Get-VibeLaunchActiveState
    $proc = Get-VibeLaunchVibettyProcess -Port $port
    $bindAddrs = @($listeners | Select-Object -ExpandProperty LocalAddress -Unique)

    @{
        profile        = [string]$Config['profile']
        port           = $port
        preset         = if ($state -and $state['preset']) { [string]$state['preset'] } else { $null }
        pid            = if ($proc) { $proc.Id } else { $null }
        listening      = ($listeners.Count -gt 0)
        bindAddrs      = $bindAddrs
        keypadUrl      = Get-VibeLaunchKeypadUrl -Config $Config
        webUrl         = Get-VibeLaunchWebUrl -Config $Config
        setupUrl       = "$(Get-VibeLaunchWebUrl -Config $Config)setup"
        keypadReadiness = Test-VibeLaunchKeypadReadiness -Config $Config
    }
}

function Get-VibeLaunchPreflightObject {
    param([hashtable]$Config)

    $port = [int]$Config['port']
    $vibettyPath = Expand-VibeLaunchTemplate -Text ([string]$Config['vibettyPath']) -Config $Config
    $checks = New-Object System.Collections.Generic.List[hashtable]

    $checks.Add(@{
        level   = if (Test-Path -LiteralPath $vibettyPath) { 'OK' } else { 'FAIL' }
        message = if (Test-Path -LiteralPath $vibettyPath) { "vibetty: $vibettyPath" } else { "vibetty not found: $vibettyPath" }
    }) | Out-Null

    $listeners = @(Get-VibeLaunchPortListener -Port $port)
    if ($listeners.Count -eq 0) {
        $checks.Add(@{ level = 'OK'; message = "port $port is free" }) | Out-Null
    } else {
        $proc = Get-VibeLaunchVibettyProcess -Port $port
        $addrs = ($listeners | Select-Object -ExpandProperty LocalAddress -Unique) -join ', '
        if ($proc) {
            $checks.Add(@{ level = 'WARN'; message = "port $port in use by vibetty PID $($proc.Id) (bind: $addrs)" }) | Out-Null
        } else {
            $checks.Add(@{ level = 'WARN'; message = "port $port in use (bind: $addrs) but not vibetty" }) | Out-Null
        }
    }

    $codex = Test-VibeLaunchCodexPath
    $checks.Add(@{ level = if ($codex.Ok) { 'OK' } else { 'WARN' }; message = $codex.Message }) | Out-Null

    $fw = Test-VibeLaunchFirewallBlocks -VibettyPath $vibettyPath
    $checks.Add(@{ level = if ($fw.Ok) { 'OK' } else { 'FAIL' }; message = $fw.Message }) | Out-Null

    $hermesWin = Test-VibeLaunchWindowsCommand -Name 'hermes'
    $checks.Add(@{
        level   = if ($hermesWin) { 'OK' } else { 'INFO' }
        message = if ($hermesWin) { 'hermes on Windows PATH' } else { 'hermes not on Windows PATH (OK if you use WSL presets only)' }
    }) | Out-Null

    if ($Config['wsl'] -and $Config['wsl']['enabled']) {
        $null = & wsl.exe -e true 2>&1
        $checks.Add(@{
            level   = if ($LASTEXITCODE -eq 0) { 'OK' } else { 'FAIL' }
            message = if ($LASTEXITCODE -eq 0) { 'WSL available' } else { 'WSL unavailable' }
        }) | Out-Null

        $wslUser = Test-VibeLaunchWslUserConfigured -Config $Config
        $checks.Add(@{
            level   = if ($wslUser.Ok) { 'OK' } else { 'FAIL' }
            message = $wslUser.Message
        }) | Out-Null

        if ($wslUser.Ok) {
            $hermesWsl = Test-VibeLaunchWslCommand -Name 'hermes' -Config $Config
            $checks.Add(@{
                level   = if ($hermesWsl) { 'OK' } else { 'INFO' }
                message = if ($hermesWsl) { 'hermes in WSL' } else { 'hermes not in WSL (install or use Windows-native presets)' }
            }) | Out-Null

            $openclawWsl = Test-VibeLaunchWslCommand -Name 'openclaw' -Config $Config
            $checks.Add(@{
                level   = if ($openclawWsl) { 'OK' } else { 'INFO' }
                message = if ($openclawWsl) { 'openclaw in WSL' } else { 'openclaw not in WSL (WSL-only; no native Windows companion yet)' }
            }) | Out-Null
        }
    }

    @{
        checks    = @($checks)
        keypadUrl = Get-VibeLaunchKeypadUrl -Config $Config
        webUrl    = Get-VibeLaunchWebUrl -Config $Config
        profile   = [string]$Config['profile']
        bind      = Get-VibeLaunchBindAddress -Config $Config
    }
}

function Save-VibeLaunchPresetLocal {
    param(
        [string]$Name,
        [string]$Label,
        [string[]]$Tokens,
        [string[]]$Spawn,
        [string]$Cwd,
        [string]$Notes
    )

    $paths = Get-VibeLaunchConfigPaths
    $localPath = $paths.PresetsLocal
    $existing = @{}
    $raw = Read-JsonFile $localPath
    if ($raw) {
        $raw.PSObject.Properties | ForEach-Object { $existing[$_.Name] = $_.Value }
    }

    $entry = @{
        label  = $Label
        tokens = @($Tokens)
        spawn  = @($Spawn)
    }
    if ($Cwd) { $entry['cwd'] = $Cwd }
    if ($Notes) { $entry['notes'] = $Notes }

    $existing[$Name] = $entry
    $existing | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $localPath -Encoding UTF8
}

function Get-VibeLaunchConfigPaths {
    $root = Get-VibeLaunchRoot
    @{
        Root           = $root
        Defaults       = Join-Path $root 'config\defaults.json'
        Presets        = Join-Path $root 'config\presets.json'
        PresetsLocal   = Join-Path $root 'config\presets.local.json'
        ProfilesDir    = Join-Path $root 'config\profiles'
        UserDefaults   = Join-Path $env:LOCALAPPDATA 'VibeLaunch\defaults.local.json'
    }
}

function Get-VibeLaunchConfig {
    $paths = Get-VibeLaunchConfigPaths
    $cfg = ConvertTo-HashtableDeep (Read-JsonFile $paths.Defaults)
    if (-not $cfg) { throw "Missing defaults: $($paths.Defaults)" }

    $profileName = $cfg['profile']
    if ($profileName) {
        $profilePath = Join-Path $paths.ProfilesDir "$profileName.json"
        $profile = ConvertTo-HashtableDeep (Read-JsonFile $profilePath)
        if ($profile) {
            $cfg = Merge-Hashtable -Base $cfg -Overlay $profile
        }
    }

    $userDefaults = ConvertTo-HashtableDeep (Read-JsonFile $paths.UserDefaults)
    if ($userDefaults) {
        $cfg = Merge-Hashtable -Base $cfg -Overlay $userDefaults
    }

    if (-not $cfg['workspaces']) { $cfg['workspaces'] = @{} }
    if (-not $cfg['confirmKill']) {
        $cfg['confirmKill'] = @{ hermes = $true; openclaw = $true; claude = $false; codex = $false }
    }

    Resolve-VibeLaunchWorkspacePaths -Config $cfg -RepoRoot (Split-Path -Parent $paths.Root)

    return @{
        Config = $cfg
        Paths  = $paths
    }
}

function Resolve-VibeLaunchWorkspacePaths {
    # The shipped config intentionally carries <windows-user> placeholders in
    # workspaces.default so no personal path leaks on publish. Nothing else
    # resolves them, so a fresh clone would pass a literal "C:\Users\
    # <windows-user>\..." into Test-Path and crash. When VibeLaunch runs from
    # the repo (Root = <repo>\vibelaunch), derive the real paths from the repo
    # location; when installed to Program Files (parent is not a checkout),
    # leave the value and let the pre-launch guard fall back to the cwd.
    param(
        [hashtable]$Config,
        [string]$RepoRoot
    )
    $ws = $Config['workspaces']
    if ($ws -isnot [hashtable]) { return }

    $repoUsable = $RepoRoot -and (Test-Path -LiteralPath $RepoRoot) -and ($RepoRoot -notlike "$env:ProgramFiles\*") -and ($RepoRoot -notlike "${env:ProgramFiles(x86)}\*")

    $winPath = [string]$ws['default']
    if (([string]::IsNullOrWhiteSpace($winPath) -or $winPath -match '<[^>]+>') -and $repoUsable) {
        $ws['default'] = $RepoRoot
        $winPath = $RepoRoot
    }

    $wslPath = [string]$ws['default-wsl']
    if (([string]::IsNullOrWhiteSpace($wslPath) -or $wslPath -match '<[^>]+>') -and
        $winPath -and $winPath -notmatch '<[^>]+>' -and $winPath -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        $ws['default-wsl'] = "/mnt/$drive/$rest"
    }

}

function Get-VibeLaunchPresets {
    $paths = Get-VibeLaunchConfigPaths
    $merged = @{}
    $base = Read-JsonFile $paths.Presets
    if ($base) {
        $base.PSObject.Properties | ForEach-Object { $merged[$_.Name] = $_.Value }
    }
    $local = Read-JsonFile $paths.PresetsLocal
    if ($local) {
        $local.PSObject.Properties | ForEach-Object { $merged[$_.Name] = $_.Value }
    }
    return $merged
}

function Expand-VibeLaunchTemplate {
    param(
        [string]$Text,
        [hashtable]$Config
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    # Resolve {{cwd}} before workspace tokens because the shipped cwd itself is
    # {{workspaces.default}}. Doing this last leaves a nested token unresolved.
    $cwdVal = [string]$Config['cwd']
    $Text = $Text -replace '\{\{cwd\}\}', $cwdVal
    $workspaces = $Config['workspaces']
    if ($workspaces -is [hashtable]) {
        foreach ($k in $workspaces.Keys) {
            $Text = $Text -replace [regex]::Escape("{{workspaces.$k}}"), [string]$workspaces[$k]
        }
    }
    $keypadHostVal = [string]$Config['keypadHost']
    if ([string]::IsNullOrWhiteSpace($keypadHostVal)) { $keypadHostVal = 'localhost' }
    $port = [string]$Config['port']
    $Text = $Text -replace '\{\{host\}\}', $keypadHostVal
    $Text = $Text -replace '\{\{port\}\}', $port
    $wslUserVal = ''
    if ($Config['wsl'] -is [hashtable]) { $wslUserVal = [string]$Config['wsl']['user'] }
    $Text = $Text -replace '\{\{wsl\.user\}\}', $wslUserVal
    return $Text
}

function Test-VibeLaunchWslUserConfigured {
    # WSL-based presets need a real `wsl.user` (config.wsl.user, resolved via
    # {{wsl.user}}) before spawning `wsl.exe -u <user> ...`. An empty value or
    # a leftover `<placeholder>` (copy-paste from an .example file, or an
    # unresolved template) produces a confusing wsl.exe/vibetty failure
    # instead of a clear one -- catch it here so preflight and launch both
    # give the same actionable message.
    param([hashtable]$Config)

    $user = ''
    if ($Config['wsl'] -is [hashtable]) { $user = [string]$Config['wsl']['user'] }
    $user = $user.Trim()

    if ([string]::IsNullOrWhiteSpace($user)) {
        return @{
            Ok      = $false
            Message = 'wsl.user is not set. Edit %LOCALAPPDATA%\VibeLaunch\defaults.local.json (or run setup-wsl-remote.ps1) and set "wsl": { "user": "<your-wsl-username>" }.'
        }
    }
    if ($user -match '^<.*>$') {
        return @{
            Ok      = $false
            Message = "wsl.user is still the placeholder '$user'. Replace it with your real WSL username in %LOCALAPPDATA%\VibeLaunch\defaults.local.json (or config/defaults.local.json.example before copying it)."
        }
    }
    return @{ Ok = $true; Message = "wsl.user: $user" }
}

function Expand-VibeLaunchArray {
    param(
        [object[]]$Items,
        [hashtable]$Config
    )
    if (-not $Items) { return @() }
    return @($Items | ForEach-Object { Expand-VibeLaunchTemplate -Text ([string]$_) -Config $Config })
}

function Normalize-VibeLaunchTokens {
    param([string[]]$Tokens)
    @($Tokens | ForEach-Object {
        $t = $_.Trim().ToLowerInvariant()
        $t -replace '\s+', '-'
    })
}

function Resolve-VibeLaunchPreset {
    param(
        [string[]]$Arguments,
        [hashtable]$Config
    )

    $presets = Get-VibeLaunchPresets
    if ($presets.Count -eq 0) { throw 'No presets configured' }

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        $name = $Config['defaultPreset']
        if (-not $name -or -not $presets.ContainsKey($name)) {
            throw 'No preset specified and defaultPreset is not set. Run: vibelaunch list'
        }
        return @{ Name = $name; Preset = $presets[$name] }
    }

    $first = $Arguments[0]
    if ($Arguments.Count -eq 1 -and $presets.ContainsKey($first)) {
        return @{ Name = $first; Preset = $presets[$first] }
    }

    $tokens = @(Normalize-VibeLaunchTokens -Tokens $Arguments)
    $candidates = @()
    foreach ($entry in $presets.GetEnumerator()) {
        $presetTokens = @()
        if ($entry.Value.tokens) {
            $presetTokens = @(Normalize-VibeLaunchTokens -Tokens @($entry.Value.tokens))
        }
        if ($presetTokens.Count -eq 0) { continue }
        if ($tokens.Count -lt $presetTokens.Count) { continue }
        $match = $true
        for ($i = 0; $i -lt $presetTokens.Count; $i++) {
            if ($tokens[$i] -ne $presetTokens[$i]) { $match = $false; break }
        }
        if ($match) {
            $candidates += [pscustomobject]@{
                Name       = $entry.Key
                Preset     = $entry.Value
                TokenCount = $presetTokens.Count
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No preset matches: $($Arguments -join ' '). Run: vibelaunch list"
    }

    $best = $candidates | Sort-Object -Property TokenCount -Descending | Select-Object -First 1
    return @{ Name = $best.Name; Preset = $best.Preset }
}

function Get-VibeLaunchBindAddress {
    param([hashtable]$Config)
    $addr = [string]$Config['bindAddr']
    $port = [int]$Config['port']
    if ([string]::IsNullOrWhiteSpace($addr)) { $addr = '0.0.0.0' }
    return "$addr`:$port"
}

function Get-VibeLaunchKeypadUrl {
    param([hashtable]$Config)
    $tpl = [string]$Config['keypadUrlTemplate']
    if ([string]::IsNullOrWhiteSpace($tpl)) {
        $tpl = 'ws://{{host}}:{{port}}/ws'
    }
    Expand-VibeLaunchTemplate -Text $tpl -Config $Config
}

function Get-VibeLaunchPortListener {
    param([int]$Port)
    try {
        return @((Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue))
    } catch {
        return @()
    }
}

function Get-VibeLaunchVibettyProcess {
    param([int]$Port)
    $listeners = Get-VibeLaunchPortListener -Port $Port
    foreach ($conn in $listeners) {
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        if (-not $proc) { continue }
        if ($proc.ProcessName -match 'vibetty') {
            return $proc
        }
        # Parent might be vibetty wrapper
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
            if ($parent -and $parent.Name -match 'vibetty') { return Get-Process -Id $proc.Id }
        } catch { }
    }
    return $null
}

function Stop-VibeLaunchProcessTree {
    param(
        [int]$ProcessId,
        [switch]$Force
    )
    $toKill = New-Object System.Collections.Generic.List[int]
    $queue = [System.Collections.Queue]::Synchronized([System.Collections.Queue]::new())
    $queue.Enqueue($ProcessId)
    while ($queue.Count -gt 0) {
        $pid = [int]$queue.Dequeue()
        if ($toKill -contains $pid) { continue }
        $toKill.Add($pid) | Out-Null
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$pid" -ErrorAction SilentlyContinue |
            ForEach-Object { $queue.Enqueue([int]$_.ProcessId) }
    }
    foreach ($pid in ($toKill | Sort-Object -Descending)) {
        try {
            Stop-Process -Id $pid -Force:$Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not stop PID $pid : $_"
        }
    }
}

function Get-VibeLaunchActiveState {
    $path = Get-VibeLaunchStatePath
    $state = Read-JsonFile $path
    if (-not $state) { return $null }
    return ConvertTo-HashtableDeep $state
}

function Set-VibeLaunchActiveState {
    param(
        [string]$PresetName,
        [int]$Port,
        [int]$ProcessId
    )
    $path = Get-VibeLaunchStatePath
    @{
        preset    = $PresetName
        port      = $Port
        pid       = $ProcessId
        startedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
}

function Clear-VibeLaunchActiveState {
    $path = Get-VibeLaunchStatePath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Test-VibeLaunchConfirmKill {
    param(
        [hashtable]$Config,
        [string]$PresetName,
        [object]$Preset,
        [switch]$Force
    )
    if ($Force) { return $true }

    $tags = @()
    if ($Preset.tags) { $tags = @($Preset.tags) }
    $confirm = $Config['confirmKill']
    if (-not ($confirm -is [hashtable])) { return $true }

    $needsConfirm = $false
    foreach ($tag in $tags) {
        $key = [string]$tag
        if ($confirm.ContainsKey($key) -and $confirm[$key]) {
            $needsConfirm = $true
            break
        }
    }

    if (-not $needsConfirm) { return $true }

    $label = if ($Preset.label) { $Preset.label } else { $PresetName }
    $msg = "Active session may be a live agent ($label). Kill and relaunch? [y/N]"
    $answer = Read-Host $msg
    return ($answer -match '^[yY]')
}

function Stop-VibeLaunchSession {
    param(
        [hashtable]$Config,
        [switch]$Force
    )
    $port = [int]$Config['port']
    $proc = Get-VibeLaunchVibettyProcess -Port $port
    if (-not $proc) {
        Clear-VibeLaunchActiveState
        Write-Host "No vibetty listener on port $port."
        return $true
    }

    if (-not $Force) {
        $state = Get-VibeLaunchActiveState
        if ($state -and $state['preset']) {
            $presets = Get-VibeLaunchPresets
            $name = [string]$state['preset']
            if ($presets.ContainsKey($name)) {
                if (-not (Test-VibeLaunchConfirmKill -Config $Config -PresetName $name -Preset $presets[$name])) {
                    Write-Host 'Stop cancelled.'
                    return $false
                }
            }
        }
    }

    Write-Host "Stopping vibetty (PID $($proc.Id)) on port $port ..."
    Stop-VibeLaunchProcessTree -ProcessId $proc.Id -Force
    Start-Sleep -Milliseconds 500
    Clear-VibeLaunchActiveState
    Write-Host 'Stopped.'
    return $true
}

function Test-VibeLaunchCodexPath {
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) {
        return @{ Ok = $true; Message = "codex found: $($cmd.Source)" }
    }
    return @{
        Ok      = $false
        Message = 'codex not on PATH - open a fresh shell or update your Codex install PATH'
    }
}

function Test-VibeLaunchWindowsCommand {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-VibeLaunchWslCommand {
    param(
        [string]$Name,
        [hashtable]$Config
    )
    $wslUser = Test-VibeLaunchWslUserConfigured -Config $Config
    if (-not $wslUser.Ok) { return $false }
    $user = [string]$Config['wsl']['user']
    & wsl.exe -u $user bash -lic "command -v $Name" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-VibeLaunchPresetPlatformPreference {
    param([hashtable]$Config)
    if ($Config['wsl'] -is [hashtable] -and $Config['wsl']['enabled']) {
        return 'wsl'
    }
    return 'windows'
}

function Resolve-VibeLaunchPresetSpawnSource {
    param(
        [object]$Preset,
        [hashtable]$Config
    )

    $platform = ''
    if ($Preset.PSObject.Properties['platform']) {
        $platform = [string]$Preset.platform
        if ($platform) { $platform = $platform.Trim().ToLowerInvariant() }
    }

    if ($platform -eq 'wsl') {
        $items = if ($Preset.spawn) { @($Preset.spawn) } else { @($Preset.spawnWsl) }
        return @{ Items = $items; RequiresWsl = $true; Resolved = 'wsl' }
    }
    if ($platform -eq 'windows') {
        $hasSpawnWindows = $null -ne $Preset.PSObject.Properties['spawnWindows']
        $items = if ($hasSpawnWindows -and $Preset.spawnWindows) { @($Preset.spawnWindows) } else { @($Preset.spawn) }
        return @{ Items = $items; RequiresWsl = $false; Resolved = 'windows' }
    }
    if ($platform -eq 'auto') {
        $prefer = Get-VibeLaunchPresetPlatformPreference -Config $Config
        $wslItems = @($Preset.spawnWsl)
        $winItems = @($Preset.spawnWindows)
        $wslOk = ($wslItems.Count -gt 0) -and (Test-VibeLaunchWslCommand -Name 'hermes' -Config $Config)
        $winOk = ($winItems.Count -gt 0) -and (Test-VibeLaunchWindowsCommand -Name 'hermes')

        if ($prefer -eq 'wsl' -and $wslOk) {
            return @{ Items = $wslItems; RequiresWsl = $true; Resolved = 'wsl' }
        }
        if ($prefer -eq 'windows' -and $winOk) {
            return @{ Items = $winItems; RequiresWsl = $false; Resolved = 'windows' }
        }
        if ($wslOk) {
            return @{ Items = $wslItems; RequiresWsl = $true; Resolved = 'wsl' }
        }
        if ($winOk) {
            return @{ Items = $winItems; RequiresWsl = $false; Resolved = 'windows' }
        }
        throw @(
            'Hermes not found on Windows PATH or in WSL.',
            'Install Hermes Desktop / CLI, or set wsl.user and install hermes in WSL.',
            'Override: vibelaunch hermes windows | vibelaunch hermes wsl'
        ) -join ' '
    }

    $items = @($Preset.spawn)
    $requiresWsl = (($items -join ' ') -match 'wsl\.exe')
    return @{ Items = $items; RequiresWsl = $requiresWsl; Resolved = 'default' }
}

function Get-VibeLaunchPresetPlatformHint {
    param(
        [object]$Preset,
        [hashtable]$Config
    )

    $platform = ''
    if ($Preset.PSObject.Properties['platform']) { $platform = [string]$Preset.platform }
    if ($platform -eq 'auto') {
        $prefer = Get-VibeLaunchPresetPlatformPreference -Config $Config
        $wslOk = ($Preset.spawnWsl) -and (Test-VibeLaunchWslCommand -Name 'hermes' -Config $Config)
        $winOk = ($Preset.spawnWindows) -and (Test-VibeLaunchWindowsCommand -Name 'hermes')
        if ($wslOk -and $winOk) { return "auto (prefers $prefer)" }
        if ($wslOk) { return 'auto -> wsl' }
        if ($winOk) { return 'auto -> windows' }
        return 'auto (hermes not detected)'
    }
    if ($platform) { return $platform }
    if (($Preset.spawn -join ' ') -match 'wsl\.exe') { return 'wsl' }
    return 'windows'
}

function Test-VibeLaunchFirewallBlocks {
    param([string]$VibettyPath)
    try {
        $blocks = @(Get-NetFirewallRule -DisplayName 'vibetty' -ErrorAction SilentlyContinue |
            Where-Object { $_.Action -eq 'Block' -and $_.Direction -eq 'Inbound' })
        if ($blocks.Count -eq 0) {
            return @{ Ok = $true; Message = 'No inbound Block rules named vibetty' }
        }
        return @{
            Ok      = $false
            Message = "Found $($blocks.Count) inbound Block rule(s) for vibetty - Block beats Allow. Remove in elevated PowerShell (see VIBEKEYS_REMOTE.md)."
        }
    } catch {
        return @{ Ok = $true; Message = "Firewall check skipped: $_" }
    }
}

function Invoke-VibeLaunchPreflight {
    param([hashtable]$Config)

    $port = [int]$Config['port']
    $vibettyPath = Expand-VibeLaunchTemplate -Text ([string]$Config['vibettyPath']) -Config $Config
    $lines = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $vibettyPath)) {
        $lines.Add("FAIL vibetty not found: $vibettyPath")
    } else {
        $lines.Add("OK   vibetty: $vibettyPath")
    }

    $listeners = @(Get-VibeLaunchPortListener -Port $port)
    if ($listeners.Count -eq 0) {
        $lines.Add("OK   port $port is free")
    } else {
        $addrs = ($listeners | Select-Object -ExpandProperty LocalAddress -Unique) -join ', '
        $proc = Get-VibeLaunchVibettyProcess -Port $port
        if ($proc) {
            $lines.Add("WARN port $port in use by vibetty PID $($proc.Id) (bind: $addrs)")
        } else {
            $lines.Add("WARN port $port in use (bind: $addrs) but not vibetty - pick another port")
        }
    }

    $codex = Test-VibeLaunchCodexPath
    $lines.Add(("$(if ($codex.Ok) { 'OK  ' } else { 'WARN' }) $($codex.Message)"))

    $fw = Test-VibeLaunchFirewallBlocks -VibettyPath $vibettyPath
    $lines.Add(("$(if ($fw.Ok) { 'OK  ' } else { 'FAIL' }) $($fw.Message)"))

    $url = Get-VibeLaunchKeypadUrl -Config $Config
    $lines.Add("INFO keypad URL: $url")
    $lines.Add("INFO profile: $($Config['profile']) bind $(Get-VibeLaunchBindAddress -Config $Config)")

    if ($Config['wsl'] -and $Config['wsl']['enabled']) {
        $wslTest = & wsl.exe -e true 2>&1
        if ($LASTEXITCODE -eq 0) {
            $lines.Add('OK   WSL available')
        } else {
            $lines.Add("FAIL WSL: $wslTest")
        }

        $wslUser = Test-VibeLaunchWslUserConfigured -Config $Config
        $lines.Add(("$(if ($wslUser.Ok) { 'OK  ' } else { 'FAIL' }) $($wslUser.Message)"))
    }

    $lines -join "`n"
}

function Get-VibeLaunchStatusText {
    param([hashtable]$Config)

    $port = [int]$Config['port']
    $listeners = @(Get-VibeLaunchPortListener -Port $port)
    $state = Get-VibeLaunchActiveState
    $proc = Get-VibeLaunchVibettyProcess -Port $port
    $bind = if ($listeners.Count -gt 0) {
        ($listeners | Select-Object LocalAddress, LocalPort | Format-Table -AutoSize | Out-String).Trim()
    } else {
        '(not listening)'
    }

    $preset = if ($state -and $state['preset']) { $state['preset'] } else { '(unknown)' }
    $pidText = if ($proc) { $proc.Id } else { '-' }

    @(
        "VibeLaunch status",
        "  profile:     $($Config['profile'])",
        "  port:        $port",
        "  preset:      $preset",
        "  vibetty pid: $pidText",
        "  bind:        $bind",
        "  keypad URL:  $(Get-VibeLaunchKeypadUrl -Config $Config)"
    ) -join "`n"
}

function Get-VibeLaunchListText {
    $presets = Get-VibeLaunchPresets
    $cfg = (Get-VibeLaunchConfig).Config
    $default = [string]$cfg['defaultPreset']
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Presets (default: ' + $(if ($default) { $default } else { '(none)' }) + ')') | Out-Null
    $lines.Add('') | Out-Null
    foreach ($entry in ($presets.GetEnumerator() | Sort-Object Name)) {
        $p = $entry.Value
        $tok = if ($p.tokens) { ($p.tokens -join ' ') } else { '-' }
        $label = if ($p.label) { $p.label } else { $entry.Key }
        $plat = Get-VibeLaunchPresetPlatformHint -Preset $p -Config $cfg
        $lines.Add("$($entry.Key)`t$label`t[$tok]`t$plat") | Out-Null
        if ($p.notes) {
            $lines.Add("  $($p.notes)") | Out-Null
        }
    }
    $lines -join "`n"
}

function ConvertTo-VibeLaunchVibettySpawn {
    param([string[]]$SpawnArgv)
    if ($SpawnArgv.Count -eq 0) { return $SpawnArgv }
    # Single command line from vibelaunch run --spawn "..."
    if ($SpawnArgv.Count -eq 1) {
        $line = [string]$SpawnArgv[0]
        if ($line -match '^\s*cmd\.exe\s+/c\s+(.+)$') {
            return @('cmd.exe', '/c', $Matches[1].Trim())
        }
        if ($line -match 'wsl\.exe') {
            return @('cmd.exe', '/c', $line.Trim())
        }
    }
    if ($SpawnArgv.Count -lt 2 -or $SpawnArgv[0] -ne 'wsl.exe') {
        return $SpawnArgv
    }
    # vibetty + Start-Process split argv; bash -lic needs one quoted command string.
    # Match the working manual: wsl.exe -u USER bash -lic "command here"
    if ($SpawnArgv.Count -ge 6 -and $SpawnArgv[3] -eq 'bash' -and $SpawnArgv[4] -eq '-lic') {
        $prefix = ($SpawnArgv[0..4] -join ' ')
        $bashCmd = ($SpawnArgv[5..($SpawnArgv.Count - 1)] -join ' ')
        $line = "$prefix `"$bashCmd`""
        return @('cmd.exe', '/c', $line)
    }
    return @('cmd.exe', '/c', ($SpawnArgv -join ' '))
}

function Build-VibeLaunchSpawnArgv {
    param(
        [object]$Preset,
        [hashtable]$Config,
        [string[]]$ExtraArgs
    )
    $src = Resolve-VibeLaunchPresetSpawnSource -Preset $Preset -Config $Config
    $spawn = Expand-VibeLaunchArray -Items @($src.Items) -Config $Config
    $args = @()
    if ($Preset.args) { $args += Expand-VibeLaunchArray -Items @($Preset.args) -Config $Config }
    if ($ExtraArgs) { $args += $ExtraArgs }

    # Force array semantics: when each side has one item, PowerShell otherwise
    # treats `+` as string concatenation (for example `claude` + `-c`).
    $merged = if ($args.Count -gt 0) { @($spawn) + @($args) } else { @($spawn) }
    return ConvertTo-VibeLaunchVibettySpawn -SpawnArgv @($merged)
}

function Start-VibeLaunchSession {
    param(
        [string]$PresetName,
        [object]$Preset,
        [hashtable]$Config,
        [string[]]$ExtraArgs,
        [switch]$Force,
        [switch]$NoKill,
        [switch]$Wait,
        [switch]$DryRun,
        [int]$ConsoleCols = 0,
        [int]$ConsoleRows = 0,
        [switch]$HideConsole
    )

    $port = [int]$Config['port']
    $existing = Get-VibeLaunchVibettyProcess -Port $port
    if ($existing -and -not $NoKill -and -not $DryRun) {
        if (-not (Test-VibeLaunchConfirmKill -Config $Config -PresetName $PresetName -Preset $Preset -Force:$Force)) {
            Write-Host 'Launch cancelled.'
            return 1
        }
        $null = Stop-VibeLaunchSession -Config $Config -Force
        Start-Sleep -Milliseconds 400
    }

    $vibettyPath = Expand-VibeLaunchTemplate -Text ([string]$Config['vibettyPath']) -Config $Config
    if (-not (Test-Path -LiteralPath $vibettyPath)) {
        throw "vibetty not found: $vibettyPath"
    }

    $bind = Get-VibeLaunchBindAddress -Config $Config
    $spawnArgv = Build-VibeLaunchSpawnArgv -Preset $Preset -Config $Config -ExtraArgs $ExtraArgs

    if (($spawnArgv -join ' ') -match 'wsl\.exe') {
        $wslUser = Test-VibeLaunchWslUserConfigured -Config $Config
        if (-not $wslUser.Ok) {
            throw "Cannot launch '$PresetName': $($wslUser.Message)"
        }
    }

    $cwd = Expand-VibeLaunchTemplate -Text ([string]$Preset.cwd) -Config $Config
    if ([string]::IsNullOrWhiteSpace($cwd)) {
        $cwd = Expand-VibeLaunchTemplate -Text ([string]$Config['cwd']) -Config $Config
    }
    if ([string]::IsNullOrWhiteSpace($cwd)) {
        $cwd = Get-Location
    }
    if (-not (Test-Path -LiteralPath $cwd)) {
        New-Item -ItemType Directory -Path $cwd -Force | Out-Null
    }

    $vibettyArgs = @('--bind-addr', $bind, '--') + $spawnArgv

    if ($DryRun) {
        Write-Host "DRY RUN preset: $PresetName"
        Write-Host "  cwd:   $cwd"
        Write-Host "  cmd:   $vibettyPath --bind-addr $bind -- $($spawnArgv -join ' ')"
        if ($ConsoleCols -gt 0) { Write-Host "  cols:  $ConsoleCols" }
        if ($ConsoleRows -gt 0) { Write-Host "  rows:  $ConsoleRows" }
        if ($HideConsole) { Write-Host '  hide:  vibetty console window' }
        return 0
    }

    Write-Host "Launching preset: $PresetName ($($Preset.label))"
    Write-Host "  keypad: $(Get-VibeLaunchKeypadUrl -Config $Config)"
    Write-Host "  web:    $(Get-VibeLaunchWebUrl -Config $Config)"
    Write-Host "  cwd:    $cwd"
    if ($ConsoleCols -gt 0 -and $ConsoleRows -gt 0) {
        Write-Host "  geometry: ${ConsoleCols}x${ConsoleRows}"
    }

    $needsGeometry = ($ConsoleCols -gt 0 -and $ConsoleRows -gt 0)

    if ($Wait) {
        Push-Location -LiteralPath $cwd
        try {
            Set-VibeLaunchHermesGeometryEnv -Cols $ConsoleCols -Rows $ConsoleRows
            if ($needsGeometry) {
                $console = Get-VibeLaunchConsoleSizeForPty -PtyCols $ConsoleCols -PtyRows $ConsoleRows
                cmd.exe /c "mode con: cols=$($console.Cols) lines=$($console.Rows) >nul 2>&1"
            }
            & $vibettyPath @('--bind-addr', $bind, '--') + $spawnArgv
            $exit = $LASTEXITCODE
        } finally {
            Clear-VibeLaunchHermesGeometryEnv
            Pop-Location
        }
        Clear-VibeLaunchActiveState
        return $exit
    }

    try {
        Set-VibeLaunchHermesGeometryEnv -Cols $ConsoleCols -Rows $ConsoleRows
        $null = Start-VibeLaunchVibettyProcess `
            -VibettyPath $vibettyPath `
            -ArgumentList (@('--bind-addr', $bind, '--') + $spawnArgv) `
            -WorkingDirectory $cwd `
            -ConsoleCols $ConsoleCols `
            -ConsoleRows $ConsoleRows `
            -HideConsole:$HideConsole
    } finally {
        Clear-VibeLaunchHermesGeometryEnv
    }

    Start-Sleep -Milliseconds 1200
    $listener = Get-VibeLaunchVibettyProcess -Port $port
    if ($listener) {
        if ($needsGeometry) {
            # Geometry is applied at spawn via `mode con` (post-attach resize cannot
            # shrink vibetty's buffer). Verify from vibetty's headless conhost args.
            $ok = $false
            $headless = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($listener.Id)" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -match '--headless' -and $_.CommandLine -match '--width' } |
                Select-Object -First 1
            if ($headless -and $headless.CommandLine -match '--width\s+(\d+).*--height\s+(\d+)') {
                $gotCols = [int]$Matches[1]
                $gotRows = [int]$Matches[2]
                # Allow +/-1 for font/chrome rounding; PTY = console - TUI padding.
                $expectCols = $ConsoleCols
                $expectRows = $ConsoleRows
                if ([Math]::Abs($gotCols - $expectCols) -le 2 -and [Math]::Abs($gotRows - $expectRows) -le 2) {
                    $ok = $true
                }
                Write-Host "  pty geometry: ${gotCols}x${gotRows} (requested ${ConsoleCols}x${ConsoleRows})$(if ($ok) { ' ok' } else { ' mismatch' })"
            } else {
                Write-Host "  pty geometry: requested ${ConsoleCols}x${ConsoleRows} (spawned via mode con; verify in preview)"
            }
            if ($ConsoleCols -gt 35) {
                Write-Host '  note: VibeKeys Sync clamps width to 35 cols while the keypad is connected (upstream vibetty)'
            }
        }
        if ($HideConsole) {
            $null = Hide-VibeLaunchProcessWindow -ProcessId $listener.Id
        }
        Set-VibeLaunchActiveState -PresetName $PresetName -Port $port -ProcessId $listener.Id
        Write-Host "vibetty started (PID $($listener.Id)). Logs: vibetty_*.log in $cwd"
        return 0
    }

    Write-Warning 'vibetty exited quickly - run vibelaunch preflight or launch from a fresh shell (Codex PATH).'
    return 1
}

function Invoke-VibeLaunchRunRaw {
    param(
        [string[]]$SpawnParts,
        [string]$Cwd,
        [hashtable]$Config,
        [switch]$Force,
        [switch]$Wait
    )
    if (-not $SpawnParts -or $SpawnParts.Count -eq 0) {
        throw 'run requires --spawn with a command'
    }
    $fake = [pscustomobject]@{
        label = 'raw'
        tags  = @()
        spawn = $SpawnParts
        cwd   = $Cwd
        args  = @()
    }
    return Start-VibeLaunchSession -PresetName 'run' -Preset $fake -Config $Config -Force:$Force -Wait:$Wait
}

function Invoke-VibeLaunchLaunchResolved {
    param(
        [hashtable]$Resolved,
        [hashtable]$Config,
        [hashtable]$Flags
    )

    $opts = Resolve-VibeLaunchLaunchOptions -Flags $Flags -Config $Config
    return Start-VibeLaunchSession -PresetName $Resolved.Name -Preset $Resolved.Preset `
        -Config $Config -ExtraArgs @($Flags.Extra) -Force:([bool]$Flags.Force) -Wait:([bool]$Flags.Wait) `
        -DryRun:([bool]$Flags.DryRun) `
        -ConsoleCols $opts.ConsoleCols -ConsoleRows $opts.ConsoleRows -HideConsole:([bool]$opts.HideConsole)
}

function Invoke-VibeLaunchMain {
    param([string[]]$Arguments)

    $loaded = Get-VibeLaunchConfig
    $cfg = $loaded.Config

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        $flags = Split-VibeLaunchLaunchFlags -Arguments @()
        $resolved = Resolve-VibeLaunchPreset -Arguments @() -Config $cfg
        return Invoke-VibeLaunchLaunchResolved -Resolved $resolved -Config $cfg -Flags $flags
    }

    $cmd = $Arguments[0].ToLowerInvariant()
    $rest = @()
    if ($Arguments.Count -gt 1) { $rest = $Arguments[1..($Arguments.Count - 1)] }

    switch ($cmd) {
        'list' {
            Write-Host (Get-VibeLaunchListText)
            return 0
        }
        'status' {
            if ($rest -contains '--json') {
                Write-Host ((Get-VibeLaunchStatusObject -Config $cfg) | ConvertTo-Json -Depth 6 -Compress)
                return 0
            }
            Write-Host (Get-VibeLaunchStatusText -Config $cfg)
            return 0
        }
        'preflight' {
            if ($rest -contains '--json') {
                Write-Host ((Get-VibeLaunchPreflightObject -Config $cfg) | ConvertTo-Json -Depth 5 -Compress)
                return 0
            }
            Write-Host (Invoke-VibeLaunchPreflight -Config $cfg)
            return 0
        }
        'gui-config' {
            Write-Host ((Get-VibeLaunchMergedGuiSettings -Config $cfg) | ConvertTo-Json -Depth 5 -Compress)
            return 0
        }
        'gui-links' {
            Write-Host ((Get-VibeLaunchGuiLinks) | ConvertTo-Json -Depth 3 -Compress)
            return 0
        }
        'paths' {
            if ($rest -contains '--json') {
                Write-Host ((Get-VibeLaunchPathsObject) | ConvertTo-Json -Depth 3 -Compress)
                return 0
            }
            $po = Get-VibeLaunchPathsObject
            Write-Host (@(
                "Root:                $($po.root)",
                "Config:              $($po.configDir)",
                "Presets:             $($po.presets)",
                "User config:         $($po.userConfigDir)",
                "PTY size presets:    $($po.ptySizePresets)",
                "PTY presets (local): $($po.ptySizePresetsLocal)"
            ) -join "`n")
            return 0
        }
        'gui-save' {
            $cols = 35
            $rows = 200
            $label = 'VibeKeys (35x200)'
            $hide = $true
            $theme = $null
            for ($i = 0; $i -lt $rest.Count; $i++) {
                switch ($rest[$i]) {
                    '--cols' { $i++; $cols = [int]$rest[$i]; continue }
                    '--rows' { $i++; $rows = [int]$rest[$i]; continue }
                    '--label' { $i++; $label = [string]$rest[$i]; continue }
                    '--theme' { $i++; $theme = [string]$rest[$i]; continue }
                    '--hide-console' { $hide = $true; continue }
                    '--show-console' { $hide = $false; continue }
                }
            }
            Set-VibeLaunchGuiLocalSettings -Cols $cols -Rows $rows -SizePresetLabel $label -HideVibettyConsole $hide -Theme $theme
            return 0
        }
        'stop' {
            $force = $rest -contains '--force'
            $stopped = Stop-VibeLaunchSession -Config $cfg -Force:$force
            if ($stopped) { return 0 }
            return 1
        }
        'config' {
            if ($rest.Count -ge 1 -and $rest[0] -eq 'path') {
                $p = Get-VibeLaunchConfigPaths
                Write-Host (@(
                    "Root:         $($p.Root)",
                    "Defaults:     $($p.Defaults)",
                    "Presets:      $($p.Presets)",
                    "PresetsLocal: $($p.PresetsLocal)",
                    "UserDefaults: $($p.UserDefaults)",
                    "State:        $(Get-VibeLaunchStatePath)",
                    "GuiLocal:     $(Get-VibeLaunchGuiLocalPath)"
                ) -join "`n")
                return 0
            }
            throw 'Usage: vibelaunch config path'
        }
        'run' {
            $spawn = $null
            $cwd = $null
            $flags = Split-VibeLaunchLaunchFlags -Arguments $rest
            for ($i = 0; $i -lt $rest.Count; $i++) {
                switch ($rest[$i]) {
                    '--spawn' {
                        $i++
                        if ($i -ge $rest.Count) { throw '--spawn requires a value' }
                        $spawn = @([string]$rest[$i])
                    }
                    '--cwd' {
                        $i++
                        if ($i -ge $rest.Count) { throw '--cwd requires a value' }
                        $cwd = $rest[$i]
                    }
                }
            }
            $opts = Resolve-VibeLaunchLaunchOptions -Flags $flags -Config $cfg
            if (-not $spawn -or $spawn.Count -eq 0) {
                throw 'run requires --spawn with a command'
            }
            $fake = [pscustomobject]@{
                label = 'raw'
                tags  = @()
                spawn = $spawn
                cwd   = $cwd
                args  = @()
            }
            return Start-VibeLaunchSession -PresetName 'run' -Preset $fake -Config $cfg `
                -Force:([bool]$flags.Force) -Wait:([bool]$flags.Wait) `
                -ConsoleCols $opts.ConsoleCols -ConsoleRows $opts.ConsoleRows -HideConsole:([bool]$opts.HideConsole)
        }
        default {
            $flags = Split-VibeLaunchLaunchFlags -Arguments $Arguments
            $resolved = Resolve-VibeLaunchPreset -Arguments @($flags.Positionals) -Config $cfg
            return Invoke-VibeLaunchLaunchResolved -Resolved $resolved -Config $cfg -Flags $flags
        }
    }
}

Export-ModuleMember -Function @(
    'Get-VibeLaunchRoot',
    'Get-VibeLaunchConfig',
    'Get-VibeLaunchConfigPaths',
    'Get-VibeLaunchPresets',
    'Resolve-VibeLaunchPreset',
    'Invoke-VibeLaunchPreflight',
    'Get-VibeLaunchStatusText',
    'Get-VibeLaunchStatusObject',
    'Get-VibeLaunchPreflightObject',
    'Get-VibeLaunchMergedGuiSettings',
    'Get-VibeLaunchGuiLinks',
    'Get-VibeLaunchPtySizePresets',
    'Get-VibeLaunchPathsObject',
    'Test-VibeLaunchKeypadReadiness',
    'Get-VibeLaunchWebUrl',
    'Get-VibeLaunchListText',
    'Stop-VibeLaunchSession',
    'Start-VibeLaunchSession',
    'Invoke-VibeLaunchMain',
    'Get-VibeLaunchKeypadUrl',
    'Save-VibeLaunchPresetLocal',
    'Set-VibeLaunchGuiLocalSettings'
)
