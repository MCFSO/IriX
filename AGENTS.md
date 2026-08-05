# AGENTS.md

## 项目概览

IriX（X Minecraft Server Launcher）—— Minecraft 服务器管理工具。Flutter 构建跨平台 UI，Rust 提供高性能底层支持（ZIP 压缩、下载、文件操作、日志），通过 FFI 交互。

## 技术栈

- **UI**: Flutter 3.x (Dart SDK >= 3.12), Provider 状态管理
- **Rust**: workspace（backup / downloader / file_ops / logger），release profile 开启 `opt-level = 3` + `lto`
- **存储**: SQLite（sqflite_common_ffi）、SharedPreferences
- **FFI**: `package:ffi` 调用 `xmc_backup.dll`、`xmc_downloader.dll`、`xmc_file_ops.dll`、`xmc_logger.dll`
- **数据库**: mysql_dart, postgres, redis
- **网络**: Rust 侧 ureq + rustls；Dart 侧 http

## 目录结构

```
lib/
├── main.dart              # 入口
├── models/                # 数据模型（实例、节点、市场、远程）
├── screens/               # 页面（home、nodes、marketplace、frp、database、ai 等）
├── services/              # API 服务与 FFI 封装（*_ffi.dart、*_api_service.dart、*_provider.dart）
├── state/                 # AppState、NodeState
├── utils/                 # 工具（docker_visibility、naming、code_highlight 等）
├── widgets/               # 通用组件
└── data/                  # 静态数据（config_descriptions、server_cores）
rust/
├── backup/                # ZIP 并行压缩/解压
├── downloader/            # HTTP 流式/分片下载（断点续传）
├── file_ops/              # 文件扫描、移动、回收站
└── logger/                # 日志
test/                      # Flutter 测试
windows/ linux/ macos/     # 平台代码（rust/runner 目录存 FFI 动态库）
dist/ build/               # 打包产物，勿修改
```

## 常用命令

```bash
# Rust FFI 库编译（Windows 直接双击 build_rust.bat）
cargo build --release --manifest-path rust/Cargo.toml
# 产物复制到 windows/runner/（build_rust.bat 已处理）

# Dart 依赖
flutter pub get

# 开发运行 / 测试 / 分析
flutter run
flutter test
flutter analyze

# 发行构建
flutter build windows --release
```

## 关键约定

- **修改 Rust 代码后**必须先重新编译并复制 DLL 到 `windows/runner/`，否则运行的是旧动态库
- Rust 导出函数通过 FFI 调用，Dart 侧封装在 `lib/services/*_ffi.dart`（如 `backup_ffi.dart`、`file_ops_ffi.dart`、`logger_ffi.dart`）
- 状态管理统一走 `lib/state/`（Provider），不在 widget 内直接持有全局状态
- 持久化数据用 SQLite（`instance_store.dart`、`node_store.dart`、`trash_store.dart` 等），轻量设置用 SharedPreferences
- 新增页面放 `lib/screens/`，新增 API 服务放 `lib/services/`，命名遵循现有 `*_api_service.dart` / `*_provider.dart` 模式
- 全局暗色主题，UI 组件参考 `lib/utils/apple_widgets.dart`
- 勿编辑 `rust/target/`、`build/`、`dist/` 等生成目录
