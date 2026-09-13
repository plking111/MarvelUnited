# 英雄卡表切片工具（第一季众筹素材 → 游戏资源）
#
# 规则（与第一批 1.x 一致）：
#   卡表：6 列 × 2 行、行优先 = 卡 1~12；每格切下后 resize 到 853×1198
#   背面：resize 到 853×1198（jpg/png 都输出 png）
# 输出：MarvelUnitedGame\assets\cards\heroes\<id>\card_01..12.png + back.png
#
# 用法：
#   powershell -File devtools\slice_hero_sheets.ps1 -Batch 2   # 第二批 12 位（已切）
#   powershell -File devtools\slice_hero_sheets.ps1 -Batch 3   # 第三批 13 位（已切，含 3.0 起编号）
#   （新批次照着 $maps 里加一段映射表即可）
param(
  [int]$Batch = 2
)
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$srcRoot = Join-Path $root '素材和相关信息\英雄\6第一季众筹'
$dstRoot = Join-Path $root 'MarvelUnitedGame\assets\cards\heroes'
$CARD_W = 853
$CARD_H = 1198

# 素材文件夹 → 游戏内 id（按第一批的命名习惯：小写英文、不用下划线）
$maps = @{
  2 = [ordered]@{
    '2.1螳螂女'      = 'mantis'
    '2.2尚气'        = 'shangchi'
    '2.3德拉克斯'    = 'drax'
    '2.4奇异博士'    = 'drstrange'
    '2.5铁拳'        = 'ironfist'
    '2.6惩罚者'      = 'punisher'
    '2.7绯红女巫'    = 'scarletwitch'
    '2.8卢克凯奇'    = 'lukecage'
    '2.9杰西卡・琼斯' = 'jessicajones'
    '2.10快银'       = 'quicksilver'
    '2.11夜魔侠'     = 'daredevil'
    '2.12艾丽卡'     = 'elektra'
  }
  3 = [ordered]@{
    '3.0术士亚当'    = 'adamwarlock'
    '3.1美国小姐'    = 'missamerica'
    '3.2星云'        = 'nebula'
    '3.3勇度'        = 'yondou'
    '3.4恶灵骑士'    = 'ghostrider'
    '3.5仿声鸟'      = 'mockingbird'
    '3.6女浩克'      = 'shehulk'
    '3.7松鼠女'      = 'squirrelgirl'
    '3.8月光骑士'    = 'moonknight'
    '3.9新星'        = 'nova'
    '3.10刀锋战士'   = 'blade'
    '3.11霍华德鸭'   = 'howardtheduck'
    '3.12惊奇女士'   = 'msmarvel'
  }
}
$map = $maps[$Batch]
if ($null -eq $map) { Write-Host "没有第 $Batch 批的映射表"; exit 2 }

function Save-Resized([System.Drawing.Image]$img, [System.Drawing.Rectangle]$srcRect, [string]$outPath) {
  $bmp = New-Object System.Drawing.Bitmap($CARD_W, $CARD_H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $dst = New-Object System.Drawing.Rectangle(0, 0, $CARD_W, $CARD_H)
  $g.DrawImage($img, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

foreach ($folder in $map.Keys) {
  $id = $map[$folder]
  $srcDir = Join-Path $srcRoot $folder
  $outDir = Join-Path $dstRoot $id
  New-Item -ItemType Directory -Force $outDir | Out-Null

  # 卡表 = 横版那张（宽 > 高）；背面 = 竖版那张。
  # 注意：不能用「文件最大」判断 —— 杰西卡・琼斯的竖版背面文件反而比横版卡表大，会切错。
  $imgs = Get-ChildItem $srcDir -File | Where-Object { $_.Extension -match '\.(png|jpg|jpeg)$' }
  $sheetPath = ''
  $backPath = ''
  foreach ($f in $imgs) {
    $im = [System.Drawing.Image]::FromFile($f.FullName)
    $isLandscape = ($im.Width -gt $im.Height)
    $im.Dispose()
    if ($isLandscape -and $sheetPath -eq '') { $sheetPath = $f.FullName }
    elseif (-not $isLandscape -and $backPath -eq '') { $backPath = $f.FullName }
  }
  if ($sheetPath -eq '' -or $backPath -eq '') { Write-Host "  [$id] 素材不足（横版卡表 / 竖版背面没找齐）"; continue }

  $sheet = [System.Drawing.Image]::FromFile($sheetPath)
  $cw = [int][math]::Floor($sheet.Width / 6)
  $ch = [int][math]::Floor($sheet.Height / 2)
  for ($r = 0; $r -lt 2; $r++) {
    for ($c = 0; $c -lt 6; $c++) {
      $idx = $r * 6 + $c + 1
      $rect = New-Object System.Drawing.Rectangle(($c * $cw), ($r * $ch), $cw, $ch)
      $out = Join-Path $outDir ("card_{0:d2}.png" -f $idx)
      Save-Resized $sheet $rect $out
    }
  }
  $sw = $sheet.Width; $sh = $sheet.Height
  $sheet.Dispose()

  $back = [System.Drawing.Image]::FromFile($backPath)
  $brect = New-Object System.Drawing.Rectangle(0, 0, $back.Width, $back.Height)
  Save-Resized $back $brect (Join-Path $outDir 'back.png')
  $bw = $back.Width; $bh = $back.Height
  $back.Dispose()

  $n = (Get-ChildItem $outDir -Filter 'card_*.png').Count
  Write-Host ("  [{0}] {1}：卡表 {2}x{3}（每格 {4}x{5}）→ {6} 张；背面 {7}x{8}" -f $id, $folder, $sw, $sh, $cw, $ch, $n, $bw, $bh)
}
Write-Host "完成"
