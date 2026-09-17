# winprobe.ps1 - dump child windows of a process, click controls, set text, read titles
# ASCII only. usage:
#   powershell -File winprobe.ps1 -Proc gui-2 -Dump
#   powershell -File winprobe.ps1 -Proc gui-2 -SetText 2 "ABC"
#   powershell -File winprobe.ps1 -Proc gui-2 -Click 1
#   powershell -File winprobe.ps1 -Proc gui-2 -Title
#   powershell -File winprobe.ps1 -Proc gui-2 -SetChildText 6 "hello"   (WM_SETTEXT on child by id)
#   powershell -File winprobe.ps1 -Proc gui-2 -Msg 6 0x0402 5 0     (SendMessage child by id: msg wParam lParam)
param(
  [Parameter(Mandatory=$true)][string]$Proc,
  [int]$ProcId = 0,
  [switch]$Dump,
  [switch]$Title,
  [int]$Click = -1,
  [int]$SetText = -1,
  [string]$Text = "",
  [int]$SetChildText = -1,
  [string]$ChildText = "",
  [int]$Msg = -1,
  [int]$MsgId = 0,
  [long]$MsgW = 0,
  [long]$MsgL = 0,
  [int]$WaitMs = 400
)
$ErrorActionPreference = 'Stop'
if (-not ("SecProbeNative" -as [type])) {
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class SecProbeNative{
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,string l);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 public static string T(IntPtr h){var sb=new StringBuilder(2048);GetWindowTextW(h,sb,2048);return sb.ToString();}
 public static string C(IntPtr h){var sb=new StringBuilder(256);GetClassNameW(h,sb,256);return sb.ToString();}
 public static string Dump(IntPtr p){ var r=new StringBuilder(); EnumChildWindows(p,(h,l)=>{ r.Append(string.Format("  hwnd={0} cls={1} id={2} text='{3}'",h,C(h),GetDlgCtrlID(h),T(h))); r.Append(Environment.NewLine); return true;},IntPtr.Zero); return r.ToString(); }
 public static IntPtr ById(IntPtr p,int id){ IntPtr f=IntPtr.Zero; EnumChildWindows(p,(h,l)=>{ if(f==IntPtr.Zero && GetDlgCtrlID(h)==id) f=h; return true;},IntPtr.Zero); return f; }
}
"@ }
$p = $null
if ($ProcId -ne 0) { $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue }
else { $p = Get-Process $Proc -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $p) { Write-Output "process not found"; exit 2 }
$h = [IntPtr]$p.MainWindowHandle
if ($h -eq [IntPtr]::Zero -or -not [SecProbeNative]::IsWindow($h)) {
  # fall back: first visible top-level window of that pid
  $h = [IntPtr]::Zero
}
Write-Output ("proc={0} pid={1} hwnd={2} title='{3}'" -f $p.ProcessName, $p.Id, $h, [SecProbeNative]::T($h))
if ($Dump) { Write-Output "children:"; Write-Output ([SecProbeNative]::Dump($h)) }
if ($Title) { Write-Output ("title now = '" + [SecProbeNative]::T($h) + "'") }
if ($SetText -ge 0) {
  $c = [SecProbeNative]::ById($h, $SetText)
  if ($c -eq [IntPtr]::Zero) { Write-Output "child id=$SetText not found"; exit 3 }
  [void][SecProbeNative]::SendMessageW($c, 0x000C, [IntPtr]::Zero, $Text)
  Start-Sleep -Milliseconds $WaitMs
  Write-Output ("title after WM_SETTEXT(id=$SetText) = '" + [SecProbeNative]::T($h) + "'")
}
if ($SetChildText -ge 0) {
  $c = [SecProbeNative]::ById($h, $SetChildText)
  if ($c -eq [IntPtr]::Zero) { Write-Output "child id=$SetChildText not found"; exit 3 }
  [void][SecProbeNative]::SendMessageW($c, 0x000C, [IntPtr]::Zero, $ChildText)
  Start-Sleep -Milliseconds $WaitMs
  Write-Output ("child id=$SetChildText text now = '" + [SecProbeNative]::T($c) + "'")
}
if ($Click -ge 0) {
  $c = [SecProbeNative]::ById($h, $Click)
  if ($c -eq [IntPtr]::Zero) { Write-Output "child id=$Click not found"; exit 3 }
  [void][SecProbeNative]::SendMessageW($c, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $WaitMs
  Write-Output ("title after BM_CLICK(id=$Click) = '" + [SecProbeNative]::T($h) + "'")
}
if ($Msg -ge 0) {
  $c = [SecProbeNative]::ById($h, $MsgId)
  if ($c -eq [IntPtr]::Zero) { Write-Output "child id=$MsgId not found"; exit 3 }
  $r = [SecProbeNative]::SendMessageW($c, [uint32]$Msg, [IntPtr]$MsgW, [IntPtr]$MsgL)
  Start-Sleep -Milliseconds $WaitMs
  Write-Output ("SendMessage(child id=$MsgId, msg=0x{0:X}) -> {1}; title now = '{2}'" -f $Msg, $r, [SecProbeNative]::T($h))
}
