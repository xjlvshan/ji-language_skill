# winenum.ps1 - ASCII only. Enumerate top-level windows of a PID / click a control in the #32770 dialog.
#   powershell -File winenum.ps1 -ProcId 1234                  -> list top-level windows
#   powershell -File winenum.ps1 -ProcId 1234 -ClickId 1       -> BM_CLICK child id=1 inside class #32770 dialog
param(
  [Parameter(Mandatory=$true)][int]$ProcId,
  [int]$ClickId = -1,
  [int]$WaitMs = 400
)
$ErrorActionPreference = 'Stop'
if (-not ("SecEnumNative" -as [type])) {
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class SecEnumNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static string T(IntPtr h){var sb=new StringBuilder(2048);GetWindowTextW(h,sb,2048);return sb.ToString();}
 public static string C(IntPtr h){var sb=new StringBuilder(256);GetClassNameW(h,sb,256);return sb.ToString();}
 public static List<IntPtr> TopOf(uint pid){var r=new List<IntPtr>();EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid)r.Add(h);return true;},IntPtr.Zero);return r;}
 public static IntPtr ChildById(IntPtr p,int id){IntPtr f=IntPtr.Zero;EnumChildWindows(p,(h,l)=>{if(f==IntPtr.Zero&&GetDlgCtrlID(h)==id)f=h;return true;},IntPtr.Zero);return f;}
}
"@ }
$list = [SecEnumNative]::TopOf([uint32]$ProcId)
foreach($h in $list){
  Write-Output ("hwnd={0} cls='{1}' visible={2} title='{3}'" -f $h, [SecEnumNative]::C($h), [SecEnumNative]::IsWindowVisible($h), [SecEnumNative]::T($h))
}
if($ClickId -ge 0){
  $dlg = $null
  foreach($h in $list){ if([SecEnumNative]::C($h) -eq '#32770'){ $dlg = $h; break } }
  if(-not $dlg){ Write-Output 'DIALOG NOT FOUND'; exit 3 }
  $c = [SecEnumNative]::ChildById($dlg, $ClickId)
  if($c -eq [IntPtr]::Zero){ Write-Output ("child id=$ClickId not found in dialog"); exit 4 }
  [void][SecEnumNative]::SendMessageW($c, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $WaitMs
  Write-Output ("BM_CLICK(id=$ClickId) sent to hwnd=$dlg")
  exit 0
}
exit 0