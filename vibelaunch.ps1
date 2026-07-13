#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\VibeLaunch.psm1') -Force
$results = @(Invoke-VibeLaunchMain -Arguments @($args))
$exitCode = ($results | Where-Object { $_ -is [int] } | Select-Object -Last 1)
if ($null -eq $exitCode) { $exitCode = 0 }
exit $exitCode
