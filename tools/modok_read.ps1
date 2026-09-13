# MODOK card inspection helper (ASCII only on purpose: PS 5.1 + no BOM safety)
# Outputs:
#   1) _testlog\modok_crops\sheet_move.png   - right column (move number + BAM) of all 12 action cards, 2x
#   2) _testlog\modok_crops\sheet_place.png  - bottom placement-pattern band of all 12 action cards, 1.6x
#   3) _testlog\modok_crops\threat_NN.png    - 6 threat cards, 1.2x
#   4) stdout: per-card pixel analysis of the pattern band (red = thug, blue = civ), blob counts per frame
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\modok'
$out = Join-Path $root '_testlog\modok_crops'
New-Item -ItemType Directory -Force $out | Out-Null

function LoadBmp([string]$p) {
  $src = [System.Drawing.Image]::FromFile($p)
  $bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.DrawImage($src, 0, 0, $src.Width, $src.Height)
  $g.Dispose(); $src.Dispose()
  return $bmp
}

function CropScaled([System.Drawing.Bitmap]$b, [int]$x, [int]$y, [int]$w, [int]$h, [double]$mul) {
  $ow = [int]($w * $mul); $oh = [int]($h * $mul)
  $nb = New-Object System.Drawing.Bitmap($ow, $oh)
  $g = [System.Drawing.Graphics]::FromImage($nb)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($b, (New-Object System.Drawing.Rectangle(0, 0, $ow, $oh)), (New-Object System.Drawing.Rectangle($x, $y, $w, $h)), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  return $nb
}

function Count-Blobs($grid, [int]$w, [int]$h) {
  # 4-connected component count on the coarse boolean grid (>=4 cells to count)
  $seen = New-Object 'bool[,]' $w, $h
  $n = 0
  for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
      if (-not $grid[$x, $y] -or $seen[$x, $y]) { continue }
      $stack = New-Object System.Collections.Stack
      $stack.Push(@($x, $y))
      $seen[$x, $y] = $true
      $size = 0
      while ($stack.Count -gt 0) {
        $pt = $stack.Pop(); $cx = $pt[0]; $cy = $pt[1]
        $size++
        foreach ($d in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
          $nx = $cx + $d[0]; $ny = $cy + $d[1]
          if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $w -or $ny -ge $h) { continue }
          if ($grid[$nx, $ny] -and -not $seen[$nx, $ny]) { $seen[$nx, $ny] = $true; $stack.Push(@($nx, $ny)) }
        }
      }
      if ($size -ge 4) { $n++ }
    }
  }
  return $n
}

$font = New-Object System.Drawing.Font('Arial', 22, [System.Drawing.FontStyle]::Bold)
$brush = [System.Drawing.Brushes]::Black

# ---------- 1) move/BAM sheet (12 rows stacked) ----------
$cw = 853; $ch = 1198
$cropX = 470; $cropY = 140; $cropW = 383; $cropH = 430
$mul = 1.5
$tw = [int]($cropW * $mul); $th = [int]($cropH * $mul)
$sheet = New-Object System.Drawing.Bitmap(($tw + 170), ($th * 12))
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.Clear([System.Drawing.Color]::White)
for ($i = 1; $i -le 12; $i++) {
  $p = Join-Path $dir ("action_{0:d2}.png" -f $i)
  $b = LoadBmp $p
  $c = CropScaled $b $cropX $cropY $cropW $cropH $mul
  $sg.DrawImage($c, 170, (($i - 1) * $th))
  $sg.DrawString(("card {0:d2}" -f $i), $font, $brush, 8, (($i - 1) * $th + 40))
  $c.Dispose(); $b.Dispose()
  $sg.DrawLine([System.Drawing.Pens]::Gray, 0, ($i * $th), ($tw + 170), ($i * $th))
}
$sg.Dispose()
$sheet.Save((Join-Path $out 'sheet_move.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

# ---------- 2) placement band sheet ----------
$pY = 780; $pH = 418
$pmul = 1.0
$pw = [int]($cw * $pmul); $ph = [int]($pH * $pmul)
$psheet = New-Object System.Drawing.Bitmap($pw, (($ph + 30) * 12))
$pg = [System.Drawing.Graphics]::FromImage($psheet)
$pg.Clear([System.Drawing.Color]::White)
for ($i = 1; $i -le 12; $i++) {
  $p = Join-Path $dir ("action_{0:d2}.png" -f $i)
  $b = LoadBmp $p
  $c = CropScaled $b 0 $pY $cw $pH $pmul
  $pg.DrawImage($c, 0, (($i - 1) * ($ph + 30) + 30))
  $pg.DrawString(("card {0:d2}" -f $i), $font, $brush, 8, (($i - 1) * ($ph + 30) + 2))
  $c.Dispose(); $b.Dispose()
}
$pg.Dispose()
$psheet.Save((Join-Path $out 'sheet_place.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$psheet.Dispose()

# ---------- 3) threat cards ----------
for ($i = 1; $i -le 6; $i++) {
  $p = Join-Path $dir ("threat_{0:d2}.png" -f $i)
  $b = LoadBmp $p
  $c = CropScaled $b 0 0 $b.Width $b.Height 1.0
  $c.Save((Join-Path $out ("threat_{0:d2}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png)
  $c.Dispose(); $b.Dispose()
}

# ---------- 4) pixel analysis of the placement band ----------
# frames (original px, derived from the 853x1198 card): left / middle / right
$frames = @(
  @{ n = 'left '; x0 = 60;  x1 = 300 },
  @{ n = 'mid  '; x0 = 320; x1 = 560 },
  @{ n = 'right'; x0 = 560; x1 = 820 }
)
Write-Host '=== placement pattern analysis (red=thug, blue=civ) ==='
for ($i = 1; $i -le 12; $i++) {
  $p = Join-Path $dir ("action_{0:d2}.png" -f $i)
  $b = LoadBmp $p
  $line = ("card {0:d2}: " -f $i)
  foreach ($f in $frames) {
    # coarse grid 1 cell = 8x8 px
    $gtw = [int](($f.x1 - $f.x0) / 8); $gth = [int](380 / 8)
    $red = New-Object 'bool[,]' $gtw, $gth
    $blu = New-Object 'bool[,]' $gtw, $gth
    for ($gy = 0; $gy -lt $gth; $gy++) {
      for ($gx = 0; $gx -lt $gtw; $gx++) {
        $px = $f.x0 + $gx * 8 + 4
        $py = 800 + $gy * 8 + 4
        $c = $b.GetPixel($px, $py)
        if ($c.R -gt 140 -and $c.G -lt 100 -and $c.B -lt 100) { $red[$gx, $gy] = $true }
        if ($c.B -gt 170 -and $c.R -lt 170 -and $c.G -gt 160) { $blu[$gx, $gy] = $true }
      }
    }
    $rc = Count-Blobs $red $gtw $gth
    $bc = Count-Blobs $blu $gtw $gth
    $line += ("{0}:T{1}/C{2}  " -f $f.n, $rc, $bc)
  }
  Write-Host $line
  $b.Dispose()
}
Write-Host ("crops -> {0}" -f $out)
