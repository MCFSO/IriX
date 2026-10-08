# 打包示例插件为 IriX 插件 zip 包（Windows）
# 用法：在项目根或本目录执行 `.\build_and_package.ps1`
# 步骤：构建 cdylib -> 改名为协议文件名 -> 与 manifest.json / README.md 一起打 zip

# 注意：不要用 $ErrorActionPreference = "Stop"——cargo 会把进度信息写到 stderr，
# 在该设置下会被 PowerShell 当作终止错误而中断脚本。改为检查 $LASTEXITCODE。

# 切到本脚本目录
Push-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

try {
    Write-Host "构建示例插件 (cargo build --release) ..."
    & cargo build --release 2>&1 | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Rust 构建失败" -ForegroundColor Red
        exit 1
    }

    $out = "target/release/irix_example_plugin.dll"
    if (-not (Test-Path $out)) {
        Write-Host "未找到构建产物: $out" -ForegroundColor Red
        exit 1
    }

    # 组装插件包目录
    $pkg = "package"
    Remove-Item -Recurse -Force $pkg -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path "$pkg/lib" | Out-Null

    Copy-Item "manifest.json" "$pkg/manifest.json"
    Copy-Item "README.md" "$pkg/README.md"
    # 协议文件名：<entry>.<platform>.dll
    Copy-Item $out "$pkg/lib/plugin.windows-x64.dll"

    # 打成 zip。用 .NET 逐条目写入并把分隔符统一成 '/'：Compress-Archive 会写成
    # 反斜杠（zip 惯例是正斜杠，跨平台更通用）。目标路径固定为脚本目录的上一级
    # （仓库 plugins/ 下），与 build_and_package.sh 保持一致。
    $zipAbs = [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path "../irix-example-plugin.zip"))
    if (Test-Path $zipAbs) { Remove-Item -Force $zipAbs }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $pkgFull = (Resolve-Path $pkg).Path
    $archive = [System.IO.Compression.ZipFile]::Open($zipAbs, 'Create')
    try {
        foreach ($f in Get-ChildItem -Recurse -File $pkgFull) {
            $rel = $f.FullName.Substring($pkgFull.Length + 1).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $f.FullName, $rel) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }

    if (-not (Test-Path $zipAbs)) {
        Write-Host "打包失败：未生成 $zipAbs" -ForegroundColor Red
        exit 1
    }
    Write-Host "插件包已生成: $zipAbs" -ForegroundColor Green
}
finally {
    Pop-Location
}
