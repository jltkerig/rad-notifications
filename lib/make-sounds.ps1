# Writes the built-in notification sounds (short synthesized chimes) into the sounds folder. Run by install.ps1;
# existing files are left alone, so a sound you replaced stays replaced. Use -Force to rewrite them.
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$folder = Join-Path (Split-Path -Parent $PSScriptRoot) 'sounds'
New-Item -ItemType Directory -Force -Path $folder | Out-Null

$sampleRate = 22050

# notes: @(frequency in Hz, length in seconds); frequency 0 is a rest
function New-RadWave([string]$Path, $Notes, [double]$Gain) {
    $samples = New-Object System.Collections.Generic.List[int16]
    foreach ($note in $Notes) {
        $count = [int]($sampleRate * $note[1])
        for ($i = 0; $i -lt $count; $i++) {
            $position = $i / $count
            $envelope = [math]::Min(1, $i / 200) * [math]::Pow(1 - $position, 1.6)
            $wave = if ($note[0] -gt 0) { [math]::Sin(2 * [math]::PI * $note[0] * $i / $sampleRate) } else { 0 }
            $samples.Add([int16]($wave * $envelope * $Gain * 32767))
        }
    }
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter $stream
    $dataLength = $samples.Count * 2
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36 + $dataLength))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16); $writer.Write([int16]1); $writer.Write([int16]1)
    $writer.Write([int]$sampleRate); $writer.Write([int]($sampleRate * 2)); $writer.Write([int16]2); $writer.Write([int16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int]$dataLength)
    foreach ($sample in $samples) { $writer.Write($sample) }
    $writer.Flush()
    [IO.File]::WriteAllBytes($Path, $stream.ToArray())
}

$sounds = [ordered]@{
    done      = @{ gain = 0.5; notes = @(@(659.25, 0.14), @(830.61, 0.14), @(987.77, 0.34)) }
    attention = @{ gain = 0.5; notes = @(@(880, 0.16), @(0, 0.06), @(880, 0.16), @(0, 0.06), @(1174.66, 0.3)) }
    error     = @{ gain = 0.5; notes = @(@(392, 0.2), @(311.13, 0.4)) }
    info      = @{ gain = 0.4; notes = @(,@(783.99, 0.22)) }
}
foreach ($name in $sounds.Keys) {
    $path = Join-Path $folder "$name.wav"
    if ((Test-Path -LiteralPath $path) -and -not $Force) { continue }
    New-RadWave $path $sounds[$name].notes $sounds[$name].gain
}
