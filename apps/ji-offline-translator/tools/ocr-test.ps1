# ocr-test.ps1 - end-to-end test of 截图识别:
#   1) show a helper window with known text at a known screen position
#   2) launch the translator, click 截图识别 (button id 11)
#   3) drag a selection rectangle over the helper window with real mouse messages
#   4) wait for OCR + translation and read the input/output/status controls
#  [ASCII only]
param(
  [string]$Exe = ".\离线翻译助手.exe",
  [string]$Text = "Hello, how are you today?",
  [int]$StartWait = 12,
  [int]$OcrWait = 180,
  [string]$Shot = ".\shots\ocr-e2e.png",
  [string]$OverlayShot = ""
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if(-not ("OcrNative" -as [type])){
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class OcrNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,StringBuilder l);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 public static string C(IntPtr h){var sb=new StringBuilder(256);GetClassNameW(h,sb,256);return sb.ToString();}
 public static string Cap(IntPtr h){var sb=new StringBuilder(512);GetWindowTextW(h,sb,512);return sb.ToString();}
 public static string T(IntPtr h){var sb=new StringBuilder(200000);SendMessageW(h,0x000D,(IntPtr)sb.Capacity,sb);return sb.ToString();}
 public static IntPtr MainWin(uint pid){ IntPtr f=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
   if(C(h)!="SecClass") return true; f=h; return false;},IntPtr.Zero); return f; }
 // the selection overlay: a visible SecClass window wider than 1000 px
 public static IntPtr Overlay(uint pid, IntPtr exclude){ IntPtr f=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
   if(C(h)!="SecClass") return true; if(h==exclude) return true;
   RECT r; GetWindowRect(h,out r); if((r.R-r.L)<1000) return true; f=h; return false;},IntPtr.Zero); return f; }
 public static IntPtr ById(IntPtr p,int id){ IntPtr f=IntPtr.Zero;
  EnumChildWindows(p,(h,l)=>{ if(f==IntPtr.Zero && GetDlgCtrlID(h)==id) f=h; return true;},IntPtr.Zero); return f; }
 public static IntPtr LP(int x,int y){ return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@ }

function Pump([int]$ms){
  $sw=[Diagnostics.Stopwatch]::StartNew()
  while($sw.ElapsedMilliseconds -lt $ms){ [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
}

# ---------- 1. helper window with known text ----------
$form = New-Object Windows.Forms.Form
$form.Text = "ocr-target"
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point 100,100
$form.ClientSize = New-Object Drawing.Size 880,130
$form.FormBorderStyle = 'None'
$form.BackColor = [Drawing.Color]::White
$lbl = New-Object Windows.Forms.Label
$lbl.Text = $Text
$lbl.Font = New-Object Drawing.Font 'Consolas',34
$lbl.ForeColor = [Drawing.Color]::Black
$lbl.Dock = 'Fill'
$lbl.TextAlign = 'MiddleLeft'
$form.Controls.Add($lbl)
$form.TopMost = $true
$form.Show()
Pump 800
Write-Output "helper window shown at (100,100) size 880x130 : '$Text'"

# ---------- 2. launch the translator ----------
$Exe = (Resolve-Path $Exe).Path
$proc = Start-Process $Exe -PassThru
$hw=[IntPtr]::Zero
for($i=0;$i -lt 40 -and $hw -eq [IntPtr]::Zero;$i++){ Pump 300; $hw=[OcrNative]::MainWin([uint32]$proc.Id) }
if($hw -eq [IntPtr]::Zero){ Write-Output "main window not found"; $form.Close(); if(-not $proc.HasExited){$proc.Kill()}
  Start-Sleep -Milliseconds 500
  Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $proc.Id) -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; exit 3 }
Write-Output "pid=$($proc.Id) main=$hw"
Pump ($StartWait*1000)

# ---------- 3. click 截图识别 and drag ----------
$btn=[OcrNative]::ById($hw,11)
if($btn -eq [IntPtr]::Zero){ Write-Output "button 11 not found"; $proc.Kill(); $form.Close(); exit 4 }

function ClickCapture(){
  [void][OcrNative]::SendMessageW($btn,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)   # BM_CLICK
  Pump 1500
  return [OcrNative]::Overlay([uint32]$proc.Id,$hw)
}

# phase A: right-click cancel (also proves the overlay window is reused)
for($rep=1; $rep -le 2; $rep++){
  $ovc = ClickCapture
  if($ovc -eq [IntPtr]::Zero){ Write-Output "rep$rep overlay not found"; break }
  [void][OcrNative]::SendMessageW($ovc,0x0204,[IntPtr]2,[OcrNative]::LP(400,300))   # WM_RBUTTONDOWN
  Pump 1200
  $stc=[OcrNative]::ById([OcrNative]::MainWin([uint32]$proc.Id),22)
  Write-Output ("cancel #{0}: overlay={1} status='{2}'" -f $rep,$ovc,[OcrNative]::T($stc))
}

$ov=ClickCapture
if($ov -eq [IntPtr]::Zero){ Write-Output "selection overlay not found"; $proc.Kill(); $form.Close(); exit 5 }
$r=New-Object OcrNative+RECT; [void][OcrNative]::GetWindowRect($ov,[ref]$r)
Write-Output ("overlay hwnd={0} rect={1},{2}-{3},{4}" -f $ov,$r.L,$r.T,$r.R,$r.B)

# drag from (110,110) to (1000,240) in screen coords == overlay client coords
$p1=[OcrNative]::LP(110,110); $p2=[OcrNative]::LP(1000,240)
[void][OcrNative]::SendMessageW($ov,0x0201,[IntPtr]1,$p1)   # WM_LBUTTONDOWN
Pump 300
[void][OcrNative]::SendMessageW($ov,0x0200,[IntPtr]1,$p2)   # WM_MOUSEMOVE
Pump 400
if($OverlayShot -ne ""){
  $dir=[IO.Path]::GetDirectoryName($OverlayShot); if($dir -and -not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $b=New-Object Drawing.Bitmap 3200,1080
  $g=[Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen(0,0,0,0,(New-Object Drawing.Size 3200,1080))
  $g.Dispose(); $b.Save($OverlayShot,[Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
  Write-Output "overlay shot -> $OverlayShot"
}
Pump 300
[void][OcrNative]::SendMessageW($ov,0x0202,[IntPtr]0,$p2)   # WM_LBUTTONUP
Write-Output "dragged 110,110 -> 1000,240"

# ---------- 4. wait for OCR ----------
$st=[IntPtr]::Zero; $inp=[IntPtr]::Zero; $out=[IntPtr]::Zero
$deadline=(Get-Date).AddSeconds($OcrWait)
$last=''
while((Get-Date) -lt $deadline){
  Pump 1000
  if($proc.HasExited){ Write-Output "PROCESS EXITED code=$($proc.ExitCode)"; $form.Close(); exit 6 }
  $w=[OcrNative]::MainWin([uint32]$proc.Id)
  if($w -eq [IntPtr]::Zero){ continue }
  $st=[OcrNative]::ById($w,22)
  $s=[OcrNative]::T($st)
  if($s -ne $last){ Write-Output "  status: $s"; $last=$s }
  if($s -match '识别完成' -or $s -match '失败'){ break }
}
$w=[OcrNative]::MainWin([uint32]$proc.Id)
$inp=[OcrNative]::ById($w,16); $out=[OcrNative]::ById($w,17)
Write-Output "--- result ---"
Write-Output ("status = " + [OcrNative]::T([OcrNative]::ById($w,22)))
Write-Output ("input  = " + ([OcrNative]::T($inp) -replace "`r`n","\n"))
Write-Output ("output = " + ([OcrNative]::T($out) -replace "`r`n","\n"))

if($Shot -ne ""){
  $dir=[IO.Path]::GetDirectoryName($Shot); if($dir -and -not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $rr=New-Object OcrNative+RECT; [void][OcrNative]::GetWindowRect($w,[ref]$rr)
  $bmp=New-Object Drawing.Bitmap ($rr.R-$rr.L),($rr.B-$rr.T)
  $g=[Drawing.Graphics]::FromImage($bmp); $dc=$g.GetHdc()
  [void][OcrNative]::PrintWindow($w,$dc,2)
  $g.ReleaseHdc($dc); $g.Dispose(); $bmp.Save($Shot,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  Write-Output "shot -> $Shot"
}

# ---------- 5. cleanup ----------
$form.Close()
if(-not $proc.HasExited){ $proc.Kill() }
  Start-Sleep -Milliseconds 500
  Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $proc.Id) -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Output "done"
