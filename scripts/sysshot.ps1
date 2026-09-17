# sysshot.ps1 - screenshot the console window of a given process (ASCII only)
param([Parameter(Mandatory=$true)][int]$Pid2,[Parameter(Mandatory=$true)][string]$Out)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
if(-not ("SysShotNative" -as [type])){
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class SysShotNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 [StructLayout(LayoutKind.Sequential)] public struct POINT{public int X,Y;}
 public static string Cls(IntPtr h){ var sb=new StringBuilder(256); GetClassNameW(h,sb,256); return sb.ToString(); }
 public static IntPtr Find(uint pid){ IntPtr found=IntPtr.Zero;
  EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p!=pid) return true; if(!IsWindowVisible(h)) return true;
    string c=Cls(h); if(c=="ConsoleWindowClass"){ found=h; return false; } return true;},IntPtr.Zero); return found; }
}
"@ }
$h=[SysShotNative]::Find([uint32]$Pid2)
if($h -eq [IntPtr]::Zero){ Write-Output 'console window not found'; exit 1 }
[void][SysShotNative]::ShowWindow($h,5)
[void][SysShotNative]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 900
$r=New-Object SysShotNative+RECT; [void][SysShotNative]::GetWindowRect($h,[ref]$r)
$w=$r.R-$r.L; $ht=$r.B-$r.T
if($w -lt 20 -or $ht -lt 20){ $w=960; $ht=480 }
$bmp=New-Object Drawing.Bitmap $w,$ht
$g=[Drawing.Graphics]::FromImage($bmp)
$hdc=$g.GetHdc()
[void][SysShotNative]::PrintWindow($h,$hdc,3)
$g.ReleaseHdc($hdc)
$g.Dispose()
$dir=[IO.Path]::GetDirectoryName($Out); if($dir -and -not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bmp.Save($Out,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output "saved $Out (${w}x${ht}) hwnd=$h"
