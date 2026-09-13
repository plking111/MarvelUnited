# 生成并合并「摩多克」(modok) 到 data/villains.json
# 规则：先构建对象 → JSON 序列化 → 反序列化校验 → 通过才写回（避免手写坏 JSON）
#
# 数据来源：12 张行动卡 + 6 张威胁卡 + 面板**全部逐张读图核对**（素材和相关信息\反派\7.3摩多克），
#           docx（_testlog\modok.txt）只作参考，冲突以卡图为准。
# 卡图核对结论：
#   卡 1  万能(顺时针:*) + 无 BAM + 无图案 + 效果「制备」
#   卡 2  移动0 + BAM + 无图案 + 无效果
#   卡 3  移动1 + **无 BAM** + 暴/暴暴/暴
#   卡 4  移动2 + BAM + 暴/暴暴/暴
#   卡 5  移动4 + BAM + 暴/暴暴/暴
#   卡 6  移动3 + BAM + 民/民民/民
#   卡 7  移动2 + BAM + 民/民民/民
#   卡 8  移动1 + **无 BAM** + 民/民民/民
#   卡 9  移动5 + **无 BAM** + 民暴/民暴/民暴
#   卡 10 移动3 + BAM + 效果「意识转移」
#   卡 11 移动3 + BAM + 效果「意识转移」
#   卡 12 移动0 + BAM + 效果「超级天才智能」
#   （本批 docx 与卡图**无实质冲突**，仅 docx 把 BAM! 写成 "BAN!"，按卡图 BAM! 处理）
# 威胁卡核对（6 张卡图逐张看过）：
#   能量投射 hp 无 / 到达:翻转1张英雄卡 / 3 英勇槽
#   活体激光 hp 4 / BAM:本地点每个英雄1伤；无英雄则翻转1张英雄卡 / 无英勇槽
#   科技共情 hp 无 / 到达:英雄失去全部行动指示物，可翻转2张英雄卡避免 / 3 英勇槽
#   变色龙   hp 4 / BAM:本地点1名英雄受"最后2张英雄卡底部攻击图标数"伤害 / 无英勇槽
#   心灵异能 hp 无 / 在此地点开始回合的英雄必须面朝下出牌 / 3 英勇槽
#   斑点     hp 4 / BAM:翻转"最后2张英雄卡底部英勇图标数"张英雄卡 / 无英勇槽
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'MarvelUnitedGame\data\villains.json'

function A([int]$move, [bool]$bam, $effect = $null, $place = $null) {
  return [ordered]@{ move = $move; bam = $bam; effect = $effect; place = $place }
}
# 威胁卡：$heroic_n = 0 时**不写 clear 键**（该威胁只能用攻击打死，卡面底部没有英勇槽）
function T([string]$name, [string]$text, [int]$hp, [bool]$bam, [bool]$arrival, [bool]$start_turn, [bool]$constant, [int]$heroic_n) {
  $d = [ordered]@{
    name = $name; text = $text; henchman_hp = $hp; bam = $bam
    arrival = $arrival; start_turn = $start_turn; constant = $constant
  }
  if ($heroic_n -gt 0) {
    $clear = @()
    for ($i = 0; $i -lt $heroic_n; $i++) { $clear += 'heroic' }
    $d['clear'] = $clear
  }
  return $d
}

$thug3 = @(@('thug'), @('thug', 'thug'), @('thug'))
$civ3  = @(@('civ'), @('civ', 'civ'), @('civ'))
# 卡 9 每一格各 1 暴徒 + 1 平民：按项目约定"每个放置点内先放暴徒、再放平民"
$mix3  = @(@('thug', 'civ'), @('thug', 'civ'), @('thug', 'civ'))

$modok = [ordered]@{
  name = '摩多克'
  name_en = 'M.O.D.O.K.'
  color = '#e8930c'
  image = 'res://assets/cards/villains/modok/panel.png'
  back = 'res://assets/cards/villains/modok/back.png'
  health = [ordered]@{ '2' = 4; '3' = 7; '4' = 10 }
  bam = '翻转 1 张英雄卡：把故事情节中最接近开始处的正面朝上的英雄行动卡翻为正面朝下。'
  overflow = '如果 1 个或多个平民/暴徒指示物无法添加到某个地点，翻转 1 张英雄卡。'
  plot = ''
  plot_track = 'none'
  fear_track_max = 0
  special = '特殊规则：当摩多克翻转英雄卡时，将故事情节中最接近开始处的正面朝上的英雄行动卡翻为正面朝下（面朝下的卡被视为空白：不给下一位英雄行动，也不被其它效果引用）。恶毒的阴谋：如果故事情节中的所有英雄卡都面朝下，英雄就输了。特殊设置：「制备」必定是摩多克打出的第一张行动卡。'
  threats = @(
    (T '能量投射' '到达地点效果：翻转 1 张英雄卡。（卡面底部有 3 个英勇槽，需用 3 个英勇行动化解。）' 0 $false $true $false $false 3),
    (T '活体激光' 'BAM!：对该地点的每个英雄造成 1 点伤害。如果此地点没有英雄，则翻转 1 张英雄卡。' 4 $true $false $false $false 0),
    (T '科技共情' '到达地点效果：英雄失去所有的行动指示物；英雄可以选择翻转 2 张英雄卡，然后不失去行动指示物。（卡面底部有 3 个英勇槽。）' 0 $false $true $false $false 3),
    (T '变色龙' 'BAM!：对该地点的 1 名英雄造成等于故事情节中最后 2 张英雄卡牌底部的攻击图标数量的伤害。' 4 $true $false $false $false 0),
    (T '心灵异能' '在这个地点开始回合的英雄必须在故事情节中面朝下打出他们的牌（他们不会从自己的牌中获得任何行动）。（卡面底部有 3 个英勇槽。）' 0 $false $false $true $false 3),
    (T '斑点' 'BAM!：翻转与故事情节中最后 2 张英雄卡底部的英勇图标数量等量的英雄卡。' 4 $true $false $false $false 0)
  )
  actions = @(
    (A 0 $false ([ordered]@{ type = 'modok_preparation'; name = '制备'; text = '将 M.O.D.O.K 移动到英雄的起始地点。' })),
    (A 0 $true $null $null),
    (A 1 $false $null $thug3),
    (A 2 $true $null $thug3),
    (A 4 $true $null $thug3),
    (A 3 $true $null $civ3),
    (A 2 $true $null $civ3),
    (A 1 $false $null $civ3),
    (A 5 $false $null $mix3),
    (A 3 $true ([ordered]@{ type = 'modok_mind_transfer'; name = '意识转移'; text = '只要这张卡在故事情节中正面朝上，反派 BAM！之后翻转 1 张英雄卡。' })),
    (A 3 $true ([ordered]@{ type = 'modok_mind_transfer'; name = '意识转移'; text = '只要这张卡在故事情节中正面朝上，反派 BAM！之后翻转 1 张英雄卡。' })),
    (A 0 $true ([ordered]@{ type = 'modok_superior_intellect'; name = '超级天才智能'; text = '下一个反派回合多打出 1 张反派行动卡。' }))
  )
}

# ---------------------------------------------------------------- 自校验
$json = $modok | ConvertTo-Json -Depth 10
$back = $json | ConvertFrom-Json
if ($back.actions.Count -ne 12) { throw "行动卡应为 12 张，实际 $($back.actions.Count)" }
if ($back.threats.Count -ne 6) { throw "威胁卡应为 6 张，实际 $($back.threats.Count)" }
if ($back.name -ne '摩多克' -or $back.name_en -ne 'M.O.D.O.K.') { throw "名称字段不对" }
if ($back.health.'2' -ne 4 -or $back.health.'3' -ne 7 -or $back.health.'4' -ne 10) { throw "生命值应为 4/7/10" }
if ($back.plot_track -ne 'none' -or $back.fear_track_max -ne 0) { throw "摩多克没有专属失败轨道（plot_track=none / fear_track_max=0）" }
if ($back.image -ne 'res://assets/cards/villains/modok/panel.png') { throw "面板图路径不对" }
if ($back.back -ne 'res://assets/cards/villains/modok/back.png') { throw "行动牌背面路径不对" }

# 每张行动卡字段齐全
for ($i = 0; $i -lt 12; $i++) {
  $c = $back.actions[$i]
  foreach ($k in 'move', 'bam', 'effect', 'place') {
    if (-not ($c.PSObject.Properties.Name -contains $k)) { throw ("卡 {0} 缺字段 {1}" -f ($i + 1), $k) }
  }
  if ($c.move -isnot [int] -and $c.move -isnot [long] -and $c.move -isnot [double]) { throw ("卡 {0} 的 move 应为整数" -f ($i + 1)) }
}
# 卡 1 = 制备（无 BAM / 无图案）
if ($back.actions[0].move -ne 0 -or $back.actions[0].bam -ne $false) { throw "卡1 应为 移动0/无BAM（万能符号卡）" }
if ($back.actions[0].effect.type -ne 'modok_preparation') { throw "卡1 效果应为 modok_preparation（制备）" }
if ($null -ne $back.actions[0].place) { throw "卡1 卡面没有放置图案，place 应为 null" }
# 卡 2 = 移动0 + BAM，无图案无效果
if ($back.actions[1].move -ne 0 -or $back.actions[1].bam -ne $true) { throw "卡2 应为 移动0/BAM" }
if ($null -ne $back.actions[1].place -or $null -ne $back.actions[1].effect) { throw "卡2 无图案无效果" }
# 逐卡移动值（卡图实测）
$moves = @(0, 0, 1, 2, 4, 3, 2, 1, 5, 3, 3, 0)
for ($i = 0; $i -lt 12; $i++) {
  if ($back.actions[$i].move -ne $moves[$i]) { throw ("卡 {0} 移动应为 {1}，实际 {2}" -f ($i + 1), $moves[$i], $back.actions[$i].move) }
}
# 逐卡 BAM（卡图实测：3/8/9 无 BAM）
$bams = @($false, $true, $false, $true, $true, $true, $true, $false, $false, $true, $true, $true)
for ($i = 0; $i -lt 12; $i++) {
  if ($back.actions[$i].bam -ne $bams[$i]) { throw ("卡 {0} BAM 应为 {1}" -f ($i + 1), $bams[$i]) }
}
# 有图案的卡：3~9；每张必须三槽齐全、每槽非空、种类只能是 civ/thug
for ($i = 2; $i -le 8; $i++) {
  $pl = $back.actions[$i].place
  if ($null -eq $pl) { throw ("卡 {0} 应有放置图案" -f ($i + 1)) }
  if ($pl.Count -ne 3) { throw ("卡 {0} 的 place 应为 3 个槽位，实际 {1}" -f ($i + 1), $pl.Count) }
  foreach ($slot in $pl) {
    if ($null -eq $slot -or $slot.Count -lt 1) { throw ("卡 {0} 有空槽位" -f ($i + 1)) }
    foreach ($k in $slot) { if ($k -ne 'civ' -and $k -ne 'thug') { throw ("卡 {0} 出现非法指示物种类 {1}" -f ($i + 1), $k) } }
  }
}
# 逐卡图案（卡图实测）
$expect = @{
  3 = @(@('thug'), @('thug', 'thug'), @('thug'));
  4 = @(@('thug'), @('thug', 'thug'), @('thug'));
  5 = @(@('thug'), @('thug', 'thug'), @('thug'));
  6 = @(@('civ'), @('civ', 'civ'), @('civ'));
  7 = @(@('civ'), @('civ', 'civ'), @('civ'));
  8 = @(@('civ'), @('civ', 'civ'), @('civ'));
  9 = @(@('thug', 'civ'), @('thug', 'civ'), @('thug', 'civ'))
}
foreach ($n in 3..9) {
  $want = $expect[$n]
  $got = $back.actions[$n - 1].place
  for ($s = 0; $s -lt 3; $s++) {
    $g = @($got[$s]); $w = @($want[$s])
    if ($g.Count -ne $w.Count) { throw ("卡 {0} 第 {1} 格指示物数应为 {2}，实际 {3}" -f $n, ($s + 1), $w.Count, $g.Count) }
    for ($t = 0; $t -lt $w.Count; $t++) {
      if ($g[$t] -ne $w[$t]) { throw ("卡 {0} 第 {1} 格第 {2} 个指示物应为 {3}，实际 {4}" -f $n, ($s + 1), ($t + 1), $w[$t], $g[$t]) }
    }
  }
}
# 无图案的卡：1/2/10/11/12
foreach ($n in 1, 2, 10, 11, 12) {
  if ($null -ne $back.actions[$n - 1].place) { throw ("卡 {0} 卡面没有放置图案，place 应为 null" -f $n) }
}
# 卡 10/11 = 意识转移；卡 12 = 超级天才智能（移动0 + BAM）
if ($back.actions[9].effect.type -ne 'modok_mind_transfer' -or $back.actions[10].effect.type -ne 'modok_mind_transfer') { throw "卡10/11 效果应为 modok_mind_transfer（意识转移）" }
if ($back.actions[11].effect.type -ne 'modok_superior_intellect') { throw "卡12 效果应为 modok_superior_intellect（超级天才智能）" }
if ($back.actions[11].move -ne 0 -or $back.actions[11].bam -ne $true) { throw "卡12 应为 移动0/BAM" }
# 效果卡的 effect 三字段齐全
for ($i = 0; $i -lt 12; $i++) {
  $e = $back.actions[$i].effect
  if ($null -ne $e) {
    foreach ($k in 'type', 'name', 'text') { if (-not ($e.PSObject.Properties.Name -contains $k)) { throw ("卡 {0} 的 effect 缺字段 {1}" -f ($i + 1), $k) } }
  }
}
# 威胁卡校验
$withHp = @($back.threats | Where-Object { $_.henchman_hp -gt 0 })
if ($withHp.Count -ne 3) { throw "应有 3 张带生命值的威胁卡（活体激光/变色龙/斑点），实际 $($withHp.Count)" }
if (@($withHp | Where-Object { $_.henchman_hp -ne 4 }).Count -ne 0) { throw "3 张爪牙威胁卡生命值都应是 4" }
if (@($withHp | Where-Object { $_.bam -ne $true }).Count -ne 0) { throw "3 张带生命值的威胁卡卡面都印了 BAM!" }
if (@($withHp | Where-Object { $_.PSObject.Properties.Name -contains 'clear' }).Count -ne 0) { throw "带生命值的威胁卡卡面底部没有英勇槽，不应有 clear" }
$noHp = @($back.threats | Where-Object { $_.henchman_hp -eq 0 })
if ($noHp.Count -ne 3) { throw "应有 3 张无生命值的威胁卡（能量投射/科技共情/心灵异能）" }
if (@($noHp | Where-Object { $_.bam -eq $true }).Count -ne 0) { throw "3 张无生命值的威胁卡都没有 BAM!" }
if (@($noHp | Where-Object { $_.clear.Count -ne 3 }).Count -ne 0) { throw "3 张无生命值的威胁卡卡面底部都是 3 个英勇槽" }
if (@($noHp | Where-Object { ($_.clear | Where-Object { $_ -ne 'heroic' }).Count -ne 0 }).Count -ne 0) { throw "英勇槽只能填 heroic" }
if ($back.threats[0].arrival -ne $true) { throw "能量投射是到达地点效果" }
if ($back.threats[2].arrival -ne $true) { throw "科技共情是到达地点效果" }
# 心灵异能与既有 6 张 start_turn 威胁卡（奥创病毒/折磨摧残/太空伏击）同型：
# 卡面都是"整幅无徽标的文字行"，数据都是 start_turn=true + constant=false。
# 反例：constant=true 只用于"只要…/被动规则"卡（险恶地形/武学大师/战术支援/幻象…），从不与 start_turn 并用。
if ($back.threats[4].start_turn -ne $true) { throw "心灵异能是在该地点开始回合的效果（start_turn=true）" }
if ($back.threats[4].constant -ne $false) { throw "心灵异能必须与既有 start_turn 威胁卡同型：constant=false" }
if (@($back.threats | Where-Object { $_.start_turn -eq $true -and $_.constant -eq $true }).Count -ne 0) { throw "start_turn 与 constant 不应同时为真" }
$tnames = @($back.threats | ForEach-Object { $_.name })
foreach ($n in '能量投射', '活体激光', '科技共情', '变色龙', '心灵异能', '斑点') {
  if ($tnames -notcontains $n) { throw "缺少威胁卡 $n" }
}
foreach ($t in $back.threats) { if ([string]::IsNullOrWhiteSpace($t.text)) { throw ("威胁卡 {0} 缺 text" -f $t.name) } }

# ---------------------------------------------------------------- 合并进现有文件
$all = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($all.PSObject.Properties.Name -contains 'modok') {
  Write-Host "  已存在 modok，覆盖之"
  $all.PSObject.Properties.Remove('modok')
}
$all | Add-Member -NotePropertyName 'modok' -NotePropertyValue $back -Force
$out = $all | ConvertTo-Json -Depth 10
$null = $out | ConvertFrom-Json    # 写回前再校验一次
[System.IO.File]::WriteAllText($path, $out, [System.Text.UTF8Encoding]::new($false))
$check = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("  villains.json 反派数 = {0}（含 modok：{1}）" -f $check.PSObject.Properties.Name.Count, ($check.PSObject.Properties.Name -contains 'modok'))
Write-Host ("  modok：生命 {0}/{1}/{2}，威胁 {3} 张，行动 {4} 张" -f $check.modok.health.'2', $check.modok.health.'3', $check.modok.health.'4', $check.modok.threats.Count, $check.modok.actions.Count)
