# Apply the WSL / remote-keypad profile for VibeLaunch (non-Admin).
# Writes %LOCALAPPDATA%\VibeLaunch\defaults.local.json, filling in the
# machine-specific values the shipped example ships as placeholders
# (<wsl-user>, <LAN-IP>) so WSL presets (hermes-vk, openclaw-vk, ...) work
# on first run instead of failing on an unresolved placeholder.
#
# Optional params let you script this non-interactively:
#   .\setup-wsl-remote.ps1 -WslUser <wsl-user> -KeypadHost <LAN-IP>

param(
    [string]$WslUser,
    [string]$KeypadHost
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$example = Join-Path $root 'config\defaults.local.json.example'
$destDir = Join-Path $env:LOCALAPPDATA 'VibeLaunch'
$dest = Join-Path $destDir 'defaults.local.json'

if (-not (Test-Path -LiteralPath $example)) {
    throw "Missing $example"
}

$template = Get-Content -LiteralPath $example -Raw -Encoding UTF8 | ConvertFrom-Json

# If a defaults.local.json already exists, use its values as the re-run
# default so re-running this script doesn't blank out a working config.
$existingUser = $null
$existingHost = $null
if (Test-Path -LiteralPath $dest) {
    try {
        $existing = Get-Content -LiteralPath $dest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.wsl -and $existing.wsl.user -and $existing.wsl.user -notmatch '^<.*>$') {
            $existingUser = [string]$existing.wsl.user
        }
        if ($existing.keypadHost -and $existing.keypadHost -notmatch '^<.*>$') {
            $existingHost = [string]$existing.keypadHost
        }
    } catch {
        # Ignore an unreadable/corrupt existing file; prompts below still work.
    }
}

# Best-effort auto-detect suggestions (never fail setup if these don't work).
$suggestedUser = $existingUser
if (-not $suggestedUser) {
    try {
        $whoami = & wsl.exe -e whoami 2>$null
        if ($LASTEXITCODE -eq 0 -and $whoami) { $suggestedUser = ([string]$whoami).Trim() }
    } catch { }
}

$suggestedHost = $existingHost
if (-not $suggestedHost) {
    try {
        $candidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' -and $_.IPAddress -notmatch '^169\.254\.' } |
            Select-Object -First 1 -ExpandProperty IPAddress
        if ($candidate) { $suggestedHost = $candidate }
    } catch { }
}

if (-not $WslUser) {
    $promptSuffix = if ($suggestedUser) { " [$suggestedUser]" } else { '' }
    $input = Read-Host "WSL username for Hermes/OpenClaw presets$promptSuffix"
    $WslUser = if ([string]::IsNullOrWhiteSpace($input)) { $suggestedUser } else { $input.Trim() }
}
if ([string]::IsNullOrWhiteSpace($WslUser)) {
    throw 'wsl.user is required for the wsl-remote profile (Hermes/OpenClaw presets run via WSL). Re-run with -WslUser <name> or answer the prompt.'
}

if (-not $KeypadHost) {
    $promptSuffix = if ($suggestedHost) { " [$suggestedHost]" } else { ' (LAN IP the keypad will connect to)' }
    $input = Read-Host "Keypad host / LAN IP$promptSuffix"
    $KeypadHost = if ([string]::IsNullOrWhiteSpace($input)) { $suggestedHost } else { $input.Trim() }
}
if ([string]::IsNullOrWhiteSpace($KeypadHost)) {
    Write-Warning 'keypadHost left blank -- edit defaults.local.json manually before the keypad can connect remotely.'
    $KeypadHost = 'localhost'
}

$template.keypadHost = $KeypadHost
if (-not $template.wsl) { $template | Add-Member -NotePropertyName wsl -NotePropertyValue ([pscustomobject]@{}) }
$template.wsl.user = $WslUser

# Persist explicit workspace paths so an installed copy (C:\Program Files\
# VibeLaunch, where the repo root can't be derived from the module location)
# still resolves {{workspaces.default}} instead of the shipped placeholder.
# This repo is the parent of the vibelaunch folder.
$repoRoot = Split-Path -Parent $root
$repoWsl = $null
if ($repoRoot -match '^([A-Za-z]):[\\/](.*)$') {
    $repoWsl = "/mnt/$($Matches[1].ToLowerInvariant())/$($Matches[2] -replace '\\','/')"
}
if (-not $template.workspaces) { $template | Add-Member -NotePropertyName workspaces -NotePropertyValue ([pscustomobject]@{}) }
$template.workspaces | Add-Member -NotePropertyName 'default' -NotePropertyValue $repoRoot -Force
if ($repoWsl) { $template.workspaces | Add-Member -NotePropertyName 'default-wsl' -NotePropertyValue $repoWsl -Force }

if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}
($template | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $dest -Encoding UTF8

# Deploy Hermes ACP client into WSL ~/bin so hermes-acp-* presets resolve.
$acpSrc = Join-Path $root 'tools\hermes-acp-client.py'
if (Test-Path -LiteralPath $acpSrc) {
    $wslSrc = $null
    if ($acpSrc -match '^([A-Za-z]):[\\/](.*)$') {
        $wslSrc = "/mnt/$($Matches[1].ToLowerInvariant())/$($Matches[2] -replace '\\','/')"
    }
    if ($wslSrc) {
        & wsl.exe -u $WslUser bash -lic "mkdir -p ~/bin && cp -f '$wslSrc' ~/bin/hermes-acp-client.py && chmod +x ~/bin/hermes-acp-client.py" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Deployed Hermes ACP client -> WSL ~/bin/hermes-acp-client.py"
        } else {
            Write-Warning "Could not deploy hermes-acp-client.py to WSL ~/bin (exit $LASTEXITCODE). Copy tools\hermes-acp-client.py manually."
        }
    }
} else {
    Write-Warning "Missing $acpSrc — Hermes ACP presets will fail until it is installed to WSL ~/bin."
}

Write-Host "Wrote $dest"
Write-Host "  wsl.user:    $WslUser"
Write-Host "  keypadHost:  $KeypadHost"
Write-Host "  workspace:   $repoRoot"
Write-Host 'Run from this folder:  .\vibelaunch.cmd preflight'
Write-Host '  (expect port 3001, WSL enabled, wsl.user OK). After install.ps1, use: vibelaunch preflight'
