# Crop helper: right-column (move/BAM) montage + threat-card halves (ASCII only)
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\modok'
$out = Join-Path $root '_testlog\modok_crops'
New-Item -ItemType Directory -Force $out | Out-Null

function LoadBmp([string]$p) {
  $src = [System.Drawing.Image]::FromFile($p)
  $bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose()
  $src.Dispose(); return $bmp
}
function Blit($dstG, [System.Drawing.Bitmap]$src, [int]$x, [int]$y, [int]$w, [int]$h) {
  $dstG.DrawImage($src, (New-Object System.Drawing.Rectangle($x, $y, $w, $h)))
}
$font = New-Object System.Drawing.Font('Arial', 18, [System.Drawing.FontStyle]::Bold)

# ---- montage of move+BAM region: 6 cards (3,4,5,6,7,8) ----
$ids = @(3, 6, 8, 9, 10, 12)
$cw = 340; $chh = 330; $mul = 1.9
$ow = [int]($cw * $mul); $oh = [int]($chh * $mul)
$sheet = New-Object System.Drawing.Bitmap(($ow * 2), (($oh + 34) * 3))
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::White)
$k = 0
foreach ($i in $ids) {
  $b = LoadBmp (Join-Path $dir ("action_{0:d2}.png" -f $i))
  $col = $k % 2; $row = [int][math]::Floor($k / 2)
  $dx = $col * $ow; $dy = $row * ($oh + 34)
  $g.DrawImage($b, (New-Object System.Drawing.Rectangle($dx, ($dy + 34), $ow, $oh)), (New-Object System.Drawing.Rectangle(450, 370, $cw, $chh)), [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString(("card {0:d2}  (x450-790,y370-700)" -f $i), $font, [System.Drawing.Brushes]::Black, ($dx + 4), ($dy + 4))
  $b.Dispose(); $k++
}
$g.Dispose()
$sheet.Save((Join-Path $out 'montage_movebam.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

# ---- threat cards: top/bottom halves at 1.0x ----
foreach ($t in 1..6) {
  $b = LoadBmp (Join-Path $dir ("threat_{0:d2}.png" -f $t))
  $hh = [int]($b.Height / 2)      # 426
  foreach ($half in 0, 1) {
    $nb = New-Object System.Drawing.Bitmap($b.Width, ($hh + 30))
    $ng = [System.Drawing.Graphics]::FromImage($nb)
    $ng.Clear([System.Drawing.Color]::White)
    $ng.DrawImage($b, (New-Object System.Drawing.Rectangle(0, 30, $b.Width, $hh)), (New-Object System.Drawing.Rectangle(0, ($half * $hh), $b.Width, $hh)), [System.Drawing.GraphicsUnit]::Pixel)
    $ng.DrawString(("threat {0:d2} half {1} ({2}x{3})" -f $t, ($half + 1), $b.Width, $b.Height), $font, [System.Drawing.Brushes]::Black, 6, 4)
    $ng.Dispose()
    $nb.Save((Join-Path $out ("threat_{0:d2}_h{1}.png" -f $t, ($half + 1))), [System.Drawing.Imaging.ImageFormat]::Png)
    $nb.Dispose()
  }
  $b.Dispose()
}
Write-Host ("done -> {0}" -f $out)
