# MODOK: pixel-level detection of BAM! burst, effect box, and pattern frames (ASCII only)
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\modok'

function LoadBmp([string]$p) {
  $src = [System.Drawing.Image]::FromFile($p)
  $bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose()
  $src.Dispose(); return $bmp
}

function BlobCount($grid, [int]$w, [int]$h) {
  $seen = New-Object 'bool[,]' $w, $h
  $n = 0
  for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
      if (-not $grid[$x, $y] -or $seen[$x, $y]) { continue }
      $stack = New-Object System.Collections.Stack
      $stack.Push(@($x, $y)); $seen[$x, $y] = $true; $size = 0
      while ($stack.Count -gt 0) {
        $pt = $stack.Pop(); $cx = $pt[0]; $cy = $pt[1]; $size++
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
function Ranges($cols) {
  if ($cols.Count -eq 0) { return '-' }
  $out = @(); $start = $cols[0]; $prev = $cols[0]
  for ($k = 1; $k -lt $cols.Count; $k++) { if ($cols[$k] - $prev -gt 2) { $out += ("{0}-{1}" -f $start, $prev); $start = $cols[$k] }; $prev = $cols[$k] }
  $out += ("{0}-{1}" -f $start, $prev)
  return ($out -join ',')
}

Write-Host 'card | BAMpx(x460-760,y360-560) | whiteFramePx(y700-1150) | textBoxPx(x60-800,y740-1190) | redBlobs | blueBlobs | frameXclusters'
for ($i = 1; $i -le 12; $i++) {
  $b = LoadBmp (Join-Path $dir ("action_{0:d2}.png" -f $i))
  $bam = 0; $white = 0; $txt = 0
  for ($y = 360; $y -lt 560; $y += 2) {
    for ($x = 460; $x -lt 760; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.R -gt 90 -and $c.G -lt 70 -and $c.B -lt 70) { $bam++ }
    }
  }
  for ($y = 700; $y -lt 1150; $y += 2) {
    for ($x = 0; $x -lt 853; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.R -gt 235 -and $c.G -gt 235 -and $c.B -gt 235) { $white++ }
    }
  }
  # effect text box: light gray (~0xE8) rectangle with dark text, top-left region of the lower band
  for ($y = 740; $y -lt 1190; $y += 2) {
    for ($x = 60; $x -lt 800; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.R -gt 210 -and $c.R -lt 245 -and [math]::Abs($c.R - $c.G) -lt 8 -and [math]::Abs($c.G - $c.B) -lt 8) { $txt++ }
    }
  }
  # icon blobs on a coarse grid over y 850..1150
  $gw = 107; $gh = 38
  $red = New-Object 'bool[,]' $gw, $gh
  $blu = New-Object 'bool[,]' $gw, $gh
  for ($gy = 0; $gy -lt $gh; $gy++) {
    for ($gx = 0; $gx -lt $gw; $gx++) {
      $c = $b.GetPixel(($gx * 8 + 4), (850 + $gy * 8 + 4))
      if ($c.R -gt 140 -and $c.G -lt 100 -and $c.B -lt 100) { $red[$gx, $gy] = $true }
      if ($c.B -gt 170 -and $c.R -lt 170 -and $c.G -gt 160) { $blu[$gx, $gy] = $true }
    }
  }
  $colsR = @(); for ($gx = 0; $gx -lt $gw; $gx++) { $s = 0; for ($gy = 0; $gy -lt $gh; $gy++) { if ($red[$gx, $gy]) { $s++ } }; if ($s -gt 0) { $colsR += $gx } }
  $colsB = @(); for ($gx = 0; $gx -lt $gw; $gx++) { $s = 0; for ($gy = 0; $gy -lt $gh; $gy++) { if ($blu[$gx, $gy]) { $s++ } }; if ($s -gt 0) { $colsB += $gx } }
  function Ranges($cols) {
    if ($cols.Count -eq 0) { return '-' }
    $out = @(); $start = $cols[0]; $prev = $cols[0]
    for ($k = 1; $k -lt $cols.Count; $k++) { if ($cols[$k] - $prev -gt 2) { $out += ("{0}-{1}" -f $start, $prev); $start = $cols[$k] }; $prev = $cols[$k] }
    $out += ("{0}-{1}" -f $start, $prev)
    return ($out -join ',')
  }
  Write-Host ("{0:d2} | {1,6} | {2,6} | {3,6} | {4} | {5} | R[{6}] B[{7}]" -f $i, $bam, $white, $txt, (BlobCount $red $gw $gh), (BlobCount $blu $gw $gh), (Ranges $colsR), (Ranges $colsB))
  $b.Dispose()
}
