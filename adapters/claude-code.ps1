# Claude Code hook adapter. Register this one script for the Notification, Stop and UserPromptSubmit hooks
# (install.ps1 does that). Claude Code sends the hook's details as JSON on stdin.
#   Notification / Stop -> a popup (the events and messages are set under "claudeCode" in settings.json)
#   UserPromptSubmit    -> nothing shown; remembers the prompt (for the {task} variable) and whether it started with
#                          the keyword that "finishOnlyAfterKeyword" waits for
# -DryRun prints what would be shown instead of showing it (used by the tests).
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\core.ps1')

function Read-HookInput {
    $reader = New-Object IO.StreamReader ([Console]::OpenStandardInput()), (New-Object Text.UTF8Encoding($false))
    $text = $reader.ReadToEnd().TrimStart([char]0xFEFF)
    if (-not $text.Trim()) { throw 'No hook input on stdin.' }
    return ConvertTo-RadHashtable (ConvertFrom-Json $text)
}

function Get-SessionFile([string]$Kind, $Hook) {
    $session = if ($Hook.session_id) { $Hook.session_id } else { 'none' }
    return Join-Path ([IO.Path]::GetTempPath()) "rad-notify-$Kind-$session"
}

# The VS Code workspace (a .code-workspace file in settings "claudeCode.workspacesFolder") whose folder holds the
# session's folder, most specific first. The files allow comments and trailing commas, so folder paths are read with a pattern.
function Get-WorkspaceName([string]$WorkspacesFolder, [string]$Cwd) {
    if (-not $WorkspacesFolder -or -not $Cwd -or -not (Test-Path -LiteralPath $WorkspacesFolder)) { return '' }
    $here = [IO.Path]::GetFullPath($Cwd).TrimEnd('\')
    $best = ''; $bestLength = -1
    foreach ($file in Get-ChildItem -LiteralPath $WorkspacesFolder -Filter *.code-workspace -ErrorAction SilentlyContinue) {
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($file.FullName), '"path"\s*:\s*"([^"]+)"')) {
            try { $folder = [IO.Path]::GetFullPath((Join-Path $WorkspacesFolder ($match.Groups[1].Value -replace '\\\\', '\'))).TrimEnd('\') } catch { continue }
            $inside = ($here -ieq $folder) -or $here.StartsWith($folder + '\', [StringComparison]::OrdinalIgnoreCase)
            if ($inside -and $folder.Length -gt $bestLength) { $best = $file.BaseName; $bestLength = $folder.Length }
        }
    }
    return $best
}

function Save-Prompt($Hook, $Settings) {
    $prompt = [string]$Hook.prompt
    $first = ($prompt -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    $max = [int]$Settings.claudeCode.taskMaxLength
    if ($first -and $first.Length -gt $max) { $first = $first.Substring(0, $max - 1).TrimEnd() + '...' }
    [IO.File]::WriteAllText((Get-SessionFile 'task' $Hook), [string]$first, (New-Object Text.UTF8Encoding($false)))
    $keyword = [string]$Settings.claudeCode.finishOnlyAfterKeyword
    $marker = Get-SessionFile 'keyword' $Hook
    if ($keyword -and $prompt -match ('^\s*' + [regex]::Escape($keyword) + '\b')) { New-Item -ItemType File -Force -Path $marker | Out-Null }
}

# True when the finish popup should be skipped: a keyword is required and this turn did not start with it.
function Test-SkipFinish($Hook, $Settings) {
    if (-not [string]$Settings.claudeCode.finishOnlyAfterKeyword) { return $false }
    $marker = Get-SessionFile 'keyword' $Hook
    if (-not (Test-Path -LiteralPath $marker)) { return $true }
    Remove-Item -LiteralPath $marker -Force
    return $false
}

function Get-EventName($Hook, $Settings) {
    $byType = $Settings.claudeCode.notificationTypes[[string]$Hook.notification_type]
    if ($Hook.hook_event_name -eq 'Notification' -and $byType) { return $byType }
    return $Settings.claudeCode.hooks[[string]$Hook.hook_event_name]
}

function New-HookRequest($Hook, $Settings, [string]$EventName) {
    $message = [string]$Hook.message
    if (-not $message -and $Hook.hook_event_name -eq 'Stop') { $message = [string]$Settings.claudeCode.stopMessage }
    $taskFile = Get-SessionFile 'task' $Hook
    $task = if (Test-Path -LiteralPath $taskFile) { [IO.File]::ReadAllText($taskFile, [Text.Encoding]::UTF8) } else { '' }
    $folder = if ($Hook.cwd) { Split-Path -Leaf ([string]$Hook.cwd) } else { '' }
    $workspace = Get-WorkspaceName ([string]$Settings.claudeCode.workspacesFolder) ([string]$Hook.cwd)
    return @{
        event = $EventName
        vars = @{ message = $message; task = $task; folder = $folder; workspace = $(if ($workspace) { $workspace } else { $folder })
                  hook = [string]$Hook.hook_event_name; type = [string]$Hook.notification_type }
    }
}

try {
    $hook = Read-HookInput
    $settings = Get-RadSettings
    if ($hook.hook_event_name -eq 'UserPromptSubmit') { Save-Prompt $hook $settings; return }

    $eventName = Get-EventName $hook $settings
    if (-not $eventName) { return }
    if ($hook.hook_event_name -eq 'Stop' -and (Test-SkipFinish $hook $settings)) { return }

    $spec = Send-RadNotification (New-HookRequest $hook $settings $eventName) -DryRun:$DryRun
    if ($DryRun) { ConvertTo-Json $spec -Depth 10 }
} catch {
    Write-RadLog "claude-code adapter failed: $($_.Exception.Message)"
    exit 0   # a notification problem must never block Claude Code
}
