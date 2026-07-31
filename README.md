# IriX

Minecraft 服务器管理工具。Flutter 构建 UI，Rust 提供高性能底层支持，涵盖实例管理、插件市场、备份压缩、文件管理等完整工作流。

## 功能

- **服务器实例管理** —— 创建、导入、配置多个 Minecraft 服务端实例，一键启停
- **核心下载** —— 从 Modrinth / Hangar / MSL 镜像获取 Paper、Purpur、Folia 等服务端核心
- **插件 & Mod 市场** —— 浏览和安装 Modrinth / Hangar 上的一键汉化资源，支持关键词搜索与版本筛选
- **配置文件编辑器** —— 内置 YAML 语法高亮、行号、撤销/重做、注释说明
- **文件管理器** —— 文件树的复制、粘贴、移动、重命名，含回收站（7 天自动清理）
- **备份 & 压缩** —— Rust 驱动的 ZIP 并行压缩与解压，支持大文件流式下载（分片 + 断点续传）
- **暗色主题** —— 全局暗色 UI

## 技术栈

| 层 | 技术 |
|---|---|
| UI | Flutter 3.x, Provider |
| 网络 | ureq + rustls（Rust）, HTTP（Dart） |
| 存储 | SharedPreferences, 本地 JSON |
| 压缩 | flate2 (zlib-ng) + crc32fast, rayon 并行 |
| 文件操作 | walkdir, serde_json, Rust FFI |

## 构建

### 前置条件

- Flutter SDK >= 3.12
- Rust 工具链（rustc, cargo）
- Windows：Visual Studio 2022（C++ 桌面开发）
- macOS：Xcode 15+
- Linux：GTK 3, CMake

### 步骤

```bash
# 1. 编译 Rust 动态库
cargo build --release
# 或 Windows 下双击
build_rust.bat

# 2. 复制 Rust 产物到对应位置
# Windows: 拷贝 rust/target/release/*.dll 到 windows/runner/
# Linux:   拷贝 rust/target/release/*.so 到 linux/
# macOS:   拷贝 rust/target/release/*.dylib 到 macos/

# 3. 获取 Flutter 依赖
flutter pub get

# 4. 运行
flutter run
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
│   ├── models/              # 数据模型
│   ├── screens/             # 页面（首页、市场、文件管理、配置编辑器等）
│   ├── services/            # API 服务（Modrinth、Hangar、下载器、备份）
│   ├── state/               # 状态管理（Provider）
│   └── utils/               # 工具（代码高亮、命名等）
├── rust/                    # Rust 原生库
│   ├── backup/              # ZIP 并行压缩
│   ├── downloader/          # HTTP 流式/分片下载
│   └── file_ops/            # 文件扫描、移动、回收站
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
