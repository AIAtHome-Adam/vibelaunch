# Install VibeLaunch to C:\Program Files\VibeLaunch\
# Run as Administrator:
#   & "...\vibelaunch\install.ps1"

$ErrorActionPreference = 'Stop'

$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DestRoot   = 'C:\Program Files\VibeLaunch'

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Ensure-Dir $DestRoot

foreach ($item in @(
        'vibelaunch.ps1',
        'vibelaunch.cmd',
        'vibelaunch-gui.cmd',
        'vibelaunch-gui.ps1',
        'lib',
        'config',
        'schemas',
        'gui',
        'tools',
        'docs',
        'skills'
    )) {
    $src = Join-Path $SourceRoot $item
    $dst = Join-Path $DestRoot $item
    if (-not (Test-Path -LiteralPath $src)) { continue }
    if (Test-Path -LiteralPath $dst) {
        Remove-Item -LiteralPath $dst -Recurse -Force
    }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    Write-Host "Installed $item"
}

# WPF GUI (Release build)
$guiSrc = Join-Path $SourceRoot 'gui\VibeLaunchGui.Fluent\bin\Release\net8.0-windows'
if (Test-Path -LiteralPath (Join-Path $guiSrc 'VibeLaunchGui.Fluent.exe')) {
    $guiDst = Join-Path $DestRoot 'gui\VibeLaunchGui.Fluent\bin\Release\net8.0-windows'
    Ensure-Dir $guiDst
    Copy-Item -LiteralPath "$guiSrc\*" -Destination $guiDst -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $guiSrc 'VibeLaunchGui.Fluent.exe') -Destination (Join-Path $DestRoot 'gui\VibeLaunchGui.Fluent.exe') -Force
    Write-Host 'Installed gui\VibeLaunchGui.Fluent.exe (WPF)'
}

# User PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ -and ($_ -ne $DestRoot) })
if ($parts -notcontains $DestRoot) {
    $parts = @($DestRoot) + $parts
}
$newPath = ($parts -join ';').TrimEnd(';')
[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

Write-Host ''
Write-Host "VibeLaunch installed to $DestRoot"
Write-Host 'Open a NEW terminal, then: vibelaunch list'
Write-Host ''
Write-Host 'WSL profile + Hermes ACP client deploy:'
Write-Host '  .\setup-wsl-remote.ps1   (or copy tools\hermes-acp-client.py -> WSL ~/bin/)'
Write-Host 'WSL profile overlay: %LOCALAPPDATA%\VibeLaunch\defaults.local.json'
Write-Host '  or set "profile": "wsl-remote" after editing install copy.'
