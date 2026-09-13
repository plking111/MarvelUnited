# 把"第一季众筹第二批"12 位英雄合并进 data\heroes.json
# 用法：pwsh -File devtools\gen_batch2_heroes.ps1
# 说明：数据源是 _testlog\batch2_cards.json（docx 结构化解析结果），
#       已用卡图核对过的 3 处写在 $overrides 里（以卡图为准）。
# 注意：必须先备份 heroes.json；本脚本只在生成结果能通过 JSON 校验时才写回。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root 'MarvelUnitedGame\data\heroes.json'
$src = Join-Path $root '_testlog\batch2_cards.json'

$meta = @{
  mantis        = @{cn='螳螂女';      en='Mantis';        color='#8ee36b'}
  shangchi      = @{cn='尚气';        en='Shang-Chi';     color='#e8c33d'}
  drax          = @{cn='德拉克斯';    en='Drax';          color='#5aa9e6'}
  drstrange     = @{cn='奇异博士';    en='Doctor Strange';color='#c05fd6'}
  ironfist      = @{cn='铁拳';        en='Iron Fist';     color='#f2d24b'}
  punisher      = @{cn='惩罚者';      en='Punisher';      color='#e05a5a'}
  scarletwitch  = @{cn='绯红女巫';    en='Scarlet Witch'; color='#e0558f'}
  lukecage      = @{cn='卢克凯奇';    en='Luke Cage';     color='#c9a227'}
  jessicajones  = @{cn='杰西卡・琼斯';en='Jessica Jones'; color='#7f6fd6'}
  quicksilver   = @{cn='快银';        en='Quicksilver';   color='#6fd6d6'}
  daredevil     = @{cn='夜魔侠';      en='Daredevil';     color='#d64545'}
  elektra       = @{cn='艾丽卡';      en='Elektra';       color='#d64f8f'}
}
$slugs = @{
  '心灵治疗'='mantis_mind_heal'; '星体投射'='mantis_astral_projection'; '移情操控'='mantis_empathic_control'
  '武术大师'='shangchi_martial_master'
  '复仇'='drax_vengeance'
  '悬浮斗篷'='drstrange_cloak'; '维度传送门'='drstrange_portal'
  '阿戈摩托之球'='drstrange_orb_of_agamotto'; '阿戈摩托之眼'='drstrange_eye_of_agamotto'; '维山蒂之书'='drstrange_book_of_vishanti'
  '气之强化'='ironfist_chi_boost'
  '精准射击'='punisher_precise_shot'; '强大火力'='punisher_heavy_firepower'; '特种作战训练'='punisher_special_ops'
  '心灵能量'='scarletwitch_psychic_energy'; '心灵能量场'='scarletwitch_psychic_field'; '混沌魔法'='scarletwitch_chaos_magic'
  '超人力量'='lukecage_super_strength'; '再生治愈因子'='lukecage_healing_factor'; '近乎无敌'='lukecage_near_invincible'
  '私家侦探'='jessicajones_private_eye'; '心灵防护'='jessicajones_psychic_shield'; '侦探专家'='jessicajones_master_detective'
  '超人速度'='quicksilver_super_speed'; '速度格斗'='quicksilver_speed_combat'; '奔赴救援'='quicksilver_dash_rescue'
  '盲眼正义'='daredevil_blind_justice'; '无畏之人'='daredevil_man_without_fear'; '雷达感官'='daredevil_radar_sense'
  '刺杀大师'='elektra_assassin'; '忍者训练'='elektra_ninja_training'; '双截棍'='elektra_nunchaku'
}
# 已用卡图核对过的 3 处（docx 不完整）
$overrides = @{
  'jessicajones|12' = @{symbols=@('move'); name='侦探专家'; text='展示反派行动牌堆顶的一张牌，你获得等同于这张牌移动数量的指示物（指示物类型由你选择）。'}
  'daredevil|10'    = @{symbols=@('move'); name='雷达感官'; text='本回合你每进入一个地点，获得 1 个英勇指示物或 1 个攻击指示物（由你选择）。'}
  'punisher|10'     = @{symbols=@();       name='精准射击'; text='对一个敌人造成 4 次攻击；本回合你造成的伤害无法被取消或忽略。'}
}
$order = @('mantis','shangchi','drax','drstrange','ironfist','punisher','scarletwitch','lukecage','jessicajones','quicksilver','daredevil','elektra')

function Esc([string]$s) { return ($s -replace '\\','\\' -replace '"','\"' -replace "`r",'' -replace "`n",' ') }

$b = Get-Content $src -Raw -Encoding UTF8 | ConvertFrom-Json
$sb = New-Object System.Text.StringBuilder
$first = $true
foreach ($id in $order) {
  if (-not $first) { [void]$sb.AppendLine(',') }
  $first = $false
  $m = $meta[$id]
  [void]$sb.AppendLine(('  "{0}": {{' -f $id))
  [void]$sb.AppendLine(('    "name": "{0}",' -f $m.cn))
  [void]$sb.AppendLine(('    "name_en": "{0}",' -f $m.en))
  [void]$sb.AppendLine(('    "color": "{0}",' -f $m.color))
  [void]$sb.AppendLine(('    "back": "res://assets/cards/heroes/{0}/back.png",' -f $id))
  [void]$sb.AppendLine('    "expansion": "第一季众筹",')
  [void]$sb.AppendLine('    "cards": [')
  $cards = $b.$id
  for ($i = 0; $i -lt 12; $i++) {
    $c = $cards[$i]
    $ov = $overrides["$id|$($i + 1)"]
    $syms = if ($ov) { $ov.symbols } else { $c.symbols }
    $text = if ($ov) { "$($ov.name)：$($ov.text)" } else { [string]$c.text }
    $line = '      { "symbols": [' + (($syms | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']'
    if ($text -ne '') {
      $parts = $text -split '：', 2
      $ename = Esc $parts[0]
      $etext = if ($parts.Count -gt 1) { Esc $parts[1] } else { '' }
      $etype = $slugs[$parts[0]]
      if (-not $etype) { Write-Host "⚠ 缺 slug：$($parts[0])（英雄 $id 卡 $($i+1)）"; $etype = "${id}_todo$($i+1)" }
      $line += ', "effect": { "type": "' + $etype + '", "name": "' + $ename + '", "text": "' + $etext + '" }'
    }
    $line += ' }'
    if ($i -lt 11) { $line += ',' }
    [void]$sb.AppendLine($line)
  }
  [void]$sb.AppendLine('    ]')
  [void]$sb.Append('  }')
}
$raw = [System.IO.File]::ReadAllText($target, [System.Text.UTF8Encoding]::new($false)).TrimEnd()
$idx = $raw.LastIndexOf('}')
# 关键：原文件最后一个条目结尾没有逗号，所以插入块必须以逗号开头
$newJson = $raw.Substring(0, $idx).TrimEnd() + ",`n" + $sb.ToString() + "`n}`n"
try {
  $chk = $newJson | ConvertFrom-Json
  $n = $chk.PSObject.Properties.Name.Count
  Write-Host "JSON 校验通过，英雄总数 = $n"
} catch {
  Write-Host "❌ 生成的 JSON 不合法，未写回：$($_.Exception.Message)"
  exit 1
}
[System.IO.File]::WriteAllText($target, $newJson, [System.Text.UTF8Encoding]::new($false))
Write-Host "已写回 $target"
