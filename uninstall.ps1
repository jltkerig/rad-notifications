<#
.SYNOPSIS
Removes the rad-notifications hooks from Claude Code (and the PATH entry). Files stay unless -RemoveFiles is given.
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'rad-notifications'),
    [string]$ClaudeSettings = (Join-Path $HOME '.claude\settings.json'),
    [switch]$RemoveFiles
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\claude-hooks.ps1')
$InstallDir = [IO.Path]::GetFullPath($InstallDir)

if (Remove-RadClaudeHooks $ClaudeSettings) { Write-Host "Removed the hooks from $ClaudeSettings (backup saved next to it)." }
else { Write-Host 'No rad-notifications hooks were found in the Claude Code settings.' }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $InstallDir })
if ($parts.Count -ne @($userPath -split ';' | Where-Object { $_ }).Count) {
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    Write-Host 'Removed the install folder from your PATH.'
}

if ($RemoveFiles -and (Test-Path -LiteralPath $InstallDir)) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "Deleted $InstallDir"
} else { Write-Host "Files kept in $InstallDir (use -RemoveFiles to delete them, including your settings.json)." }
