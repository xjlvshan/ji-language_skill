# build.ps1 - 离线翻译助手 构建脚本（极语言 / SEC）
#
# 为什么不直接 `sec.ps1 -Src src\translator.txt`：
#   sec.ps1 会把源码**就地**翻成 GBK，而本仓库的 master 源码用 UTF-8 保存
#   （便于编辑器/工具读写）。所以这里先把 UTF-8 master 规范化成
#   GBK + CRLF 的临时副本，再交给 sec.ps1 编译，产物再拷回项目根目录。
#
# 用法：
#   powershell -File tools\build.ps1            只编译
#   powershell -File tools\build.ps1 -GuiTest   编译后用 tools\gui-test.ps1 冒烟
param(
  [switch]$Quiet,
  [int]$WaitSec = 20
)
$ErrorActionPreference = 'Stop'
$gbk  = [Text.Encoding]::GetEncoding('GB18030')
$root = Split-Path -Parent $PSScriptRoot
$master = Join-Path $root 'src\translator.txt'
$tmpDir = Join-Path $root 'src\_build'
$secPs1 = 'C:\Users\lvshan\.agents\skills\ji-language\scripts\sec.ps1'

if (-not (Test-Path $master)) { throw "master source not found: $master" }

# ---- 1. 读 master（UTF-8 带/不带 BOM 均可，也兼容 GBK 旧文件）----
$raw = [IO.File]::ReadAllBytes($master)
$txt = $null
if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
  $txt = [Text.Encoding]::UTF8.GetString($raw,3,$raw.Length-3)
} else {
  try { $txt = (New-Object Text.UTF8Encoding($false,$true)).GetString($raw) }
  catch { $txt = $gbk.GetString($raw) }
}
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n").Replace("`n","`r`n")

# ---- 2. 写 GBK+CRLF 临时副本 ----
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$tmp = Join-Path $tmpDir 'translator.txt'
[IO.File]::WriteAllText($tmp, $txt, $gbk)

# ---- 3. 编译 ----
$out = & powershell -File $secPs1 -Src $tmp -WaitSec $WaitSec
if (-not $Quiet) { $out | Write-Output }
$ok = ($out -join "`n") -match 'BUILD_OK'
$art = Join-Path $tmpDir 'translator.exe'
if ($ok -and (Test-Path $art)) {
  Copy-Item $art (Join-Path $root '离线翻译助手.exe') -Force
  Copy-Item $art (Join-Path $root 'src\translator.exe') -Force
  if (-not $Quiet) { Write-Output "DEPLOY: 离线翻译助手.exe + src\translator.exe ($((Get-Item $art).Length) bytes)" }
} else {
  Write-Output "BUILD FAILED - artifact not deployed"
  exit 1
}
