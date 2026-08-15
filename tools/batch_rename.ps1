<#
.SYNOPSIS
    批量重命名发布产物（如 IriX_1.1.1_macos_arm64.dmg → irix-1.1.1-macOS-arm64.dmg）。

.DESCRIPTION
    扫描目录中的文件，按模板重命名。自动从原文件名 / 扩展名识别
    平台（windows / macOS / linux）与架构（x64 / arm64 / x86），
    版本号可显式指定或自动从文件名提取（如 1.1.1）。

    模板占位符：
      {name}    项目名（-Name 参数，默认 irix，输出为小写）
      {version} 版本号（-Version 参数；缺省自动从原文件名提取）
      {os}      平台：windows / macOS / linux（自动识别，未识别时报错跳过）
      {arch}    架构：x64 / arm64 / x86 / armv7（自动识别，未识别时报错跳过）
      {ext}     扩展名（小写，如 dmg / exe）
      {base}    原文件名（不含扩展名）
      {index}   序号（1 起，防重名）

    安全特性：
      - 默认只预览（改名表），加 -Apply 才真正执行
      - 目标文件已存在时逐个询问（或用 -SkipExisting / -Overwrite）
      - 改名记录到 CSV 日志，可用 -Undo 按日志回滚

.EXAMPLE
    # 预览：dist 目录全部文件按默认模板
    .\tools\batch_rename.ps1 -Dir .\dist

.EXAMPLE
    # 执行：指定版本 1.1.1
    .\tools\batch_rename.ps1 -Dir .\dist -Version 1.1.1 -Apply

.EXAMPLE
    # 仅处理 exe，且目标重名时直接跳过
    .\tools\batch_rename.ps1 -Dir .\dist -Filter *.exe -SkipExisting -Apply

.EXAMPLE
    # 按日志回滚上一次改名
    .\tools\batch_rename.ps1 -Undo -LogPath .\rename-log.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # 扫描目录（必填；-Undo 时不需要）
    [string]$Dir,

    # 目标名模板
    [string]$Pattern = '{name}-{version}-{os}-{arch}.{ext}',

    # 项目名（{name} 占位符）
    [string]$Name = 'irix',

    # 版本号（缺省自动从文件名提取）
    [string]$Version = '',

    # 文件过滤（如 *.dmg、*.exe）
    [string]$Filter = '*',

    # 排除过滤（如 *.dmg，可配合多次运行实现不同命名）
    [string]$Exclude = '',

    # 强制指定架构（覆盖自动识别）
    [string]$Arch = '',

    # 文件名无架构关键字时的回退架构（如 x64；缺省则跳过该文件）
    [string]$DefaultArch = '',

    # 递归子目录
    [switch]$Recurse,

    # 真正执行改名（不加则仅预览）
    [switch]$Apply,

    # 目标已存在：跳过（默认逐个询问）
    [switch]$SkipExisting,

    # 目标已存在：直接覆盖
    [switch]$Overwrite,

    # 按日志回滚改名
    [switch]$Undo,

    # 改名日志路径（默认 <Dir>\rename-log.csv）
    [string]$LogPath = '',

    # 回滚时目标已存在也强制改回
    [switch]$ForceUndo
)

$ErrorActionPreference = 'Stop'

# ---------------- 平台 / 架构识别 ----------------

function Get-OsName([string]$fileName) {
    $lower = $fileName.ToLowerInvariant()
    $ext = [System.IO.Path]::GetExtension($fileName).ToLowerInvariant()
    if ($lower -match 'windows|win32|win64|msix|msi\b|\.exe\b' -or $ext -in @('.exe', '.msi', '.msix')) { return 'windows' }
    if ($lower -match 'macos|darwin|osx|\bmac\b' -or $ext -in @('.dmg', '.pkg', '.app')) { return 'macOS' }
    if ($lower -match 'linux|ubuntu|debian|fedora|appimage|opensuse|archlinux' -or $ext -in @('.appimage', '.deb', '.rpm', '.snap', '.flatpak')) { return 'linux' }
    return $null
}

function Get-ArchName([string]$fileName) {
    $lower = $fileName.ToLowerInvariant()
    # 用「非字母数字边界」代替 \b（\b 会把下划线当单词字符，导致 _x64 漏检）
    $border = '(?<![a-z0-9])'
    $end = '(?![a-z0-9])'
    if ($lower -match 'aarch64|arm64') { return 'arm64' }
    if ($lower -match 'x86_64|x86-64|amd64' -or $lower -match "${border}x64${end}") { return 'x64' }
    if ($lower -match 'armv7|armhf') { return 'armv7' }
    if ($lower -match 'i386|i686|ia32' -or $lower -match "${border}x86${end}") { return 'x86' }
    return $null
}

function Get-VersionFromName([string]$fileName) {
    # 仅接受「数字开头」或已知预发布词的 -/+ 后缀，避免吞掉 "-linux"/"-arm64" 之类的平台段
    $match = [regex]::Match(
        $fileName,
        '(\d+\.\d+(?:\.\d+)?(?:[+-](?:\d|alpha|beta|rc|dev|pre|snapshot)[0-9A-Za-z.]*)?)'
    )
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

# ---------------- 模板渲染 ----------------

function Expand-Template([string]$pattern, [hashtable]$tokens) {
    $result = $pattern
    foreach ($key in $tokens.Keys) {
        $result = $result.Replace("{$key}", [string]$tokens[$key])
    }
    # 未替换的占位符保留原样，便于发现问题
    return $result
}

# ---------------- 回滚 ----------------

if ($Undo) {
    if ([string]::IsNullOrWhiteSpace($LogPath)) { throw '回滚需要 -LogPath（改名日志 CSV 路径）' }
    if (-not (Test-Path $LogPath)) { throw "日志不存在: $LogPath" }
    $rows = Import-Csv $LogPath
    $reversed = @($rows | Sort-Object { [int]$_.Index } -Descending)
    $count = 0
    foreach ($row in $reversed) {
        $newPath = $row.NewPath
        $oldPath = $row.OldPath
        if (-not (Test-Path $newPath)) {
            Write-Warning "跳过（新文件已不在）: $newPath"
            continue
        }
        # 仅大小写不同的改名（Windows 大小写不敏感文件系统）：直接改回
        $sameFile = [string]::Equals(
            $newPath, $oldPath, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $sameFile -and (Test-Path $oldPath)) {
            if ($ForceUndo) {
                Remove-Item $oldPath -Force
            } else {
                Write-Warning "跳过（原名已存在，加 -ForceUndo 覆盖）: $oldPath"
                continue
            }
        }
        if ($PSCmdlet.ShouldProcess($newPath, "回滚为 $oldPath")) {
            Move-Item -LiteralPath $newPath -Destination $oldPath
            Write-Host "回滚: $newPath -> $oldPath" -ForegroundColor Yellow
            $count++
        }
    }
    Write-Host "`n回滚完成，共 $count 个文件。" -ForegroundColor Green
    return
}

# ---------------- 主流程 ----------------

if ([string]::IsNullOrWhiteSpace($Dir)) { throw '缺少 -Dir（扫描目录）' }
if (-not (Test-Path $Dir)) { throw "目录不存在: $Dir" }

$version = $Version
$tokens = @{}
$logRows = @()
$logPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
    Join-Path $Dir 'rename-log.csv'
} else {
    $LogPath
}

$files = Get-ChildItem -Path $Dir -Filter $Filter -File -Recurse:$Recurse |
    Where-Object {
        $_.FullName -ne $logPath -and          # 排除改名日志自身
        ($([string]::IsNullOrWhiteSpace($Exclude)) -or ($_.Name -notlike $Exclude))
    }
$plans = New-Object System.Collections.Generic.List[object]
$index = 1

foreach ($file in $files) {
    $os = Get-OsName $file.Name
    $arch = if (-not [string]::IsNullOrWhiteSpace($Arch)) { $Arch } else { Get-ArchName $file.Name }
    if ([string]::IsNullOrWhiteSpace($arch) -and -not [string]::IsNullOrWhiteSpace($DefaultArch)) {
        $arch = $DefaultArch
    }
    $ver = if ([string]::IsNullOrWhiteSpace($version)) { Get-VersionFromName $file.Name } else { $version }
    $ext = $file.Extension.TrimStart('.')
    if ([string]::IsNullOrWhiteSpace($os) -and $Pattern -match '\{os\}') { Write-Warning "跳过（无法识别平台）: $($file.Name)"; continue }
    if ([string]::IsNullOrWhiteSpace($arch) -and $Pattern -match '\{arch\}') { Write-Warning "跳过（无法识别架构，可用 -Arch 或 -DefaultArch）: $($file.Name)"; continue }
    if ([string]::IsNullOrWhiteSpace($ver) -and $Pattern -match '\{version\}') { Write-Warning "跳过（无法确定版本号，请加 -Version）: $($file.Name)"; continue }

    $targetName = Expand-Template $Pattern @{
        name    = $Name.ToLowerInvariant()
        version = $ver
        os      = $os
        arch    = $arch
        ext     = $ext.ToLowerInvariant()
        origext = $ext
        base    = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        index   = $index
    }
    # 清理 Windows 非法字符
    $targetName = ($targetName -replace '[<>:"/\\|?*]', '-').Trim()

    if ([string]::IsNullOrWhiteSpace($targetName)) { Write-Warning "跳过（模板结果为空）: $($file.Name)"; continue }

    $plans.Add([pscustomobject]@{
            Index    = $index
            Source   = $file.FullName
            OldName  = $file.Name
            NewName  = $targetName
            Target   = Join-Path $file.DirectoryName $targetName
            Detected = "$os / $arch / v$ver"
        })
    $index++
}

if ($plans.Count -eq 0) {
    Write-Host '没有需要改名的文件（检查 -Filter 与文件名是否含平台/架构关键字）。' -ForegroundColor Yellow
    return
}

# ---------------- 预览 ----------------

Write-Host ''
Write-Host ('{0,-6} {1,-40} {2,-40} {3,-24}' -f '序号', '原名', '新名', '识别') -ForegroundColor Cyan
Write-Host ('-' * 118)
foreach ($plan in $plans) {
    Write-Host ('{0,-6} {1,-40} {2,-40} {3,-24}' -f $plan.Index, $plan.OldName, $plan.NewName, $plan.Detected)
}
Write-Host ('-' * 118)
Write-Host "共 $($plans.Count) 个文件。"

if (-not $Apply) {
    Write-Host '预览模式：确认无误后加 -Apply 执行改名。' -ForegroundColor Yellow
    return
}

# ---------------- 执行 ----------------

$renamed = 0
foreach ($plan in $plans) {
    # 完全同名（含大小写）才跳过；仅大小写不同也执行改名
    if ($plan.OldName -ceq $plan.NewName) { continue }
    # Windows 文件系统大小写不敏感：仅大小写不同的改名直接执行，不做冲突判定
    $sameFile = [string]::Equals(
        $plan.Target, $plan.Source, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $sameFile -and (Test-Path -LiteralPath $plan.Target)) {
        if ($SkipExisting) { Write-Warning "跳过（目标已存在）: $($plan.NewName)"; continue }
        if (-not $Overwrite) {
            $answer = Read-Host "目标已存在 $($plan.NewName)，覆盖? (y/n，默认 n)"
            if ($answer -notmatch '^[yY]') { Write-Warning "跳过: $($plan.OldName)"; continue }
        }
        Remove-Item -LiteralPath $plan.Target -Force
    }
    if ($PSCmdlet.ShouldProcess($plan.Source, "重命名为 $($plan.NewName)")) {
        Move-Item -LiteralPath $plan.Source -Destination $plan.Target
        Write-Host "√ $($plan.OldName) -> $($plan.NewName)" -ForegroundColor Green
        $logRows += [pscustomobject]@{
            Index   = $plan.Index
            OldPath = $plan.Source
            NewPath = $plan.Target
            Time    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        $renamed++
    }
}

if ($renamed -gt 0) {
    $logRows | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8
    Write-Host "`n完成，共改名 $renamed 个文件。日志: $logPath（可 -Undo 回滚）" -ForegroundColor Green
} else {
    Write-Host '`n没有文件被改名。' -ForegroundColor Yellow
}
