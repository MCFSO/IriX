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

    # 打成 zip
    $zip = "../irix-example-plugin.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path "$pkg/*" -DestinationPath $zip
    Write-Host "插件包已生成: $zip" -ForegroundColor Green
}
finally {
    Pop-Location
}
