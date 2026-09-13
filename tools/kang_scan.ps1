# KANG: pixel-level scan of the token pattern band (ASCII output only).
# For each action card, scan the lower band, mark a coarse grid cell when it contains a
# red (thug) or blue (civ) icon pixel, then connected-component the grid: one blob = one icon.
# Prints per-card icon centroids so each icon can be assigned to one of the three boxes.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'MarvelUnitedGame\assets\cards\villains\kang'

function LoadBmp([string]$p) {
  $src = [System.Drawing.Image]::FromFile($p)
  $bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose()
  $src.Dispose(); return $bmp
}

# band actually containing the three tilted white boxes (verified with devtools\kang_crop.ps1 output)
$X0 = 70; $X1 = 805; $Y0 = 860; $Y1 = 1150
$step = 6
$gw = [int](($X1 - $X0) / $step); $gh = [int](($Y1 - $Y0) / $step)

function ScanCard([string]$path) {
  $b = LoadBmp $path
  $red = New-Object 'bool[,]' $gw, $gh
  $blu = New-Object 'bool[,]' $gw, $gh
  for ($gy = 0; $gy -lt $gh; $gy++) {
    for ($gx = 0; $gx -lt $gw; $gx++) {
      $hitR = $false; $hitB = $false
      for ($dy = 0; $dy -lt $step; $dy += 3) {
        for ($dx = 0; $dx -lt $step; $dx += 3) {
          $c = $b.GetPixel(($X0 + $gx * $step + $dx), ($Y0 + $gy * $step + $dy))
          if ($c.R -gt 150 -and $c.G -lt 110 -and $c.B -lt 110) { $hitR = $true }
          if ($c.B -gt 165 -and $c.R -lt 175 -and $c.G -gt 150 -and ($c.B - $c.R) -gt 30) { $hitB = $true }
        }
      }
      $red[$gx, $gy] = $hitR; $blu[$gx, $gy] = $hitB
    }
  }
  $b.Dispose()
  return @{ red = $red; blu = $blu }
}

function Blobs($grid, [int]$w, [int]$h) {
  $seen = New-Object 'bool[,]' $w, $h
  $out = @()
  for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
      if (-not $grid[$x, $y] -or $seen[$x, $y]) { continue }
      $stack = New-Object System.Collections.Stack
      $stack.Push(@($x, $y)); $seen[$x, $y] = $true
      $n = 0; $sx = 0; $sy = 0
      while ($stack.Count -gt 0) {
        $pt = $stack.Pop(); $cx = $pt[0]; $cy = $pt[1]; $n++; $sx += $cx; $sy += $cy
        foreach ($d in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1), @(1, 1), @(1, -1), @(-1, 1), @(-1, -1))) {
          $nx = $cx + $d[0]; $ny = $cy + $d[1]
          if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $w -or $ny -ge $h) { continue }
          if ($grid[$nx, $ny] -and -not $seen[$nx, $ny]) { $seen[$nx, $ny] = $true; $stack.Push(@($nx, $ny)) }
        }
      }
      if ($n -ge 8) {
        $px = [int]($X0 + ($sx / $n) * $step)
        $py = [int]($Y0 + ($sy / $n) * $step)
        $out += , @($px, $py, $n)
      }
    }
  }
  return $out
}

Write-Host ("band x={0}..{1} y={2}..{3} step={4} grid={5}x{6}" -f $X0, $X1, $Y0, $Y1, $step, $gw, $gh)
Write-Host 'card | thugN | civN | thug centroids | civ centroids'
for ($i = 1; $i -le 12; $i++) {
  $s = ScanCard (Join-Path $dir ("action_{0:d2}.png" -f $i))
  $rb = @(Blobs $s.red $gw $gh) | Sort-Object { $_[0] }
  $bb = @(Blobs $s.blu $gw $gh) | Sort-Object { $_[0] }
  $rs = ''; foreach ($o in $rb) { $rs += ('(' + $o[0] + ',' + $o[1] + ') ') }
  $bs = ''; foreach ($o in $bb) { $bs += ('(' + $o[0] + ',' + $o[1] + ') ') }
  Write-Host ("{0:d2} | {1} | {2} | {3}| {4}" -f $i, $rb.Count, $bb.Count, $rs, $bs)
}
