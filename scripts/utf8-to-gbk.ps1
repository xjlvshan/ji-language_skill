param(
  [Parameter(Mandatory=$true)][string]$Name,
  [string]$Dir = 'D:\SEC\deepseek-sec\tmp\adv'
)
# ASCII-only: build a GBK source with CRLF endings from <Dir>\<Name>.u8
$gbk = [Text.Encoding]::GetEncoding('GB18030')
$u = Join-Path $Dir ($Name + '.u8')
$t = Join-Path $Dir ($Name + '.txt')
$txt = [IO.File]::ReadAllText($u, [Text.Encoding]::UTF8)
$txt = $txt -replace "`r`n", "`n"
$txt = $txt -replace "`n", "`r`n"
[IO.File]::WriteAllText($t, $txt, $gbk)
Write-Output ("wrote " + $t + " bytes=" + (Get-Item $t).Length)
