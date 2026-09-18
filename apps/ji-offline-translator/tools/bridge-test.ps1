# bridge-test.ps1 - talk to bridge.py directly (skip the GUI)  [ASCII only]
# usage: powershell -File tools\bridge-test.ps1 -Cmd translate -Text "Hello" -Wait 60
#        powershell -File tools\bridge-test.ps1 -Cmd ocr_translate -Img D:\tmp\a.bmp -Wait 120
param(
  [string]$Root = "",          # project root (defaults to parent of this script)
  [string]$Cmd = "translate",
  [string]$Text = "Hello",
  [string]$Dir = "auto",
  [string]$Img = "",
  [int]$Wait = 60,             # max seconds to wait for bridge_port.txt
  [switch]$NoStart             # do not start the engine, just use an existing port file
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$py = Join-Path $Root 'engine\python.exe'
$bridge = Join-Path $Root 'bridge.py'
$portFile = Join-Path $Root 'bridge_port.txt'

$proc = $null
if (-not $NoStart) {
  if (Test-Path $portFile) { Remove-Item $portFile -Force }
  $proc = Start-Process -FilePath $py -ArgumentList "`"$bridge`"" -WorkingDirectory $Root -PassThru -WindowStyle Hidden
  Write-Output "started bridge pid=$($proc.Id)"
}
$t0 = Get-Date
$port = 0
while (((Get-Date) - $t0).TotalSeconds -lt $Wait) {
  if (Test-Path $portFile) {
    Start-Sleep -Milliseconds 300
    $s = (Get-Content $portFile -Raw).Trim()
    if ($s -match '^\d+$') { $port = [int]$s; break }
  }
  if ($proc -and $proc.HasExited) { Write-Output "bridge died early code=$($proc.ExitCode)"; break }
  Start-Sleep -Milliseconds 300
}
if ($port -le 0) { Write-Output "NO PORT after $Wait s"; if ($proc -and -not $proc.HasExited) { $proc.Kill() }; exit 2 }
Write-Output "port=$port  (ready after $([int]((Get-Date)-$t0).TotalSeconds)s)"

if ($Cmd -eq 'ocr' -or $Cmd -eq 'ocr_translate') {
  $req = '{"cmd":"' + $Cmd + '","img":"' + ($Img -replace '\\','\\') + '","dir":"' + $Dir + '"}'
} elseif ($Cmd -eq 'translate') {
  $req = '{"cmd":"translate","text":"' + ($Text -replace '"','\"') + '","dir":"' + $Dir + '"}'
} else {
  $req = '{"cmd":"' + $Cmd + '"}'
}
$body = [Text.Encoding]::UTF8.GetBytes($req)
$hdr = [Text.Encoding]::ASCII.GetBytes(('{0:d8}' -f $body.Length))

$cli = New-Object Net.Sockets.TcpClient('127.0.0.1', $port)
$ns = $cli.GetStream()
$ns.Write($hdr,0,$hdr.Length); $ns.Write($body,0,$body.Length); $ns.Flush()
$buf = New-Object byte[] 8
$n = 0; while ($n -lt 8) { $r = $ns.Read($buf,$n,8-$n); if ($r -le 0) { break }; $n += $r }
$len = [int][Text.Encoding]::ASCII.GetString($buf,0,$n).Trim()
$ms = New-Object IO.MemoryStream
$tmp = New-Object byte[] 65536
$got = 0
while ($got -lt $len) {
  $r = $ns.Read($tmp,0,[Math]::Min(65536,$len-$got)); if ($r -le 0) { break }
  $ms.Write($tmp,0,$r); $got += $r
}
$cli.Close()
$resp = [Text.Encoding]::UTF8.GetString($ms.ToArray())
Write-Output "--- response ($got bytes) ---"
Write-Output $resp

if ($proc -and -not $proc.HasExited -and -not $NoStart) { $proc.Kill(); Write-Output "killed bridge pid=$($proc.Id)" }
