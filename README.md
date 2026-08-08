# IriX（X Minecraft Server Launcher）

Minecraft 服务器管理工具。Flutter 构建跨平台 UI，Rust 提供高性能底层支持（压缩、下载、文件操作），覆盖实例管理、核心下载、插件市场、备份压缩、文件管理、内网穿透、节点管理与 AI 助手等完整工作流。

AI作品轻喷

## 功能

- **服务器实例管理** —— 创建、导入、配置多个 Minecraft 服务端实例，一键启停
- **核心下载** —— 从 MSL API 获取 Paper、Purpur、Folia 等服务端核心
- **插件 & Mod 市场** —— 浏览和安装 Modrinth / Hangar 上的资源，支持关键词搜索与版本筛选
- **节点管理** —— 统一管理 MCSManager 面板与 IriX 本地 Go 守护进程节点，远程查看实例、文件与系统状态
- **配置文件编辑器** —— 内置 YAML 语法高亮、行号、撤销/重做、注释说明
- **文件管理器** —— 本地与远程文件树的复制、粘贴、移动、重命名，含回收站（7 天自动清理）
- **备份 & 压缩** —— Rust 驱动的 ZIP 并行压缩与解压，支持大文件流式下载（分片 + 断点续传）
- **内网穿透** —— 集成 OpenFrp、SakuraFrp、HayFrp、ChmlFrp、OFrp 与自建 frps 等隧道服务
- **远程数据库管理** —— 连接 MySQL / MariaDB / PostgreSQL / Redis（Rust 驱动，无 OpenSSL），浏览库表并执行查询
- **AI 助手** —— 本地 Ollama 对话，内置 MCP 服务器（可查看/操作实例、备份等）
- **知识库（RAG）** —— 导入 .txt/.md 文档构建本地向量库，AI 对话自动检索相关内容作答
- **暗色主题** —— 全局暗色 UI

## 技术栈

| 层 | 技术 |
|---|---|
| UI | Flutter 3.x, Provider |
| 网络 | ureq + rustls（Rust，Dart 侧禁用 package:http） |
| 存储 | SQLite（sqflite_common_ffi）, SharedPreferences |
| 压缩 | flate2 (zlib-ng) + crc32fast, rayon 并行 |
| 文件操作 | walkdir, serde_json, Rust FFI |
| 远程数据库 | Rust mysql / postgres / redis 驱动（db_client FFI） |
| 知识库 | rusqlite + sqlite-vec（vector_store FFI）；embedding 由 Rust HTTP 调 AI 模型 API 生成（Dart 侧组装请求） |

## 构建

### 前置条件

- Flutter SDK >= 3.12
- Rust 工具链（rustc, cargo）
- Windows：Visual Studio 2022（C++ 桌面开发）
- macOS：Xcode 15+
- Linux：GTK 3, CMake

### 步骤

```bash
# 1. 编译 Rust 动态库（workspace 一次编译全部 crate）
cargo build --release --manifest-path rust/Cargo.toml
# 或 Windows 下双击 build_rust.bat，Linux/macOS 运行 ./build_rust.sh
# （脚本会自动复制产物到 windows/runner/、linux/、macos/）

# 2. 获取 Flutter 依赖
flutter pub get

# 3. 运行
flutter run
```

### 测试

```bash
flutter test            # FFI 集成测试（*_ffi_test.dart）需先编译并复制 Rust 动态库
flutter test test/knowledge_ffi_test.dart   # 只跑单个 FFI 测试
```

### 构建发行版

```bash
# Windows (.exe)
flutter build windows --release

# macOS (.app)
flutter build macos --release

# Linux
flutter build linux --release
```

## 项目结构

```
irix/
├── lib/                     # Flutter 应用层
│   ├── main.dart
│   ├── models/              # 数据模型（实例、节点、市场、远程）
│   ├── screens/             # 页面（首页、节点、市场、文件、配置、FRP、AI、数据库等）
│   ├── services/            # API 服务（Modrinth、Hangar、MSL、节点、FRP、备份等）
│   ├── state/               # 状态管理（AppState、NodeState）
│   ├── utils/               # 工具（Docker 可见性等）
│   └── widgets/             # 通用组件（添加节点向导等）
├── rust/                    # Rust 原生库（FFI 动态库）
│   ├── backup/              # ZIP 并行压缩
│   ├── downloader/          # HTTP 流式/分片下载（断点续传）
│   ├── http_client/         # 通用 HTTP 请求（ureq + rustls）
│   ├── file_ops/            # 文件扫描、移动、回收站
│   ├── db_client/           # 远程数据库客户端（MySQL/PostgreSQL/Redis）
│   ├── logger/              # 日志
│   └── vector_store/        # 向量知识库（rusqlite + sqlite-vec）
├── windows/                 # Windows 平台代码
├── macos/                   # macOS 平台代码
├── linux/                   # Linux 平台代码
└── test/                    # 测试
```

## 打包

使用 [Fastforge](https://github.com/localleon/fastforge) 进行各平台打包：

```bash
# Windows MSIX
fastforge config --platform windows --format msix

# macOS DMG
fastforge config --platform macos --format dmg

# Linux (AppImage / deb / rpm)
fastforge config --platform linux --format appimage
```

各平台打包配置位于对应 `dist` 目录下。

## 许可

MIT License, Copyright (c) 2026 MCFSO
