# Tests for rad-notifications. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-RadNotifications.ps1
# Everything runs against temporary folders: it never reads or writes your real settings or Claude Code settings.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\core.ps1')
. (Join-Path $root 'lib\claude-hooks.ps1')

$script:failures = 0
$script:passed = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ("$Actual" -ceq "$Expected") { $script:passed++; return }
    $script:failures++
    Write-Host "FAIL: $Name`n  expected: $Expected`n  actual:   $Actual" -ForegroundColor Red
}
function Assert-True($Condition, [string]$Name) { Assert-Equal ([bool]$Condition) $true $Name }

$temp = Join-Path ([IO.Path]::GetTempPath()) ("rad-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$savedEnv = $env:RAD_NOTIFY_SETTINGS

try {
    # ---- settings, templates and specs ----
    $env:RAD_NOTIFY_SETTINGS = Join-Path $temp 'none.json'
    $settings = Get-RadSettings
    Assert-Equal $settings.theme 'dark' 'default theme'
    Assert-Equal $settings.events.done.duration 8 'default done duration'

    $request = @{ event = 'done'; vars = @{ workspace = 'programs'; message = 'ok'; task = 'Build it' } }
    $spec = Resolve-RadSpec $request $settings
    Assert-Equal $spec.title 'programs: Finished' 'title template'
    Assert-Equal $spec.message 'ok' 'message template'
    Assert-Equal $spec.note 'Build it' 'note template'
    Assert-Equal $spec.colors.accent '#22C55E' 'event color over theme'
    Assert-Equal $spec.colors.background '#1F2430' 'theme color kept'
    Assert-True (Test-Path -LiteralPath $spec.sound) 'built-in sound name resolves to a file'

    $spec = Resolve-RadSpec @{ event = 'nope'; message = 'hi'; vars = @{} } $settings
    Assert-Equal $spec.event 'info' 'unknown event falls back to info'

    $spec = Resolve-RadSpec @{ event = 'done'; title = 'Mine'; duration = 0; sound = 'none'; theme = 'light'; colors = @{ accent = '#FF00AA' }; popup = @{ position = 'top-left' }; vars = @{} } $settings
    Assert-Equal $spec.title 'Mine' 'request title wins'
    Assert-Equal $spec.duration 0 'request duration wins'
    Assert-Equal $spec.sound '' 'sound none'
    Assert-Equal $spec.colors.background '#FFFFFF' 'request theme wins'
    Assert-Equal $spec.colors.accent '#FF00AA' 'request color wins'
    Assert-Equal $spec.popup.position 'top-left' 'request popup option wins'

    Set-Content -LiteralPath (Join-Path $temp 'custom.json') -Value '{ "events": { "deploy": { "title": "Deploy", "colors": { "accent": "#00FFAA" } } } }'
    $env:RAD_NOTIFY_SETTINGS = Join-Path $temp 'custom.json'
    $spec = Resolve-RadSpec @{ event = 'deploy'; message = 'live'; vars = @{} } (Get-RadSettings)
    Assert-Equal $spec.event 'deploy' 'a custom event keeps its name'
    Assert-Equal $spec.title 'Deploy' 'custom event title'
    Assert-Equal $spec.duration 6 'a custom event inherits info duration, not zero'
    Assert-Equal $spec.colors.accent '#00FFAA' 'custom event color'

    # a user settings file overrides only what it names
    Set-Content -LiteralPath (Join-Path $temp 'user.json') -Value '{ "theme": "forest", "events": { "done": { "title": "All done", "enabled": false } }, "popup": { "width": 500 } }'
    $env:RAD_NOTIFY_SETTINGS = Join-Path $temp 'user.json'
    $settings = Get-RadSettings
    $spec = Resolve-RadSpec @{ event = 'done'; vars = @{} } $settings
    Assert-Equal $spec.title 'All done' 'user title override'
    Assert-Equal $spec.enabled $false 'user can disable an event'
    Assert-Equal $spec.popup.width 500 'user popup override'
    Assert-Equal $spec.popup.height $null 'untouched defaults stay'
    Assert-Equal $settings.events.done.sound 'done' 'sibling default kept after override'
    Assert-Equal $settings.themes.dark.accent '#4F8CFF' 'themes survive override'

    # the same settings, with notes and sounds changed per event
    Set-Content -LiteralPath (Join-Path $temp 'notes.json') -Value '{ "events": { "attention": { "title": "STOP {workspace}", "note": "Look at {folder} at {time}", "sound": "none", "duration": 30 } } }'
    $env:RAD_NOTIFY_SETTINGS = Join-Path $temp 'notes.json'
    $spec = Resolve-RadSpec @{ event = 'attention'; vars = @{ workspace = 'w'; folder = 'f' } } (Get-RadSettings)
    Assert-Equal $spec.title 'STOP w' 'custom title'
    Assert-True ($spec.note -match '^Look at f at \d\d:\d\d$') 'custom note with variables'
    Assert-Equal $spec.sound '' 'event sound turned off'
    Assert-Equal $spec.duration 30 'event duration'

    # ---- command line ----
    $env:RAD_NOTIFY_SETTINGS = Join-Path $temp 'none.json'
    $dry = & (Join-Path $root 'rad-notify.ps1') -Event error -Message 'Boom' -Accent '#123456' -Duration 3 -DryRun | ConvertFrom-Json
    Assert-Equal $dry.event 'error' 'cli event'
    Assert-Equal $dry.message 'Boom' 'cli message'
    Assert-Equal $dry.colors.accent '#123456' 'cli accent'
    Assert-Equal $dry.duration 3 'cli duration'
    $dry = '{"event":"attention","message":"From json","colors":{"accent":"#FF00AA"},"duration":0}' | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'rad-notify.ps1') -Stdin -DryRun | ConvertFrom-Json
    Assert-Equal $dry.message 'From json' 'stdin json message'
    Assert-Equal $dry.colors.accent '#FF00AA' 'stdin json color'
    Assert-Equal $dry.duration 0 'stdin json duration'

    # ---- the popup draws ----
    $png = Join-Path $temp 'shot.png'
    & (Join-Path $root 'rad-notify.ps1') -Event done -Title 'Test' -Message 'A message' -Note 'A note' -Screenshot $png
    Assert-True ((Test-Path -LiteralPath $png) -and (Get-Item -LiteralPath $png).Length -gt 1000) 'popup renders to a png'

    # ---- built-in sounds ----
    foreach ($name in 'done', 'attention', 'error', 'info') {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $root "sounds\$name.wav"))
        Assert-True ($bytes.Length -gt 1000 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'RIFF') "sound $name is a wav"
    }

    # ---- Claude Code adapter ----
    $workspaces = Join-Path $temp 'workspaces'
    New-Item -ItemType Directory -Force -Path $workspaces, (Join-Path $temp 'projects\app\sub'), (Join-Path $temp 'projects\other') | Out-Null
    Set-Content -LiteralPath (Join-Path $workspaces 'my-app.code-workspace') -Value "{`n  // comment`n  `"folders`": [ { `"path`": `"../projects/app`", }, ],`n}"
    $workspacesJson = $workspaces.Replace('\', '\\')
    Set-Content -LiteralPath (Join-Path $temp 'claude.json') -Value "{ `"claudeCode`": { `"workspacesFolder`": `"$workspacesJson`", `"finishOnlyAfterKeyword`": `"update`" } }"
    $env:RAD_NOTIFY_SETTINGS = Join-Path $temp 'claude.json'
    $adapter = Join-Path $root 'adapters\claude-code.ps1'
    function Invoke-Adapter($Hook) {
        $json = $Hook | ConvertTo-Json -Compress
        $output = $json | & powershell -NoProfile -ExecutionPolicy Bypass -File $adapter -DryRun
        if ($output) { return ($output -join "`n") | ConvertFrom-Json }
    }
    $cwd = Join-Path $temp 'projects\app\sub'
    $session = 'rad-test-' + [guid]::NewGuid().ToString('N')

    $shown = Invoke-Adapter @{ hook_event_name = 'Notification'; session_id = $session; cwd = $cwd; message = 'Claude needs your permission to use Bash'; notification_type = 'permission_prompt' }
    Assert-Equal $shown.event 'attention' 'permission prompt is an attention popup'
    Assert-Equal $shown.title 'my-app: Needs you' 'workspace name from the .code-workspace file'
    Assert-Equal $shown.message 'Claude needs your permission to use Bash' 'hook message shown'

    $shown = Invoke-Adapter @{ hook_event_name = 'Notification'; session_id = $session; cwd = (Join-Path $temp 'projects\other'); message = 'Waiting'; notification_type = 'idle_prompt' }
    Assert-Equal $shown.event 'info' 'idle prompt is info'
    Assert-Equal $shown.title 'other' 'no workspace matches, so the folder name'

    $shown = Invoke-Adapter @{ hook_event_name = 'Stop'; session_id = $session; cwd = $cwd }
    Assert-Equal $shown $null 'finish popup skipped when the turn did not start with the keyword'
    Invoke-Adapter @{ hook_event_name = 'UserPromptSubmit'; session_id = $session; cwd = $cwd; prompt = "update the readme`nplease" } | Out-Null
    $shown = Invoke-Adapter @{ hook_event_name = 'Stop'; session_id = $session; cwd = $cwd }
    Assert-Equal $shown.event 'done' 'finish popup after the keyword'
    Assert-Equal $shown.message 'Claude finished' 'stop message'
    Assert-Equal $shown.note 'update the readme' 'task is the first line of the prompt'
    $shown = Invoke-Adapter @{ hook_event_name = 'Stop'; session_id = $session; cwd = $cwd }
    Assert-Equal $shown $null 'the keyword only counts for one turn'
    Remove-Item (Join-Path ([IO.Path]::GetTempPath()) "rad-notify-*-$session") -Force -ErrorAction SilentlyContinue

    # ---- install and uninstall against temporary copies ----
    $target = Join-Path $temp 'installed'
    $claude = Join-Path $temp 'claude-settings.json'
    Set-Content -LiteralPath $claude -Value '{ "model": "sonnet", "hooks": { "Notification": [ { "hooks": [ { "type": "command", "command": "echo mine & more" } ] } ], "PostToolUse": [ { "matcher": "Edit", "hooks": [ { "type": "command", "command": "echo edit" } ] } ] } }'
    $install = Join-Path $root 'install.ps1'
    & $install -InstallDir $target -ClaudeSettings $claude -NoTest | Out-Null
    & $install -InstallDir $target -ClaudeSettings $claude -NoTest | Out-Null   # twice: must not duplicate
    $after = Get-Content -LiteralPath $claude -Raw | ConvertFrom-Json
    Assert-Equal @($after.hooks.Notification).Count 2 'Notification keeps the existing hook and gains one'
    Assert-Equal @($after.hooks.Stop).Count 1 'Stop hook added once after two installs'
    Assert-Equal @($after.hooks.UserPromptSubmit).Count 1 'UserPromptSubmit hook added once'
    Assert-Equal $after.hooks.Notification[0].hooks[0].command 'echo mine & more' 'existing hook untouched'
    Assert-Equal $after.hooks.PostToolUse[0].matcher 'Edit' 'other hook events untouched'
    Assert-Equal $after.model 'sonnet' 'other settings untouched'
    Assert-True ($after.hooks.Stop[0].hooks[0].command -like "*$target*adapters*claude-code.ps1*") 'hook points at the installed adapter'
    Assert-True (@(Get-ChildItem (Split-Path $claude) -Filter 'claude-settings.json.rad-backup-*').Count -ge 1) 'a backup was made'
    Assert-True ((Test-Path (Join-Path $target 'sounds\done.wav')) -and (Test-Path (Join-Path $target 'settings.json'))) 'installed sounds and settings.json'

    $edited = '{"theme":"midnight"}'
    Set-Content -LiteralPath (Join-Path $target 'settings.json') -Value $edited
    & $install -InstallDir $target -ClaudeSettings $claude -NoTest | Out-Null
    Assert-Equal ((Get-Content -LiteralPath (Join-Path $target 'settings.json') -Raw).Trim()) $edited 'reinstall keeps the user settings.json'

    & (Join-Path $root 'uninstall.ps1') -InstallDir $target -ClaudeSettings $claude | Out-Null
    $after = Get-Content -LiteralPath $claude -Raw | ConvertFrom-Json
    Assert-Equal @($after.hooks.Notification).Count 1 'uninstall removes only its own Notification hook'
    Assert-Equal $after.hooks.Notification[0].hooks[0].command 'echo mine & more' 'the existing hook is still there'
    Assert-Equal $after.hooks.PSObject.Properties['Stop'] $null 'uninstall removed Stop'
    Assert-Equal $after.hooks.PostToolUse[0].matcher 'Edit' 'uninstall leaves other hooks'
}
finally {
    $env:RAD_NOTIFY_SETTINGS = $savedEnv
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "$script:passed passed, $script:failures failed"
exit ([int]($script:failures -gt 0))
