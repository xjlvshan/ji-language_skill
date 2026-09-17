# sec.ps1 - Ji Language (SEC / Sc.exe) build+run harness   [ASCII only on purpose]
# lock-free: each call only touches the Sc.exe process it started, so several calls can run in parallel
# usage:
#   powershell -File sec.ps1 -Src a.txt
#   powershell -File sec.ps1 -Src a.txt -Run [-RunSeconds 6]
# source must be GBK plain text (no BOM); extension .txt / .SEC recommended
param(
  [Parameter(Mandatory=$true)][string]$Src,
  [switch]$Run,
  [int]$RunSeconds = 6,
  [int]$WaitSec = 15
)
$ErrorActionPreference='Stop'
if(-not ("SecBuildNative" -as [type])){
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class SecBuildNative{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h,uint m,IntPtr w,StringBuilder l);
 [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static string Txt(IntPtr h){ var sb=new StringBuilder(120000); SendMessageW(h,0x000D,(IntPtr)sb.Capacity,sb); return sb.ToString(); }
 public static string Cls(IntPtr h){ var sb=new StringBuilder(256); GetClassNameW(h,sb,256); return sb.ToString(); }
 public static string Cap(IntPtr h){ var sb=new StringBuilder(1024); GetWindowTextW(h,sb,1024); return sb.ToString(); }
 public static List<IntPtr> Dlg(uint want){ var res=new List<IntPtr>();
  EnumWindows((h,l)=>{ uint pid; GetWindowThreadProcessId(h,out pid); if(pid!=want) return true; if(!IsWindowVisible(h)) return true;
   string c=Cls(h); if(c=="ThunderRT6FormDC" || c=="#32770") res.Add(h); return true;},IntPtr.Zero); return res; }
 public static List<IntPtr> Kids(IntPtr p){ var res=new List<IntPtr>(); EnumChildWindows(p,(h,l)=>{res.Add(h);return true;},IntPtr.Zero); return res; }
 public static string AllText(IntPtr dlg){ var sb=new StringBuilder(); foreach(var k in Kids(dlg)){ string c=Cls(k); if(c=="ThunderRT6TextBox"||c=="Static"||c=="Edit"){ string t=Txt(k); if(t.Trim().Length>0) sb.AppendLine(t); } } return sb.ToString(); }
}
"@ }
$SecDir = 'D:\SEC'
if(-not (Test-Path "$SecDir\Sc.exe")){ Write-Output "FATAL: Sc.exe not found"; exit 2 }
$M_ERR1  = [string]([char]0x5185 + [char]0x90E8 + [char]0x9519 + [char]0x8BEF)
$M_ERR2  = [string]([char]0x672A + [char]0x5B9A + [char]0x4E49 + [char]0x7684 + [char]0x540D + [char]0x79F0)
$M_ERR3  = [string]([char]0x4E0D + [char]0x5B58 + [char]0x5728)
$M_ERR4  = [string]([char]0x8BED + [char]0x6CD5 + [char]0x6709 + [char]0x8BEF)
$srcFull = (Resolve-Path $Src).Path
# --- normalize source: accept UTF-8 or GBK, force GBK + CRLF (compiler needs CRLF) ---
$raw = [IO.File]::ReadAllBytes($srcFull)
$txt = $null
if($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF){ $txt = [Text.Encoding]::UTF8.GetString($raw,3,$raw.Length-3) }
else {
  try { $strict = New-Object Text.UTF8Encoding($false,$true); $txt = $strict.GetString($raw) }
  catch { $txt = [Text.Encoding]::GetEncoding(936).GetString($raw) }
}
$norm = $txt.Replace("`r`n","`n").Replace("`r","`n").Replace("`n","`r`n")
if($norm -ne $txt -or $null -ne $txt){
  $orig = [Text.Encoding]::GetEncoding(936).GetString($raw)
  if($norm -ne $orig){ [IO.File]::WriteAllText($srcFull,$norm,[Text.Encoding]::GetEncoding(936)) }
}
$base = [IO.Path]::GetFileNameWithoutExtension($srcFull)
$folder = [IO.Path]::GetDirectoryName($srcFull)
$cands = New-Object Collections.ArrayList
foreach($ext in @('.exe','.com','.bin','.dll')){ [void]$cands.Add((Join-Path $folder ($base + $ext))) }
# housekeeping: drop only ancient Sc.exe leftovers (started > 180s ago)
Get-Process Sc -ErrorAction SilentlyContinue | Where-Object { ((Get-Date) - $_.StartTime).TotalSeconds -gt 180 } | Stop-Process -Force -ErrorAction SilentlyContinue
foreach($c in $cands){ if(Test-Path $c){ Remove-Item $c -Force -ErrorAction SilentlyContinue } }
$proc=$null
try{
  $proc = Start-Process "$SecDir\Sc.exe" -ArgumentList $srcFull -PassThru
  $dlg=[IntPtr]::Zero; $deadline=(Get-Date).AddSeconds($WaitSec)
  while((Get-Date) -lt $deadline){
    Start-Sleep -Milliseconds 200
    if($proc.HasExited){ break }
    $d=[SecBuildNative]::Dlg([uint32]$proc.Id)
    if($d.Count -gt 0){ $dlg=$d[0]; break }
  }
  $msgs=''; $title=''
  if($dlg -ne [IntPtr]::Zero){
    $title=[SecBuildNative]::Cap($dlg)
    $msgs=[SecBuildNative]::AllText($dlg)
    [void][SecBuildNative]::PostMessageW($dlg,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 250
  }
  if($proc -and -not $proc.HasExited){ try{ $proc.Kill() }catch{} }; Start-Sleep -Milliseconds 200
  $art=$null; $t3=(Get-Date).AddSeconds(8)
  while((Get-Date) -lt $t3){
    foreach($c in $cands){ if(Test-Path $c){ $art=$c; break } }
    if($art){ break }
    if($proc.HasExited -and $dlg -ne [IntPtr]::Zero){ } 
    Start-Sleep -Milliseconds 200
  }
  $hasErr = ($msgs -match [regex]::Escape($M_ERR1)) -or ($msgs -match [regex]::Escape($M_ERR2)) -or ($msgs -match [regex]::Escape($M_ERR3)) -or ($msgs -match [regex]::Escape($M_ERR4))
  $ok = ($null -ne $art) -and (-not $hasErr)
  Write-Output ("BUILD_" + $(if($ok){'OK'}else{'FAIL'}))
  if($msgs.Trim().Length -gt 0){ Write-Output "--- compiler messages ---"; Write-Output $msgs.Trim() }
  if($title.Trim().Length -gt 0){ Write-Output "DIALOG_TITLE: $($title.Trim())" }
  if($art){ Write-Output "ARTIFACT: $art ($((Get-Item $art).Length) bytes)" } else { Write-Output "ARTIFACT: <none>" }
  if($Run -and $art){
    Write-Output "--- program output ---"
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$art; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.UseShellExecute=$false; $psi.StandardOutputEncoding=[Text.Encoding]::GetEncoding(936); $psi.StandardErrorEncoding=[Text.Encoding]::GetEncoding(936)
    $psi.WorkingDirectory=$folder
    $done=$false; $out=''; $err=''
    for($attempt=1; $attempt -le 2 -and -not $done; $attempt++){
      $p=[Diagnostics.Process]::Start($psi)
      $done=$p.WaitForExit($RunSeconds*1000)
      if($done){ Write-Output "[exit=$($p.ExitCode)]" } else { Write-Output "[TIMEOUT ${RunSeconds}s attempt $attempt -> killed]"; try{ $p.Kill() }catch{}; Start-Sleep -Milliseconds 400 }
      $out=$p.StandardOutput.ReadToEnd(); $err=$p.StandardError.ReadToEnd()
    }
    Write-Output $out
    if($err.Trim().Length -gt 0){ Write-Output "[stderr]"; Write-Output $err }
  }
} finally {
  if($proc -and -not $proc.HasExited){ try{ $proc.Kill() }catch{} }
}
