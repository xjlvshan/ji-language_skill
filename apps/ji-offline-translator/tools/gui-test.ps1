# gui-test.ps1 - offline translator GUI end-to-end test  (ASCII only on purpose:
# Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI, so Chinese breaks the parser)
#
# usage:
#   powershell -File tools\gui-test.ps1 -Exe .\src\translator.exe -Type "Hello"
#   powershell -File tools\gui-test.ps1 -ProcId 1234 -Click 23 -Settle 8 -Shot .\shots\x.png
#
# Typing is done with real WM_CHAR messages (SetWindowTextA from outside is NOT
# visible to the in-process "~" control operator - see README section 6 #15).
param(
  [string]$Exe = "",
  [int]$ProcId = 0,
  [string]$Type = "",
  [int]$StartWait = 10,     # seconds to wait for engine/window readiness
  [int]$TypeDelay = 40,     # ms between typed characters
  [int]$Settle = 6,         # seconds to wait after input before judging
  [int[]]$Click = @(),      # control IDs to BM_CLICK in order
  [int]$ClickDelay = 3000,
  [string]$Shot = "",
  [int[]]$Extra = @(),      # extra "wait N" points? (unused)
  [switch]$Keep
)
$ErrorActionPreference = 'Stop'

if (-not ("GuiTestNative" -as [type])) {
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class GuiTestNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,StringBuilder l);
 [DllImport("user32.dll")] public static extern IntPtr PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 public static string T(IntPtr h){var sb=new StringBuilder(200000);SendMessageW(h,0x000D,(IntPtr)sb.Capacity,sb);return sb.ToString();}
 public static string C(IntPtr h){var sb=new StringBuilder(256);GetClassNameW(h,sb,256);return sb.ToString();}
 public static string Cap(IntPtr h){var sb=new StringBuilder(512);GetWindowTextW(h,sb,512);return sb.ToString();}
 public static IntPtr MainWin(uint pid){ IntPtr f=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
   if(C(h)!="SecClass") return true; f=h; return false;},IntPtr.Zero); return f; }
 public static IntPtr ById(IntPtr p,int id){ IntPtr f=IntPtr.Zero;
  EnumChildWindows(p,(h,l)=>{ if(f==IntPtr.Zero && GetDlgCtrlID(h)==id) f=h; return true;},IntPtr.Zero); return f; }
 public static string Dump(IntPtr p){ var r=new StringBuilder();
  EnumChildWindows(p,(h,l)=>{ r.Append(string.Format("  id={0,-3} cls={1,-16} text='{2}'",GetDlgCtrlID(h),C(h),T(h).Replace("\r\n","\\n").Replace("\r","\\n").Replace("\n","\\n"))); r.Append(Environment.NewLine); return true;},IntPtr.Zero); return r.ToString(); }
}
"@ }

function Find-Window([int]$targetPid) {
  for ($i=0; $i -lt 40; $i++) {
    $h = [GuiTestNative]::MainWin([uint32]$targetPid)
    if ($h -ne [IntPtr]::Zero) { return $h }
    Start-Sleep -Milliseconds 300
  }
  return [IntPtr]::Zero
}

$proc = $null
if ($ProcId -ne 0) {
  $proc = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
  if (-not $proc) { Write-Output "proc $ProcId not found"; exit 2 }
} else {
  if (-not $Exe) { Write-Output "need -Exe or -ProcId"; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  $proc = Start-Process $Exe -PassThru
  Write-Output "started pid=$($proc.Id) exe=$Exe"
}

$hw = Find-Window $proc.Id
if ($hw -eq [IntPtr]::Zero) { Write-Output "main window (SecClass) not found"; exit 3 }
Write-Output "main hwnd=$hw title='$([GuiTestNative]::Cap($hw))'"
if ($StartWait -gt 0) { Start-Sleep -Seconds $StartWait }
if (-not $proc.HasExited) { [void][GuiTestNative]::ShowWindow($hw,9); [void][GuiTestNative]::SetForegroundWindow($hw) }
Start-Sleep -Milliseconds 400

if ($Type -ne "") {
  $edit = [GuiTestNative]::ById($hw,16)
  if ($edit -eq [IntPtr]::Zero) { Write-Output "input edit(id=16) not found"; exit 4 }
  # '|' in -Type means "pause 2500 ms here" (to let a debounce timer fire)
  $bytes = [Text.Encoding]::GetEncoding(936).GetBytes($Type)
  foreach ($b in $bytes) {
    if ($b -eq 0x7C) { Start-Sleep -Milliseconds 2500; Write-Output "  [pause]"; continue }
    [void][GuiTestNative]::SendMessageW($edit, 0x0102, [IntPtr][int]$b, [IntPtr]::Zero)   # WM_CHAR
    Start-Sleep -Milliseconds $TypeDelay
    if ($proc.HasExited) { break }
  }
  Write-Output "typed $($bytes.Length) bytes (GBK)"
}

foreach ($id in $Click) {
  if ($proc.HasExited) { break }
  $c = [GuiTestNative]::ById($hw,$id)
  if ($c -eq [IntPtr]::Zero) { Write-Output "button id=$id not found"; continue }
  [void][GuiTestNative]::SendMessageW($c, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)  # BM_CLICK
  Write-Output "clicked id=$id"
  Start-Sleep -Milliseconds $ClickDelay
}

if ($Settle -gt 0 -and -not $proc.HasExited) { Start-Sleep -Seconds $Settle }

if ($Shot -ne "") {
  $dir = [IO.Path]::GetDirectoryName($Shot); if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Add-Type -AssemblyName System.Drawing
  Add-Type @"
using System;using System.Runtime.InteropServices;
public class ShotNative{
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
}
"@
  $w3 = [GuiTestNative]::MainWin([uint32]$proc.Id)
  if ($w3 -ne [IntPtr]::Zero) {
    $r = New-Object ShotNative+RECT; [void][ShotNative]::GetWindowRect($w3,[ref]$r)
    $bw = $r.R - $r.L; $bh = $r.B - $r.T
    $bmp = New-Object Drawing.Bitmap $bw,$bh
    $g = [Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
    [void][ShotNative]::PrintWindow($w3,$dc,2)
    $g.ReleaseHdc($dc); $g.Dispose()
    $bmp.Save($Shot,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output "shot $Shot (${bw}x${bh})"
  } else { Write-Output "shot skipped (no window)" }
}

Write-Output "--- state ---"
if ($proc.HasExited) {
  Write-Output "PROCESS EXITED code=$($proc.ExitCode)  (0xC0000409 = -1073740791, 0xC0000005 = -1073741819)"
} else {
  $w = [GuiTestNative]::MainWin([uint32]$proc.Id)
  if ($w -eq [IntPtr]::Zero) { Write-Output "ALIVE but main window gone" }
  else {
    $st = [GuiTestNative]::ById($w,22); $out = [GuiTestNative]::ById($w,17); $inp = [GuiTestNative]::ById($w,16)
    Write-Output "ALIVE  status='$([GuiTestNative]::T($st))'"
    Write-Output "input ='$(([GuiTestNative]::T($inp) -replace "`r`n","\n"))'"
    Write-Output "output='$(([GuiTestNative]::T($out) -replace "`r`n","\n"))'"
    if ($Shot -eq "") { Write-Output "--- children ---"; Write-Output ([GuiTestNative]::Dump($w)) }
  }
}

if (-not $Keep -and $ProcId -eq 0) {
  # close the window first so the app's own 收尾 runs (it kills the python engine);
  # only then fall back to Kill + reaping stray bridge.py children
  if (-not $proc.HasExited) {
    $wm = [GuiTestNative]::MainWin([uint32]$proc.Id)
    if ($wm -ne [IntPtr]::Zero) { [void][GuiTestNative]::PostMessageW($wm,0x0010,[IntPtr]::Zero,[IntPtr]::Zero) }
    for ($i=0; $i -lt 20 -and -not $proc.HasExited; $i++) { Start-Sleep -Milliseconds 200 }
    if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
  }
  Start-Sleep -Milliseconds 500
  Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $proc.Id) -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Write-Output "closed pid=$($proc.Id)"
}
