# 康（kang）卡图放大裁剪工具：把已切好的单卡按区域裁出来并放大，方便人眼逐格核对指示物图案/文字。
# 用法：powershell -File devtools\kang_crop.ps1
param(
  [string]$OutDir = '',
  [double]$Scale = 2.0
)
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$srcDir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\kang'
if ($OutDir -eq '') { $OutDir = Join-Path $root '_testlog\kang_crops' }
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Crop-Zoom([string]$src, [double]$rx, [double]$ry, [double]$rw, [double]$rh, [string]$out, [double]$scale) {
  $img = [System.Drawing.Image]::FromFile($src)
  $x = [int]($img.Width * $rx); $y = [int]($img.Height * $ry)
  $w = [int]($img.Width * $rw); $h = [int]($img.Height * $rh)
  if ($x + $w -gt $img.Width) { $w = $img.Width - $x }
  if ($y + $h -gt $img.Height) { $h = $img.Height - $y }
  $ow = [int]($w * $scale); $oh = [int]($h * $scale)
  $bmp = New-Object System.Drawing.Bitmap($ow, $oh)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $ow, $oh)), (New-Object System.Drawing.Rectangle($x, $y, $w, $h)), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose(); $img.Dispose()
  Write-Host ("  {0}  ({1},{2}) {3}x{4} -> {5}x{6}" -f (Split-Path $out -Leaf), $x, $y, $w, $h, $ow, $oh)
}

# ① 行动卡：指示物图案带（下半部）逐张放大
foreach ($i in 1..12) {
  $n = '{0:d2}' -f $i
  $p = Join-Path $srcDir ("action_{0}.png" -f $n)
  Crop-Zoom $p 0.05 0.62 0.90 0.36 (Join-Path $OutDir ("act{0}_tokens.png" -f $n)) $Scale
}
# ② 行动卡：右上移动/BAM 区逐张放大
foreach ($i in 1..12) {
  $n = '{0:d2}' -f $i
  $p = Join-Path $srcDir ("action_{0}.png" -f $n)
  Crop-Zoom $p 0.55 0.16 0.45 0.35 (Join-Path $OutDir ("act{0}_movebam.png" -f $n)) $Scale
}
# ③ 面板：BAM 文本区 / 特别规则 / 溢出 / 生命值 分别放大（面板 1140x525）
$panel = Join-Path $srcDir 'panel.png'
Crop-Zoom $panel 0.28 0.05 0.42 0.30 (Join-Path $OutDir 'panel_special.png') $Scale
Crop-Zoom $panel 0.28 0.30 0.42 0.62 (Join-Path $OutDir 'panel_bam.png') $Scale
Crop-Zoom $panel 0.70 0.10 0.30 0.65 (Join-Path $OutDir 'panel_overflow.png') $Scale
Crop-Zoom $panel 0.00 0.55 0.16 0.45 (Join-Path $OutDir 'panel_health.png') $Scale
# ④ 威胁卡：文本带（上 2/3）逐张放大
foreach ($i in 1..6) {
  $n = '{0:d2}' -f $i
  $p = Join-Path $srcDir ("threat_{0}.png" -f $n)
  Crop-Zoom $p 0.04 0.10 0.92 0.62 (Join-Path $OutDir ("thr{0}_text.png" -f $n)) $Scale
  Crop-Zoom $p 0.04 0.70 0.92 0.28 (Join-Path $OutDir ("thr{0}_bottom.png" -f $n)) $Scale
}
Write-Host ("完成：{0}" -f $OutDir)
