# 编译检查（只抓语法/编译错误，很便宜，改完脚本立刻跑）
# 注意：必须用 Tee-Object 落盘再读 —— 在本环境里 `$out = & godot ... 2>&1` 拿不到任何输出
#（会给出"no parse errors"的假阴性，本会话因此漏掉过一次重复定义函数的 Parse Error）。
$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'MarvelUnitedGame'
$godot = Join-Path $PSScriptRoot 'godot\editor\Godot_v4.7.2-stable_win64.exe'
$env:TEMP = $root
$env:TMP = $root
$log = Join-Path $root '_testlog\import_check.log'
& $godot --headless --path $proj --import *>&1 | Tee-Object -FilePath $log | Out-Null
$all = Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue
$pe = $all | Select-String -Pattern 'Parse Error|Compile Error|SCRIPT ERROR' -CaseSensitive
if ($pe) {
  "==== 发现 $($pe.Count) 条编译/脚本错误 ===="
  $pe | Select-Object -First 25 | ForEach-Object { "  " + $_.Line.Trim() }
  exit 1
}
"==== 编译检查通过：无 Parse/Compile Error ===="
exit 0
