# 把源码提交到本地 git 仓库（仓库根 = MarvelUnitedGame\），并打印推送命令
# 用法：
#   powershell -File devtools\上传GitHub.ps1                     # 用 installer.iss 里的版本号当提交说明
#   powershell -File devtools\上传GitHub.ps1 -Message "自定义提交说明"
#   powershell -File devtools\上传GitHub.ps1 -Push                # 直接推送（需要本机已有 GitHub 凭据）
#
# 说明：本脚本只做「同步文档/脚本 → git add → commit」，远端推送默认交给你手动执行，
#       因为沙箱/CI 环境常常拿不到 GitHub 凭据（表现为 schannel: SEC_E_NO_CREDENTIALS）。
param(
  [string]$Message = '',
  [switch]$Push
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$root = Split-Path $PSScriptRoot -Parent
$repo = Join-Path $root 'MarvelUnitedGame'
if (-not (Test-Path (Join-Path $repo '.git'))) { $repo = $root }   # 兼容脚本放在工程内 tools\ 的情况
if (-not (Test-Path (Join-Path $repo '.git'))) { Write-Host '找不到 git 仓库（应在 MarvelUnitedGame\ 下）'; exit 2 }
$workspace = Split-Path $repo -Parent

# ① 把工作区里的开发脚本与文档同步进仓库，让源码自洽
$toolsSrc = Join-Path $workspace 'devtools'
$toolsDst = Join-Path $repo 'tools'
$docsDst = Join-Path $repo 'docs'
if (Test-Path $toolsSrc) {
  if (-not (Test-Path $toolsDst)) { New-Item -ItemType Directory -Path $toolsDst | Out-Null }
  Get-ChildItem $toolsSrc -File -Filter '*.ps1' | ForEach-Object { Copy-Item $_.FullName $toolsDst -Force }
  Write-Host '已同步 devtools\*.ps1 → 仓库 tools\'
}
if (-not (Test-Path $docsDst)) { New-Item -ItemType Directory -Path $docsDst | Out-Null }
Get-ChildItem $workspace -File -Filter '*.md' |
  Where-Object { $_.Name -match '交接|项目进度备忘|已确认规则' } |
  ForEach-Object { Copy-Item $_.FullName $docsDst -Force }
$issSrc = Join-Path $workspace 'installer.iss'
if (Test-Path $issSrc) { Copy-Item $issSrc (Join-Path $toolsDst 'installer.iss') -Force }
Write-Host '已同步交接文档 / installer.iss → 仓库'

# ② 提交
if ($Message -eq '') {
  $iss = Join-Path $workspace 'installer.iss'
  $ver = 'v?'
  if (Test-Path $iss) { $ver = 'v' + ([regex]::Match([System.IO.File]::ReadAllText($iss, [System.Text.Encoding]::UTF8), '#define MyAppVersion "([^"]*)"')).Groups[1].Value }
  $Message = $ver + '：新增第一季众筹反派（泽莫男爵 / 摩多克 / 康 / 犀牛人）与第一季众筹英雄三批，修复灭霸 BAM 范围等多项问题'
}
Push-Location $repo
$pending = & git status --porcelain
if (-not $pending) { Write-Host '没有需要提交的改动'; Pop-Location; exit 0 }
& git add -A
$staged = & git status --porcelain
Write-Host ('暂存改动 ' + ($staged | Measure-Object).Count + ' 项：')
$staged | Group-Object { $_.Substring(0, 2) } | ForEach-Object { Write-Host ('  ' + $_.Name.Trim() + ' → ' + $_.Count) }
& git commit -m $Message | ForEach-Object { Write-Host ('  ' + $_) }
$newCommit = & git log --oneline -1
Write-Host ('最新提交：' + $newCommit)

if ($Push) {
  Write-Host '开始推送…'
  & git push origin main
  Write-Host ('推送退出码 = ' + $LASTEXITCODE)
} else {
  Write-Host ''
  Write-Host '下一步（在你自己能访问 GitHub 的终端里执行）：'
  Write-Host ('  cd "' + $repo + '"')
  Write-Host '  git push origin main'
  Write-Host '如果提示要身份验证：用 GitHub 的 Personal Access Token 当密码，或改用 SSH 远端。'
}
Pop-Location
