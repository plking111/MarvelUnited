# 生成并合并「犀牛人」(rhino) 到 data/villains.json
# 规则：先构建对象 → JSON 序列化 → 反序列化校验 → 通过才写回（避免手写坏 JSON）
# 并发纪律：写回前重读原文件，确认 zemo/modok/kang 还在、且"读入时的指纹"没变（康那一路可能同时在写）；
#           变了就重试；写回后复查 zemo/modok/kang/rhino 四个键都在。
#
# 数据来源：12 张行动卡 + 6 张威胁卡 + 面板**全部逐张读图核对**（素材和相关信息\反派\7.5犀牛人），
#           docx（devtools\犀牛人_docx原文.txt）只作参考，冲突以卡图为准。
# 卡图核对结论（devtools\rhino_scan.ps1 像素扫描交叉验证：BAM 红像素 1~10 张有、11/12 为 0）：
#   卡 1~4 顺时针→下一有英雄地点 + BAM! + 无图案 + 卡名「犀牛充电」
#   卡 5   移动4 + BAM + 暴/暴/暴（三槽各 1 个暴徒）
#   卡 6   移动2 + BAM + 暴/暴/暴
#   卡 7   移动1 + BAM + 暴/暴/暴
#   卡 8   移动1 + BAM + 民/民/民（三槽各 1 个平民）
#   卡 9   移动2 + BAM + 民/民/民
#   卡 10  移动3 + BAM + 民/民/民
#   卡 11  移动5 + **无 BAM** + 民暴/民暴/民暴（三槽各 1 暴徒 + 1 平民 = 6 个指示物）
#   卡 12  移动0 + **无 BAM** + 民暴/民暴/民暴（同上）
# 威胁卡核对（6 张卡图逐张看过，像素指纹完全一致：无生命值图标、底部 3 个英勇槽、无 BAM/到达徽标）：
#   01 开阔地带 OPEN FIELD  hp 无 / 在此地点受到伤害的英雄还将获得 1 个危机指示物 / 3 英勇槽
#   02 无掩护   NO COVER    hp 无 / 在此位置结束回合的英雄将获得 1 个危机指示物 / 3 英勇槽
#   03 开阔地带（与 01 同）
#   04 无掩护（与 02 同）
#   05 开阔地带（与 01 同）
#   06 无掩护（与 02 同）
#   即 docx 说的"开阔地带 ×3 + 无掩护 ×3"，与卡图一致（是重复卡，不是抄错）。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'MarvelUnitedGame\data\villains.json'

function A($move, [bool]$bam, $effect = $null, $place = $null) {
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

$charge = [ordered]@{ dir = 'cw'; hero_in = $true }   # 犀牛充电：顺时针移动到下一个有英雄的地点
$thug1 = @(@('thug'), @('thug'), @('thug'))
$civ1  = @(@('civ'), @('civ'), @('civ'))
# 卡 11/12 每一格各 1 暴徒 + 1 平民：按项目约定"每个放置点内先放暴徒、再放平民"
$mix1  = @(@('thug', 'civ'), @('thug', 'civ'), @('thug', 'civ'))

$rhino = [ordered]@{
  name = '犀牛人'
  name_en = 'Rhino'
  color = '#9fa6b2'   # 卡名条主色（威胁卡 01 名条实测 #9fa6b2）
  image = 'res://assets/cards/villains/rhino/panel.png'
  back = 'res://assets/cards/villains/rhino/back.png'
  health = [ordered]@{ '2' = 5; '3' = 8; '4' = 11 }
  bam = '对犀牛人所在地点的每个英雄造成等同于他本回合进入的地点数量的伤害（多余伤害忽略），然后把这些英雄顺时针移动 1 个地点。'
  overflow = '如果无法将 1 个或多个平民/暴徒指示物添加到某个地点，请抽取另一张反派行动卡并将其面朝下添加到故事情节。'
  plot = ''
  plot_track = 'none'
  fear_track_max = 0
  special = '特殊规则：当英雄被 KO 时，犀牛人不会激活他的 BAM！然后该英雄获得 1 个危机指示物。如果英雄有任何危机指示物，他们下一回合打牌必须正面朝下在故事情节中，然后丢弃他们所有的危机指示物。'
  threats = @(
    (T '开阔地带' '在此地点受到伤害的英雄还将获得 1 个危机指示物。（卡面底部有 3 个英勇槽。）' 0 $false $false $false $true 3),
    (T '无掩护' '在此位置结束回合的英雄将获得 1 个危机指示物。（卡面底部有 3 个英勇槽。）' 0 $false $false $false $true 3),
    (T '开阔地带' '在此地点受到伤害的英雄还将获得 1 个危机指示物。（卡面底部有 3 个英勇槽。）' 0 $false $false $false $true 3),
    (T '无掩护' '在此位置结束回合的英雄将获得 1 个危机指示物。（卡面底部有 3 个英勇槽。）' 0 $false $false $false $true 3),
    (T '开阔地带' '在此地点受到伤害的英雄还将获得 1 个危机指示物。（卡面底部有 3 个英勇槽。）' 0 $false $false $false $true 3),
    (T '无掩护' '在此位置结束回合的英雄将获得 1 个危机指示物。（卡面底部有 3 个英勇槽。）' 0 $false $false $false $true 3)
  )
  actions = @(
    (A $charge $true),
    (A $charge $true),
    (A $charge $true),
    (A $charge $true),
    (A 4 $true $null $thug1),
    (A 2 $true $null $thug1),
    (A 1 $true $null $thug1),
    (A 1 $true $null $civ1),
    (A 2 $true $null $civ1),
    (A 3 $true $null $civ1),
    (A 5 $false $null $mix1),
    (A 0 $false $null $mix1)
  )
}

# ---------------------------------------------------------------- 自校验
$json = $rhino | ConvertTo-Json -Depth 10
$back = $json | ConvertFrom-Json
if ($back.actions.Count -ne 12) { throw "行动卡应为 12 张，实际 $($back.actions.Count)" }
if ($back.threats.Count -ne 6) { throw "威胁卡应为 6 张，实际 $($back.threats.Count)" }
if ($back.name -ne '犀牛人' -or $back.name_en -ne 'Rhino') { throw "名称字段不对" }
if ($back.health.'2' -ne 5 -or $back.health.'3' -ne 8 -or $back.health.'4' -ne 11) { throw "生命值应为 5/8/11（面板实测）" }
if ($back.plot_track -ne 'none' -or $back.fear_track_max -ne 0) { throw "犀牛人没有专属失败轨道（plot_track=none / fear_track_max=0）" }
if ($back.plot -ne '') { throw "plot 应为空串（没有邪恶计划轨道）" }
if ($back.image -ne 'res://assets/cards/villains/rhino/panel.png') { throw "面板图路径不对" }
if ($back.back -ne 'res://assets/cards/villains/rhino/back.png') { throw "行动牌背面路径不对" }

# 每张行动卡字段齐全
for ($i = 0; $i -lt 12; $i++) {
  $c = $back.actions[$i]
  foreach ($k in 'move', 'bam', 'effect', 'place') {
    if (-not ($c.PSObject.Properties.Name -contains $k)) { throw ("卡 {0} 缺字段 {1}" -f ($i + 1), $k) }
  }
}
# 卡 1~4：顺时针移动到下一个有英雄的地点（dict move），带 BAM、无图案、无效果
for ($i = 0; $i -lt 4; $i++) {
  $mv = $back.actions[$i].move
  if ($mv -isnot [System.Management.Automation.PSCustomObject]) { throw ("卡 {0} 的 move 应为 dict（犀牛充电）" -f ($i + 1)) }
  if ($mv.dir -ne 'cw' -or $mv.hero_in -ne $true) { throw ("卡 {0} 的 move 应为 顺时针/有英雄" -f ($i + 1)) }
  if ($back.actions[$i].bam -ne $true) { throw ("卡 {0} 卡面印了 BAM!" -f ($i + 1)) }
  if ($null -ne $back.actions[$i].place) { throw ("卡 {0} 卡面没有放置图案" -f ($i + 1)) }
  if ($null -ne $back.actions[$i].effect) { throw ("卡 {0} 无特殊效果（移动由 move 字段表达）" -f ($i + 1)) }
}
# 逐卡移动值（卡图实测；1~4 为 dict 移动，单独处理）
$moves = @($null, $null, $null, $null, 4, 2, 1, 1, 2, 3, 5, 0)
for ($i = 4; $i -lt 12; $i++) {
  if ($back.actions[$i].move -ne $moves[$i]) { throw ("卡 {0} 移动应为 {1}，实际 {2}" -f ($i + 1), $moves[$i], $back.actions[$i].move) }
}
# 逐卡 BAM（卡图实测 + 像素扫描：11/12 无 BAM）
$bams = @($true, $true, $true, $true, $true, $true, $true, $true, $true, $true, $false, $false)
for ($i = 0; $i -lt 12; $i++) {
  if ($back.actions[$i].bam -ne $bams[$i]) { throw ("卡 {0} BAM 应为 {1}" -f ($i + 1), $bams[$i]) }
}
# 有图案的卡：5~12；每张必须三槽齐全、每槽非空、种类只能是 civ/thug
for ($i = 4; $i -le 11; $i++) {
  $pl = $back.actions[$i].place
  if ($null -eq $pl) { throw ("卡 {0} 应有放置图案" -f ($i + 1)) }
  if ($pl.Count -ne 3) { throw ("卡 {0} 的 place 应为 3 个槽位，实际 {1}" -f ($i + 1), $pl.Count) }
  foreach ($slot in $pl) {
    if ($slot -is [string]) { throw ("卡 {0} 的槽位被 PowerShell 展平成一维数组了" -f ($i + 1)) }
    if ($null -eq $slot -or $slot.Count -lt 1) { throw ("卡 {0} 有空槽位" -f ($i + 1)) }
    foreach ($k in $slot) { if ($k -ne 'civ' -and $k -ne 'thug') { throw ("卡 {0} 出现非法指示物种类 {1}" -f ($i + 1), $k) } }
  }
}
# 逐卡图案（卡图实测，逐格逐指示物核对）
$expect = @{
  5  = @(@('thug'), @('thug'), @('thug'));
  6  = @(@('thug'), @('thug'), @('thug'));
  7  = @(@('thug'), @('thug'), @('thug'));
  8  = @(@('civ'), @('civ'), @('civ'));
  9  = @(@('civ'), @('civ'), @('civ'));
  10 = @(@('civ'), @('civ'), @('civ'));
  11 = @(@('thug', 'civ'), @('thug', 'civ'), @('thug', 'civ'));
  12 = @(@('thug', 'civ'), @('thug', 'civ'), @('thug', 'civ'))
}
foreach ($n in 5..12) {
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
# 无图案的卡：1~4
foreach ($n in 1, 2, 3, 4) {
  if ($null -ne $back.actions[$n - 1].place) { throw ("卡 {0} 卡面没有放置图案，place 应为 null" -f $n) }
}
# 效果卡的 effect 三字段齐全（本批应全部为 null）
for ($i = 0; $i -lt 12; $i++) {
  $e = $back.actions[$i].effect
  if ($null -ne $e) {
    foreach ($k in 'type', 'name', 'text') { if (-not ($e.PSObject.Properties.Name -contains $k)) { throw ("卡 {0} 的 effect 缺字段 {1}" -f ($i + 1), $k) } }
  }
}
# 威胁卡校验：6 张全部无生命值、无 BAM、无到达/开始回合、都有 3 个英勇槽
if (@($back.threats | Where-Object { $_.henchman_hp -ne 0 }).Count -ne 0) { throw "6 张威胁卡卡面都没有生命值图标（henchman_hp 应全为 0）" }
if (@($back.threats | Where-Object { $_.bam -eq $true }).Count -ne 0) { throw "6 张威胁卡卡面都没有 BAM! 星爆（像素扫描确认）" }
if (@($back.threats | Where-Object { $_.arrival -eq $true }).Count -ne 0) { throw "6 张威胁卡卡面都没有到达地点徽标" }
if (@($back.threats | Where-Object { $_.start_turn -eq $true }).Count -ne 0) { throw "6 张威胁卡都不是'开始回合'型效果" }
if (@($back.threats | Where-Object { $_.clear.Count -ne 3 }).Count -ne 0) { throw "6 张威胁卡卡面底部都是 3 个英勇槽" }
if (@($back.threats | Where-Object { ($_.clear | Where-Object { $_ -ne 'heroic' }).Count -ne 0 }).Count -ne 0) { throw "英勇槽只能填 heroic" }
if (@($back.threats | Where-Object { $_.start_turn -eq $true -and $_.constant -eq $true }).Count -ne 0) { throw "start_turn 与 constant 不应同时为真" }
$tnames = @($back.threats | ForEach-Object { $_.name })
if (($tnames -join ',') -ne '开阔地带,无掩护,开阔地带,无掩护,开阔地带,无掩护') {
  throw ("威胁卡顺序应为 开阔地带/无掩护 交替（拼版 01..06），实际 $($tnames -join ',')")
}
if (@($tnames | Where-Object { $_ -eq '开阔地带' }).Count -ne 3) { throw "开阔地带应有 3 张" }
if (@($tnames | Where-Object { $_ -eq '无掩护' }).Count -ne 3) { throw "无掩护应有 3 张" }
foreach ($t in $back.threats) { if ([string]::IsNullOrWhiteSpace($t.text)) { throw ("威胁卡 {0} 缺 text" -f $t.name) } }

# ---------------------------------------------------------------- 合并进现有文件（并发安全）
$attempt = 0
while ($true) {
  $attempt++
  $raw = Get-Content $path -Raw -Encoding UTF8
  $sha = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
      [System.Text.Encoding]::UTF8.GetBytes($raw))).Replace('-', '')
  foreach ($must in 'zemo', 'modok', 'kang') {
    if ($raw -notmatch ('"' + $must + '"\s*:')) { throw "读入的 villains.json 里没有 $must，疑似被别的进程改坏，停手" }
  }
  $all = $raw | ConvertFrom-Json
  if ($all.PSObject.Properties.Name -contains 'rhino') {
    Write-Host "  已存在 rhino，覆盖之"
    $all.PSObject.Properties.Remove('rhino')
  }
  $all | Add-Member -NotePropertyName 'rhino' -NotePropertyValue $back -Force
  $out = $all | ConvertTo-Json -Depth 10
  $null = $out | ConvertFrom-Json    # 写回前再校验一次
  # 写回前最后确认：文件自我读入后没有被改过（康那一路可能刚写完）
  $raw2 = Get-Content $path -Raw -Encoding UTF8
  $sha2 = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
      [System.Text.Encoding]::UTF8.GetBytes($raw2))).Replace('-', '')
  if ($sha -ne $sha2) {
    if ($attempt -ge 6) { throw "villains.json 在读-写窗口内被其它进程改了 6 次，停手避免覆盖别人的改动" }
    Write-Host "  ⚠ villains.json 在读-写窗口内被改动（第 $attempt 次），重试"
    Start-Sleep -Milliseconds 800
    continue
  }
  [System.IO.File]::WriteAllText($path, $out, [System.Text.UTF8Encoding]::new($false))
  break
}

# ---------------------------------------------------------------- 写回后复查
$check = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
$keys = @($check.PSObject.Properties.Name)
foreach ($must in 'zemo', 'modok', 'kang', 'rhino') {
  if ($keys -notcontains $must) { throw "写回后丢了 $must 键！" }
}
Write-Host ("  villains.json 反派数 = {0}（zemo/modok/kang/rhino 四个键都在）" -f $keys.Count)
Write-Host ("  rhino：生命 {0}/{1}/{2}，威胁 {3} 张，行动 {4} 张" -f $check.rhino.health.'2', $check.rhino.health.'3', $check.rhino.health.'4', $check.rhino.threats.Count, $check.rhino.actions.Count)
