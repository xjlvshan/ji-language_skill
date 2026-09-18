# build-check.ps1 - Ji Language (SEC) build + ARTIFACT LOAD VALIDATION
#   sec.ps1 only checks "artifact exists + no compiler error text".
#   It CANNOT tell that the produced PE is rejected by Windows
#   (error 193 ERROR_BAD_EXE_FORMAT) - a real failure mode of this compiler.
#   This wrapper compiles via sec.ps1 and then really tries to CreateProcess it.
#
# usage:
#   powershell -File build-check.ps1 -Src app.txt
#   powershell -File build-check.ps1 -Src app.txt -RunSeconds 5   # GUI keep-alive test
#
# ASCII only on purpose (Windows PowerShell 5.1 reads non-BOM scripts as ANSI).
param(
  [Parameter(Mandatory=$true)][string]$Src,
  [int]$RunSeconds = 0,
  [int]$RunSecondsConsole = 0
)
$ErrorActionPreference = 'Continue'

function Write-Out($m){ Write-Output $m }

$srcFull = (Resolve-Path $Src).Path
$sec = Join-Path $PSScriptRoot 'sec.ps1'
if(-not (Test-Path $sec)){ Write-Out "FATAL: sec.ps1 not found next to build-check.ps1"; exit 2 }

Write-Out "=== build ==="
$build = & powershell -ExecutionPolicy Bypass -File $sec -Src $srcFull 2>&1 | Out-String
Write-Out $build.TrimEnd()

$base   = [IO.Path]::GetFileNameWithoutExtension($srcFull)
$folder = [IO.Path]::GetDirectoryName($srcFull)
$art = $null
foreach($ext in @('.exe','.com','.bin','.dll')){
  $c = Join-Path $folder ($base + $ext)
  if(Test-Path $c){ $art = $c; break }
}
if(-not $art){ Write-Out 'LOAD_FAIL (no artifact produced)'; exit 1 }

if($build -notmatch 'BUILD_OK'){
  Write-Out 'NOTE: compiler reported BUILD_FAIL but an artifact exists; still validating it.'
}

# ---- validate by actually loading the image ----
if(-not ("SecLoadCheck" -as [type])){
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SecLoadCheck{
 [StructLayout(LayoutKind.Sequential)] public struct SI{
   public int cb; public string r1,r2,r3;
   public int x,y,xs,ys,xc,yc,fa,fl; public short sw; public short rr;
   public IntPtr r4,hi,ho,he; }
 [StructLayout(LayoutKind.Sequential)] public struct PI{ public IntPtr hp,ht; public int pid,tid; }
 [DllImport("kernel32.dll",SetLastError=true,CharSet=CharSet.Ansi)]
 public static extern bool CreateProcessA(string app,string cmd,IntPtr pa,IntPtr ta,
   bool inherit,int flags,IntPtr env,string dir,ref SI si,out PI pi);
}
"@ }

$si = New-Object SecLoadCheck+SI
$si.cb = 68
$pi = New-Object SecLoadCheck+PI
$ok = [SecLoadCheck]::CreateProcessA($art, $null, [IntPtr]::Zero, [IntPtr]::Zero,
        $false, 0x08000000, [IntPtr]::Zero, $folder, [ref]$si, [ref]$pi)

if(-not $ok){
  $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  $msg = (New-Object ComponentModel.Win32Exception($e)).Message
  Write-Out ("LOAD_FAIL({0}) {1}  <== Windows refuses to load this PE" -f $e,$msg)
  if($e -eq 193){
    Write-Out '  This is the known compiler bug: image is self-consistent but rejected.'
    Write-Out '  Workaround: split/rewrite the procedure that triggers it, then rebuild.'
  }
  exit 3
}

$size = (Get-Item $art).Length
Write-Out ("LOAD_OK  {0} ({1} bytes)  pid={2}" -f $art,$size,$pi.pid)

if($RunSeconds -gt 0){
  Start-Sleep -Seconds $RunSeconds
  $alive = Get-Process -Id $pi.pid -ErrorAction SilentlyContinue
  if($alive){
    Write-Out ("ALIVE   still running after {0}s" -f $RunSeconds)
  } else {
    $ext = [IO.Path]::GetExtension($art).ToLower()
    if($ext -eq '.com'){
      Write-Out ("EXITED  console program finished within {0}s (normal for a console app)" -f $RunSeconds)
    } else {
      Write-Out ("EXITED  GUI program died within {0}s  <== look for 0xC0000005 / 0xC0000409" -f $RunSeconds)
    }
  }
}

if($pi.pid -gt 0){ Stop-Process -Id $pi.pid -Force -ErrorAction SilentlyContinue }
Write-Out '=== done ==='
