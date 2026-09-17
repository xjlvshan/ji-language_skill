# shot.ps1 - capture a window to PNG (the built-in screenshot tool is broken this session)
# usage: powershell -File shot.ps1 -Proc calc -Out D:\tmp\a.png
#        powershell -File shot.ps1 -Title 'ji' -Out D:\tmp\a.png
param([string]$Proc,[string]$Title,[Parameter(Mandatory=$true)][string]$Out,[int]$W=0,[int]$H=0)
Add-Type -AssemblyName System.Drawing
if(-not ("ShotNative" -as [type])){
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class ShotNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 public static string Cap(IntPtr h){ var sb=new StringBuilder(512); GetWindowTextW(h,sb,512); return sb.ToString(); }
 public static IntPtr Find(uint pid,string title){
  IntPtr found=IntPtr.Zero;
  EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true; uint p; GetWindowThreadProcessId(h,out p);
    string t=Cap(h); if(t.Length==0) return true;
    if(pid!=0 && p!=pid) return true;
    if(title.Length>0 && t.IndexOf(title,StringComparison.OrdinalIgnoreCase)<0) return true;
    RECT r; GetWindowRect(h,out r); if((r.R-r.L)<20||(r.B-r.T)<20) return true;
    found=h; return false;},IntPtr.Zero); return found; }
}
"@ }
$pid2=0; if($Proc){ $p=Get-Process $Proc -ErrorAction SilentlyContinue | Select-Object -First 1; if(-not $p){ Write-Output "process $Proc not found"; exit 1 }; $pid2=$p.Id }
$hw=[ShotNative]::Find([uint32]$pid2,$(if($Title){$Title}else{''}))
if($hw -eq [IntPtr]::Zero){ Write-Output 'window not found'; exit 1 }
[void][ShotNative]::ShowWindow($hw,9); [void][ShotNative]::SetForegroundWindow($hw); Start-Sleep -Milliseconds 600
$r=New-Object ShotNative+RECT; [void][ShotNative]::GetWindowRect($hw,[ref]$r)
$w=$r.R-$r.L; $ht=$r.B-$r.T
if($W -gt 0){$w=$W}; if($H -gt 0){$ht=$H}
$bmp=New-Object Drawing.Bitmap $w,$ht
$g=[Drawing.Graphics]::FromImage($bmp)
$hdc=$g.GetHdc()
[void][ShotNative]::PrintWindow($hw,$hdc,2)
$g.ReleaseHdc($hdc); $g.Dispose()
$dir=[IO.Path]::GetDirectoryName($Out); if($dir -and -not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bmp.Save($Out,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output "saved $Out (${w}x${ht}) hwnd=$hw title='$([ShotNative]::Cap($h))'"
