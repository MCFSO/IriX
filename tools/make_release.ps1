<#
.SYNOPSIS
    生成新闻学风格（倒金字塔 + 5W1H 导语）的 Release 说明，并给出 gh release 命令。

.DESCRIPTION
    新闻学结构：标题 → 导语（5W1H：何事/何时/何人/何地/为何/如何）→ 正文按重要性
    递减（新增 → 修复 → 优化 → 其它）→ 下载与校验 → 背景 → 反馈。

    自动完成：
      - 5W1H 导语（时间取当天，其余可用参数覆盖）
      - 变更清单：从 git log（上一个 tag 起，只读）按 commit 前缀分组
      - 产物校验：扫描 -Dist 目录，计算每个文件的 SHA-256 与大小，
        写入 RELEASE_NOTES-<版本>.md 并生成 SHA256SUMS-<版本>.txt
      - gh 命令：默认只打印 `gh release create --draft` 命令供你复制执行；
        加 -Draft 才真正调用 gh（在 GitHub 上创建草稿，不发布）

.EXAMPLE
    # 只生成说明与校验和（预览 gh 命令，不执行）
    .\tools\make_release.ps1 -Version 1.1.1 -Dist .\dist

.EXAMPLE
    # 带要点（新闻导语引用第一条）
    .\tools\make_release.ps1 -Version 1.1.1 -Dist .\dist `
        -Highlights '新增集群编排系统','修复 Windows 下载崩溃'

.EXAMPLE
    # 生成说明并用 gh 创建草稿 Release（仅草稿，不公开发布）
    .\tools\make_release.ps1 -Version 1.1.1 -Dist .\dist -Draft
#>
[CmdletBinding()]
param(
    # 版本号（必填，如 1.1.1）
    [Parameter(Mandatory = $true)][string]$Version,

    # 产物目录（默认 .\dist）
    [string]$Dist = '.\dist',

    # 新闻标题（缺省自动生成："IriX <版本> 发布：<首条要点/稳定升级>"）
    [string]$Title = '',

    # 要点（按重要性从高到低，导语会引用）
    [string[]]$Highlights = @(),

    # 5W1H 覆盖项
    [string]$What = '',       # 何事（一句话）
    [string]$Who = 'IriX 项目组',           # 何人（发布方）
    [string]$Audience = 'Minecraft 服务器管理员与开服玩家',  # 受众（给谁）
    [string]$Why = '',        # 为何（本版目标）
    [string]$Where = 'GitHub Releases（含官网渠道）',        # 何地/渠道

    # 变更清单来源：上一个 tag（缺省自动取最近 tag）；git 不可用时跳过
    [string]$SinceTag = '',

    # 说明文件输出路径（默认 <Dist>\RELEASE_NOTES-<版本>.md）
    [string]$NotesOut = '',

    # 真正调用 gh 创建草稿 Release（默认只打印命令）
    [switch]$Draft,

    # 直接发布（先建草稿再取消草稿状态，避免 gh 交互确认；谨慎使用）
    [switch]$Publish,

    # gh release 附加：--prerelease
    [switch]$Prerelease,

    # tag 前缀（默认 v）
    [string]$TagPrefix = 'v',

    # GitHub 仓库（gh 默认当前仓库）
    [string]$Repo = '',

    # tag 目标分支/commit（gh --target，默认当前分支）
    [string]$Target = '',

    # 跳过校验和计算（纯写稿）
    [switch]$SkipChecksums
)

$ErrorActionPreference = 'Stop'

# ---------------- 工具函数 ----------------

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N1} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N0} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
}

function Get-RepoRoot {
    try {
        $root = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $root) { return $root.Trim() }
    } catch { }
    return $null
}

# 自动取最近 tag（只读）
function Get-LatestTag([string]$repoRoot) {
    try {
        $tags = git -C $repoRoot tag --sort=-creatordate 2>$null
        if ($LASTEXITCODE -eq 0 -and $tags) {
            foreach ($t in $tags) {
                if ($t -match '^v?\d') { return $t.Trim() }
            }
        }
    } catch { }
    return $null
}

# 变更清单（只读 git log，按 commit 前缀分组）
function Get-Changelog([string]$repoRoot, [string]$sinceTag) {
    if (-not $repoRoot) { return @{} }
    $range = if ($sinceTag) { "$sinceTag..HEAD" } else { '-10' }
    try {
        $lines = git -C $repoRoot log --pretty=format:'%s' $range 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $lines) { return @{} }
    } catch { return @{} }

    $groups = @{ '新增' = @(); '修复' = @(); '优化' = @(); '其它' = @() }
    foreach ($line in $lines) {
        $subject = $line.Trim()
        if (-not $subject -or $subject -match '^(Merge|Revert)') { continue }
        $scope = $subject -replace '^(feat|fix|perf|refactor|chore|docs|style|test|build|ci)(\([^)]*\))?!?:\s*', ''
        if ($scope -eq $subject) {
            $groups['其它'] += $subject
            continue
        }
        if ($subject -match '^feat') { $groups['新增'] += $scope }
        elseif ($subject -match '^fix') { $groups['修复'] += $scope }
        elseif ($subject -match '^(perf|refactor|chore|build|ci)') { $groups['优化'] += $scope }
        else { $groups['其它'] += $scope }
    }
    return $groups
}

# ---------------- 参数整理 ----------------

$distPath = (Resolve-Path $Dist -ErrorAction SilentlyContinue).Path
if (-not $distPath) {
    $distPath = (New-Item -ItemType Directory -Force -Path $Dist).FullName
    Write-Warning "产物目录不存在，已创建: $distPath"
}
$notesPath = if ($NotesOut) { $NotesOut } else { Join-Path $distPath "RELEASE_NOTES-$Version.md" }
$tag = "$TagPrefix$Version"
$repoRoot = Get-RepoRoot
$since = if ($SinceTag) { $SinceTag } else { Get-LatestTag $repoRoot }
$today = Get-Date -Format 'yyyy年M月d日'

$whatLine = if ($What) { $What }
elseif ($Highlights.Count -gt 0) { "带来「$($Highlights[0])」等改进" }
else { '发布稳定升级' }

$whyLine = if ($Why) { $Why } else { '持续提升服务器管理的稳定性与容器化体验' }
$headline = if ($Title) { $Title }
elseif ($Highlights.Count -gt 0) { "IriX $Version 发布：$($Highlights[0])" }
else { "IriX $Version 发布：稳定升级与体验改进" }

$changelog = Get-Changelog $repoRoot $since

# ---------------- 校验和 ----------------

$assets = @()
if (-not $SkipChecksums) {
    $files = Get-ChildItem -Path $distPath -File |
        Where-Object {
            $_.Name -notmatch '^RELEASE_NOTES-' -and
            $_.Name -notmatch '^SHA256SUMS-' -and
            $_.Name -ne 'rename-log.csv'
        } |
        Sort-Object Name
    foreach ($file in $files) {
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $assets += [pscustomobject]@{
            File = $file.Name
            Size = Format-Size $file.Length
            Sha  = $hash
        }
    }
}

# ---------------- 新闻稿渲染（倒金字塔） ----------------

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# $headline")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 导语')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("**IriX $Version 已于 $today 发布。**")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("| 新闻要素 | 内容 |")
[void]$sb.AppendLine("|----------|------|")
[void]$sb.AppendLine("| 何事（What） | $whatLine |")
[void]$sb.AppendLine("| 何时（When） | $today |")
[void]$sb.AppendLine("| 何人（Who） | $Who |")
[void]$sb.AppendLine("| 给谁（Whom） | $Audience |")
[void]$sb.AppendLine("| 何地（Where） | $Where |")
[void]$sb.AppendLine("| 为何（Why） | $whyLine |")
[void]$sb.AppendLine("| 如何（How） | 在下载区选择对应平台安装包，覆盖安装即完成升级 |")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("> **一句话新闻**：$Who 于 $today 发布 IriX $Version，$whatLine。")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 本版要点')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('（按新闻重要性从高到低排列）')
[void]$sb.AppendLine('')
if ($Highlights.Count -gt 0) {
    foreach ($h in $Highlights) { [void]$sb.AppendLine("- $h") }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 变更详情')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> 以下由 git log 自动汇总（`' + $(if ($since) { $since } else { '最近提交' }) + '` 起），发布前请人工校对。')
[void]$sb.AppendLine('')
foreach ($group in @('新增', '修复', '优化', '其它')) {
    $items = $changelog[$group]
    if ($items -and $items.Count -gt 0) {
        [void]$sb.AppendLine("### $group")
        [void]$sb.AppendLine('')
        foreach ($item in ($items | Select-Object -Unique)) {
            [void]$sb.AppendLine("- $item")
        }
        [void]$sb.AppendLine('')
    }
}
if (-not $Highlights -and (-not $changelog['新增'] -and -not $changelog['修复'] -and -not $changelog['优化'] -and -not $changelog['其它'])) {
    [void]$sb.AppendLine('（本版无自动汇总的变更记录；可用 -Highlights 参数补充要点。）')
    [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('## 下载与校验')
[void]$sb.AppendLine('')
if ($assets.Count -gt 0) {
    [void]$sb.AppendLine('| 文件 | 大小 | SHA-256 |')
    [void]$sb.AppendLine('|------|------|---------|')
    foreach ($a in $assets) {
        [void]$sb.AppendLine("| $($a.File) | $($a.Size) | ``$($a.Sha)`` |")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("校验和文件：``SHA256SUMS-$Version.txt``（与产物同目录）")
} else {
    [void]$sb.AppendLine('（产物目录无文件，跳过校验和；用 -Dist 指定产物目录。）')
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 升级与安装')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- 覆盖安装即可，实例与配置数据自动保留；')
[void]$sb.AppendLine('- 升级后建议先启动一次既有实例确认无异常；')
[void]$sb.AppendLine('- 回退：重新安装上一版本安装包即可。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 背景')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('IriX 是面向 Minecraft 服务器管理的开源工具，支持单机与多机集群模式，')
[void]$sb.AppendLine('并内建 Docker / Bastille 容器管理与 K8s 风格编排能力。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 反馈')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('问题与建议请提交至 GitHub Issues。')

$notes = $sb.ToString()
[System.IO.File]::WriteAllText($notesPath, $notes, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已生成新闻稿: $notesPath" -ForegroundColor Green

# SHA256SUMS
if ($assets.Count -gt 0) {
    $sumsPath = Join-Path $distPath "SHA256SUMS-$Version.txt"
    $sumLines = $assets | ForEach-Object { "$($_.Sha)  $($_.File)" }
    [System.IO.File]::WriteAllLines($sumsPath, $sumLines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已生成校验和: $sumsPath" -ForegroundColor Green
}

# ---------------- gh 命令（默认只打印） ----------------

$target = if ($Target) { $Target } else {
    try { (git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch { '' }
}

$ghArgs = @('release', 'create', $tag, '--draft', '--title', "`"$headline`"", '--notes-file', "`"$notesPath`"")
if ($target) { $ghArgs += '--target', $target }
if ($Prerelease) { $ghArgs += '--prerelease' }
if ($Repo) { $ghArgs += '--repo', $Repo }
foreach ($a in $assets) {
    $ghArgs += "`"$(Join-Path $distPath $a.File)`""
}
$ghCommand = 'gh ' + ($ghArgs -join ' ')

Write-Host ''
if ($Draft -or $Publish) {
    # 统一先建草稿（无交互确认），-Publish 时再取消草稿状态正式发布
    if ($Publish) {
        Write-Host '正在用 gh 创建并发布 Release ...' -ForegroundColor Yellow
    } else {
        Write-Host '正在用 gh 创建草稿 Release（仅草稿，不会公开发布）...' -ForegroundColor Yellow
    }
    & gh @ghArgs
    if ($LASTEXITCODE -ne 0) { throw "gh 执行失败（exit $LASTEXITCODE）" }
    if ($Publish) {
        & gh release edit $tag --draft=false
        if ($LASTEXITCODE -ne 0) { throw "gh release edit 失败（exit $LASTEXITCODE）" }
        Write-Host "Release v$Version 已发布: $(gh release view $tag --json url -q .url)" -ForegroundColor Green
    } else {
        Write-Host '草稿已创建，请到 GitHub Releases 页面确认后手动发布。' -ForegroundColor Green
    }
} else {
    Write-Host '以下命令可创建草稿 Release（复制执行，或加 -Draft/-Publish 自动执行）：' -ForegroundColor Cyan
    Write-Host $ghCommand -ForegroundColor White
    Write-Host ''
    Write-Host '提示：gh 会创建「草稿」，确认无误后在 GitHub 网页手动点 Publish。' -ForegroundColor Yellow
}
