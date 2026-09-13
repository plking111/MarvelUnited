# 局域网联机端到端测试：同一台机上跑两个进程（主机 + 客户端），校验两个日志。
# 用法：& devtools\run_net_test.ps1
$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'MarvelUnitedGame'
$godot = Join-Path $PSScriptRoot 'godot\editor\Godot_v4.7.2-stable_win64.exe'
$env:TEMP = $root
$env:TMP = $root
$out = Join-Path $root '_testlog\net'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

# 清掉可能占着 27015 端口的残留进程
Get-Process Godot_v4.7.2-stable_win64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$scene = 'res://tests/net_lan_test.tscn'
$hlog = Join-Path $out 'host.log'
$clog = Join-Path $out 'client.log'

$hostProc = Start-Process -FilePath $godot -PassThru -NoNewWindow -ArgumentList @(
  '--headless', '--path', $proj, $scene, '--log-file', $hlog, '--', 'host')
Start-Sleep -Milliseconds 1800
$cliProc = Start-Process -FilePath $godot -PassThru -NoNewWindow -ArgumentList @(
  '--headless', '--path', $proj, $scene, '--log-file', $clog, '--', 'client')

$hostProc.WaitForExit(90000) | Out-Null
$cliProc.WaitForExit(90000) | Out-Null
if (-not $hostProc.HasExited) { try { $hostProc.Kill() } catch {} }
if (-not $cliProc.HasExited) { try { $cliProc.Kill() } catch {} }

foreach ($pair in @(@($hlog, '主机'), @($clog, '客户端'))) {
  $log = $pair[0]
  $who = $pair[1]
  "---- $who ----"
  if (Test-Path $log) {
    Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^(PASS|FAIL):|^===' } | ForEach-Object { "  $_" }
  } else {
    "  （没有日志，进程可能没起来）"
  }
}
$pf = 0
$ff = 0
foreach ($log in @($hlog, $clog)) {
  if (Test-Path $log) {
    $pf += (Get-Content $log -Encoding UTF8 | Select-String -Pattern '^PASS' -CaseSensitive).Count
    $ff += (Get-Content $log -Encoding UTF8 | Select-String -Pattern 'FAIL[:：]|FAILED' -CaseSensitive).Count
  }
}
""
"==== 汇总：PASS=$pf FAIL=$ff ===="
if ($ff -gt 0) { exit 1 } else { exit 0 }
