#!/usr/bin/env bash
# Rust 模块编译脚本 (workspace: backup + downloader + file_ops + logger + http_client + db_client)
# Linux/macOS 使用；Windows 请使用 build_rust.bat
#
# 编译六个 Rust FFI 动态库并复制到对应 Flutter 平台目录：
#   Linux  -> linux/  （开发运行时与 CMake 打包均从这里取）
#   macOS  -> macos/  （Xcode build phase 复制进 app bundle）
set -euo pipefail
cd "$(dirname "$0")/rust"

echo "Compiling Rust workspace (backup + downloader + file_ops + logger + http_client + db_client)..."
cargo build --release

case "$(uname -s)" in
  Linux)
    echo "Copying .so files to linux/ ..."
    cp -f target/release/libxmc_backup.so ../linux/
    cp -f target/release/libxmc_downloader.so ../linux/
    cp -f target/release/libxmc_file_ops.so ../linux/
    cp -f target/release/libxmc_logger.so ../linux/
    cp -f target/release/libxmc_http_client.so ../linux/
    cp -f target/release/libxmc_db_client.so ../linux/
    ;;
  Darwin)
    echo "Copying .dylib files to macos/ ..."
    cp -f target/release/libxmc_backup.dylib ../macos/
    cp -f target/release/libxmc_downloader.dylib ../macos/
    cp -f target/release/libxmc_file_ops.dylib ../macos/
    cp -f target/release/libxmc_logger.dylib ../macos/
    cp -f target/release/libxmc_http_client.dylib ../macos/
    cp -f target/release/libxmc_db_client.dylib ../macos/
    ;;
  *)
    echo "Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac

echo "Done!"
