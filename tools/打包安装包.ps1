# 打包 Windows 安装包（Inno Setup）
# 用法：
#   powershell -File devtools\打包安装包.ps1                 # 用 installer.iss 里现有的版本号
#   powershell -File devtools\打包安装包.ps1 -Version 3.11    # 指定版本号（同时改写 installer.iss）
#
# 做三件事：
#   ① 校验 build\ 里的 exe/pck/data 是否比源码新（防止把旧构建打进安装包）
#   ② 调用 Inno Setup 的 ISCC.exe 编译 installer.iss
#   ③ 核对产物时间戳与体积
param(
  [string]$Version = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'MarvelUnitedGame'
if (-not (Test-Path $proj)) { $proj = $root }
$build = Join-Path $proj 'build'

$iss = Join-Path $root 'installer.iss'
if (-not (Test-Path $iss)) { $iss = Join-Path (Split-Path $root -Parent) 'installer.iss' }
if (-not (Test-Path $iss)) { Write-Host '找不到 installer.iss'; exit 2 }

# ① 校验构建比源码新
$exe = Join-Path $build 'MarvelUnited.exe'
$pck = Join-Path $build 'MarvelUnited.pck'
if (-not (Test-Path $exe)) { Write-Host ('缺少构建产物: ' + $exe + '（先导出一次）'); exit 2 }
if (-not (Test-Path $pck)) { Write-Host ('缺少构建产物: ' + $pck + '（先导出一次）'); exit 2 }
$pckTime = (Get-Item $pck).LastWriteTime
$srcNewest = Get-ChildItem (Join-Path $proj 'src'), (Join-Path $proj 'data') -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($srcNewest -and $srcNewest.LastWriteTime -gt $pckTime) {
  Write-Host ('警告：源码比 pck 新 —— ' + $srcNewest.Name + '（' + $srcNewest.LastWriteTime.ToString('MM-dd HH:mm:ss') + '）> pck（' + $pckTime.ToString('MM-dd HH:mm:ss') + '），请先重新导出，否则安装包里是旧内容')
  exit 3
}
$msg = '构建时间戳 OK：pck = ' + $pckTime.ToString('MM-dd HH:mm:ss') + '，最新源码 = ' + $srcNewest.LastWriteTime.ToString('MM-dd HH:mm:ss')
Write-Host $msg

# ② 需要时改写版本号
$issText = [System.IO.File]::ReadAllText($iss, [System.Text.Encoding]::UTF8)
if ($Version -ne '') {
  $issText = [regex]::Replace($issText, '#define MyAppVersion "[^"]*"', ('#define MyAppVersion "' + $Version + '"'))
  $issText = [regex]::Replace($issText, 'OutputBaseFilename=[^\r\n]*', ('OutputBaseFilename=漫威联合安装程序_v' + $Version))
  [System.IO.File]::WriteAllText($iss, $issText, (New-Object System.Text.UTF8Encoding $true))
  Write-Host ('已把 installer.iss 的版本号改成 ' + $Version)
}
$ver = ([regex]::Match($issText, '#define MyAppVersion "([^"]*)"')).Groups[1].Value
$outBase = ([regex]::Match($issText, 'OutputBaseFilename=([^\r\n]*)')).Groups[1].Value
$outDir = ([regex]::Match($issText, 'OutputDir=([^\r\n]*)')).Groups[1].Value

# ③ 找 ISCC.exe：环境变量 → 常见路径 → 工作区旁边的 Inno Setup 7
$iscc = ''
if ($env:ISCC_BIN) { $iscc = $env:ISCC_BIN }
if ($iscc -eq '' -or -not (Test-Path $iscc)) {
  $cands = @(
    'C:\Program Files (x86)\Inno Setup 7\ISCC.exe',
    'C:\Program Files\Inno Setup 7\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    (Join-Path (Split-Path $root -Parent) 'Inno Setup 7\ISCC.exe')
  )
  foreach ($c in $cands) { if (Test-Path $c) { $iscc = $c; break } }
}
if ($iscc -eq '' -or -not (Test-Path $iscc)) { Write-Host '找不到 ISCC.exe（设 ISCC_BIN 环境变量指向它）'; exit 2 }
Write-Host ('用编译器: ' + $iscc)
Write-Host ('版本号: ' + $ver + ' → 产物名: ' + $outBase + '.exe')

# ④ 编译
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $iscc $iss
$code = $LASTEXITCODE
$sw.Stop()
if ($code -ne 0) { Write-Host ('ISCC 失败，退出码 ' + $code); exit $code }

# 记录本次打包用的 pck 指纹（验收脚本据此判断安装包内容是否与当前 pck 一致）
$pckHash = (Get-FileHash $pck -Algorithm SHA256).Hash
$recPath = Join-Path $build '_打包记录.txt'
[System.IO.File]::WriteAllText($recPath, ($pckHash + '  ' + [string](Get-Item $pck).Length), (New-Object System.Text.UTF8Encoding $false))
Write-Host ('已记录 pck 指纹: ' + $pckHash.Substring(0,16) + '... → ' + $recPath)
$outFile = Join-Path $outDir ($outBase + '.exe')
if (Test-Path $outFile) {
  $o = Get-Item $outFile
  $done = '安装包已生成：' + $o.FullName + '  ' + [string][int]($o.Length / 1MB) + ' MB  ' + $o.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '（用时 ' + [string][int]$sw.Elapsed.TotalSeconds + ' 秒）'
  Write-Host $done
} else {
  Write-Host ('没找到产物: ' + $outFile)
  exit 4
}
