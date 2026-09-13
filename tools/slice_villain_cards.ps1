# 反派素材切片工具（素材 → 游戏资源）
# 规则（与现有反派一致，尺寸取自 corvus 的成品）：
#   行动卡表：6 列 × 2 行、行优先 = action_01..12；每格 resize 到 853×1198
#   行动卡背面 → back.png（853×1198）
#   面板/面板背面 → panel.png / panel_back.png（1140×525）
#   威胁卡表：2 列 × 3 行、行优先 = threat_01..06；每格 resize 到 1198×853
#   威胁卡背面 → threat_back.png（1198×853）
#
# 用法：powershell -File devtools\slice_villain_cards.ps1 -Villain zemo
param(
  [string]$Villain = 'zemo'
)
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$srcRoot = Join-Path $root '素材和相关信息\反派'
$dstRoot = Join-Path $root 'MarvelUnitedGame\assets\cards\villains'

# 素材文件夹 → 游戏内 id
$maps = @{
  'zemo' = @{ folder = '7.2泽莫男爵'; id = 'zemo' }
  'modok' = @{ folder = '7.3摩多克'; id = 'modok' }
  'kang' = @{ folder = '7.4康'; id = 'kang' }
  'rhino' = @{ folder = '7.5犀牛人'; id = 'rhino' }
}

$cfg = $maps[$Villain]
if ($null -eq $cfg) { Write-Host "没有 $Villain 的映射"; exit 2 }
$srcDir = Join-Path $srcRoot $cfg.folder
$outDir = Join-Path $dstRoot $cfg.id
New-Item -ItemType Directory -Force $outDir | Out-Null

function Save-Cell([System.Drawing.Image]$img, [System.Drawing.Rectangle]$src, [int]$w, [int]$h, [string]$outPath) {
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), $src, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# 找素材：按文件名关键字归类（比"最大文件"稳，前两批吃过亏）
$files = Get-ChildItem $srcDir -File | Where-Object { $_.Extension -match '\.(png|jpg|jpeg)$' }
function Pick([string]$include, [string]$exclude) {
  $c = $files | Where-Object { $_.Name -like "*$include*" -and ($exclude -eq '' -or $_.Name -notlike "*$exclude*") }
  if ($c.Count -gt 0) { return $c[0].FullName }
  return ''
}
$actionSheet = Pick '行动卡' '背面'
$actionBack  = Pick '行动卡背面' ''
$panel       = Pick '面板' '背面'
$panelBack   = Pick '面板背面' ''
$threatSheet = Pick '威胁卡' '背面'
$threatBack  = Pick '威胁卡背面' ''

if ($actionSheet -eq '' -or $actionBack -eq '' -or $panel -eq '' -or $threatSheet -eq '' -or $threatBack -eq '') {
  Write-Host "素材没找齐：action=$actionSheet back=$actionBack panel=$panel threat=$threatSheet threatBack=$threatBack"
  exit 3
}

# ① 行动卡 6×2
$img = [System.Drawing.Image]::FromFile($actionSheet)
$cw = [int][math]::Floor($img.Width / 6); $ch = [int][math]::Floor($img.Height / 2)
for ($r = 0; $r -lt 2; $r++) {
  for ($c = 0; $c -lt 6; $c++) {
    $idx = $r * 6 + $c + 1
    Save-Cell $img (New-Object System.Drawing.Rectangle(($c * $cw), ($r * $ch), $cw, $ch)) 853 1198 (Join-Path $outDir ("action_{0:d2}.png" -f $idx))
  }
}
Write-Host ("  行动卡表 {0}x{1}（每格 {2}x{3}）→ 12 张" -f $img.Width, $img.Height, $cw, $ch)
$img.Dispose()

# ② 行动卡背面
$img = [System.Drawing.Image]::FromFile($actionBack)
Save-Cell $img (New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)) 853 1198 (Join-Path $outDir 'back.png')
Write-Host ("  行动卡背面 {0}x{1} → back.png 853x1198" -f $img.Width, $img.Height)
$img.Dispose()

# ③ 面板 / 面板背面（1140x525）
foreach ($pair in @(@($panel, 'panel.png'), @($panelBack, 'panel_back.png'))) {
  if ($pair[0] -eq '') { continue }
  $img = [System.Drawing.Image]::FromFile($pair[0])
  Save-Cell $img (New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)) 1140 525 (Join-Path $outDir $pair[1])
  Write-Host ("  {0} {1}x{2} → {3} 1140x525" -f (Split-Path $pair[0] -Leaf), $img.Width, $img.Height, $pair[1])
  $img.Dispose()
}

# ④ 威胁卡 2×3
$img = [System.Drawing.Image]::FromFile($threatSheet)
$tw = [int][math]::Floor($img.Width / 2); $th = [int][math]::Floor($img.Height / 3)
for ($r = 0; $r -lt 3; $r++) {
  for ($c = 0; $c -lt 2; $c++) {
    $idx = $r * 2 + $c + 1
    Save-Cell $img (New-Object System.Drawing.Rectangle(($c * $tw), ($r * $th), $tw, $th)) 1198 853 (Join-Path $outDir ("threat_{0:d2}.png" -f $idx))
  }
}
Write-Host ("  威胁卡表 {0}x{1}（每格 {2}x{3}）→ 6 张" -f $img.Width, $img.Height, $tw, $th)
$img.Dispose()

# ⑤ 威胁卡背面
$img = [System.Drawing.Image]::FromFile($threatBack)
Save-Cell $img (New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)) 1198 853 (Join-Path $outDir 'threat_back.png')
Write-Host ("  威胁卡背面 {0}x{1} → threat_back.png 1198x853" -f $img.Width, $img.Height)
$img.Dispose()

Write-Host ("完成：{0}" -f $outDir)
