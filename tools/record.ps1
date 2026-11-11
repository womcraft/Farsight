# Captures the WoW window: one still (-Frames 1) or a series of frames for an animated GIF.
# Frames are scaled to -Width pixels and saved as frame-000.gif ... in -OutDir; tools\gifmerge.py joins them.
param([string]$Proc = 'Wow', [string]$OutDir, [int]$Frames = 1, [int]$IntervalMs = 250, [int]$Width = 900, [string]$Still)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SR { [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  public struct R { public int L,T,Rt,B; } }
"@
[void][SR]::SetProcessDpiAwarenessContext([IntPtr](-4))
$p = Get-Process $Proc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "no window"; exit 1 }
$r = New-Object SR+R; [void][SR]::GetWindowRect($p.MainWindowHandle, [ref]$r)
$w = $r.Rt - $r.L; $h = $r.B - $r.T
$sw = $Width; $sh = [int]($h * $Width / $w)
$full = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($full)
$small = New-Object System.Drawing.Bitmap $sw, $sh
$gs = [System.Drawing.Graphics]::FromImage($small)
$gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
if ($Still) {
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $full.Size)
  $gs.DrawImage($full, 0, 0, $sw, $sh)
  $small.Save($Still, [System.Drawing.Imaging.ImageFormat]::Png)
  "still ${sw}x${sh}"; exit 0
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$sw0 = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $Frames; $i++) {
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $full.Size)
  $gs.DrawImage($full, 0, 0, $sw, $sh)
  $small.Save((Join-Path $OutDir ("frame-{0:d3}.gif" -f $i)), [System.Drawing.Imaging.ImageFormat]::Gif)
  $wait = ($i + 1) * $IntervalMs - $sw0.ElapsedMilliseconds
  if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
}
"frames $Frames ${sw}x${sh} in $($sw0.ElapsedMilliseconds) ms"
