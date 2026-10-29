# Draws one popup from a spec file and closes it when its time is up. Started by Start-RadPopup; run it with -STA.
# -Screenshot <png> renders the popup to an image instead of showing it (used by the tests and to preview a theme).
param(
    [Parameter(Mandatory)][string]$SpecFile,
    [string]$Screenshot
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'core.ps1')

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $spec = ConvertTo-RadHashtable (ConvertFrom-Json ([IO.File]::ReadAllText($SpecFile, [Text.Encoding]::UTF8)))
    Remove-Item -LiteralPath $SpecFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-RadLog "Popup could not start: $($_.Exception.Message)"
    exit 1
}

$popup = $spec.popup
$colors = $spec.colors

function New-Brush([string]$Name, [string]$Fallback) {
    $text = $colors[$Name]
    try { return New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($text)) }
    catch { Write-RadLog "Bad color '$text' for $Name, using $Fallback"; return New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Fallback)) }
}

function New-TextBlock([string]$Text, [double]$Size, $Brush, [bool]$Bold, [int]$MaxLines) {
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = $Text
    $block.FontSize = $Size
    $block.Foreground = $Brush
    $block.TextWrapping = 'Wrap'
    $block.TextTrimming = 'CharacterEllipsis'
    if ($Bold) { $block.FontWeight = [Windows.FontWeights]::SemiBold }
    if ($MaxLines -gt 0) { $block.MaxHeight = [math]::Ceiling($Size * 1.4 * $MaxLines) }
    return $block
}

# Slots: popup n sits n steps from the screen edge. A slot is taken by holding its lock file open until the popup closes,
# so a crashed popup frees its slot by itself.
function Lock-Slot([int]$Count) {
    for ($n = 0; $n -lt $Count; $n++) {
        $path = Join-Path ([IO.Path]::GetTempPath()) "rad-notify-slot-$n.lock"
        try { return @{ number = $n; stream = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None') } } catch [IO.IOException] { continue }
    }
    return @{ number = $Count - 1; stream = $null }
}

$window = New-Object Windows.Window
$window.WindowStyle = 'None'
$window.AllowsTransparency = $true
$window.Background = [Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.ResizeMode = 'NoResize'
$window.SizeToContent = 'Height'
$shadowMargin = if ($popup.shadow) { 14 } else { 0 }
$window.Width = [double]$popup.width + 2 * $shadowMargin
$window.MaxHeight = [double]$popup.maxHeight + 2 * $shadowMargin
$window.FontFamily = New-Object Windows.Media.FontFamily ([string]$popup.fontFamily)
$window.Opacity = if ($popup.animation -and -not $Screenshot) { 0 } else { [double]$popup.opacity }

$card = New-Object Windows.Controls.Border
$card.Margin = New-Object Windows.Thickness $shadowMargin
$card.CornerRadius = New-Object Windows.CornerRadius ([double]$popup.cornerRadius)
$card.Background = New-Brush 'background' '#1F2430'
$card.BorderBrush = New-Brush 'border' '#2D3442'
$card.BorderThickness = New-Object Windows.Thickness ([double]$popup.borderWidth)
$card.ClipToBounds = $true
if ($popup.shadow) {
    $glow = New-Object Windows.Media.Effects.DropShadowEffect
    $glow.BlurRadius = 14; $glow.ShadowDepth = 2; $glow.Opacity = 0.45; $glow.Color = [Windows.Media.Colors]::Black
    $card.Effect = $glow
}

$layout = New-Object Windows.Controls.Grid
foreach ($height in 1, 2) { $row = New-Object Windows.Controls.RowDefinition; $row.Height = [Windows.GridLength]::Auto; $layout.RowDefinitions.Add($row) }
$stripeColumn = New-Object Windows.Controls.ColumnDefinition; $stripeColumn.Width = [Windows.GridLength]::Auto
$bodyColumn = New-Object Windows.Controls.ColumnDefinition; $bodyColumn.Width = New-Object Windows.GridLength (1, [Windows.GridUnitType]::Star)
$layout.ColumnDefinitions.Add($stripeColumn); $layout.ColumnDefinitions.Add($bodyColumn)

$stripe = New-Object Windows.Controls.Border
$stripe.Width = [double]$popup.stripeWidth
$stripe.Background = New-Brush 'accent' '#4F8CFF'
[Windows.Controls.Grid]::SetRowSpan($stripe, 2)
$layout.Children.Add($stripe) | Out-Null

$body = New-Object Windows.Controls.StackPanel
$body.Margin = New-Object Windows.Thickness (14, 12, 34, 12)
[Windows.Controls.Grid]::SetColumn($body, 1)
$text = New-Brush 'text' '#F5F7FA'
$muted = New-Brush 'muted' '#9AA4B2'
if ($spec.title) { $body.Children.Add((New-TextBlock $spec.title ([double]$popup.titleSize) $text $true 2)) | Out-Null }
if ($spec.message) {
    $line = New-TextBlock $spec.message ([double]$popup.messageSize) $text $false 3
    $line.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $body.Children.Add($line) | Out-Null
}
if ($spec.note) {
    $line = New-TextBlock $spec.note ([double]$popup.noteSize) $muted $false 2
    $line.Margin = New-Object Windows.Thickness (0, 6, 0, 0)
    $body.Children.Add($line) | Out-Null
}
$layout.Children.Add($body) | Out-Null

if ($popup.closeButton) {
    $close = New-Object Windows.Controls.TextBlock
    $close.Text = [string][char]0x2715
    $close.FontSize = 12
    $close.Foreground = $muted
    $close.Cursor = [Windows.Input.Cursors]::Hand
    $close.HorizontalAlignment = 'Right'
    $close.VerticalAlignment = 'Top'
    $close.Margin = New-Object Windows.Thickness (0, 10, 12, 0)
    [Windows.Controls.Grid]::SetColumn($close, 1)
    $layout.Children.Add($close) | Out-Null
}

$bar = $null
if ($popup.showProgress -and $spec.duration -gt 0) {
    $bar = New-Object Windows.Controls.Border
    $bar.Height = 3
    $bar.Background = New-Brush 'progress' '#4F8CFF'
    $bar.HorizontalAlignment = 'Stretch'
    $bar.RenderTransformOrigin = New-Object Windows.Point (0, 0.5)
    $bar.RenderTransform = New-Object Windows.Media.ScaleTransform (1, 1)
    [Windows.Controls.Grid]::SetRow($bar, 1)
    [Windows.Controls.Grid]::SetColumn($bar, 1)
    $layout.Children.Add($bar) | Out-Null
}
$card.Child = $layout
$window.Content = $card

# --- screenshot mode: draw onto a gray backdrop and save a PNG ---
if ($Screenshot) {
    $window.Left = -10000; $window.Top = -10000
    $window.Show()
    $window.UpdateLayout()
    $width = [int][math]::Ceiling($window.ActualWidth); $height = [int][math]::Ceiling($window.ActualHeight)
    $visual = New-Object Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $context.DrawRectangle((New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#7A7F8A'))), $null, (New-Object Windows.Rect (0, 0, $width, $height)))
    $context.DrawRectangle((New-Object Windows.Media.VisualBrush $card), $null, (New-Object Windows.Rect (0, 0, $width, $height)))
    $context.Close()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($Screenshot)
    $encoder.Save($stream); $stream.Close()
    $window.Close()
    exit 0
}

# --- position: a slot per open popup, stacked away from the screen edge ---
$slot = Lock-Slot ([int][math]::Min([int]$popup.maxStack, 8))
$work = [Windows.SystemParameters]::WorkArea
$margin = [double]$popup.margin - $shadowMargin
$step = [double]$popup.maxHeight + [double]$popup.stackGap
$offset = $slot.number * $step
$position = [string]$popup.position
$window.Left = if ($position -like '*left') { $work.Left + $margin } elseif ($position -like '*center') { $work.Left + ($work.Width - $window.Width) / 2 } else { $work.Right - $window.Width - $margin }
$window.WindowStartupLocation = 'Manual'
$window.Top = -10000
$window.Add_Loaded({
    if ($position -like 'top*') { $window.Top = $work.Top + $margin + $offset }
    else { $window.Top = $work.Bottom - $window.ActualHeight - $margin - $offset }
})

# --- sound ---
$player = $null
$soundDone = $true
if ($spec.sound) {
    try {
        $player = New-Object Windows.Media.MediaPlayer
        $soundDone = $false
        $player.Add_MediaEnded({ $script:soundDone = $true; if ($script:windowClosed) { [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } })
        $player.Add_MediaFailed({ $script:soundDone = $true; Write-RadLog "Sound could not play: $($_.ErrorException.Message)" })
        $player.Open([Uri]$spec.sound)
        $player.Volume = [math]::Max(0, [math]::Min(1, [double]$spec.volume))
        $player.Play()
    } catch { Write-RadLog "Sound could not play: $($_.Exception.Message)" }
}

# --- closing, with a fade ---
$closing = $false
function Close-Popup {
    if ($script:closing) { return }
    $script:closing = $true
    if ($popup.animation) {
        $fade = New-Object Windows.Media.Animation.DoubleAnimation (0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(180))))
        $fade.Add_Completed({ $window.Close() })
        $window.BeginAnimation([Windows.Window]::OpacityProperty, $fade)
    } else { $window.Close() }
}

# --- click: focus the editor window for the workspace, or just dismiss ---
Add-Type -Namespace Rad -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr hWnd);
'@
function Focus-EditorWindow {
    $allowed = @($popup.focusProcesses)
    foreach ($target in @($spec.focusTargets)) {
        $found = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $allowed -contains $_.ProcessName -and $_.MainWindowTitle -like "*$target*" } | Select-Object -First 1
        if (-not $found) { continue }
        if ([Rad.Native]::IsIconic($found.MainWindowHandle)) { [Rad.Native]::ShowWindow($found.MainWindowHandle, 9) | Out-Null }
        [Rad.Native]::SetForegroundWindow($found.MainWindowHandle) | Out-Null
        return
    }
}
$card.Add_MouseLeftButtonUp({
    if ($popup.clickAction -eq 'focus') { Focus-EditorWindow }
    if ($popup.clickAction -ne 'none') { Close-Popup }
})
if ($popup.closeButton) {
    $close.Add_MouseLeftButtonUp({ param($sender, $e) $e.Handled = $true; Close-Popup })
}

# --- timing: the bar shrinks over the duration; hovering pauses it; duration 0 stays until clicked ---
$storyboard = $null
$window.Add_ContentRendered({
    if ($popup.animation) {
        $in = New-Object Windows.Media.Animation.DoubleAnimation ([double]$popup.opacity, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(180))))
        $window.BeginAnimation([Windows.Window]::OpacityProperty, $in)
    }
    if ($spec.duration -le 0) { return }
    $timer = New-Object Windows.Media.Animation.DoubleAnimation (1, 0, (New-Object Windows.Duration ([TimeSpan]::FromSeconds($spec.duration))))
    $script:storyboard = New-Object Windows.Media.Animation.Storyboard
    if ($bar) {
        [Windows.Media.Animation.Storyboard]::SetTarget($timer, $bar)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($timer, (New-Object Windows.PropertyPath '(UIElement.RenderTransform).(ScaleTransform.ScaleX)'))
    } else {
        [Windows.Media.Animation.Storyboard]::SetTarget($timer, $card)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($timer, (New-Object Windows.PropertyPath '(UIElement.Opacity)'))
        $timer.From = 1; $timer.To = 1
    }
    $script:storyboard.Children.Add($timer)
    $script:storyboard.Add_Completed({ Close-Popup })
    $script:storyboard.Begin($window, $true)
})
if ($popup.pauseOnHover) {
    $card.Add_MouseEnter({ if ($script:storyboard) { $script:storyboard.Pause($window) } })
    $card.Add_MouseLeave({ if ($script:storyboard) { $script:storyboard.Resume($window) } })
}

# the process ends when the popup is closed and its sound has finished (at most ten seconds after closing)
$windowClosed = $false
$window.Add_Closed({
    if ($slot.stream) { $slot.stream.Dispose() }
    $script:windowClosed = $true
    if ($script:soundDone) { [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown(); return }
    $limit = New-Object Windows.Threading.DispatcherTimer
    $limit.Interval = [TimeSpan]::FromSeconds(10)
    $limit.Add_Tick({ [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })
    $limit.Start()
})

$window.Show()
[Windows.Threading.Dispatcher]::Run()
if ($player) { $player.Close() }
