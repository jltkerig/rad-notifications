# Shared code: settings, templates, turning a request into a popup spec, and starting the popup.
# Dot-source this file; it only defines functions. Keep it ASCII (Windows PowerShell 5.1 reads files without a BOM as ANSI).

$script:RadRoot = Split-Path -Parent $PSScriptRoot
$script:SlotCount = 8

function ConvertTo-RadHashtable($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $table = @{}
        foreach ($property in $Value.PSObject.Properties) { $table[$property.Name] = ConvertTo-RadHashtable $property.Value }
        return $table
    }
    if ($Value -is [System.Collections.IList]) {
        return , @($Value | ForEach-Object { ConvertTo-RadHashtable $_ })
    }
    return $Value
}

function Merge-RadHashtable($Base, $Over) {
    $merged = @{}
    foreach ($key in $Base.Keys) { $merged[$key] = $Base[$key] }
    foreach ($key in $Over.Keys) {
        if ($merged[$key] -is [hashtable] -and $Over[$key] -is [hashtable]) { $merged[$key] = Merge-RadHashtable $merged[$key] $Over[$key] }
        else { $merged[$key] = $Over[$key] }
    }
    return $merged
}

function Read-RadJsonFile($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if (-not $text.Trim()) { return @{} }
    return ConvertTo-RadHashtable (ConvertFrom-Json $text)
}

function Write-RadLog($Message) {
    try {
        $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message
        Add-Content -LiteralPath (Join-Path $script:RadRoot 'rad-notify.log') -Value $line -Encoding UTF8
    } catch { [Console]::Error.WriteLine("rad-notify: $Message") }
}

# defaults.json is shipped and never edited; settings.json holds only what the user changed (RAD_NOTIFY_SETTINGS can point elsewhere).
function Get-RadSettings {
    $defaults = Read-RadJsonFile (Join-Path $script:RadRoot 'defaults.json')
    $userFile = if ($env:RAD_NOTIFY_SETTINGS) { $env:RAD_NOTIFY_SETTINGS } else { Join-Path $script:RadRoot 'settings.json' }
    try { $user = Read-RadJsonFile $userFile }
    catch { Write-RadLog "settings.json could not be read, using the defaults: $($_.Exception.Message)"; $user = @{} }
    return Merge-RadHashtable $defaults $user
}

function Expand-RadTemplate([string]$Template, $Variables) {
    if (-not $Template) { return '' }
    return [regex]::Replace($Template, '\{(\w+)\}', {
        param($match)
        $value = $Variables[$match.Groups[1].Value]
        if ($null -eq $value) { '' } else { [string]$value }
    }).Trim()
}

function Resolve-RadSound([string]$Sound) {
    if (-not $Sound -or $Sound -eq 'none') { return '' }
    $candidates = @($Sound, (Join-Path $script:RadRoot $Sound), (Join-Path $script:RadRoot "sounds\$Sound.wav"), (Join-Path $script:RadRoot "sounds\$Sound.mp3"))
    foreach ($candidate in $candidates) {
        if ([IO.Path]::IsPathRooted($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    Write-RadLog "Sound not found: $Sound"
    return ''
}

# A request is a hashtable: event, title/message/note (literal text, may use {variables}), vars (for the templates),
# sound, volume, duration, theme, colors, popup. Anything given in the request wins over the event's settings.
function Resolve-RadSpec($Request, $Settings) {
    $eventName = if ($Request.event) { [string]$Request.event } else { 'info' }
    $event = $Settings.events[$eventName]
    if (-not $event) { $event = $Settings.events['info']; $eventName = 'info' }
    $event = Merge-RadHashtable $Settings.events['info'] $event   # an event you add only needs the keys that differ from info

    $variables = @{ event = $eventName; time = (Get-Date -Format 'HH:mm'); date = (Get-Date -Format 'yyyy-MM-dd') }
    foreach ($key in @($Request.vars.Keys)) { $variables[$key] = $Request.vars[$key] }
    foreach ($key in 'title', 'message', 'note') { if ($Request[$key]) { $variables[$key] = $Request[$key] } }

    $pick = { param($key) if ($Request[$key]) { $Request[$key] } else { $event[$key] } }
    $title = Expand-RadTemplate (& $pick 'title') $variables
    $variables['title'] = $title
    $message = Expand-RadTemplate (& $pick 'message') $variables
    $variables['message'] = $message
    $note = Expand-RadTemplate (& $pick 'note') $variables

    $themeName = if ($Request.theme) { $Request.theme } elseif ($event.theme) { $event.theme } else { $Settings.theme }
    $theme = $Settings.themes[$themeName]
    if (-not $theme) { Write-RadLog "Unknown theme '$themeName', using dark"; $theme = $Settings.themes['dark'] }
    $colors = Merge-RadHashtable $theme $(if ($event.colors) { $event.colors } else { @{} })
    if ($Request.colors) { $colors = Merge-RadHashtable $colors $Request.colors }

    $popup = Merge-RadHashtable $Settings.popup $(if ($event.popup) { $event.popup } else { @{} })
    if ($Request.popup) { $popup = Merge-RadHashtable $popup $Request.popup }

    $duration = if ($null -ne $Request.duration) { $Request.duration } else { $event.duration }
    $volume = if ($null -ne $Request.volume) { $Request.volume } elseif ($null -ne $event.volume) { $event.volume } else { 1.0 }
    $enabled = if ($null -ne $event.enabled) { [bool]$event.enabled } else { $true }
    $soundName = if ($null -ne $Request.sound) { $Request.sound } else { $event.sound }

    return @{
        event = $eventName; enabled = $enabled; title = $title; message = $message; note = $note
        sound = (Resolve-RadSound ([string]$soundName)); volume = [double]$volume; duration = [double]$duration
        colors = $colors; popup = $popup
        focusTargets = @($Request.vars.workspace, $Request.vars.folder | Where-Object { $_ })
    }
}

function Start-RadPopup($Spec, [switch]$Wait, [string]$Screenshot) {
    $specFile = Join-Path ([IO.Path]::GetTempPath()) ("rad-notify-{0}.json" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($specFile, (ConvertTo-Json $Spec -Depth 10), (New-Object Text.UTF8Encoding($false)))
    $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$(Join-Path $script:RadRoot 'lib\popup.ps1')`" -SpecFile `"$specFile`""
    if ($Screenshot) { $arguments += " -Screenshot `"$Screenshot`"" }
    $info = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', $arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($info)
    if ($Wait -or $Screenshot) { $process.WaitForExit() }
}

# Sends one notification. Returns the resolved spec (handy for -DryRun and tests).
function Send-RadNotification($Request, [switch]$DryRun, [switch]$Wait, [string]$Screenshot) {
    $settings = Get-RadSettings
    $spec = Resolve-RadSpec $Request $settings
    if ($DryRun -or -not $spec.enabled) { return $spec }
    Start-RadPopup $spec -Wait:$Wait -Screenshot $Screenshot
    return $spec
}
