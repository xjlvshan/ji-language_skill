# brem.ps1 - remove whole procedures from a given source and re-compile
#   -All      drop every listed procedure at once, compile once
#   (default) drop one at a time, compile after each
param([string]$Src,[string]$Names,[switch]$All)
$ErrorActionPreference='Stop'
$gbk=[Text.Encoding]::GetEncoding('GB18030')
$root=Split-Path -Parent $PSScriptRoot
$src0=$gbk.GetString([IO.File]::ReadAllBytes($Src))

function Drop([string]$src,[string]$name){
  $lines=$src -split "`r`n"
  $out=New-Object Collections.ArrayList
  $i=0; $done=$false
  while($i -lt $lines.Count){
    $l=$lines[$i]
    if(-not $done -and $l -match ("^程序\s+"+[regex]::Escape($name)+"\s*(\(|$)")){
      $i++
      while($i -lt $lines.Count -and $lines[$i] -ne '结束'){ $i++ }
      $i++   # skip the 结束 too
      $done=$true
      continue
    }
    [void]$out.Add($l); $i++
  }
  if(-not $done){ throw "procedure not found: $name" }
  return ($out -join "`r`n")
}

function Report([string]$v,[string]$label){
  $f = "$root\src\_lab\q_$label.txt"
  [IO.File]::WriteAllText($f,$v,$gbk)
  $r = & powershell -File 'C:\Users\lvshan\.agents\skills\ji-language\scripts\sec.ps1' -Src $f
  $txt = $r -join "`n"
  $ok = $txt -match 'BUILD_OK'
  $e = ($r | Select-String -Pattern '语法|内部错误|未定义|不存在' | Select-Object -First 2) -join ' ; '
  Write-Output ("{0,-14} BUILD_OK={1,-5} {2}" -f $label,$ok,$e)
}

if($All){
  $v=$src0
  foreach($n in ($Names -split ',')){ $v = Drop $v $n }
  Report $v 'all'
} else {
  foreach($n in ($Names -split ',')){ Report (Drop $src0 $n) $n }
}
