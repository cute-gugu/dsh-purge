#Requires -Version 5.1
<#
    dsh-purge 状态自检
      只看不改。退出码：0 = 一切正常；1 = 有问题（可修）；2 = 没装
    用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File check-dsh-purge.ps1
      ... -DshHome "D:\x" -Profile desktop
      ... -Fix     # 发现"登记在但文件缺失"时，顺手用 payload 重装一遍
#>
[CmdletBinding()]
param(
    [string]$DshHome = '',
    [string]$Profile = '',
    [switch]$Fix,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$script:problems = New-Object System.Collections.ArrayList
$script:notes = New-Object System.Collections.ArrayList

function Say($text) { Write-Host $text }
function Ok($t) { Write-Host "  [OK]    $t" -ForegroundColor Green }
function Bad($t) { Write-Host "  [问题]  $t" -ForegroundColor Red; [void]$script:problems.Add($t) }
function Note($t) { Write-Host "  [提示]  $t" -ForegroundColor Yellow; [void]$script:notes.Add($t) }
function Info($t) { Write-Host "  [..]    $t" -ForegroundColor Gray }

# ---------------------------------------------------------------- payload 版本
$payloadRoot = Join-Path $PSScriptRoot 'payload\dsh-purge'
$payloadVersion = $null
if (Test-Path -LiteralPath (Join-Path $payloadRoot 'package.json')) {
    $tmp = [System.IO.File]::ReadAllText((Join-Path $payloadRoot 'package.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $payloadVersion = [string]$tmp.version
}

Say ''
Say '  dsh-purge 状态自检'
Say '  ---------------------------------------------------'

# ---------------------------------------------------------------- DSH_HOME
if ([string]::IsNullOrWhiteSpace($DshHome)) {
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_HOME)) { $DshHome = $env:DSH_HOME }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
if ([string]::IsNullOrWhiteSpace($DshHome) -or -not (Test-Path -LiteralPath $DshHome)) {
    Bad "找不到 DSH_HOME：$DshHome"
    Say ''
    Say '  先把 DSH 打开一次，让它生成 .dsh 目录。'
    exit 2
}
$DshHome = [System.IO.Path]::GetFullPath($DshHome)
Ok "DSH_HOME = $DshHome"
if ($payloadVersion) { Info "本机 payload 版本 = $payloadVersion" }

$profilesDir = Join-Path $DshHome 'profiles'
if (-not (Test-Path -LiteralPath $profilesDir)) {
    Bad "没有 $profilesDir —— DSH 还没初始化过"
    exit 2
}
$candidates = @()
foreach ($dir in Get-ChildItem -LiteralPath $profilesDir -Directory) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName 'package.json')) { $candidates += $dir.Name }
}
if ($candidates.Count -eq 0) { Bad "$profilesDir 下没有带 package.json 的 profile"; exit 2 }

if ([string]::IsNullOrWhiteSpace($Profile)) {
    if ($candidates -contains 'desktop') { $Profile = 'desktop' } else { $Profile = $candidates[0] }
}
if (-not ($candidates -contains $Profile)) {
    Bad "profile '$Profile' 不存在（可选：$($candidates -join ', ')）"
    exit 2
}
$profileDir = Join-Path $profilesDir $Profile
Ok "profile = $Profile（共 $($candidates.Count) 个：$($candidates -join ', ')）"

# ---------------------------------------------------------------- DSH 是否在跑
$running = @()
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    if ($p.ProcessName -match '^(DSH|dsh)') { $running += "$($p.ProcessName)#$($p.Id)" }
}
if ($running.Count -gt 0) { Note "DSH 正在运行（$($running -join ', ')）—— 装/卸之后必须完全退出再开才生效" }
else { Ok 'DSH 当前没在运行（这样最稳）' }

# ---------------------------------------------------------------- profile.json
$profilePkgPath = Join-Path $profileDir 'package.json'
try {
    $rawText = [System.IO.File]::ReadAllText($profilePkgPath, [System.Text.Encoding]::UTF8)
    $profilePkg = $rawText | ConvertFrom-Json
}
catch {
    Bad "profile 的 package.json 读不了或不是合法 JSON：$($_.Exception.Message)"
    exit 2
}
Ok 'profile/package.json 可解析'

$depValue = $null
if ($profilePkg.PSObject.Properties.Name -contains 'dependencies') {
    $depValue = $profilePkg.dependencies.'dsh-purge'
}
$bundles = @()
if ($profilePkg.PSObject.Properties.Name -contains 'dsh' -and $profilePkg.dsh -and $profilePkg.dsh.profile) {
    $bundles = @($profilePkg.dsh.profile.bundles)
}

$registered = (-not [string]::IsNullOrWhiteSpace($depValue)) -and ($bundles -contains 'dsh-purge')
$targetDir = Join-Path $profileDir 'node_modules\dsh-purge'
$installedHere = Test-Path -LiteralPath (Join-Path $targetDir 'package.json')

if ([string]::IsNullOrWhiteSpace($depValue)) { Bad 'dependencies 里没有 dsh-purge（没登记）' }
else {
    Ok "dependencies.dsh-purge = $depValue"
    $specPath = $null
    if ($depValue -match '^(file|link):(.+)$') { $specPath = $matches[2] }
    elseif ($depValue -match '^[A-Za-z]:/') { $specPath = $depValue }
    if ($specPath) {
        $specPath = $specPath -replace '/', '\'
        if (Test-Path -LiteralPath $specPath) { Ok "依赖指向的目录存在：$specPath" }
        else { Bad "依赖指向的目录不存在：$specPath（改过路径或换过电脑，需修复）" }
    }
}
if ($bundles -contains 'dsh-purge') { Ok "bundles 里有 dsh-purge（共 $($bundles.Count) 项）" }
else { Bad 'dsh.profile.bundles 里没有 dsh-purge（装了也不会加载）' }

# ---------------------------------------------------------------- 文件本体
if ($installedHere) {
    $inst = [System.IO.File]::ReadAllText((Join-Path $targetDir 'package.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Ok "插件文件在位：版本 $($inst.version)"
    if ($payloadVersion -and ([string]$inst.version -ne $payloadVersion)) {
        Note "profile 里的版本（$($inst.version)）与 payload（$payloadVersion）不一致，可修复升级"
    }
    foreach ($need in @('lib\index.js', 'cordis.patch.yml', 'client.js')) {
        if (Test-Path -LiteralPath (Join-Path $targetDir $need)) { Ok "关键文件在：$need" }
        else { Bad "关键文件缺失：$need" }
    }
    if (Test-Path -LiteralPath (Join-Path $targetDir 'node_modules\yaml\package.json')) { Ok '依赖 yaml 在位' }
    else { Bad '缺 node_modules\yaml（宿主可能加载失败，需修复）' }

    # 与母本比对 package.json 是否同一版本内容
    $masterDir = $null
    if ($env:LOCALAPPDATA) { $masterDir = Join-Path $env:LOCALAPPDATA "dsh-purge\$($inst.version)" }
    if ($masterDir -and (Test-Path -LiteralPath (Join-Path $masterDir 'package.json'))) {
        $a = (Get-FileHash -LiteralPath (Join-Path $masterDir 'package.json') -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath (Join-Path $targetDir 'package.json') -Algorithm SHA256).Hash
        if ($a -eq $b) { Ok "与母本一致（$masterDir）" }
        else { Note "与母本 package.json 不一致（也许被手改过），可修复覆盖" }
    }
    else { Info '没找到母本副本（不影响使用，修复时会重新生成）' }
}
else {
    if ($registered) { Bad "登记表里有 dsh-purge，但文件不存在：$targetDir（需修复）" }
    else { Bad '没安装（profile 里没有 dsh-purge，也没有插件文件）' }
}

# ---------------------------------------------------------------- 旧插件残留
$legacy = @()
foreach ($old in @('dsh-purge-community', 'dsh-unrestricted')) {
    $hit = @()
    if ($profilePkg.PSObject.Properties.Name -contains 'dependencies' -and $profilePkg.dependencies.PSObject.Properties.Name -contains $old) { $hit += 'dependencies' }
    if ($bundles -contains $old) { $hit += 'bundles' }
    if (Test-Path -LiteralPath (Join-Path $profileDir "node_modules\$old")) { $hit += 'node_modules' }
    if ($hit.Count -gt 0) { $legacy += "$old($($hit -join '+'))" }
}
if ($legacy.Count -eq 0) { Ok '没有旧插件残留（dsh-purge-community / dsh-unrestricted）' }
else { Note "发现旧插件残留：$($legacy -join '，') —— 会和新插件抢同一条提示词，建议卸载/修复时清掉" }

# ---------------------------------------------------------------- 结论
Say ''
Say '  ---------------------------------------------------'
if ($script:problems.Count -eq 0) {
    if ($installedHere -and $registered) {
        Say '  结论：已安装且一切正常。' -ForegroundColor Green
        Say '        改过任何东西之后记得完全退出 DSH 再打开。' -ForegroundColor DarkGray
        exit 0
    }
    Say '  结论：状态异常但没查出具体问题，建议直接跑一次「一键安装/修复」。' -ForegroundColor Yellow
    exit 1
}
Say "  结论：发现 $($script:problems.Count) 个问题：" -ForegroundColor Red
foreach ($p in $script:problems) { Say "    - $p" -ForegroundColor Red }
if ($script:notes.Count -gt 0) {
    Say "  另有 $($script:notes.Count) 条提示。" -ForegroundColor Yellow
}

if ($Fix) {
    Say ''
    Say '  开始修复（用 payload 重装一遍）……' -ForegroundColor Cyan
    $installer = Join-Path $PSScriptRoot 'install-dsh-purge.ps1'
    if (-not (Test-Path -LiteralPath $installer)) {
        Say "  找不到 install-dsh-purge.ps1，无法自动修复。" -ForegroundColor Red
        exit 1
    }
    & $installer -DshHome $DshHome -Profile $Profile
    exit $LASTEXITCODE
}
Say ''
Say '  想修：回到控制台选 [1] 一键安装 / 修复。' -ForegroundColor DarkGray
exit 1
