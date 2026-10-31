# rad-notifications

Popup notifications for AI coding assistants. When Claude Code (or any tool that can run a command) finishes, needs
your permission, or hits an error, a small popup floats on your screen with the title, note, sound and colors you chose.

- Windows 10 or 11. Nothing to install first: it uses the Windows PowerShell that ships with Windows.
- Every title, note, sound, color and display time is a setting. No code editing.
- Works as a Claude Code hook out of the box, and as a plain command (`rad-notify`) for everything else.

## Install

Open PowerShell in this folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

This copies the tool to `%LOCALAPPDATA%\rad-notifications`, creates the sounds, adds the Claude Code hooks to
`~\.claude\settings.json` (a backup is saved next to it) and shows a test popup. Your other Claude Code hooks are not touched.

| Option | What it does |
|---|---|
| `-InstallDir <folder>` | Install somewhere else. |
| `-ClaudeSettings <file>` | Hook into a different Claude Code settings file. |
| `-NoClaudeHooks` | Install only. Use `rad-notify` from any other tool. |
| `-AddToPath` | Lets you type `rad-notify` in any new terminal. |
| `-NoTest` | Skip the test popup. |

Running the installer again upgrades the code and keeps your `settings.json` and any sounds you replaced.
To remove it: `powershell -ExecutionPolicy Bypass -File uninstall.ps1` (add `-RemoveFiles` to delete the folder too).

## Use it

With Claude Code, there is nothing to do. The hooks show a popup when:

| Claude Code event | Popup |
|---|---|
| Permission request or question (Notification) | `attention`, 60 seconds |
| A turn finishes (Stop) | `done`, 8 seconds |
| Idle reminder | `info` |

Click a popup to jump to the editor window for that workspace and close it. The x button closes it without jumping.
Hovering pauses the timer.

From anywhere else:

```powershell
rad-notify -Event done -Title "Build" -Message "All tests passed" -Note "42 seconds"
rad-notify -Event error -Message "Deploy failed" -Duration 20 -Accent "#FF3355"
'{"event":"attention","message":"Waiting for you","duration":0}' | rad-notify -Stdin
```

### Any other AI assistant

Anything that can run a command when it finishes or needs you can call `rad-notify`. Point its hook, notify setting or
wrapper script at `rad-notify.cmd` (in the install folder) with the arguments above, or send JSON on stdin with `-Stdin`.
The JSON keys are the same as the settings: `event`, `title`, `message`, `note`, `sound`, `volume`, `duration`,
`theme`, `colors`, `popup`, and `vars` (values for the `{variables}`). Check the assistant's own documentation for how
and when it runs commands; only the Claude Code adapter is included.

## Customize

Edit `settings.json` in the install folder. It starts empty (`{}`). Add only what you want to change; everything else
keeps the defaults in `defaults.json` (read it for the full list, and do not edit it). Changes apply to the next popup.

```json
{
  "theme": "midnight",
  "popup": { "position": "top-right", "width": 420 },
  "events": {
    "done": {
      "title": "{workspace} is done",
      "note": "{task}",
      "sound": "C:/Sounds/my-chime.wav",
      "duration": 5
    },
    "attention": { "duration": 30, "colors": { "accent": "#FF00AA" } },
    "error": { "enabled": false }
  }
}
```

### Events

`done`, `attention`, `error` and `info` come built in. Add your own name under `events` and use it with
`rad-notify -Event my-event`; it only needs the keys that differ from `info`. Each event can set:

| Key | Meaning |
|---|---|
| `enabled` | `false` turns the event off. |
| `title`, `message`, `note` | Text lines. Empty hides the line. Can use the variables below. |
| `sound` | `none`, a built-in name (`done`, `attention`, `error`, `info`), or the path to a `.wav` or `.mp3`. A relative path is looked up in the install folder. |
| `volume` | 0 to 1. |
| `duration` | Seconds on screen. `0` stays until you click it. |
| `theme` | Use another theme for this event. |
| `colors` | Color changes for this event (see Colors). |
| `popup` | Any of the Popup options below, for this event only. |

Variables: `{title}` `{message}` `{note}` `{event}` `{time}` `{date}` `{workspace}` `{folder}` `{task}` (the first line of
your last prompt, from Claude Code) `{hook}` and `{type}` (Claude Code only). Unknown variables are blank. Your own can be
passed in `vars` in the JSON.

### Colors

Pick a theme with `"theme"`: `dark`, `light`, `midnight`, `forest`, `sunset` or `high-contrast`. Add your own under
`themes`, or change one color of an existing theme:

```json
{ "themes": { "dark": { "accent": "#00C2FF" }, "paper": { "background": "#FFF8E7", "text": "#2B2B2B", "muted": "#7A7466", "accent": "#C2410C", "progress": "#C2410C", "border": "#E4D9BD" } } }
```

Color keys: `background`, `text`, `muted` (the note line), `accent` (the left stripe), `progress` (the countdown bar), `border`.
Colors are `#RRGGBB` or `#AARRGGBB` (with transparency).

### Popup

| Key | Default | Meaning |
|---|---|---|
| `position` | `bottom-right` | `top-left`, `top-center`, `top-right`, `bottom-left`, `bottom-center`, `bottom-right` |
| `margin` | 16 | Distance from the screen edge. |
| `width`, `maxHeight` | 380, 150 | Size. Long text is cut with an ellipsis. |
| `maxStack`, `stackGap` | 4, 10 | Popups stack; how many, and the space between. |
| `cornerRadius`, `borderWidth`, `stripeWidth` | 10, 1, 6 | Shape. |
| `opacity` | 0.97 | 0 (invisible) to 1. |
| `fontFamily`, `titleSize`, `messageSize`, `noteSize` | Segoe UI, 15, 13, 11 | Text. |
| `shadow`, `showProgress`, `closeButton`, `animation`, `pauseOnHover` | true | Switch features off. |
| `clickAction` | `focus` | `focus` jumps to the editor window then closes, `dismiss` only closes, `none` ignores clicks. |
| `focusProcesses` | VS Code, Cursor, Windsurf, Windows Terminal | Which programs the click may bring forward. |

### Claude Code

Under `claudeCode`:

| Key | Meaning |
|---|---|
| `workspacesFolder` | A folder of VS Code `.code-workspace` files. The popup then shows the name of the workspace that holds the session's folder, instead of the folder name. Leave empty to use the folder name. |
| `useWorkspaceColor` | `true` colors the stripe and countdown bar with the workspace's `peacock.color` (needs `workspacesFolder`), for every event. `false`, or a workspace without that setting, uses the event colors. |
| `finishOnlyAfterKeyword` | Empty shows a popup after every turn. Set to `"update"` to show the finish popup only after a prompt that starts with that word, so small questions stay quiet. |
| `stopMessage` | The text for the finish popup. |
| `taskMaxLength` | How much of your prompt `{task}` keeps. |
| `hooks`, `notificationTypes` | Which event name each Claude Code hook uses. Set one to `null` to ignore it. |

### Preview a look without waiting for an event

```powershell
rad-notify -Event done -Theme sunset -Title "Preview" -Message "How does this look?" -Note "A note" -Duration 10
rad-notify -Event done -Title "Preview" -Message "To an image" -Screenshot preview.png
```

## If something is not working

- Run the same command with `-DryRun` to print what would be shown, without showing it.
- Errors are written to `rad-notify.log` in the install folder. A bad color or a missing sound is logged and the
  default is used, so a typo never stops a popup.
- No popups from Claude Code: open `~\.claude\settings.json` and check for `rad-notifications` hooks. Claude Code reads hooks
  when a session starts, so restart the session after installing. Reports from other users say the Notification hook for
  permission prompts does not always fire inside the VS Code extension; if you see that, it is on the Claude Code side.
- Clicking does not jump to the window: Windows only lets the foreground change after your click, and the window title
  must contain the workspace or folder name. Add the program to `focusProcesses` if it is not listed.

## Limits

Windows only. These are popup windows, not Windows notifications, so they do not appear in the notification center and
may not draw over a full-screen game or video.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-RadNotifications.ps1
```

The tests use temporary folders and never touch your real settings or Claude Code settings.

## Layout

```
rad-notify.ps1 / .cmd   the command
defaults.json           every default (reference, do not edit)
settings.json           your changes
install.ps1, uninstall.ps1
lib/core.ps1            settings, templates, building a popup
lib/popup.ps1           the popup window (WPF)
lib/claude-hooks.ps1    adds and removes the Claude Code hooks
lib/make-sounds.ps1     writes the built-in sounds
adapters/claude-code.ps1
sounds/                 done.wav, attention.wav, error.wav, info.wav
tests/
```

## License

MIT. See LICENSE.
