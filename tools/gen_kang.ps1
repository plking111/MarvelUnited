# 生成并合并「康」(kang) 到 data/villains.json
# 规则：先构建对象 → JSON 序列化 → 反序列化校验 → 通过才写回（避免手写坏 JSON）
#
# 数据来源：12 张行动卡 + 6 张威胁卡 + 面板**全部逐张读图核对**（素材和相关信息\反派\7.4康），
#           devtools\康_docx原文.txt 只作参考，冲突以卡图为准。
# 卡图核对结论（每张都用整卡读图看过，并用 devtools\kang_scan.ps1 做像素级指示物计数交叉验证）：
#   卡 1~6 万能符号（顺时针:*）+ 无 BAM + 无图案 + 效果「时间大师」（6 张卡面完全相同）
#   卡 7   移动2 + BAM + 暴暴/暴/暴暴
#   卡 8   移动0 + BAM + 暴暴/暴暴/暴暴   <-- docx 写成 暴暴/暴/暴暴（少 1 个暴徒），以卡图为准
#   卡 9   移动1 + BAM + 民民/民/民民
#   卡 10  移动2 + BAM + 民民/民民/民民
#   卡 11  移动4 + BAM + 民民/民民/民民
#   卡 12  移动5 + BAM + 民民暴/民暴暴/民民暴（共 9 个指示物）
#   （docx 与卡图的差异：① 6 张「时间大师」docx 原样重复 6 遍 —— 卡图确认 6 张确实完全相同；
#     ② 卡 8 docx 写 暴暴/暴/暴暴，卡图是 暴暴/暴暴/暴暴；③ docx 的 BAN! 是 BAM! 的输入错误）
# 威胁卡核对（6 张卡图逐张看过，3 种各 2 张）：
#   时间藏匿处 TIME HIDEOUT ×2：只要康在这个或相邻的地点，他就不能受到任何伤害 / 3 英勇槽
#   时间悖论   TIME PARADOX ×2：只要此卡在发挥作用，每当康进入游戏时都以满血状态进行 / 3 英勇槽
#   时间军队   TIME ARMY    ×2：英雄们在任何一个有暴徒的位置结束回合都会受到 1 点伤害 / 3 英勇槽
#   6 张卡面都**没有生命值图标、没有 BAM! 星爆、没有到达箭头徽标**（只有 3 个星星白框 = 英勇槽），
#   文本行都是"只要…"被动句式 → constant = true（与全库口径一致：start_turn 与 constant 互斥）。
# 面板核对：生命值 2/3/4 人 = 4/7/10；特别规则=英雄被 KO 时康不激活 BAM，改为打出另一张行动牌；
#   BAM!=在场上时对康所在地点每个英雄 2 伤、**对其他位置**每个英雄 1 伤（docx 写"相邻两个地点"，以面板为准）；
#   不在场上时在每个位置添加 1 个暴徒，且不添加本张行动卡上指示的任何平民/暴徒；
#   溢出=无法添加平民/暴徒时在该地点加 1 个危机指示物，该地点失去回合结束效果。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'MarvelUnitedGame\data\villains.json'

function A([int]$move, [bool]$bam, $effect = $null, $place = $null) {
  return [ordered]@{ move = $move; bam = $bam; effect = $effect; place = $place }
}
# 威胁卡：康的 6 张威胁卡卡面底部都是 3 个英勇槽、都没有生命值图标
function T([string]$name, [string]$text, [bool]$constant, [int]$heroic_n) {
  $d = [ordered]@{
    name = $name; text = $text; henchman_hp = 0; bam = $false
    arrival = $false; start_turn = $false; constant = $constant
  }
  if ($heroic_n -gt 0) {
    $clear = @()
    for ($i = 0; $i -lt $heroic_n; $i++) { $clear += 'heroic' }
    $d['clear'] = $clear
  }
  return $d
}

# 卡 7 / 卡 8：暴徒 2-1-2 / 2-2-2（卡图实测）
$thugA = @(@('thug', 'thug'), @('thug'), @('thug', 'thug'))
$thugB = @(@('thug', 'thug'), @('thug', 'thug'), @('thug', 'thug'))
# 卡 9：平民 2-1-2
$civA  = @(@('civ', 'civ'), @('civ'), @('civ', 'civ'))
# 卡 10 / 卡 11：平民 2-2-2
$civB  = @(@('civ', 'civ'), @('civ', 'civ'), @('civ', 'civ'))
# 卡 12：民民暴 / 民暴暴 / 民民暴；每格按项目约定"先放暴徒、再放平民"落库
$mix   = @(@('thug', 'civ', 'civ'), @('thug', 'thug', 'civ'), @('thug', 'civ', 'civ'))

$kang = [ordered]@{
  name = '康'
  name_en = 'KANG'
  color = '#85d8ec'
  image = 'res://assets/cards/villains/kang/panel.png'
  back = 'res://assets/cards/villains/kang/back.png'
  health = [ordered]@{ '2' = 4; '3' = 7; '4' = 10 }
  bam = '如果康在一个地点：对康所在位置的每个英雄造成 2 点伤害，对其他位置的每个英雄造成 1 点伤害。如果康不在场上：在每个位置添加 1 个暴徒，且不再添加这张反派行动卡上指示的所有平民/暴徒。'
  overflow = '如果 1 个或多个平民/暴徒指示物无法添加到某个地点，则在该地点添加 1 个危机指示物。拥有危机指示物的地点将失去其回合结束效果。'
  plot = ''
  plot_track = 'none'
  fear_track_max = 0
  special = '特殊规则：当英雄被 KO 时，康不会激活他的 BAM！改为他打出另一张反派行动牌。康可以被「时间大师」移出游戏（不在场上）；当他不在场上时，BAM！改为在每个地点添加 1 个暴徒，且不结算行动卡所示的添加平民/暴徒。'
  threats = @(
    (T '时间藏匿处' '只要康在这个或相邻的地点，他就不能受到任何伤害。（卡面底部有 3 个英勇槽。）' $true 3),
    (T '时间悖论' '只要这张威胁卡还在发挥作用，每当康进入游戏时，他都会以满血状态进行。（卡面底部有 3 个英勇槽。）' $true 3),
    (T '时间军队' '只要这张威胁卡在起作用，英雄们在任何一个有暴徒的位置结束他们的回合都会受到 1 点伤害。（卡面底部有 3 个英勇槽。）' $true 3),
    (T '时间悖论' '只要这张威胁卡还在发挥作用，每当康进入游戏时，他都会以满血状态进行。（卡面底部有 3 个英勇槽。）' $true 3),
    (T '时间军队' '只要这张威胁卡在起作用，英雄们在任何一个有暴徒的位置结束他们的回合都会受到 1 点伤害。（卡面底部有 3 个英勇槽。）' $true 3),
    (T '时间藏匿处' '只要康在这个或相邻的地点，他就不能受到任何伤害。（卡面底部有 3 个英勇槽。）' $true 3)
  )
  actions = @(
    (A 0 $false ([ordered]@{ type = 'kang_time_master'; name = '时间大师'; text = '如果康在一个地点，将他移出游戏。如果康不在场上，把他放在英雄最多的地点上场（相同则玩家选择）。然后 BAM！' })),
    (A 0 $false ([ordered]@{ type = 'kang_time_master'; name = '时间大师'; text = '如果康在一个地点，将他移出游戏。如果康不在场上，把他放在英雄最多的地点上场（相同则玩家选择）。然后 BAM！' })),
    (A 0 $false ([ordered]@{ type = 'kang_time_master'; name = '时间大师'; text = '如果康在一个地点，将他移出游戏。如果康不在场上，把他放在英雄最多的地点上场（相同则玩家选择）。然后 BAM！' })),
    (A 0 $false ([ordered]@{ type = 'kang_time_master'; name = '时间大师'; text = '如果康在一个地点，将他移出游戏。如果康不在场上，把他放在英雄最多的地点上场（相同则玩家选择）。然后 BAM！' })),
    (A 0 $false ([ordered]@{ type = 'kang_time_master'; name = '时间大师'; text = '如果康在一个地点，将他移出游戏。如果康不在场上，把他放在英雄最多的地点上场（相同则玩家选择）。然后 BAM！' })),
    (A 0 $false ([ordered]@{ type = 'kang_time_master'; name = '时间大师'; text = '如果康在一个地点，将他移出游戏。如果康不在场上，把他放在英雄最多的地点上场（相同则玩家选择）。然后 BAM！' })),
    (A 2 $true $null $thugA),
    (A 0 $true $null $thugB),
    (A 1 $true $null $civA),
    (A 2 $true $null $civB),
    (A 4 $true $null $civB),
    (A 5 $true $null $mix)
  )
}

# ---------------------------------------------------------------- 自校验
$json = $kang | ConvertTo-Json -Depth 10
$back = $json | ConvertFrom-Json
if ($back.actions.Count -ne 12) { throw "行动卡应为 12 张，实际 $($back.actions.Count)" }
if ($back.threats.Count -ne 6) { throw "威胁卡应为 6 张，实际 $($back.threats.Count)" }
if ($back.name -ne '康' -or $back.name_en -ne 'KANG') { throw "名称字段不对" }
if ($back.health.'2' -ne 4 -or $back.health.'3' -ne 7 -or $back.health.'4' -ne 10) { throw "生命值应为 4/7/10" }
if ($back.plot_track -ne 'none' -or $back.fear_track_max -ne 0) { throw "康没有专属失败轨道（plot_track=none / fear_track_max=0）" }
if ($back.image -ne 'res://assets/cards/villains/kang/panel.png') { throw "面板图路径不对" }
if ($back.back -ne 'res://assets/cards/villains/kang/back.png') { throw "行动牌背面路径不对" }
if ($back.color -ne '#85d8ec') { throw "面板主色应为 #85d8ec（KANG 蓝）" }

# 每张行动卡字段齐全
for ($i = 0; $i -lt 12; $i++) {
  $c = $back.actions[$i]
  foreach ($k in 'move', 'bam', 'effect', 'place') {
    if (-not ($c.PSObject.Properties.Name -contains $k)) { throw ("卡 {0} 缺字段 {1}" -f ($i + 1), $k) }
  }
  if ($c.move -isnot [int] -and $c.move -isnot [long] -and $c.move -isnot [double]) { throw ("卡 {0} 的 move 应为整数" -f ($i + 1)) }
}
# 逐卡移动值（卡图实测）
$moves = @(0, 0, 0, 0, 0, 0, 2, 0, 1, 2, 4, 5)
for ($i = 0; $i -lt 12; $i++) {
  if ($back.actions[$i].move -ne $moves[$i]) { throw ("卡 {0} 移动应为 {1}，实际 {2}" -f ($i + 1), $moves[$i], $back.actions[$i].move) }
}
# 逐卡 BAM（卡图实测：1~6 没有 BAM! 星爆，7~12 都有）
$bams = @($false, $false, $false, $false, $false, $false, $true, $true, $true, $true, $true, $true)
for ($i = 0; $i -lt 12; $i++) {
  if ($back.actions[$i].bam -ne $bams[$i]) { throw ("卡 {0} BAM 应为 {1}" -f ($i + 1), $bams[$i]) }
}
# 卡 1~6 = 时间大师（万能符号卡：卡面无数字移动、无 BAM、无图案）
for ($i = 0; $i -lt 6; $i++) {
  if ($back.actions[$i].move -ne 0) { throw ("卡 {0} 卡面是万能符号（无数字移动），move 应为 0" -f ($i + 1)) }
  if ($back.actions[$i].bam -ne $false) { throw ("卡 {0} 卡面没有 BAM! 星爆" -f ($i + 1)) }
  if ($null -ne $back.actions[$i].place) { throw ("卡 {0} 卡面没有放置图案，place 应为 null" -f ($i + 1)) }
  if ($back.actions[$i].effect.type -ne 'kang_time_master') { throw ("卡 {0} 效果应为 kang_time_master（时间大师）" -f ($i + 1)) }
  if ($back.actions[$i].effect.name -ne '时间大师') { throw ("卡 {0} 效果名应为 时间大师" -f ($i + 1)) }
}
# 卡 7~12：有 BAM、有图案、无效果
for ($i = 6; $i -lt 12; $i++) {
  if ($back.actions[$i].bam -ne $true) { throw ("卡 {0} 卡面印了 BAM!" -f ($i + 1)) }
  if ($null -eq $back.actions[$i].place) { throw ("卡 {0} 应有放置图案" -f ($i + 1)) }
  if ($null -ne $back.actions[$i].effect) { throw ("卡 {0} 卡面没有效果文字" -f ($i + 1)) }
}
# 逐卡图案（卡图实测 + 像素扫描交叉验证）
# ⚠️ PowerShell 会把嵌套数组**展平**，所以不能只看 Count，必须逐槽判断"元素本身是不是数组"
$expect = @{
  7  = @(@('thug', 'thug'), @('thug'), @('thug', 'thug'));
  8  = @(@('thug', 'thug'), @('thug', 'thug'), @('thug', 'thug'));
  9  = @(@('civ', 'civ'), @('civ'), @('civ', 'civ'));
  10 = @(@('civ', 'civ'), @('civ', 'civ'), @('civ', 'civ'));
  11 = @(@('civ', 'civ'), @('civ', 'civ'), @('civ', 'civ'));
  12 = @(@('thug', 'civ', 'civ'), @('thug', 'thug', 'civ'), @('thug', 'civ', 'civ'))
}
foreach ($n in 7..12) {
  $want = $expect[$n]
  $got = $back.actions[$n - 1].place
  if ($null -eq $got) { throw ("卡 {0} 应有放置图案" -f $n) }
  if ($got.Count -ne 3) { throw ("卡 {0} 的 place 应为 3 个槽位，实际 {1}" -f $n, $got.Count) }
  for ($s = 0; $s -lt 3; $s++) {
    $g = $got[$s]
    if ($g -is [string]) { throw ("卡 {0} 第 {1} 格被展平成了字符串（应为数组）" -f $n, ($s + 1)) }
    $g = @($g); $w = @($want[$s])
    if ($g.Count -ne $w.Count) { throw ("卡 {0} 第 {1} 格指示物数应为 {2}，实际 {3}" -f $n, ($s + 1), $w.Count, $g.Count) }
    for ($t = 0; $t -lt $w.Count; $t++) {
      if ($g[$t] -ne $w[$t]) { throw ("卡 {0} 第 {1} 格第 {2} 个指示物应为 {3}，实际 {4}" -f $n, ($s + 1), ($t + 1), $w[$t], $g[$t]) }
    }
    foreach ($k in $g) { if ($k -ne 'civ' -and $k -ne 'thug') { throw ("卡 {0} 出现非法指示物种类 {1}" -f $n, $k) } }
  }
}
# 总指示物数：卡 7=5 / 卡 8=6 / 卡 9=5 / 卡 10=6 / 卡 11=6 / 卡 12=9
$totals = @{ 7 = 5; 8 = 6; 9 = 5; 10 = 6; 11 = 6; 12 = 9 }
foreach ($n in 7..12) {
  $cnt = 0
  foreach ($slot in $back.actions[$n - 1].place) { $cnt += @($slot).Count }
  if ($cnt -ne $totals[$n]) { throw ("卡 {0} 指示物总数应为 {1}，实际 {2}" -f $n, $totals[$n], $cnt) }
}
# 效果卡的 effect 三字段齐全
for ($i = 0; $i -lt 12; $i++) {
  $e = $back.actions[$i].effect
  if ($null -ne $e) {
    foreach ($k in 'type', 'name', 'text') { if (-not ($e.PSObject.Properties.Name -contains $k)) { throw ("卡 {0} 的 effect 缺字段 {1}" -f ($i + 1), $k) } }
  }
}
# 威胁卡校验
if (@($back.threats | Where-Object { $_.henchman_hp -ne 0 }).Count -ne 0) { throw "康的 6 张威胁卡卡面都没有生命值图标（henchman_hp 应为 0）" }
if (@($back.threats | Where-Object { $_.bam -eq $true }).Count -ne 0) { throw "康的 6 张威胁卡卡面都没有 BAM! 星爆" }
if (@($back.threats | Where-Object { $_.arrival -eq $true }).Count -ne 0) { throw "康的 6 张威胁卡卡面都没有到达箭头徽标" }
if (@($back.threats | Where-Object { $_.start_turn -eq $true }).Count -ne 0) { throw '康的 6 张威胁卡文本都是「只要…」被动句式，不是「在这个地点开始回合」型' }
if (@($back.threats | Where-Object { $_.constant -ne $true }).Count -ne 0) { throw "康的 6 张威胁卡都应是 constant=true（只要…被动规则）" }
if (@($back.threats | Where-Object { $_.clear.Count -ne 3 }).Count -ne 0) { throw "康的 6 张威胁卡卡面底部都是 3 个英勇槽" }
if (@($back.threats | Where-Object { ($_.clear | Where-Object { $_ -ne 'heroic' }).Count -ne 0 }).Count -ne 0) { throw "英勇槽只能填 heroic" }
if (@($back.threats | Where-Object { $_.start_turn -eq $true -and $_.constant -eq $true }).Count -ne 0) { throw "start_turn 与 constant 不应同时为真" }
$tnames = @($back.threats | ForEach-Object { $_.name })
foreach ($n in '时间藏匿处', '时间悖论', '时间军队') {
  if (@($tnames | Where-Object { $_ -eq $n }).Count -ne 2) { throw ("威胁卡 $n 应各有 2 张") }
}
foreach ($t in $back.threats) { if ([string]::IsNullOrWhiteSpace($t.text)) { throw ("威胁卡 {0} 缺 text" -f $t.name) } }

# ---------------------------------------------------------------- 合并进现有文件
$all = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($all.PSObject.Properties.Name -contains 'kang') {
  Write-Host "  已存在 kang，覆盖之"
  $all.PSObject.Properties.Remove('kang')
}
$all | Add-Member -NotePropertyName 'kang' -NotePropertyValue $back -Force
$out = $all | ConvertTo-Json -Depth 10
$null = $out | ConvertFrom-Json    # 写回前再校验一次
[System.IO.File]::WriteAllText($path, $out, [System.Text.UTF8Encoding]::new($false))
$check = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($check.PSObject.Properties.Name.Count -ne 21) { throw ("villains.json 反派数应为 21，实际 {0}" -f $check.PSObject.Properties.Name.Count) }
foreach ($vid in 'zemo', 'modok', 'kang') {
  if (-not ($check.PSObject.Properties.Name -contains $vid)) { throw "合并后缺少 $vid（绝不能覆盖别人的键）" }
}
Write-Host ("  villains.json 反派数 = {0}（zemo/modok/kang 都在：{1}/{2}/{3}）" -f $check.PSObject.Properties.Name.Count,
  ($check.PSObject.Properties.Name -contains 'zemo'), ($check.PSObject.Properties.Name -contains 'modok'), ($check.PSObject.Properties.Name -contains 'kang'))
Write-Host ("  kang：生命 {0}/{1}/{2}，威胁 {3} 张，行动 {4} 张" -f $check.kang.health.'2', $check.kang.health.'3', $check.kang.health.'4', $check.kang.threats.Count, $check.kang.actions.Count)
