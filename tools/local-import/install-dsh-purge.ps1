#Requires -Version 5.1
<#
    dsh-purge 本地一键导入（离线）
    ---------------------------------------------------------------
    做三件事，全部离线、不联网、不需要 npm / Node：
      1) 把 payload\dsh-purge 复制到 %LOCALAPPDATA%\dsh-purge\<版本>
      2) 再复制一份到 <DSH_HOME>\profiles\<profile>\node_modules\dsh-purge
      3) 在 profile 的 package.json 里登记依赖与 dsh.profile.bundles

    用法：
      双击 一键导入.cmd
      或 powershell -NoProfile -ExecutionPolicy Bypass -File install-dsh-purge.ps1
      预览不写入：  ... -File install-dsh-purge.ps1 -DryRun
      指定 DSH_HOME / profile：  -DshHome "D:\myhome" -Profile desktop
      保留旧的社区版/独立版：  -RemoveLegacy:$false
#>
[CmdletBinding()]
param(
    [string]$DshHome = '',
    [string]$Profile = '',
    [bool]$RemoveLegacy = $true,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Head($text) {
    Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan
}
function Write-Ok($text) { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Info($text) { Write-Host "  [..]   $text" -ForegroundColor Gray }
function Write-Warn2($text) { Write-Host "  [警告] $text" -ForegroundColor Yellow }
function Write-Err2($text) { Write-Host "  [失败] $text" -ForegroundColor Red }

function Fail($text) {
    Write-Err2 $text
    Write-Host ''
    Write-Host '导入未完成。把上面这段截图给发你插件的人即可。' -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------- 0. payload
Write-Host ''
Write-Host '  dsh-purge 本地一键导入 / offline installer' -ForegroundColor White
Write-Host '  ---------------------------------------------------' -ForegroundColor DarkGray

$payloadRoot = Join-Path $PSScriptRoot 'payload\dsh-purge'
if (-not (Test-Path -LiteralPath $payloadRoot)) {
    Fail "找不到插件本体：$payloadRoot（整个文件夹要一起解压，不要只解压 .cmd）"
}
$payloadPkgPath = Join-Path $payloadRoot 'package.json'
if (-not (Test-Path -LiteralPath $payloadPkgPath)) { Fail "payload 里缺少 package.json：$payloadPkgPath" }
$payloadPkg = [System.IO.File]::ReadAllText($payloadPkgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$version = [string]$payloadPkg.version
if ([string]::IsNullOrWhiteSpace($version)) { Fail 'payload\package.json 里没有 version' }
Write-Ok "插件本体：$($payloadPkg.name) $version"

# ---------------------------------------------------------------- 1. DSH_HOME
Write-Head '1/6 定位 DSH'
if ([string]::IsNullOrWhiteSpace($DshHome)) {
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_HOME)) { $DshHome = $env:DSH_HOME }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
    else { Fail '无法确定 DSH_HOME，请用 -DshHome "路径" 指定' }
}
$DshHome = [System.IO.Path]::GetFullPath($DshHome)
$profilesDir = Join-Path $DshHome 'profiles'
if (-not (Test-Path -LiteralPath $profilesDir)) {
    Fail "没找到 $profilesDir —— 先把 DSH 打开一次（初始化后才会出现 profiles 目录），再回来双击本脚本"
}
Write-Ok "DSH_HOME = $DshHome"

# ---------------------------------------------------------------- 2. profile
Write-Head '2/6 选择 profile'
$candidates = @()
foreach ($dir in Get-ChildItem -LiteralPath $profilesDir -Directory) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName 'package.json')) { $candidates += $dir.Name }
}
if ($candidates.Count -eq 0) { Fail "$profilesDir 下没有任何带 package.json 的 profile" }

if ([string]::IsNullOrWhiteSpace($Profile)) {
    if ($candidates -contains 'desktop') { $Profile = 'desktop' }
    elseif ($candidates.Count -eq 1) { $Profile = $candidates[0] }
    else {
        Write-Info "发现多个 profile：$($candidates -join ', ')"
        $answer = Read-Host '  要装进哪一个？（直接回车 = 第一个）'
        if ([string]::IsNullOrWhiteSpace($answer)) { $Profile = $candidates[0] } else { $Profile = $answer.Trim() }
    }
}
if (-not ($candidates -contains $Profile)) {
    Fail "profile '$Profile' 不存在。可选：$($candidates -join ', ')"
}
$profileDir = Join-Path $profilesDir $Profile
$profilePkgPath = Join-Path $profileDir 'package.json'
Write-Ok "profile = $Profile"

# ---------------------------------------------------------------- 3. 目标路径
Write-Head '3/6 准备目标目录'
$localRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'dsh-purge' } else { Join-Path $DshHome 'local-packages\dsh-purge' }
$masterDir = Join-Path $localRoot $version
$targetDir = Join-Path $profileDir "node_modules\dsh-purge"
Write-Info "母本目录：$masterDir"
Write-Info "profile 目录：$targetDir"

# 从 $openIndex 处的 '{' 起做括号配对，返回对应 '}' 的下标（跳过字符串内的括号）
function Get-ObjectCloseIndex([string]$text, [int]$openIndex) {
    $depth = 0
    $inStr = $false
    for ($i = $openIndex; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($inStr) {
            if ($c -eq '\') { $i++; continue }
            if ($c -eq '"') { $inStr = $false }
            continue
        }
        if ($c -eq '"') { $inStr = $true; continue }
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

# 取 $index 之前、同一行开头的缩进（没有则返回 defaultIndent）
function Get-IndentBefore([string]$text, [int]$index, [string]$defaultIndent) {
    if ($index -le 0) { return $defaultIndent }
    $nl = $text.LastIndexOf("`n", [Math]::Max(0, $index - 1))
    if ($nl -lt 0) { return $defaultIndent }
    $start = $nl + 1
    $sb = New-Object System.Text.StringBuilder
    for ($i = $start; $i -lt $index; $i++) {
        $c = $text[$i]
        if ($c -eq ' ' -or $c -eq "`t") { [void]$sb.Append($c) } else { break }
    }
    if ($sb.Length -eq 0) { return $defaultIndent }
    return $sb.ToString()
}

function Invoke-CopyTree([string]$src, [string]$dst) {
    $null = New-Item -ItemType Directory -Force -Path $dst
    $code = 0
    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        & robocopy.exe $src $dst /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
        $code = $LASTEXITCODE
    }
    else {
        Copy-Item -LiteralPath (Join-Path $src '*') -Destination $dst -Recurse -Force
        $code = 0
    }
    if ($code -ge 8) { throw "复制失败（robocopy 退出码 $code）：$src -> $dst" }
}

# 目标若是 junction/symlink，先摘掉链接本身，避免 /MIR 穿透删掉别处
function Clear-LinkOrDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        cmd /c rmdir "$path" | Out-Null
        Write-Info '先摘掉了一个旧的目录链接'
    }
}

if ($DryRun) {
    Write-Warn2 '-DryRun：只预览，不写任何文件'
}

# ---------------------------------------------------------------- 4. 复制
Write-Head '4/6 复制插件本体'
if ($DryRun) {
    Write-Info "（预览）复制 $payloadRoot -> $masterDir"
    Write-Info "（预览）复制 $masterDir -> $targetDir"
}
else {
    Clear-LinkOrDir $masterDir
    Invoke-CopyTree $payloadRoot $masterDir
    Write-Ok "母本已就位：$masterDir"

    Clear-LinkOrDir $targetDir
    if (Test-Path -LiteralPath $targetDir) {
        $existing = Get-Item -LiteralPath $targetDir -Force
        if ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "$targetDir" | Out-Null
        }
    }
    Invoke-CopyTree $masterDir $targetDir
    Write-Ok "profile 内已就位：$targetDir"
}

# ---------------------------------------------------------------- 5. 登记
Write-Head '5/6 登记到 profile'
$specPath = ($masterDir -replace '\\', '/')
$spec = "file:$specPath"
$original = [System.IO.File]::ReadAllText($profilePkgPath, [System.Text.Encoding]::UTF8)
$updated = $original

# --- dependencies: dsh-purge
$depPattern = '"dsh-purge"\s*:\s*"[^"]*"'
if ([regex]::IsMatch($updated, $depPattern)) {
    $updated = ([regex]$depPattern).Replace($updated, ('"dsh-purge": "' + $spec + '"'), 1)
    Write-Info "依赖已存在，改指向：$spec"
}
else {
    $m = [regex]::Match($updated, '"dependencies"\s*:\s*\{', 'IgnoreCase')
    if (-not $m.Success) { Fail 'profile 的 package.json 里没有 dependencies 字段，结构不认识，停止' }
    $openIdx = $m.Index + $m.Length - 1
    $closeIdx = Get-ObjectCloseIndex $updated $openIdx
    if ($closeIdx -lt 0) { Fail 'dependencies 对象没有闭合的 }，结构不认识，停止' }
    # 插到对象末尾：找到最后一个非空白字符
    $lastIdx = $closeIdx - 1
    while ($lastIdx -gt $openIdx -and [char]::IsWhiteSpace($updated[$lastIdx])) { $lastIdx-- }
    if ($lastIdx -eq $openIdx) {
        # 空对象：直接放一项
        $indent = Get-IndentBefore $updated $m.Index '    '
        $indent = $indent + '  '
        $insert = "`r`n$indent`"dsh-purge`": `"$spec`"`r`n" + (Get-IndentBefore $updated $m.Index '  ')
    }
    else {
        $indent = Get-IndentBefore $updated $lastIdx '    '
        $objText = $updated.Substring($openIdx, $closeIdx - $openIdx)
        if ($objText.Contains("`n")) {
            $insert = ",`r`n$indent`"dsh-purge`": `"$spec`""
        }
        else {
            # 单行 dependencies：保持单行，别塞换行
            $insert = ",`"dsh-purge`":`"$spec`""
        }
    }
    $updated = $updated.Substring(0, $lastIdx + 1) + $insert + $updated.Substring($lastIdx + 1)
    Write-Info "已加入依赖：dsh-purge -> $spec"
}

# --- bundles
$removeNames = @()
if ($RemoveLegacy) { $removeNames = @('dsh-purge-community', 'dsh-unrestricted') }
$bm = [regex]::Match($updated, '"bundles"\s*:\s*\[', 'IgnoreCase')
if (-not $bm.Success) { Fail 'profile 的 package.json 里没有 bundles 数组，结构不认识，停止' }
$open = $bm.Index + $bm.Length - 1
$close = $updated.IndexOf(']', $open)
if ($close -lt 0) { Fail 'bundles 数组没有闭合的 ]，结构不认识，停止' }
$seg = $updated.Substring($open + 1, $close - $open - 1)
$items = @()
foreach ($piece in $seg.Split(',')) {
    $t = $piece.Trim()
    if ($t -eq '') { continue }
    $t = $t.Trim('"').Trim()
    if ($t -eq '') { continue }
    if ($removeNames -contains $t) {
        Write-Warn2 "从 bundles 移除旧条目：$t"
        continue
    }
    $items += $t
}
if ($items -notcontains 'dsh-purge') { $items += 'dsh-purge'; Write-Info '已把 dsh-purge 加入 bundles' }
else { Write-Info 'bundles 里已有 dsh-purge' }
$multiLine = $seg.Contains("`n")
if ($multiLine) {
    $firstQuote = $seg.IndexOf('"')
    if ($firstQuote -ge 0) {
        $itemIndent = Get-IndentBefore $updated ($open + 1 + $firstQuote) '        '
    }
    else { $itemIndent = '        ' }
    $closeIndent = Get-IndentBefore $updated $bm.Index '      '
    $newSeg = "`r`n" + (($items | ForEach-Object { $itemIndent + '"' + $_ + '"' }) -join ",`r`n") + "`r`n" + $closeIndent
}
else {
    $newSeg = (($items | ForEach-Object { '"' + $_ + '"' }) -join ', ')
}
$updated = $updated.Substring(0, $open + 1) + $newSeg + $updated.Substring($close)

# --- 旧包依赖残留
if ($RemoveLegacy) {
    foreach ($old in @('dsh-purge-community', 'dsh-unrestricted')) {
        # 优先整行删除（保留缩进风格、不留空行）
        $linePattern = '[ \t]*"' + [regex]::Escape($old) + '"\s*:\s*"[^"]*"\s*,?[ \t]*\r?\n'
        $inlinePattern = '"\s*' + [regex]::Escape($old) + '\s*"\s*:\s*"[^"]*"\s*,?'
        if ([regex]::IsMatch($updated, $linePattern)) {
            $updated = ([regex]$linePattern).Replace($updated, '', 1)
            $updated = ([regex]',(\s*})').Replace($updated, '$1', 1)
            Write-Warn2 "从 dependencies 移除旧包：$old"
        }
        elseif ([regex]::IsMatch($updated, $inlinePattern)) {
            $updated = ([regex]$inlinePattern).Replace($updated, '', 1)
            $updated = ([regex]',(\s*})').Replace($updated, '$1', 1)
            Write-Warn2 "从 dependencies 移除旧包：$old"
        }
        $oldDir = Join-Path $profileDir "node_modules\$old"
        if ((Test-Path -LiteralPath $oldDir) -and -not $DryRun) {
            Clear-LinkOrDir $oldDir
            if (Test-Path -LiteralPath $oldDir) { Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue }
            if (-not (Test-Path -LiteralPath $oldDir)) { Write-Warn2 "已删除旧包目录：node_modules\$old" }
        }
    }
}

if ($updated -ne $original) {
    try { $null = $updated | ConvertFrom-Json } catch { Fail "改完的 package.json 不是合法 JSON，已放弃写入：$($_.Exception.Message)" }
    if ($DryRun) {
        Write-Warn2 '（预览）不写入 package.json'
        Write-Host ''
        Write-Host '----- 预览：改动后的 package.json -----' -ForegroundColor DarkGray
        Write-Host $updated
    }
    else {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$profilePkgPath.bak-$stamp"
        [System.IO.File]::WriteAllText($backup, $original, $script:Utf8NoBom)
        [System.IO.File]::WriteAllText($profilePkgPath, $updated, $script:Utf8NoBom)
        Write-Ok "package.json 已更新（备份：$(Split-Path -Leaf $backup)）"
    }
}
else {
    Write-Info 'package.json 已经是目标状态，无需改动'
}

# ---------------------------------------------------------------- 6. 校验
Write-Head '6/6 校验'
if ($DryRun) {
    Write-Warn2 '预览结束，什么都没改。去掉 -DryRun 再跑一次才会真正安装。'
    exit 0
}

$installedPkg = Join-Path $targetDir 'package.json'
if (-not (Test-Path -LiteralPath $installedPkg)) { Fail "装完却找不到 $installedPkg" }
$installed = [System.IO.File]::ReadAllText($installedPkg, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
Write-Ok "已安装版本：$($installed.version)"

$check = [System.IO.File]::ReadAllText($profilePkgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$depValue = $check.dependencies.'dsh-purge'
if ([string]::IsNullOrWhiteSpace($depValue)) { Fail '依赖没写进 profile（写入后又被别的程序改回去了？）' }
Write-Ok "dependencies.dsh-purge = $depValue"
$bundles = @($check.dsh.profile.bundles)
if ($bundles -notcontains 'dsh-purge') { Fail 'dsh.profile.bundles 里没有 dsh-purge' }
Write-Ok "bundles 已包含 dsh-purge（共 $($bundles.Count) 项）"
if (-not (Test-Path -LiteralPath (Join-Path $targetDir 'node_modules\yaml'))) {
    Write-Warn2 'payload 里没看到 yaml 依赖，宿主可能加载失败；确认解压完整'
}

# 包名一致性：客户端注册 id 必须等于包名，否则宿主 import failed 并进恢复模式
$instName = [string]$installed.name
$clientFile = Join-Path $targetDir 'client.js'
if (-not (Test-Path -LiteralPath $clientFile)) {
    Fail '装完却找不到 client.js'
}
$mr = [regex]::Match([System.IO.File]::ReadAllText($clientFile, [System.Text.Encoding]::UTF8), '__ModuleLoader__\.load\(\s*\{\s*id\s*:\s*["'']([^"'']+)["'']')
if (-not $mr.Success) { Write-Warn2 'client.js 里没找到模块注册 id，跳过包名一致性校验' }
elseif ($mr.Groups[1].Value -ne $instName) {
    Fail "client.js 注册 id「$($mr.Groups[1].Value)」与包名「$instName」不一致，宿主会 import failed —— 这个包是坏的，请换一份完整解压包"
}
else { Write-Ok "包名与客户端注册 id 一致：$instName" }

Write-Host ''
Write-Host '  装好了。接下来：' -ForegroundColor White
Write-Host '    1) 完全退出 DSH —— 关掉窗口，托盘图标也要右键退出，确保进程没了' -ForegroundColor White
Write-Host '    2) 重新打开 DSH' -ForegroundColor White
Write-Host '    3) 左侧栏出现 Purge 面板 = 成功；首次用请在面板里点一次「应用」' -ForegroundColor White
Write-Host ''
Write-Host '  想撤掉：双击 卸载.cmd' -ForegroundColor DarkGray
Write-Host ''
