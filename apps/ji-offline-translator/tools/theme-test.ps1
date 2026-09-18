# theme-test.ps1 - start the translator once, switch the theme combobox through every
# item and save one screenshot per theme.  [ASCII only]
#
# usage: powershell -File tools\theme-test.ps1 -Exe .\离线翻译助手.exe -OutDir .\shots
param(
  [string]$Exe = ".\离线翻译助手.exe",
  [string]$OutDir = ".\shots",
  [int]$ComboId = 4,
  [int]$StartWait = 12,
  [int]$Settle = 3,
  [int]$WaitMs = 2500
)
$ErrorActionPreference='Stop'
if(-not ("TTNative" -as [type])){
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class TTNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern IntPtr PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 public static string C(IntPtr h){var sb=new StringBuilder(256);GetClassNameW(h,sb,256);return sb.ToString();}
 public static string Cap(IntPtr h){var sb=new StringBuilder(512);GetWindowTextW(h,sb,512);return sb.ToString();}
 public static IntPtr MainWin(uint pid){ IntPtr f=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
   if(C(h)!="SecClass") return true; f=h; return false;},IntPtr.Zero); return f; }
 public static IntPtr ById(IntPtr p,int id){ IntPtr f=IntPtr.Zero;
  EnumChildWindows(p,(h,l)=>{ if(f==IntPtr.Zero && GetDlgCtrlID(h)==id) f=h; return true;},IntPtr.Zero); return f; }
 public static int ComboCount(IntPtr c){ return (int)SendMessageW(c,0x0146,IntPtr.Zero,IntPtr.Zero); }   // CB_GETCOUNT
}
"@ }
Add-Type -AssemblyName System.Drawing

$Exe = (Resolve-Path $Exe).Path
if(-not (Test-Path $OutDir)){ New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$proc = Start-Process $Exe -PassThru
$hw=[IntPtr]::Zero
for($i=0;$i -lt 40 -and $hw -eq [IntPtr]::Zero;$i++){ Start-Sleep -Milliseconds 300; $hw=[TTNative]::MainWin([uint32]$proc.Id) }
if($hw -eq [IntPtr]::Zero){ Write-Output "main window not found"; if(-not $proc.HasExited){$proc.Kill()}
  Start-Sleep -Milliseconds 500
  Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $proc.Id) -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; exit 3 }
Write-Output "pid=$($proc.Id) hwnd=$hw title='$([TTNative]::Cap($hw))'"
Start-Sleep -Seconds $StartWait
[void][TTNative]::SetForegroundWindow($hw); Start-Sleep -Milliseconds 500

$combo=[TTNative]::ById($hw,$ComboId)
if($combo -eq [IntPtr]::Zero){ Write-Output "combobox id=$ComboId not found"; $proc.Kill(); exit 4 }

for($idx=0; $idx -lt 3; $idx++){
  [void][TTNative]::SendMessageW($combo,0x014E,[IntPtr]$idx,[IntPtr]::Zero)                       # CB_SETCURSEL
  $wp = [int64]((1 -shl 16) -bor $ComboId)                                                       # CBN_SELCHANGE<<16 | id
  [void][TTNative]::SendMessageW($hw,0x0111,[IntPtr]$wp,[IntPtr]$combo)                          # WM_COMMAND to parent
  Start-Sleep -Milliseconds $WaitMs
  $lv=[TTNative]::ById($hw,21)
  $lvbk=0; $lvtx=0
  if($lv -ne [IntPtr]::Zero){
    $lvbk=[int][TTNative]::SendMessageW($lv,0x1000,[IntPtr]::Zero,[IntPtr]::Zero)   # LVM_GETBKCOLOR
    $lvtx=[int][TTNative]::SendMessageW($lv,0x1023,[IntPtr]::Zero,[IntPtr]::Zero)   # LVM_GETTEXTCOLOR
  }
  $r = New-Object TTNative+RECT; [void][TTNative]::GetWindowRect($hw,[ref]$r)
  $w=$r.R-$r.L; $h=$r.B-$r.T
  $bmp = New-Object Drawing.Bitmap $w,$h
  $g=[Drawing.Graphics]::FromImage($bmp); $dc=$g.GetHdc()
  [void][TTNative]::PrintWindow($hw,$dc,2)
  $g.ReleaseHdc($dc); $g.Dispose()
  $out = Join-Path $OutDir ("theme-{0}.png" -f $idx)
  $bmp.Save($out,[Drawing.Imaging.ImageFormat]::Png)
  $px = $bmp.GetPixel(60,700).ToString()
  $bmp.Dispose()
  Write-Output ("theme {0} -> {1}  LVM_BK=0x{2:X6} LVM_TX=0x{3:X6} listPixel={4}" -f $idx,$out,$lvbk,$lvtx,$px)
}

if(-not $proc.HasExited){ $proc.Kill() }
  Start-Sleep -Milliseconds 500
  Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $proc.Id) -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Output "done"
