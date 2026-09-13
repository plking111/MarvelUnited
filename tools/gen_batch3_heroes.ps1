# 第三批（3.x）13 位英雄：把 data/heroes.json 从 44 位扩到 57 位
#
# 设计（照第二批 gen_batch2_heroes.ps1）：
#   1) 符号与卡面文本从 _testlog\batch3_cards.json 读（已按卡图核对过关键卡）
#   2) 效果 type/名称/最终文本在本脚本的映射表里定义（type 与 game.gd 的分支一一对应）
#   3) 合并前先校验 JSON，坏了就不写回
param([switch]$WhatIf)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$jsonPath = Join-Path $root 'MarvelUnitedGame\data\heroes.json'
$dataPath = Join-Path $root '_testlog\batch3_cards.json'

$names = [ordered]@{
  adamwarlock = '术士亚当'; missamerica = '美国小姐'; nebula = '星云'; yondou = '勇度'
  ghostrider = '恶灵骑士'; mockingbird = '仿声鸟'; shehulk = '女浩克'; squirrelgirl = '松鼠女'
  moonknight = '月光骑士'; nova = '新星'; blade = '刀锋战士'; howardtheduck = '霍华德鸭'; msmarvel = '惊奇女士'
}
$namesEn = [ordered]@{
  adamwarlock = 'Adam Warlock'; missamerica = 'Miss America'; nebula = 'Nebula'; yondou = 'Yondu'
  ghostrider = 'Ghost Rider'; mockingbird = 'Mockingbird'; shehulk = 'She-Hulk'; squirrelgirl = 'Squirrel Girl'
  moonknight = 'Moon Knight'; nova = 'Nova'; blade = 'Blade'; howardtheduck = 'Howard the Duck'; msmarvel = 'Ms. Marvel'
}
$colors = [ordered]@{
  adamwarlock = '#d4af37'; missamerica = '#3a86ff'; nebula = '#7b2d8e'; yondou = '#2a9d8f'
  ghostrider = '#ff6b35'; mockingbird = '#a68a64'; shehulk = '#2ecc71'; squirrelgirl = '#d97706'
  moonknight = '#dfe6e9'; nova = '#f1c40f'; blade = '#7f1d1d'; howardtheduck = '#b8860b'; msmarvel = '#e91e63'
}

# 效果表：英雄 → 卡号(1..12) → @(type, 名称, 文本)
# 文本以卡面为准（docx 有明显笔误处按卡面语义写通顺）；口径见交接文档第 4 节
$fx = @{
  adamwarlock = @{
    6  = @('adamwarlock_life_avatar', '生命化身', '下一个反派回合翻出的反派行动卡背面朝上加入故事情节，并且没有任何效果（连移动也不发生）——该回合反派等于空过。')
    8  = @('adamwarlock_quantum_magic', '量子魔法', '查看反派行动牌堆顶的三张牌，然后你可以按任意顺序把它们放回牌堆顶（可以拖动卡牌调整顺序）。')
    9  = @('adamwarlock_immortality', '不朽', '只要这张牌在故事情节中正面朝上，你就永远不会因为弃牌而丢掉最后一张手牌。')
  }
  missamerica = @{
    2  = @('missamerica_stargate', '星门', '进行两次万能行动。')
    7  = @('missamerica_energy_infusion', '能量注入', '进行两次攻击行动。')
    12 = @('missamerica_invincible', '无敌', '直到你的下个回合开始，你无法受到任何伤害。')
  }
  nebula = @{
    10 = @('nebula_regen_implant', '再生植入体', '你可以抽牌直到你有 3 张手牌。')
    11 = @('nebula_image_projection', '影像投射', '每个英雄可以自愿把手中一张牌与故事情节中的一张牌交换（只能换自己英雄的牌，也可以不换）；随后移除反派行动牌堆顶的一张牌。')
    12 = @('nebula_electro_baton', '电机警棍', '在两个相邻地点进行两次攻击行动，由你自行分配。')
  }
  yondou = @{
    10 = @('yondou_yaka_whirlwind', '亚卡箭旋风', '从你所在地点开始顺时针计算，击败每个地点的一个暴徒，直到计算到没有暴徒的地点为止。')
    11 = @('yondou_yaka_barrage', '亚卡箭乱射', '进行三次攻击行动，可以任意分配在你所在地点和两个相邻地点。')
    12 = @('yondou_traitor', '叛徒', '你可以将你所在地点的每个平民转化为暴徒、每个暴徒转化为平民。')
  }
  ghostrider = @{
    8  = @('ghostrider_mystic_chain', '神秘锁链', '对你所在地点的每个暴徒进行两次攻击。')
    9  = @('ghostrider_hellfire_control', '地狱火操控', '对你所在地点的单个敌人造成三次攻击。')
    10 = @('ghostrider_supernatural_sense', '超自然感知', '进行一次攻击行动和一次英勇行动，然后抽取一张牌。')
  }
  mockingbird = @{
    7  = @('mockingbird_battle_staff', '战斗法杖', '击败你所在地点的 2 个暴徒。')
    9  = @('mockingbird_spy_master_1', '间谍大师', '下一个反派回合，反派无法在你所在地点添加平民/暴徒指示物。')
    10 = @('mockingbird_spy_master_2', '间谍大师', '下一个反派回合，反派无法在你所在地点添加平民/暴徒指示物。')
  }
  shehulk = @{
    9  = @('shehulk_transform_1', '变形', '进行一次攻击行动；故事情节中每有一张「变形」（包括这张），就额外进行一次攻击行动。')
    10 = @('shehulk_transform_2', '变形', '进行一次攻击行动；故事情节中每有一张「变形」（包括这张），就额外进行一次攻击行动。')
    11 = @('shehulk_transform_3', '变形', '进行一次攻击行动；故事情节中每有一张「变形」（包括这张），就额外进行一次攻击行动。')
    12 = @('shehulk_transform_4', '变形', '进行一次攻击行动；故事情节中每有一张「变形」（包括这张），就额外进行一次攻击行动。')
  }
  squirrelgirl = @{
    10 = @('squirrelgirl_night_vision', '夜视', '揭示反派行动牌堆顶的一张牌，然后你可以选择把它放到反派牌堆底部。')
    11 = @('squirrelgirl_squirrel_army', '松鼠大军', '对每个地点的一个敌人造成一点攻击（每个地点都要弹窗选择）。')
    12 = @('squirrelgirl_hyper_awareness', '非常感知', '只要故事情节中带有特殊效果的英雄行动牌数量大于反派的当前生命值，英雄们立即获胜（持续检查）。')
  }
  moonknight = @{
    6  = @('moonknight_moon_suit', '月光骑士战衣', '直到你的下个回合开始，你每次受到伤害时都可以无视该伤害，并（可选）移动到任意地点。')
    9  = @('moonknight_dissociative', '解离性身份障碍', '将你的手牌与牌库混洗，然后重新抽取三张牌。')
    10 = @('moonknight_khonshu_power', '孔苏之力', '故事情节中每有一张带特殊效果的英雄行动牌（包括这张），你就获得一个万能指示物。')
  }
  nova = @{
    10 = @('nova_helping_hand_1', '我就是援手', '在一个相邻地点进行两次英勇行动。')
    11 = @('nova_helping_hand_2', '我就是援手', '在一个相邻地点进行两次英勇行动。')
    12 = @('nova_helping_hand_3', '我就是援手', '在一个相邻地点进行两次英勇行动。')
  }
  blade = @{
    8  = @('blade_blood_bath', '血浴', '击败你所在地点的所有暴徒。')
    9  = @('blade_vampiric_heal', '吸血愈合', '抽取一张牌。')
    10 = @('blade_hunter_skill', '猎人技巧', '本回合你对单个敌人进行一次攻击行动时，改为两次攻击行动（即一次攻击行动造成两点伤害，而不是获得两个攻击行动）。')
  }
  howardtheduck = @{
    3  = @('howardtheduck_no_more_mr_nice_duck', '不再是好好先生鸭！', '对你所在地点的每个敌人造成两次攻击。')
    4  = @('howardtheduck_big_weird_gun', '巨大的怪枪', '对任意一个地点进行两次攻击行动。')
    5  = @('howardtheduck_neutron_disintegrator', '中子分解器', '对你所在地点的一个反派或爪牙造成伤害直到其生命值剩余 1 点；你本回合不能再使用攻击行动（对反派使用时依旧遵循"完成两个任务后才能攻击反派"的规则）。')
  }
  msmarvel = @{
    8  = @('msmarvel_appearance_change', '外观改造', '本回合你的所有行动都视为万能行动。')
    9  = @('msmarvel_elastic_extension', '弹性延伸', '本回合你的攻击行动可以指定相邻地点的敌人。')
    12 = @('msmarvel_morphogenesis', '形态发生', '你可以将任意数量的手牌与故事情节中任意数量正面朝上的、你自己的行动牌进行交换。')
  }
}

$cards = Get-Content $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$heroes = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

$added = 0
foreach ($id in $names.Keys) {
  if ($heroes.PSObject.Properties.Name -contains $id) { Write-Host "  已存在，跳过：$id"; continue }
  $src = $cards.$id
  if ($null -eq $src -or $src.Count -ne 12) { throw "$id 的卡数据不是 12 张" }
  $list = @()
  for ($i = 0; $i -lt 12; $i++) {
    $cardNo = $i + 1
    $sym = @($src[$i].symbols)
    $entry = [ordered]@{ symbols = $sym }
    if ($fx.ContainsKey($id) -and $fx[$id].ContainsKey($cardNo)) {
      $f = $fx[$id][$cardNo]
      $entry['effect'] = [ordered]@{ type = $f[0]; name = $f[1]; text = $f[2] }
    }
    $list += $entry
  }
  $hero = [ordered]@{
    name = $names[$id]; name_en = $namesEn[$id]; color = $colors[$id]
    back = "res://assets/cards/heroes/$id/back.png"
    expansion = '第一季众筹'
    cards = $list
  }
  $heroes | Add-Member -NotePropertyName $id -NotePropertyValue $hero
  $added++
  Write-Host ("  + {0} {1}（{2} 个效果）" -f $id, $names[$id], ($list | Where-Object { $_.Contains('effect') }).Count)
}

$out = $heroes | ConvertTo-Json -Depth 8
# 写回前先校验：能解析回来 & 英雄数正确
try {
  $check = $out | ConvertFrom-Json
  $cnt = $check.PSObject.Properties.Name.Count
  if ($cnt -ne 57) { throw "英雄数应为 57，实际 $cnt" }
  foreach ($id in $names.Keys) { if (-not ($check.PSObject.Properties.Name -contains $id)) { throw "缺少 $id" } }
} catch {
  Write-Host "❌ JSON 校验失败，未写回：$_"
  exit 1
}
if ($WhatIf) { Write-Host "（-WhatIf：只校验不写回）"; exit 0 }
[System.IO.File]::WriteAllText($jsonPath, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host ("完成：新增 {0} 位，heroes.json 现 {1} 位" -f $added, ($out | ConvertFrom-Json).PSObject.Properties.Name.Count)
