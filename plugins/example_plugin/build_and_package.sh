#!/usr/bin/env bash
# 打包示例插件为 IriX 插件 zip 包（Linux/macOS）
# 用法：在项目根或本目录执行 `./build_and_package.sh`
set -euo pipefail
cd "$(dirname "$0")"

echo "构建示例插件 (cargo build --release) ..."
cargo build --release

case "$(uname -s)" in
  Linux)  src="target/release/libirix_example_plugin.so";  dst="plugin.linux-x64.so" ;;
  Darwin) src="target/release/libirix_example_plugin.dylib"; dst="plugin.macos-$(uname -m | sed 's/x86_64/x64/').dylib" ;;
  *) echo "不支持的平台: $(uname -s)" >&2; exit 1 ;;
esac

if [ ! -f "$src" ]; then
  echo "未找到构建产物: $src" >&2
  exit 1
fi

pkg="package"
rm -rf "$pkg"
mkdir -p "$pkg/lib"
cp manifest.json "$pkg/manifest.json"
cp README.md "$pkg/README.md"
cp "$src" "$pkg/lib/$dst"

zip="../irix-example-plugin.zip"
# 统一成绝对路径：zip 分支在 (cd "$pkg") 子 shell 内执行，相对的 "../" 会少一级
# （落到插件目录而不是仓库 plugins/ 下），必须先把目标路径固定下来。
zip_abs="$(cd "$(dirname "$zip")" && pwd)/$(basename "$zip")"
rm -f "$zip_abs"

if command -v zip >/dev/null 2>&1; then
  (cd "$pkg" && zip -r "$zip_abs" .) >/dev/null
else
  # 回退：部分环境没有 zip 命令，用 python3 的 zipfile 生成等价包。
  python3 - "$pkg" "$zip_abs" <<'PY'
import os, sys, zipfile
pkg, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(pkg):
        for name in files:
            full = os.path.join(root, name)
            z.write(full, os.path.relpath(full, pkg))
PY
fi

if [ ! -f "$zip_abs" ]; then
  echo "打包失败：未生成 $zip_abs" >&2
  exit 1
fi
echo "插件包已生成: $zip_abs"
