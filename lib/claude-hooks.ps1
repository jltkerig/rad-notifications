# Adds and removes this tool's entries in a Claude Code settings.json. Only entries that run adapters\claude-code.ps1
# are touched; every other hook and setting is left as it is. The file is backed up before the first change.
# Dot-source this file; it only defines functions. Keep it ASCII.

$script:HookEvents = 'Notification', 'Stop', 'UserPromptSubmit'
$script:AdapterPattern = 'adapters[\\/]claude-code\.ps1'

function Read-ClaudeSettings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return (ConvertFrom-Json '{}') }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if (-not $text.Trim()) { return (ConvertFrom-Json '{}') }
    return ConvertFrom-Json $text
}

function Save-ClaudeSettings([string]$Path, $Settings) {
    $json = ConvertTo-Json -InputObject $Settings -Depth 32
    $json = $json -replace '\\u0026', '&' -replace '\\u003c', '<' -replace '\\u003e', '>' -replace '\\u0027', "'"
    ConvertFrom-Json $json | Out-Null   # never write a file that does not parse
    if (Test-Path -LiteralPath $Path) {
        $backup = "$Path.rad-backup-{0:yyyyMMdd-HHmmss}" -f (Get-Date)
        Copy-Item -LiteralPath $Path -Destination $backup
    } else { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null }
    [IO.File]::WriteAllText($Path, $json + "`n", (New-Object Text.UTF8Encoding($false)))
}

function Test-IsRadGroup($Group) {
    foreach ($entry in @($Group.hooks)) { if ($entry.command -match $script:AdapterPattern) { return $true } }
    return $false
}

function Remove-RadGroups($Settings) {
    if (-not $Settings.hooks) { return }
    foreach ($name in $script:HookEvents) {
        if (-not $Settings.hooks.PSObject.Properties[$name]) { continue }
        $kept = @($Settings.hooks.$name | Where-Object { -not (Test-IsRadGroup $_) })
        if ($kept.Count) { $Settings.hooks.$name = $kept } else { $Settings.hooks.PSObject.Properties.Remove($name) }
    }
}

function Add-RadClaudeHooks([string]$SettingsPath, [string]$AdapterPath) {
    $settings = Read-ClaudeSettings $SettingsPath
    if (-not $settings.PSObject.Properties['hooks']) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
    Remove-RadGroups $settings
    $command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$AdapterPath`""
    foreach ($name in $script:HookEvents) {
        $group = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $command; timeout = 10 }) }
        $existing = if ($settings.hooks.PSObject.Properties[$name]) { @($settings.hooks.$name) } else { @() }
        $all = @($existing) + @($group)
        if ($settings.hooks.PSObject.Properties[$name]) { $settings.hooks.$name = $all }
        else { $settings.hooks | Add-Member -NotePropertyName $name -NotePropertyValue $all }
    }
    Save-ClaudeSettings $SettingsPath $settings
}

function Remove-RadClaudeHooks([string]$SettingsPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return $false }
    $settings = Read-ClaudeSettings $SettingsPath
    $before = ConvertTo-Json -InputObject $settings -Depth 32
    Remove-RadGroups $settings
    if ((ConvertTo-Json -InputObject $settings -Depth 32) -eq $before) { return $false }
    if ($settings.hooks -and -not @($settings.hooks.PSObject.Properties).Count) { $settings.PSObject.Properties.Remove('hooks') }
    Save-ClaudeSettings $SettingsPath $settings
    return $true
}
