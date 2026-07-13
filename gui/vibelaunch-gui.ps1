#Requires -Version 5.1
# VibeLaunch session chooser (WinForms fallback) — shares config/CLI with vibelaunch.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'vibelaunch.ps1'
Import-Module (Join-Path $root 'lib\VibeLaunch.psm1') -Force

function Invoke-VibeLaunchCli {
    param([string[]]$CmdArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $($CmdArgs -join ' ')"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Exit = $p.ExitCode; Out = $stdout; Err = $stderr }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'VibeLaunch (WinForms fallback)'
$form.Size = New-Object System.Drawing.Size(920, 680)
$form.StartPosition = 'CenterScreen'

$list = New-Object System.Windows.Forms.ListBox
$list.Location = New-Object System.Drawing.Point(12, 32)
$list.Size = New-Object System.Drawing.Size(260, 520)
$form.Controls.Add($list)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = 'Presets'
$lbl.Location = New-Object System.Drawing.Point(12, 12)
$form.Controls.Add($lbl)

$output = New-Object System.Windows.Forms.TextBox
$output.Location = New-Object System.Drawing.Point(12, 560)
$output.Size = New-Object System.Drawing.Size(880, 100)
$output.Multiline = $true
$output.ScrollBars = 'Vertical'
$output.ReadOnly = $true
$output.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($output)

$fields = @{}
$fieldNames = @('Name', 'Label', 'Tokens', 'Cwd', 'Spawn', 'Notes')
$y = 32
foreach ($name in $fieldNames) {
    $lab = New-Object System.Windows.Forms.Label
    $lab.Text = $name
    $lab.Location = New-Object System.Drawing.Point(290, $y)
    $lab.Size = New-Object System.Drawing.Size(70, 20)
    $form.Controls.Add($lab)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(360, $y)
    if ($name -in @('Spawn', 'Notes')) {
        $box.Size = New-Object System.Drawing.Size(530, 48)
        $box.Multiline = $true
        $y += 52
    } else {
        $box.Size = New-Object System.Drawing.Size(530, 20)
        $y += 28
    }
    $form.Controls.Add($box)
    $fields[$name] = $box
}

function Refresh-PresetList {
    $list.Items.Clear()
    $presets = Get-VibeLaunchPresets
    foreach ($name in ($presets.Keys | Sort-Object)) {
        $p = $presets[$name]
        $label = if ($p.label) { "$name - $($p.label)" } else { $name }
        [void]$list.Items.Add($label)
    }
}

function Show-PresetDetails {
    param([string]$Name)
    $presets = Get-VibeLaunchPresets
    if (-not $presets.ContainsKey($Name)) { return }
    $p = $presets[$Name]
    $fields['Name'].Text = $Name
    $fields['Label'].Text = [string]$p.label
    $fields['Tokens'].Text = if ($p.tokens) { ($p.tokens -join ' ') } else { '' }
    $fields['Cwd'].Text = [string]$p.cwd
    $fields['Spawn'].Text = if ($p.spawn) { ($p.spawn -join ' ') } else { '' }
    $fields['Notes'].Text = [string]$p.notes
}

$list.Add_SelectedIndexChanged({
    $item = [string]$list.SelectedItem
    if (-not $item) { return }
    $idx = $item.IndexOf(' - ')
    $name = if ($idx -gt 0) { $item.Substring(0, $idx) } else { $item }
    Show-PresetDetails -Name $name
})

function Append-Output([string]$Text) {
    $output.AppendText($Text + [Environment]::NewLine)
}

function Run-AndShow {
    param([string]$Heading, [string[]]$CmdArgs)
    Append-Output "> $Heading"
    $r = Invoke-VibeLaunchCli -CmdArgs $CmdArgs
    if ($r.Out) { Append-Output $r.Out.TrimEnd() }
    if ($r.Err) { Append-Output $r.Err.TrimEnd() }
    Append-Output "(exit $($r.Exit))"
}

$launchBtn = New-Object System.Windows.Forms.Button
$launchBtn.Text = 'Launch'
$launchBtn.Location = New-Object System.Drawing.Point(290, 280)
$launchBtn.Size = New-Object System.Drawing.Size(100, 28)
$launchBtn.Add_Click({
    $name = $fields['Name'].Text.Trim()
    if (-not $name) { return }
    Run-AndShow "launch $name" @($name, '--force', '--gui')
})
$form.Controls.Add($launchBtn)

$browserBtn = New-Object System.Windows.Forms.Button
$browserBtn.Text = 'Open browser'
$browserBtn.Location = New-Object System.Drawing.Point(398, 320)
$browserBtn.Size = New-Object System.Drawing.Size(100, 28)
$browserBtn.Add_Click({
    $cfg = (Get-VibeLaunchConfig).Config
    Start-Process (Get-VibeLaunchWebUrl -Config $cfg)
})
$form.Controls.Add($browserBtn)

$defaultBtn = New-Object System.Windows.Forms.Button
$defaultBtn.Text = 'Launch default'
$defaultBtn.Location = New-Object System.Drawing.Point(398, 280)
$defaultBtn.Size = New-Object System.Drawing.Size(100, 28)
$defaultBtn.Add_Click({ Run-AndShow 'default' @('--force', '--gui') })
$form.Controls.Add($defaultBtn)

$stopBtn = New-Object System.Windows.Forms.Button
$stopBtn.Text = 'Stop'
$stopBtn.Location = New-Object System.Drawing.Point(506, 280)
$stopBtn.Size = New-Object System.Drawing.Size(100, 28)
$stopBtn.Add_Click({ Run-AndShow 'stop' @('stop', '--force') })
$form.Controls.Add($stopBtn)

$statusBtn = New-Object System.Windows.Forms.Button
$statusBtn.Text = 'Status'
$statusBtn.Location = New-Object System.Drawing.Point(614, 280)
$statusBtn.Size = New-Object System.Drawing.Size(100, 28)
$statusBtn.Add_Click({ Run-AndShow 'status' @('status') })
$form.Controls.Add($statusBtn)

$preflightBtn = New-Object System.Windows.Forms.Button
$preflightBtn.Text = 'Preflight'
$preflightBtn.Location = New-Object System.Drawing.Point(722, 280)
$preflightBtn.Size = New-Object System.Drawing.Size(100, 28)
$preflightBtn.Add_Click({ Run-AndShow 'preflight' @('preflight') })
$form.Controls.Add($preflightBtn)

$saveBtn = New-Object System.Windows.Forms.Button
$saveBtn.Text = 'Save local'
$saveBtn.Location = New-Object System.Drawing.Point(290, 320)
$saveBtn.Size = New-Object System.Drawing.Size(100, 28)
$saveBtn.Add_Click({
    $name = $fields['Name'].Text.Trim()
    if (-not $name) { return }
    $presets = Get-VibeLaunchPresets
    $spawn = @()
    if ($presets.ContainsKey($name) -and $presets[$name].spawn) {
        $spawn = @($presets[$name].spawn)
    }
    Save-VibeLaunchPresetLocal -Name $name `
        -Label $fields['Label'].Text.Trim() `
        -Tokens @($fields['Tokens'].Text.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) `
        -Spawn $spawn `
        -Cwd $fields['Cwd'].Text.Trim() `
        -Notes $fields['Notes'].Text.Trim()
    Refresh-PresetList
    Append-Output "Saved preset to presets.local.json: $name"
})
$form.Controls.Add($saveBtn)

Refresh-PresetList
[void]$form.ShowDialog()
