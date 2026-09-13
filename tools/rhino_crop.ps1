# Crop helper for Rhino: move/BAM montage + placement-box montage + threat cards (ASCII only)
# Produces magnified contact sheets under _testlog\rhino_crops for eyeball verification.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\rhino'
$out = Join-Path $root '_testlog\rhino_crops'
New-Item -ItemType Directory -Force $out | Out-Null

function LoadBmp([string]$p) {
  $src = [System.Drawing.Image]::FromFile($p)
  $bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose()
  $src.Dispose(); return $bmp
}
$font = New-Object System.Drawing.Font('Arial', 18, [System.Drawing.FontStyle]::Bold)
$fontS = New-Object System.Drawing.Font('Arial', 15, [System.Drawing.FontStyle]::Bold)

# ---- montage A: move number + BAM region (right column of each action card) ----
# source region inside a card: x 440..830, y 230..790
$cw = 390; $chh = 560; $mul = 1.0
$ow = [int]($cw * $mul); $oh = [int]($chh * $mul)
$cols = 4
$rows = 3
$sheet = New-Object System.Drawing.Bitmap(($ow * $cols), (($oh + 30) * $rows))
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::White)
for ($i = 1; $i -le 12; $i++) {
  $b = LoadBmp (Join-Path $dir ("action_{0:d2}.png" -f $i))
  $k = $i - 1
  $col = $k % $cols; $row = [int][math]::Floor($k / $cols)
  $dx = $col * $ow; $dy = $row * ($oh + 30)
  $g.DrawImage($b, (New-Object System.Drawing.Rectangle($dx, ($dy + 30), $ow, $oh)), (New-Object System.Drawing.Rectangle(440, 230, $cw, $chh)), [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString(("action_{0:d2}  move/BAM" -f $i), $font, [System.Drawing.Brushes]::Black, ($dx + 4), ($dy + 4))
  $b.Dispose()
}
$g.Dispose()
$sheet.Save((Join-Path $out 'montage_movebam.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

# ---- montage B: placement band (lower third of each action card), magnified 1.5x ----
# source region inside a card: x 0..853, y 760..1198  (w=853, h=438)
$pw = 853; $ph = 438; $pmul = 1.5
$pw2 = [int]($pw * $pmul); $ph2 = [int]($ph * $pmul)
$cols2 = 3
$rows2 = 4
$sheet2 = New-Object System.Drawing.Bitmap(($pw2 * $cols2), (($ph2 + 30) * $rows2))
$g2 = [System.Drawing.Graphics]::FromImage($sheet2)
$g2.Clear([System.Drawing.Color]::White)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
for ($i = 1; $i -le 12; $i++) {
  $b = LoadBmp (Join-Path $dir ("action_{0:d2}.png" -f $i))
  $k = $i - 1
  $col = $k % $cols2; $row = [int][math]::Floor($k / $cols2)
  $dx = $col * $pw2; $dy = $row * ($ph2 + 30)
  $g2.DrawImage($b, (New-Object System.Drawing.Rectangle($dx, ($dy + 30), $pw2, $ph2)), (New-Object System.Drawing.Rectangle(0, 760, $pw, $ph)), [System.Drawing.GraphicsUnit]::Pixel)
  $g2.DrawString(("action_{0:d2}  placement band" -f $i), $font, [System.Drawing.Brushes]::Black, ($dx + 4), ($dy + 4))
  $b.Dispose()
}
$g2.Dispose()
$sheet2.Save((Join-Path $out 'montage_placement.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$sheet2.Dispose()

# ---- threat cards: name bar + text band + heroic slots, one image per card ----
foreach ($t in 1..6) {
  $b = LoadBmp (Join-Path $dir ("threat_{0:d2}.png" -f $t))
  $nb = New-Object System.Drawing.Bitmap($b.Width, ($b.Height + 30))
  $ng = [System.Drawing.Graphics]::FromImage($nb)
  $ng.Clear([System.Drawing.Color]::White)
  $ng.DrawImage($b, (New-Object System.Drawing.Rectangle(0, 30, $b.Width, $b.Height)), (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)), [System.Drawing.GraphicsUnit]::Pixel)
  $ng.DrawString(("threat {0:d2} ({1}x{2})" -f $t, $b.Width, $b.Height), $fontS, [System.Drawing.Brushes]::Black, 6, 4)
  $ng.Dispose()
  $nb.Save((Join-Path $out ("threat_{0:d2}.png" -f $t)), [System.Drawing.Imaging.ImageFormat]::Png)
  $nb.Dispose()
  $b.Dispose()
}
Write-Host ("done -> {0}" -f $out)
