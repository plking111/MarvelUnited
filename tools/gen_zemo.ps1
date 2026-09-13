# 生成并合并「泽莫男爵」(zemo) 到 data/villains.json
# 规则：先构建对象 → JSON 序列化 → 反序列化校验 → 通过才写回（避免手写坏 JSON）
#
# 数据来源：_testlog\zemo.txt（docx）+ 卡图逐张核对
# 卡图核对结论（与 docx 的差异）：
#   卡 1/2  移动3 + BAM + 效果「雷电！」（docx 一致）
#   卡 3/4  顺时针移到"平民最多"的地点 + 效果「公民五」（docx 一致）
#   卡 5    移动0 + BAM（docx 一致）
#   卡 7    移动4 + BAM + 暴暴/暴/暴暴（docx 一致）
#   卡 10   移动2 + BAM + 民民/民/民民（docx 一致）
#   卡 11   移动3 + BAM + 民民/民/民民（docx 一致）
#   卡 12   移动5 + **无 BAM** + 民民暴暴/民暴/民民暴暴
#           ⚠️ docx 把卡12 写成"移动3/无BAM/民民/民/民民"（重复了卡11）——以卡图为准
# 威胁卡核对（6 张卡图逐张看过）：
#   修理师 3 血 / 2 英勇；甲虫 4 血 / 2 英勇（⚠️ docx 甲虫正文误写成"修理师…击败"）；
#   尖叫咪咪 3 血 / 2 英勇；邪恶大师 **无生命值** / 常量"爪牙无法受到任何伤害" / 3 英勇；
#   月石 5 血 / **卡面未写化解符号 → 用户裁定：不给英勇槽，只能靠伤害打掉**；歌利亚 5 血 / 3 英勇。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'MarvelUnitedGame\data\villains.json'

function A([int]$move, [bool]$bam, $effect = $null, $place = $null) {
  return [ordered]@{ move = $move; bam = $bam; effect = $effect; place = $place }
}
function T([string]$name, [string]$text, [int]$hp, [bool]$bam, [bool]$constant, [int]$heroic_n, [bool]$immune = $false) {
  $h = [ordered]@{
    name = $name; text = $text; henchman_hp = $hp; bam = $bam
    arrival = $false; start_turn = $false; constant = $constant
  }
  # 裁定③：只有卡面写了"同一回合内用 N 个英勇行动击败"的威胁卡才写 clear / same_turn_clear。
  # 月石（用户裁定：只能靠伤害打掉）两个字段**都不写** —— 引擎靠 _threat_placeable_sym 的
  # "hp>0 且没有 clear → 不可放指示物"分支实现"打不掉就打不动"，所以不能留一个空 clear 数组。
  if ($heroic_n -gt 0) {
    $clear = @()
    for ($i = 0; $i -lt $heroic_n; $i++) { $clear += 'heroic' }
    $h.clear = $clear
    $h.same_turn_clear = $true
  }
  # 裁定⑤：在场时其它爪牙（威胁卡）不受任何伤害（仅「邪恶大师」）
  $h.immune_henchmen = $immune
  return $h
}

$zemo = [ordered]@{
  name = '泽莫男爵'
  name_en = 'Baron Zemo'
  color = '#8e5ba6'
  image = 'res://assets/cards/villains/zemo/panel.png'
  back = 'res://assets/cards/villains/zemo/back.png'
  health = [ordered]@{ '2' = 3; '3' = 5; '4' = 8 }
  bam = '对泽莫男爵所在地点的一名英雄造成 1 点伤害，并且离泽莫男爵最近的英雄获得 1 个危机指示物（从所在地点起顺时针计算；平手由玩家选择）。'
  overflow = '若 1 个或多个平民/暴徒指示物无法添加到某个地点，则离该地点最近的英雄获得 1 个危机指示物（从该地点起顺时针计算；平手由玩家选择）。'
  plot = ''
  plot_track = 'none'
  fear_track_max = 0
  special = '特殊规则：英雄回合结束时，拥有危机指示物的英雄必须逐个（每个指示物弹窗一次）把危机指示物盖到本回合打出的行动卡底部的行动符号上；每张卡最多盖等同于其底部符号数、多余的危机指示物留在英雄身上。被盖住的符号永久失效：下一位英雄不能继承、其它效果也不能引用。'
  threats = @(
    (T '修理师' 'BAM!：从本地点丢弃 1 个平民。修理师可在同一回合内被玩家使用 2 个英勇行动击败。' 3 $true $false 2),
    (T '甲虫'   'BAM!：从本地点丢弃 1 个暴徒。甲虫可在同一回合内被玩家使用 2 个英勇行动击败。' 4 $true $false 2),
    (T '尖叫咪咪' 'BAM!：对相邻地点的每位英雄造成 1 点伤害。尖叫咪咪可在同一回合内被玩家使用 2 个英勇行动击败。' 3 $true $false 2),
    (T '邪恶大师' '只要此威胁卡在起作用，爪牙就无法受到任何伤害。邪恶大师可在同一回合内被玩家使用 3 个英勇行动击败。' 0 $false $true 3 $true),
    (T '月石'   'BAM!：对该地点的每个英雄造成 2 点伤害，对相邻位置的每个英雄造成 1 点伤害。' 5 $true $false 0),
    (T '歌利亚' 'BAM!：对该地点的 1 个英雄造成 2 点伤害。歌利亚可在同一回合内被玩家使用 3 个英勇行动击败。' 5 $true $false 3)
  )
  actions = @(
    (A 3 $true ([ordered]@{ type = 'zemo_thunderbolt'; name = '雷电！'; text = '将三个暴徒指示物添加到泽莫男爵所在地点，然后 BAM！' })),
    (A 3 $true ([ordered]@{ type = 'zemo_thunderbolt'; name = '雷电！'; text = '将三个暴徒指示物添加到泽莫男爵所在地点，然后 BAM！' })),
    (A 0 $false ([ordered]@{ type = 'zemo_civil_five'; name = '公民五'; text = '顺时针移动到拥有最多平民指示物的地点。丢弃泽莫男爵所在地点所有的平民和暴徒指示物。' })),
    (A 0 $false ([ordered]@{ type = 'zemo_civil_five'; name = '公民五'; text = '顺时针移动到拥有最多平民指示物的地点。丢弃泽莫男爵所在地点所有的平民和暴徒指示物。' })),
    (A 0 $true $null $null),
    (A 1 $true $null @(@('thug'), @('thug'), @('thug'))),
    (A 4 $true $null @(@('thug','thug'), @('thug'), @('thug','thug'))),
    (A 4 $true $null @(@('thug','thug'), @('thug'), @('thug','thug'))),
    (A 1 $true $null @(@('civ','civ'), @('civ'), @('civ','civ'))),
    (A 2 $true $null @(@('civ','civ'), @('civ'), @('civ','civ'))),
    (A 3 $true $null @(@('civ','civ'), @('civ'), @('civ','civ'))),
    (A 5 $false $null @(@('civ','civ','thug','thug'), @('civ','thug'), @('civ','civ','thug','thug')))
  )
}

# 校验：序列化 → 反序列化，字段齐全才算通过
$json = $zemo | ConvertTo-Json -Depth 10
$back = $json | ConvertFrom-Json
if ($back.actions.Count -ne 12) { throw "行动卡应为 12 张，实际 $($back.actions.Count)" }
if ($back.threats.Count -ne 6) { throw "威胁卡应为 6 张，实际 $($back.threats.Count)" }
if ($back.actions[11].move -ne 5 -or $back.actions[11].bam -ne $false) { throw "卡12 应为 移动5/无BAM" }
if ($back.actions[11].place.Count -ne 3) { throw "卡12 应有 3 个放置图案" }
# 月石按用户裁定没有英勇槽（只能靠伤害打掉），其余 5 张每张至少 2 槽
$no_slot = @($back.threats | Where-Object { $_.name -eq '月石' })
if ($no_slot.Count -ne 1) { throw "应恰好有 1 张「月石」威胁卡，实际 $($no_slot.Count)" }
if (@($no_slot[0].PSObject.Properties.Name) -contains 'clear') { throw "月石按用户裁定不应写 clear 字段（只能靠伤害打掉），实际写了 $($no_slot[0].clear)" }
if (@($no_slot[0].PSObject.Properties.Name) -contains 'same_turn_clear') { throw "月石没有英勇槽，不应写 same_turn_clear 字段" }
$with_slots = @($back.threats | Where-Object { $_.name -ne '月石' })
if (@($with_slots | Where-Object { $_.clear.Count -lt 2 }).Count -ne 0) { throw "除月石外每张威胁卡都应至少 2 个英勇槽" }
if (@($with_slots | Where-Object { $_.same_turn_clear -ne $true }).Count -ne 0) { throw "除月石外泽莫威胁卡都应带 same_turn_clear" }
if (@($back.threats | Where-Object { $_.immune_henchmen -eq $true }).Count -ne 1) { throw "只应有 1 张爪牙免伤威胁卡（邪恶大师）" }
if ($back.threats[3].henchman_hp -ne 0) { throw "邪恶大师卡面无生命值，应为 0" }
# 卡6（idx5）按卡图 action_06.png：移动1 + BAM! + 三个白框**各 1 个暴徒**（共 3 个）
# ⚠️ 必须逐槽检查"每槽本身是数组"，否则被 PowerShell 展平成一维数组也能骗过 Count 检查
$c6 = @($back.actions[5].place)
if ($c6.Count -ne 3) { throw "卡6 应有 3 个放置槽（卡图：三框各 1 个暴徒），实际 $($c6.Count)" }
$c6bad = 0
foreach ($g in $c6) {
  if ($g -is [string]) { $c6bad++; continue }
  $gg = @($g)
  if ($gg.Count -ne 1 -or [string]$gg[0] -ne 'thug') { $c6bad++ }
}
if ($c6bad -ne 0) { throw "卡6 三个槽应各 1 个暴徒（实际有 $c6bad 个槽不符，注意是否被展平）" }
# 卡9（idx8）按卡图 action_09.png：移动1 + BAM! + **平民 2/1/2 共 5 个**（不是暴徒）
$c9 = @($back.actions[8].place)
if ($c9.Count -ne 3) { throw "卡9 应有 3 个放置槽（卡图：平民 2/1/2），实际 $($c9.Count)" }
$c9tokens = @()
$c9bad = 0
foreach ($g in $c9) {
  if ($g -is [string]) { $c9bad++; continue }
  $c9tokens += @($g)
}
if ($c9bad -ne 0) { throw "卡9 有 $c9bad 个槽不是数组（是否被展平）" }
if ($c9tokens.Count -ne 5) { throw "卡9 应共 5 个指示物，实际 $($c9tokens.Count)" }
if (@($c9tokens | Where-Object { $_ -ne 'civ' }).Count -ne 0) { throw "卡9 应全是平民（civ），不能有暴徒" }
if (@($c9[0]).Count -ne 2 -or @($c9[1]).Count -ne 1 -or @($c9[2]).Count -ne 2) { throw "卡9 三槽应为 2/1/2" }

# 合并进现有文件
$all = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($all.PSObject.Properties.Name -contains 'zemo') {
  Write-Host "  已存在 zemo，覆盖之"
  $all.PSObject.Properties.Remove('zemo')
}
$all | Add-Member -NotePropertyName 'zemo' -NotePropertyValue $back -Force
$out = $all | ConvertTo-Json -Depth 10
# 写回前再校验一次
$null = $out | ConvertFrom-Json
[System.IO.File]::WriteAllText($path, $out, [System.Text.UTF8Encoding]::new($false))
$check = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("  villains.json 反派数 = {0}（含 zemo：{1}）" -f $check.PSObject.Properties.Name.Count, ($check.PSObject.Properties.Name -contains 'zemo'))
Write-Host ("  zemo：生命 {0}/{1}/{2}，威胁 {3} 张，行动 {4} 张" -f $check.zemo.health.'2', $check.zemo.health.'3', $check.zemo.health.'4', $check.zemo.threats.Count, $check.zemo.actions.Count)
