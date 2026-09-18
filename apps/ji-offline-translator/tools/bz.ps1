# bz.ps1 - stub out one procedure body at a time and report whether the parse cascade disappears
param([string]$Names)
$ErrorActionPreference='Stop'
$gbk=[Text.Encoding]::GetEncoding('GB18030')
$root=Split-Path -Parent $PSScriptRoot
$src=$gbk.GetString([IO.File]::ReadAllBytes("$root\src\_build\translator.txt"))
$lines = $src -split "`r`n"

function Stub([string]$name){
  $out=@()
  $i=0
  $done=$false
  while($i -lt $lines.Count){
    $l=$lines[$i]
    if(-not $done -and $l -match ("^程序\s+"+[regex]::Escape($name)+"\s*(\(|$)")){
      $out+=$l
      $i++
      while($i -lt $lines.Count -and $lines[$i] -ne '结束'){ $i++ }
      $out+="`t返回(0);"
      $done=$true
      continue
    }
    $out+=$l
    $i++
  }
  if(-not $done){ throw "procedure not found: $name" }
  return ($out -join "`r`n")
}

foreach($n in ($Names -split ',')){
  $v = Stub $n
  $f = "$root\src\_lab\s_$n.txt"
  [IO.File]::WriteAllText($f,$v,$gbk)
  $r = & powershell -File 'C:\Users\lvshan\.agents\skills\ji-language\scripts\sec.ps1' -Src $f
  $txt = $r -join "`n"
  $ok = $txt -match 'BUILD_OK'
  $cascade = $txt -match '截图识别 语法有误'
  $first = ($r | Select-String -Pattern '语法|内部错误|未定义|不存在' | Select-Object -First 2) -join ' | '
  Write-Output ("{0,-14} BUILD_OK={1,-5} cascade={2,-5} {3}" -f $n,$ok,$cascade,$first)
}
