<#
.SYNOPSIS
Shows a popup notification. Any AI assistant, script or tool that can run a command can call this.

.EXAMPLE
rad-notify -Event done -Title "Build" -Message "All tests passed" -Note "Took 42 seconds"

.EXAMPLE
'{"event":"attention","message":"Waiting for your OK","duration":0,"colors":{"accent":"#FF00AA"}}' | rad-notify -Stdin

.NOTES
Event picks the look and defaults (done, attention, error, info, or any event you add to settings.json).
Everything given here overrides the event's settings. See README.md for every option.
#>
param(
    [string]$Event = 'info',
    [string]$Title,
    [string]$Message,
    [string]$Note,
    [string]$Sound,
    [double]$Volume = -1,
    [double]$Duration = -1,
    [string]$Theme,
    [string]$Accent,
    [string]$Background,
    [string]$TextColor,
    [string]$Position,
    [string]$Workspace,
    [string]$Folder,
    [switch]$Stdin,
    [switch]$DryRun,
    [switch]$Wait,
    [string]$Screenshot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\core.ps1')

function Read-RadStdin {
    $reader = New-Object IO.StreamReader ([Console]::OpenStandardInput()), (New-Object Text.UTF8Encoding($false))
    return $reader.ReadToEnd().TrimStart([char]0xFEFF)
}

function New-RadRequestFromJson([string]$Text) {
    if (-not $Text.Trim()) { throw 'rad-notify -Stdin got no input.' }
    return ConvertTo-RadHashtable (ConvertFrom-Json $Text)
}

$bound = $PSBoundParameters
$request = if ($Stdin) { New-RadRequestFromJson (Read-RadStdin) } else { @{} }
if (-not $request.vars) { $request.vars = @{} }

if ($bound.ContainsKey('Event')) { $request.event = $Event }
foreach ($pair in @(@('Title', 'title'), @('Message', 'message'), @('Note', 'note'), @('Theme', 'theme'))) {
    if ($bound.ContainsKey($pair[0])) { $request[$pair[1]] = $bound[$pair[0]] }
}
if ($bound.ContainsKey('Sound')) { $request.sound = $Sound }
if ($bound.ContainsKey('Volume')) { $request.volume = $Volume }
if ($bound.ContainsKey('Duration')) { $request.duration = $Duration }
if ($bound.ContainsKey('Workspace')) { $request.vars.workspace = $Workspace }
if ($bound.ContainsKey('Folder')) { $request.vars.folder = $Folder }
foreach ($pair in @(@('Accent', 'accent'), @('Background', 'background'), @('TextColor', 'text'))) {
    if (-not $bound.ContainsKey($pair[0])) { continue }
    if (-not $request.colors) { $request.colors = @{} }
    $request.colors[$pair[1]] = $bound[$pair[0]]
}
if ($bound.ContainsKey('Position')) {
    if (-not $request.popup) { $request.popup = @{} }
    $request.popup.position = $Position
}
if (-not $request.vars.workspace -and -not $request.vars.folder) { $request.vars.folder = '' }

try {
    $spec = Send-RadNotification $request -DryRun:$DryRun -Wait:$Wait -Screenshot $Screenshot
    if ($DryRun) { ConvertTo-Json $spec -Depth 10 }
} catch {
    Write-RadLog "rad-notify failed: $($_.Exception.Message)"
    throw
}
