# 发布前验收检查（只读，不改任何东西）
# 用法：powershell -File devtools\验收检查.ps1
#
# 检查项：
#   ① data\ 与 build\data\ 的 JSON 是否逐一相同（外置数据必须同步）
#   ② 反派/英雄数量，以及 db.gd 里的 assert 数字是否与实际一致（防止漏改断言）
#   ③ Setup.gd 里 6 处硬编码反派 id 列表是否都登记了当前全部反派
#   ④ VillainRules.gd 的 IDS 是否与 villains.json 的键集合一致（防止漏注册）
#   ⑤ build\MarvelUnited.pck 是否比所有源码/数据新（防止把旧构建打进安装包）
#   ⑥ 安装包是否存在、时间戳与体积
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'MarvelUnitedGame'
if (-not (Test-Path $proj)) { $proj = $root }
$fail = 0
function Say($ok, $msg) {
  if ($ok) { Write-Host ('  [OK]   ' + $msg) } else { Write-Host ('  [FAIL] ' + $msg); $script:fail++ }
}

# ① 外置数据同步
Write-Host '① data\ 与 build\data\ 一致性'
$dataDir = Join-Path $proj 'data'
$buildData = Join-Path $proj 'build\data'
if (Test-Path $buildData) {
  foreach ($f in Get-ChildItem $dataDir -Filter '*.json') {
    $b = Join-Path $buildData $f.Name
    if (-not (Test-Path $b)) { Say $false ($f.Name + ' 在 build\data 里缺失'); continue }
    $h1 = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    $h2 = (Get-FileHash $b -Algorithm SHA256).Hash
    Say ($h1 -eq $h2) ($f.Name + ' SHA256 ' + $(if ($h1 -eq $h2) { '相同' } else { '不同！' }))
  }
} else { Say $false 'build\data 目录不存在（还没导出过？）' }

# ② 数量与断言
Write-Host '② 数量与 db.gd 断言'
$vjson = [System.IO.File]::ReadAllText((Join-Path $dataDir 'villains.json'), [System.Text.Encoding]::UTF8)
$hjson = [System.IO.File]::ReadAllText((Join-Path $dataDir 'heroes.json'), [System.Text.Encoding]::UTF8)
$vcount = ([regex]::Matches($vjson, '"name_en"')).Count
$hcount = ([regex]::Matches($hjson, '"name_en"')).Count
$vidKeys = [regex]::Matches($vjson, '(?m)^    "([a-z0-9_]+)":\s*\{') | ForEach-Object { $_.Groups[1].Value }
Write-Host ('  反派 = ' + $vcount + '，英雄 = ' + $hcount)
$db = [System.IO.File]::ReadAllText((Join-Path $proj 'src\autoload\db.gd'), [System.Text.Encoding]::UTF8)
$m = [regex]::Match($db, 'villains\.size\(\)\s*==\s*(\d+)')
Say ($m.Success) 'db.gd 里有 villains.size() 断言'
if ($m.Success) { Say ([int]$m.Groups[1].Value -eq $vcount) ('db.gd 断言 ' + $m.Groups[1].Value + ' 与实际反派数 ' + $vcount + ' 一致') }

# ③ Setup.gd 六处 id 列表
Write-Host '③ Setup.gd 反派 id 登记'
$setup = [System.IO.File]::ReadAllLines((Join-Path $proj 'src\ui\Setup.gd'), [System.Text.Encoding]::UTF8)
$checked = 0
# rest_ids 那行按语义就是"除无限战争反派外的全部"，那 4 个缺席属正常
$restExcept = @('thanos', 'proxima', 'cull', 'ebony')
foreach ($i in 0..($setup.Count - 1)) {
  if ($setup[$i] -match '^\s*(const VILLAIN_SORT|const VILLAIN_EXP)' -or $setup[$i] -match '^\s*(for vid in \[|var all_ids: Array = \[|var rest_ids: Array = \[)') {
    $present = @($vidKeys | Where-Object { $setup[$i].Contains('"' + $_ + '"') })
    if ($present.Count -eq 0) { continue }
    $checked++
    $expect = $vidKeys
    if ($setup[$i].Contains('rest_ids')) { $expect = @($vidKeys | Where-Object { $restExcept -notcontains $_ }) }
    $missing = @($expect | Where-Object { $present -notcontains $_ })
    Say ($missing.Count -eq 0) ('第 ' + ($i + 1) + ' 行（登记 ' + $present.Count + ' 个）：' + $(if ($missing.Count -eq 0) { '完整' } else { '缺 ' + ($missing -join ',') }))
  }
}
Say ($checked -ge 4) ('共检查到 ' + $checked + ' 处反派 id 列表（预期 ≥4）')
# ④ VillainRules.IDS 与数据键集合
Write-Host '④ VillainRules.IDS 与 villains.json 键集合'
$vr = [System.IO.File]::ReadAllText((Join-Path $proj 'src\rules\VillainRules.gd'), [System.Text.Encoding]::UTF8)
$idsMatch = [regex]::Match($vr, 'const IDS\s*:=\s*\[(.*?)\]')
if ($idsMatch.Success) {
  $ids = [regex]::Matches($idsMatch.Groups[1].Value, '"([a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value }
  $miss = @($vidKeys | Where-Object { $ids -notcontains $_ })
  $extra = @($ids | Where-Object { $vidKeys -notcontains $_ })
  Say ($miss.Count -eq 0) ('IDS 缺：' + $(if ($miss.Count -eq 0) { '无' } else { $miss -join ',' }))
  Say ($extra.Count -eq 0) ('IDS 多出（数据里没有）：' + $(if ($extra.Count -eq 0) { '无' } else { $extra -join ',' }))
  Write-Host ('  IDS 共 ' + $ids.Count + ' 个，数据共 ' + $vidKeys.Count + ' 个')
} else { Say $false '没找到 VillainRules.IDS 定义' }

# ⑤ pck 是否最新
Write-Host '⑤ 构建产物时间戳'
$pck = Join-Path $proj 'build\MarvelUnited.pck'
$exe = Join-Path $proj 'build\MarvelUnited.exe'
if ((Test-Path $pck) -and (Test-Path $exe)) {
  $pckTime = (Get-Item $pck).LastWriteTime
  # 只算真正影响包内容的构建输入（tests/ 改了不影响 pck）
  $newest = Get-ChildItem (Join-Path $proj 'src'), (Join-Path $proj 'data'), (Join-Path $proj 'assets'), (Join-Path $proj 'project.godot') -Recurse -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Say ($newest.LastWriteTime -le $pckTime) ('pck ' + $pckTime.ToString('MM-dd HH:mm:ss') + ' ≥ 最新源码 ' + $newest.Name + ' ' + $newest.LastWriteTime.ToString('MM-dd HH:mm:ss'))
  Write-Host ('  pck = ' + [int]((Get-Item $pck).Length / 1MB) + ' MB，exe = ' + [int]((Get-Item $exe).Length / 1MB) + ' MB')
} else { Say $false '缺少 build\MarvelUnited.pck 或 exe' }

# ⑥ 安装包
Write-Host '⑥ 安装包'
$iss = Join-Path $root 'installer.iss'
if (Test-Path $iss) {
  $issText = [System.IO.File]::ReadAllText($iss, [System.Text.Encoding]::UTF8)
  $ver = ([regex]::Match($issText, '#define MyAppVersion "([^"]*)"')).Groups[1].Value
  $outDir = ([regex]::Match($issText, 'OutputDir=([^\r\n]*)')).Groups[1].Value
  $outBase = ([regex]::Match($issText, 'OutputBaseFilename=([^\r\n]*)')).Groups[1].Value
  $inst = Join-Path $outDir ($outBase + '.exe')
  if (Test-Path $inst) {
    $o = Get-Item $inst
    Write-Host ('  版本 v' + $ver + ' → ' + $o.Name + '  ' + [int]($o.Length / 1MB) + ' MB  ' + $o.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    if (Test-Path $pck) { Say ($o.LastWriteTime -ge (Get-Item $pck).LastWriteTime) '安装包比 pck 新' }
  } else { Say $false ('还没生成安装包：' + $inst) }
} else { Say $false '找不到 installer.iss' }

Write-Host ''
if ($fail -eq 0) { Write-Host '✅ 验收检查全部通过' } else { Write-Host ('❌ 有 ' + $fail + ' 项未通过') }
exit $fail
