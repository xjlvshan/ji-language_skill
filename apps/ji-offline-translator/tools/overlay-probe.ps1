# overlay-probe.ps1 - check the selection overlay window: ex-style, layered attrs, and
# what it actually paints (PrintWindow).  [ASCII only]
param([string]$Exe=".\离线翻译助手.exe",[string]$Out=".\shots\ocr-overlay.png")
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
if(-not ("OvNative" -as [type])){
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class OvNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetWindowLongA(IntPtr h,int i);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint f);
 [DllImport("user32.dll")] public static extern bool GetLayeredWindowAttributes(IntPtr h,out uint key,out byte alpha,out uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 public static string C(IntPtr h){var sb=new StringBuilder(256);GetClassNameW(h,sb,256);return sb.ToString();}
 public static IntPtr MainWin(uint pid){ IntPtr f=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
   if(C(h)!="SecClass") return true; f=h; return false;},IntPtr.Zero); return f; }
 public static IntPtr Overlay(uint pid,IntPtr ex){ IntPtr f=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
   if(C(h)!="SecClass") return true; if(h==ex) return true;
   RECT r; GetWindowRect(h,out r); if((r.R-r.L)<1000) return true; f=h; return false;},IntPtr.Zero); return f; }
 public static IntPtr ById(IntPtr p,int id){ IntPtr f=IntPtr.Zero;
  EnumChildWindows(p,(h,l)=>{ if(f==IntPtr.Zero && GetDlgCtrlID(h)==id) f=h; return true;},IntPtr.Zero); return f; }
 public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@ }
function Pump([int]$ms){ $sw=[Diagnostics.Stopwatch]::StartNew(); while($sw.ElapsedMilliseconds -lt $ms){ Start-Sleep -Milliseconds 40 } }

$Exe=(Resolve-Path $Exe).Path
$proc=Start-Process $Exe -PassThru
$hw=[IntPtr]::Zero
for($i=0;$i -lt 40 -and $hw -eq [IntPtr]::Zero;$i++){ Start-Sleep -Milliseconds 300; $hw=[OvNative]::MainWin([uint32]$proc.Id) }
Start-Sleep -Seconds 8
$btn=[OvNative]::ById($hw,11)
[void][OvNative]::SendMessageW($btn,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
Start-Sleep -Seconds 2
$ov=[OvNative]::Overlay([uint32]$proc.Id,$hw)
if($ov -eq [IntPtr]::Zero){ Write-Output "overlay not found"; $proc.Kill(); exit 3 }
$ex=[OvNative]::GetWindowLongA($ov,-20)
Write-Output ("overlay hwnd={0} exstyle=0x{1:X8} (WS_EX_LAYERED=0x80000, TOPMOST=0x8, TOOLWINDOW=0x80)" -f $ov,$ex)
$key=0;[byte]$a=0;$fl=0
$ok=[OvNative]::GetLayeredWindowAttributes($ov,[ref]$key,[ref]$a,[ref]$fl)
Write-Output ("GetLayeredWindowAttributes ok={0} key=0x{1:X6} alpha={2} flags={3} (1=COLORKEY 2=ALPHA)" -f $ok,$key,$a,$fl)
# draw a selection and capture the overlay itself
[void][OvNative]::SendMessageW($ov,0x0201,[IntPtr]1,[OvNative]::LP(110,110))
Start-Sleep -Milliseconds 200
[void][OvNative]::SendMessageW($ov,0x0200,[IntPtr]1,[OvNative]::LP(1000,240))
Start-Sleep -Milliseconds 600
$r=New-Object OvNative+RECT; [void][OvNative]::GetWindowRect($ov,[ref]$r)
$bmp=New-Object Drawing.Bitmap ($r.R-$r.L),($r.B-$r.T)
$g=[Drawing.Graphics]::FromImage($bmp); $dc=$g.GetHdc()
[void][OvNative]::PrintWindow($ov,$dc,2)
$g.ReleaseHdc($dc); $g.Dispose()
$bmp.Save($Out,[Drawing.Imaging.ImageFormat]::Png)
$c1=$bmp.GetPixel(50,50).ToString(); $c2=$bmp.GetPixel(500,170).ToString(); $c3=$bmp.GetPixel(1500,900).ToString()
$bmp.Dispose()
Write-Output "PrintWindow(overlay) -> $Out   px(50,50)=$c1  px(500,170)=$c2  px(1500,900)=$c3"
[void][OvNative]::SendMessageW($ov,0x0202,[IntPtr]0,[OvNative]::LP(1000,240))
Start-Sleep -Seconds 2
if(-not $proc.HasExited){ $proc.Kill() }
  Start-Sleep -Milliseconds 500
  Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $proc.Id) -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Output "done"
