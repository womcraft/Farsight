param([string]$Proc = 'FarsightLauncher', [string]$Out, [switch]$Kill)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SD { [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  public struct R { public int L,T,Rt,B; } }
"@
[void][SD]::SetProcessDpiAwarenessContext([IntPtr](-4))
$p = Get-Process $Proc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "no window"; Get-Process $Proc -ErrorAction SilentlyContinue | Stop-Process -Force; exit 1 }
$r = New-Object SD+R; [void][SD]::GetWindowRect($p.MainWindowHandle, [ref]$r)
$w = $r.Rt - $r.L; $h = $r.B - $r.T
"rect $($r.L),$($r.T) ${w}x${h}"
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out)
if ($Kill) { Stop-Process -Id $p.Id -Force }
