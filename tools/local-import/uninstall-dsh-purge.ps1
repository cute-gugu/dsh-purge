#Requires -Version 5.1
<#
    卸载 dsh-purge（本地一键导入版）
      1) 从 profile 的 dependencies 里删掉 dsh-purge
      2) 从 dsh.profile.bundles 里删掉 dsh-purge
      3) 删除 <profile>\node_modules\dsh-purge 与 %LOCALAPPDATA%\dsh-purge
#>
[CmdletBinding()]
param(
    [string]$DshHome = '',
    [string]$Profile = '',
    [switch]$KeepLocalCopy,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Ok($t) { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Write-Info($t) { Write-Host "  [..]   $t" -ForegroundColor Gray }
function Write-Warn2($t) { Write-Host "  [警告] $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "  [失败] $t" -ForegroundColor Red; Write-Host ''; exit 1 }

Write-Host ''
Write-Host '  卸载 dsh-purge' -ForegroundColor White
Write-Host '  ---------------------------------------------------' -ForegroundColor DarkGray

if ([string]::IsNullOrWhiteSpace($DshHome)) {
    if (-not [string]::IsNullOrWhiteSpace($env:DSH_HOME)) { $DshHome = $env:DSH_HOME }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
    else { Fail '无法确定 DSH_HOME，请用 -DshHome "路径" 指定' }
}
$DshHome = [System.IO.Path]::GetFullPath($DshHome)
$profilesDir = Join-Path $DshHome 'profiles'
if (-not (Test-Path -LiteralPath $profilesDir)) { Fail "没找到 $profilesDir" }

$candidates = @()
foreach ($dir in Get-ChildItem -LiteralPath $profilesDir -Directory) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName 'package.json')) { $candidates += $dir.Name }
}
if ($candidates.Count -eq 0) { Fail "$profilesDir 下没有带 package.json 的 profile" }
if ([string]::IsNullOrWhiteSpace($Profile)) {
    if ($candidates -contains 'desktop') { $Profile = 'desktop' }
    elseif ($candidates.Count -eq 1) { $Profile = $candidates[0] }
    else {
        Write-Info "发现多个 profile：$($candidates -join ', ')"
        $answer = Read-Host '  从哪一个里卸载？（回车 = 第一个）'
        if ([string]::IsNullOrWhiteSpace($answer)) { $Profile = $candidates[0] } else { $Profile = $answer.Trim() }
    }
}
if (-not ($candidates -contains $Profile)) { Fail "profile '$Profile' 不存在。可选：$($candidates -join ', ')" }

$profileDir = Join-Path $profilesDir $Profile
$profilePkgPath = Join-Path $profileDir 'package.json'
$original = [System.IO.File]::ReadAllText($profilePkgPath, [System.Text.Encoding]::UTF8)
$updated = $original

$depPattern = '[ \t]*"dsh-purge"\s*:\s*"[^"]*"\s*,?[ \t]*\r?\n'
$inlinePattern = '"\s*dsh-purge\s*"\s*:\s*"[^"]*"\s*,?'
if ([regex]::IsMatch($updated, $depPattern)) {
    $updated = ([regex]$depPattern).Replace($updated, '', 1)
    $updated = ([regex]',(\s*})').Replace($updated, '$1', 1)
    Write-Info '从 dependencies 移除 dsh-purge'
}
elseif ([regex]::IsMatch($updated, $inlinePattern)) {
    $updated = ([regex]$inlinePattern).Replace($updated, '', 1)
    $updated = ([regex]',(\s*})').Replace($updated, '$1', 1)
    Write-Info '从 dependencies 移除 dsh-purge'
}

$bm = [regex]::Match($updated, '"bundles"\s*:\s*\[', 'IgnoreCase')
if ($bm.Success) {
    $open = $bm.Index + $bm.Length - 1
    $close = $updated.IndexOf(']', $open)
    if ($close -gt $open) {
        $seg = $updated.Substring($open + 1, $close - $open - 1)
        $items = @()
        foreach ($piece in $seg.Split(',')) {
            $t = $piece.Trim().Trim('"').Trim()
            if ($t -eq '') { continue }
            if ($t -eq 'dsh-purge') { Write-Info '从 bundles 移除 dsh-purge'; continue }
            $items += $t
        }
        $multiLine = $seg.Contains("`n")
        if ($multiLine) {
            $firstQuote = $seg.IndexOf('"')
            $itemIndent = if ($firstQuote -ge 0) {
                $nl = $seg.LastIndexOf("`n", [Math]::Max(0, $firstQuote - 1))
                if ($nl -ge 0) { $seg.Substring($nl + 1, $firstQuote - $nl - 1) } else { '        ' }
            } else { '        ' }
            if ($itemIndent.Trim() -eq '') {
                $closeIndent = '      '
            } else {
                $closeIndent = $itemIndent.Substring(0, [Math]::Max(0, $itemIndent.Length - 2))
            }
            if ($items.Count -eq 0) { $newSeg = '' }
            else {
                $newSeg = "`r`n" + (($items | ForEach-Object { $itemIndent + '"' + $_ + '"' }) -join ",`r`n") + "`r`n" + $closeIndent
            }
        }
        else {
            $newSeg = (($items | ForEach-Object { '"' + $_ + '"' }) -join ', ')
        }
        $updated = $updated.Substring(0, $open + 1) + $newSeg + $updated.Substring($close)
    }
}

if ($updated -ne $original) {
    try { $null = $updated | ConvertFrom-Json } catch { Fail "改完的 package.json 不是合法 JSON，已放弃写入：$($_.Exception.Message)" }
    if ($DryRun) { Write-Warn2 '（预览）不写入 package.json' }
    else {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        [System.IO.File]::WriteAllText("$profilePkgPath.bak-$stamp", $original, $script:Utf8NoBom)
        [System.IO.File]::WriteAllText($profilePkgPath, $updated, $script:Utf8NoBom)
        Write-Ok 'package.json 已更新（已备份）'
    }
}
else { Write-Info 'package.json 里本来就没有 dsh-purge' }

$targetDir = Join-Path $profileDir 'node_modules\dsh-purge'
$localRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'dsh-purge' } else { Join-Path $DshHome 'local-packages\dsh-purge' }
foreach ($p in @($targetDir, $localRoot)) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    if ($DryRun) { Write-Warn2 "（预览）将删除 $p"; continue }
    $item = Get-Item -LiteralPath $p -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { cmd /c rmdir "$p" | Out-Null }
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    if (-not (Test-Path -LiteralPath $p)) { Write-Ok "已删除 $p" } else { Write-Warn2 "删不掉（可能被占用，先退出 DSH）：$p" }
}

Write-Host ''
Write-Host '  卸载完成。完全退出 DSH 再打开，Purge 面板就没了。' -ForegroundColor White
Write-Host '  想装回来：双击 一键导入.cmd' -ForegroundColor DarkGray
Write-Host ''
