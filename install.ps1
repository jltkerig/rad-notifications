<#
.SYNOPSIS
Installs rad-notifications for the current user and (by default) hooks it into Claude Code.

.PARAMETER InstallDir
Where to put it. Default: %LOCALAPPDATA%\rad-notifications
.PARAMETER ClaudeSettings
The Claude Code settings file to add the hooks to. Default: ~\.claude\settings.json
.PARAMETER NoClaudeHooks
Install only; leave Claude Code alone (use rad-notify from any other tool).
.PARAMETER AddToPath
Add the install folder to your user PATH so "rad-notify" works from any terminal.
.PARAMETER NoTest
Do not show the test popup at the end.
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'rad-notifications'),
    [string]$ClaudeSettings = (Join-Path $HOME '.claude\settings.json'),
    [switch]$NoClaudeHooks,
    [switch]$AddToPath,
    [switch]$NoTest
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\claude-hooks.ps1')

$source = $PSScriptRoot
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
Write-Host "Installing rad-notifications to $InstallDir"

if ($source -ne $InstallDir) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($item in 'rad-notify.ps1', 'rad-notify.cmd', 'defaults.json', 'README.md', 'lib', 'adapters', 'tests') {
        if (Test-Path -LiteralPath (Join-Path $source $item)) { Copy-Item -LiteralPath (Join-Path $source $item) -Destination $InstallDir -Recurse -Force }
    }
    $sounds = Join-Path $source 'sounds'
    if (Test-Path -LiteralPath $sounds) {
        New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'sounds') | Out-Null
        Get-ChildItem -LiteralPath $sounds | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallDir "sounds\$($_.Name)")) } |
            Copy-Item -Destination (Join-Path $InstallDir 'sounds')
    }
}

& (Join-Path $InstallDir 'lib\make-sounds.ps1')

$userSettings = Join-Path $InstallDir 'settings.json'
if (-not (Test-Path -LiteralPath $userSettings)) { [IO.File]::WriteAllText($userSettings, "{}`n") }

if (-not $NoClaudeHooks) {
    Add-RadClaudeHooks $ClaudeSettings (Join-Path $InstallDir 'adapters\claude-code.ps1')
    Write-Host "Added the Notification, Stop and UserPromptSubmit hooks to $ClaudeSettings (backup saved next to it)."
}

if ($AddToPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';') -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $InstallDir), 'User')
        Write-Host "Added $InstallDir to your PATH. Open a new terminal to use: rad-notify"
    }
}

if (-not $NoTest) {
    & (Join-Path $InstallDir 'rad-notify.ps1') -Event done -Title 'rad-notifications' -Message 'Installed. This is how a popup looks.' -Note "Change the look in $userSettings"
}
Write-Host 'Done. Edit settings.json in the install folder to customize; see README.md for every option.'
