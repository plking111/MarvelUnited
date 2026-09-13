# RHINO card pixel scanner (ASCII only, Windows PowerShell 5.1 safe)
# Verifies: BAM! starburst presence per action card, placement-box icon kinds/counts,
# threat-card heroic star frames / BAM / HP icon fingerprints.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\rhino'

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
      $stack.Push(@($x, $y)); $seen[$x, $y] = $true
      while ($stack.Count -gt 0) {
        $pt = $stack.Pop(); $cx = $pt[0]; $cy = $pt[1]
        foreach ($d in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
          $nx = $cx + $d[0]; $ny = $cy + $d[1]
          if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $w -or $ny -ge $h) { continue }
          if ($grid[$nx, $ny] -and -not $seen[$nx, $ny]) { $seen[$nx, $ny] = $true; $stack.Push(@($nx, $ny)) }
        }
      }
      $n++
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

Write-Host '=== ACTION CARDS (853x1198) ==='
Write-Host 'card | BAMpx(x450-800,y500-780) | redBlobs | blueBlobs | iconColsR | iconColsB'
for ($i = 1; $i -le 12; $i++) {
  $b = LoadBmp (Join-Path $dir ("action_{0:d2}.png" -f $i))
  $bam = 0
  for ($y = 500; $y -lt 780; $y += 2) {
    for ($x = 450; $x -lt 800; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.R -gt 90 -and $c.G -lt 70 -and $c.B -lt 70) { $bam++ }
    }
  }
  # placement band: y 800..1130, coarse 8px grid over full width
  $gw = 107; $gh = 41
  $red = New-Object 'bool[,]' $gw, $gh
  $blu = New-Object 'bool[,]' $gw, $gh
  for ($gy = 0; $gy -lt $gh; $gy++) {
    for ($gx = 0; $gx -lt $gw; $gx++) {
      $c = $b.GetPixel(($gx * 8 + 4), (800 + $gy * 8 + 4))
      if ($c.R -gt 140 -and $c.G -lt 100 -and $c.B -lt 100) { $red[$gx, $gy] = $true }
      if ($c.B -gt 170 -and $c.R -lt 170 -and $c.G -gt 160) { $blu[$gx, $gy] = $true }
    }
  }
  $colsR = @(); for ($gx = 0; $gx -lt $gw; $gx++) { for ($gy = 0; $gy -lt $gh; $gy++) { if ($red[$gx, $gy]) { $colsR += $gx; break } } }
  $colsB = @(); for ($gx = 0; $gx -lt $gw; $gx++) { for ($gy = 0; $gy -lt $gh; $gy++) { if ($blu[$gx, $gy]) { $colsB += $gx; break } } }
  Write-Host ("{0:d2} | {1,6} | {2} | {3} | R[{4}] B[{5}]" -f $i, $bam, (BlobCount $red $gw $gh), (BlobCount $blu $gw $gh), (Ranges $colsR), (Ranges $colsB))
  $b.Dispose()
}

Write-Host ''
Write-Host '=== THREAT CARDS (1198x853) ==='
Write-Host 'card | BAMred(x520-1150,y180-560) | purpleBadge(x60-400,y180-560) | blackPx(x60-200,y540-830) | whiteFramePx(y540-830) | frameBlobs | frameCols'
for ($i = 1; $i -le 6; $i++) {
  $b = LoadBmp (Join-Path $dir ("threat_{0:d2}.png" -f $i))
  $bam = 0; $badge = 0; $black = 0; $white = 0
  for ($y = 180; $y -lt 560; $y += 2) {
    for ($x = 520; $x -lt 1150; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.R -gt 90 -and $c.G -lt 70 -and $c.B -lt 70) { $bam++ }
    }
  }
  for ($y = 180; $y -lt 560; $y += 2) {
    for ($x = 60; $x -lt 400; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.B -gt 120 -and $c.R -gt 90 -and $c.R -lt 190 -and $c.G -lt 110) { $badge++ }
    }
  }
  for ($y = 540; $y -lt 830; $y += 2) {
    for ($x = 60; $x -lt 200; $x += 2) {
      $c = $b.GetPixel($x, $y)
      if ($c.R -lt 40 -and $c.G -lt 40 -and $c.B -lt 40) { $black++ }
    }
  }
  $gw = 149; $gh = 36
  $wh = New-Object 'bool[,]' $gw, $gh
  for ($gy = 0; $gy -lt $gh; $gy++) {
    for ($gx = 0; $gx -lt $gw; $gx++) {
      $c = $b.GetPixel(($gx * 8 + 4), (540 + $gy * 8 + 4))
      if ($c.R -gt 235 -and $c.G -gt 235 -and $c.B -gt 235) { $wh[$gx, $gy] = $true }
    }
  }
  $colsW = @()
  for ($gx = 0; $gx -lt $gw; $gx++) {
    $s = 0; for ($gy = 0; $gy -lt $gh; $gy++) { if ($wh[$gx, $gy]) { $s++ } }
    if ($s -ge 3) { $white += $s; $colsW += $gx }
  }
  Write-Host ("{0:d2} | {1,6} | {2,6} | {3,6} | {4,6} | {5} | {6}" -f $i, $bam, $badge, $black, $white, (BlobCount $wh $gw $gh), (Ranges $colsW))
  $b.Dispose()
}
