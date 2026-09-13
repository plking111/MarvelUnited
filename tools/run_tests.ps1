# 测试运行器（3 分钟硬上限 + 卡死自动诊断）
# 用法：
#   pwsh -File devtools/run_tests.ps1                          # 跑 tests/ 下全部 .tscn
#   pwsh -File devtools/run_tests.ps1 -Tests docock_test,vulture_test
#
# 机制（两层，避免"傻等"）：
#   ① 进程内看门狗：Game 里内置 150 秒看门狗（只对 res://tests/ 生效），
#      卡死时打印 phase/最近日志并 quit(1) —— 卡死不再无限挂住。
#   ② 本脚本：逐个跑，记录耗时；出现"看门狗/卡死/无 PASS 且无 ==="或耗时 > 180 秒时，
#      立即自动检查：打印诊断线索 + 日志尾 + 独立跑一次 --import 抓 Parse Error。
# 注意：沙箱下 Start-Process 的重定向管道会被拒（EPERM），所以这里用同步调用 + Tee-Object 落盘。
param(
  [string[]]$Tests = @(),
  [int]$LimitSec = 180,
  # 总熔断：整轮跑超过这个秒数就停下并报告剩余（默认 180 秒 = 3 分钟）
  [int]$TotalLimitSec = 180,
  [switch]$IncludeLegacy
)
# 历史遗留测试（默认跳过；加 -IncludeLegacy 才跑）：
#   这 13 个是照"已废弃的 prompt_choice 弹窗 API"写的，弹窗层换成 prompt_action/hand/story 之后
#   它们会失败或卡死，但它们覆盖的卡牌效果目前【没有】其它测试接管（这是真实的覆盖缺口）。
#   集中登记在这里（而不是删掉、也不是散在 13 个文件里），方便随时看到欠债规模；
#   要消掉缺口就得把它们逐个改写到新 API —— 属于结构优化第 4 步。
$LegacyTests = @(
  # 结构优化第 4 步的成果：原来 13 个连旧 prompt_choice 的老测试，现在 9 个已回归日常全量
  # （combo / entangle / groot_attack_threat / ironeffect / jail_move_fill / korg_palace /
  #   tokenhold / wakanda_effect / waitinput）——靠的是 Events 里的「action→choice 测试兼容桥」。
  # 剩这 4 个仍在登记清单里：它们等的是别的弹窗家族（手牌/移动指示物/故事情节那类），
  # 兼容桥覆盖不到，需要逐个按新信号重写。
  'groot_draw_test', 'photonblast_test', 'rocket_gamora_deep_test', 'ronan_ko_fix_test'
)
# 只能双进程跑的测试（单进程跑必然假红 —— 全量跑时它一度被误当红）：
# 用 devtools\run_net_test.ps1 跑（主机/客户端两个进程互相对话）。
$DualProcessTests = @('net_lan_test')
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'MarvelUnitedGame'
$godot = Join-Path $PSScriptRoot 'godot\editor\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path $godot)) { Write-Host "找不到 Godot: $godot"; exit 2 }
$env:TEMP = $root
$env:TMP = $root
$logDir = Join-Path $root '_testlog'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$explicitTests = ($Tests.Count -gt 0)
if (-not $explicitTests) {
  $Tests = Get-ChildItem (Join-Path $proj 'tests') -Filter *.tscn | ForEach-Object { $_.BaseName } | Sort-Object
}
# 默认把历史遗留测试与双进程测试剔出去。
# 注意：显式用 -Tests 点名时必须照跑 —— 否则"想单独查某个遗留测试"会被静默跳过。
if (-not $explicitTests) {
  if (-not $IncludeLegacy) {
    $skipped = $Tests | Where-Object { $LegacyTests -contains $_ }
    if ($skipped.Count -gt 0) {
      Write-Host ("跳过历史遗留测试 {0} 个（-IncludeLegacy 可包含）：{1}" -f $skipped.Count, ($skipped -join ', '))
      $Tests = $Tests | Where-Object { $LegacyTests -notcontains $_ }
    }
  }
  $dual = $Tests | Where-Object { $DualProcessTests -contains $_ }
  if ($dual.Count -gt 0) {
    Write-Host ("跳过双进程测试 {0} 个（请用 devtools\run_net_test.ps1 跑）：{1}" -f $dual.Count, ($dual -join ', '))
    $Tests = $Tests | Where-Object { $DualProcessTests -notcontains $_ }
  }
}

$runStart = Get-Date
$breakerTripped = $false
$results = @()
foreach ($t in $Tests) {
  # ---- 总时长熔断：到点就停，避免一轮跑几分钟还不给结果 ----
  $elapsed = [math]::Round(((Get-Date) - $runStart).TotalSeconds, 1)
  if ($elapsed -ge $TotalLimitSec) {
    $notRun = $Tests[($Tests.IndexOf($t))..($Tests.Count - 1)]
    Write-Host ("⏱ 已熔断：整轮已跑 {0}s（上限 {1}s），下面 {2} 个测试本次未跑：{3}" -f $elapsed, $TotalLimitSec, $notRun.Count, ($notRun -join "", ""))
    $breakerTripped = $true
    break
  }
  $effLimit = [int][Math]::Min($LimitSec, [Math]::Max(5, $TotalLimitSec - [int]$elapsed))
  $log = Join-Path $logDir "$t.log"
  if (Test-Path $log) { Remove-Item $log -Force }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $godot --headless --path $proj "res://tests/$t.tscn" -- --test-timeout $effLimit *>&1 | Tee-Object -FilePath $log | Out-Null
  $sw.Stop()
  $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  $all = Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue
  # 不能只看行首 ^FAIL —— 有些测试把失败打印成 "=== XX TEST FAILED: [...] ==="，会被误判成 PASS
  # （曾因此把 thanos_bug_test 这种红了几轮的测试记成绿的）。
  # 必须 -CaseSensitive：否则 Godot 的 "ERROR: Failed to ..." 也会被算成失败。
  $pass = ($all | Select-String -Pattern '^PASS').Count
  $fail = ($all | Select-String -Pattern 'FAIL[:：]|FAILED' -CaseSensitive).Count
  $verdictLine = ($all | Select-String -Pattern '=== .*(PASSED|FAILED|OK)' | Select-Object -Last 1).Line
  $verdict = $verdictLine
  $verdictFailed = ($verdictLine -cmatch 'FAILED')
  $stuck = ($all | Select-String -Pattern '测试看门狗').Count -gt 0
  $bad = $stuck -or ($sec -gt $LimitSec) -or $fail -gt 0 -or $verdictFailed -or ((-not $verdict) -and $pass -eq 0)
  $status = if ($stuck -or $sec -gt $LimitSec) { 'STUCK' } elseif ($verdictFailed -or $fail -gt 0) { 'FAIL' } elseif ($verdict) { 'PASS' } else { 'NOVERDICT' }
  $results += [pscustomobject]@{ Test = $t; Status = $status; Sec = $sec; Pass = $pass; Fail = $fail }
  "{0,-24} {1,-10} {2,6}s  PASS={3} FAIL={4}" -f $t, $status, $sec, $pass, $fail
  if ($bad) {
    "   ---- 自动诊断（$t）----"
    $wd = $all | Select-String -Pattern '看门狗|卡死|Parse Error|SCRIPT ERROR|Invalid call|Nonexistent function|^FAIL' | Select-Object -First 10
    if ($wd) { $wd | ForEach-Object { "   " + $_.Line.Trim() } }
    $tailLines = $all | Select-Object -Last 12
    if ($tailLines) { "   ---- 日志尾 ----"; $tailLines | ForEach-Object { "   " + $_ } }
    # 独立编译检查：编译错误是卡死第一大原因
    $imp = Join-Path $logDir 'import_check.log'
    & $godot --headless --path $proj --import *>&1 | Out-File -Encoding UTF8 $imp
    $pe = Get-Content $imp -Encoding UTF8 -ErrorAction SilentlyContinue | Select-String -Pattern 'Parse Error' | Select-Object -First 6
    if ($pe) { "   ---- 编译错误（多半就是它）----"; $pe | ForEach-Object { "   " + $_.Line.Trim() } }
    "   ----------------------"
  }
}
""
"==== 汇总 ===="
$results | Format-Table -AutoSize
$badlist = ($results | Where-Object { $_.Status -in @('STUCK', 'FAIL') } | ForEach-Object { $_.Test }) -join ', '
"异常项: $badlist"
if ($badlist -ne '') { exit 1 } else { exit 0 }
