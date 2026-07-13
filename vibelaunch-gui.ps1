# Launch VibeLaunch GUI (use from PowerShell; vibelaunch-gui.cmd works from CMD)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$exeDir = Join-Path $root 'gui\VibeLaunchGui.Fluent\bin\Release\net8.0-windows'
$exe = Join-Path $exeDir 'VibeLaunchGui.Fluent.exe'

if (Test-Path -LiteralPath $exe) {
    Start-Process -FilePath $exe -WorkingDirectory $exeDir
    exit 0
}

$fallback = Join-Path $root 'gui\vibelaunch-gui.ps1'
if (Test-Path -LiteralPath $fallback) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fallback
    exit $LASTEXITCODE
}

Write-Error "VibeLaunch GUI not built. Run: dotnet build gui\VibeLaunchGui.Fluent\VibeLaunchGui.Fluent.csproj -c Release"
