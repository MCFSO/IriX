# 原生插件系统设计：C ABI 动态库加载（Rust 宿主 + Flutter UI）

> 目标：让 IriX 支持从 zip 包安装**预编译的原生动态库插件**（`.dll` / `.so` / `.dylib`）。
> 插件通过 **C ABI** 与宿主通信，宿主不依赖任何 Rust 具体 ABI；所有跨边界数据用
> **JSON 字符串**传递。宿主侧（加载、事件分发、权限检查、错误隔离）用 **Rust** 实现
> （`xmc_plugin_host` crate），Flutter 只负责 UI 与经 FFI 调用管理接口。

---

## 1. 架构总览

```
┌────────────────────────── IriX 桌面客户端 ──────────────────────────┐
│                                                                    │
│  PluginManagerScreen（插件页：列表 / 详情 / 安装 / 启用禁用 / 卸载） │
│        │                                                           │
│  PluginService（Dart 业务入口，AppPaths.pluginsRoot() 为插件根目录） │
│        │                                                           │
│  PluginHostNative（lib/services/plugin_ffi.dart，dart:ffi）         │
│        │  plg_init / plg_list / plg_install / plg_toggle / ...      │
│        ▼                                                           │
│  xmc_plugin_host.dll/.so/.dylib（Rust 宿主）                        │
│     ├─ registry：扫描 / 安装 / 加载 / 权限门控 / 事件分发            │
│     ├─ manifest：JSON 解析 + semver 兼容 + 平台库选择 + zip-slip 防护│
│     └─ loader：libloading::Library + catch_unwind 隔离              │
│        │  plugin_init / plugin_handle_event / ...（C ABI）          │
│        ▼                                                           │
│  插件动态库 lib/<entry>.<platform>.<ext>（进程内，无沙箱）           │
└────────────────────────────────────────────────────────────────────┘
```

关键约束（与产品定位一致）：

| 约束 | 落地方式 |
|---|---|
| 不依赖 Rust ABI | 插件按 C ABI 导出固定符号，宿主用 `libloading` 取函数指针 |
| 数据用 JSON | 事件 payload 与返回值全是 JSON 字符串，不传结构体 |
| 字符串所有权明确 | 插件返回串用 `libc::malloc` 分配，宿主用 `libc::free` 释放 |
| 加载后常驻 | 原生库不做热卸载，禁用只标记状态 |
| 崩溃不拖垮主进程 | 每次插件调用 `catch_unwind`，异常插件标记 `crashed` 后不再调用 |

---

## 2. 插件包格式

```
myplugin.zip
├── README.md          # 给人看的描述，用于插件详情页预览
├── manifest.json      # 给程序读的元数据
└── lib/               # 按平台存放预编译动态库
    ├── plugin.windows-x64.dll
    ├── plugin.macos-arm64.dylib
    ├── plugin.macos-x64.dylib
    └── plugin.linux-x64.so
```

`manifest.json` 字段：

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✅ | 插件唯一标识（如 `com.example.myplugin`），同时作为安装目录名 |
| `name` | ✅ | 展示名称 |
| `version` | ✅ | 插件版本（semver） |
| `author` | | 作者 |
| `description` | | 描述 |
| `type` | | 插件类型，目前仅支持 `native`（默认 `native`） |
| `entry` | | 产物文件名主干（不含平台后缀），默认 `plugin` |
| `min_app_version` | | 宿主最低版本要求（semver），宿主版本低于它则拒绝安装 |
| `permissions` | | 权限声明数组，如 `["instance.read", "backup.write"]` |

示例：

```json
{
  "id": "com.example.myplugin",
  "name": "我的插件",
  "version": "1.0.0",
  "author": "...",
  "description": "...",
  "type": "native",
  "entry": "plugin",
  "min_app_version": "0.1.0",
  "permissions": ["instance.read", "backup.write"]
}
```

平台库文件名由 `entry` + 当前运行平台推导（`manifest.rs::platform_lib_name`）：

| 平台 | 文件名 |
|---|---|
| Windows x64 | `<entry>.windows-x64.dll` |
| macOS Apple Silicon | `<entry>.macos-arm64.dylib` |
| macOS Intel | `<entry>.macos-x64.dylib` |
| Linux x64 | `<entry>.linux-x64.so` |

找不到当前平台对应库时，插件状态为 `not_supported`（列表可见但不加载）。

---

## 3. 插件 C ABI 契约

插件**必须导出**以下符号（`extern "C"`，`no_mangle`）：

| 函数 | 签名 | 说明 |
|---|---|---|
| `plugin_init` | `() -> i32` | 初始化，返回 `0` 表示成功 |
| `plugin_name` | `() -> *const c_char` | 返回插件名（C 字符串） |
| `plugin_version` | `() -> *const c_char` | 返回插件版本 |
| `plugin_handle_event` | `(*const c_char, *const c_char) -> *const c_char` | 处理事件：`(event_type, payload_json)` → `result_json` |
| `plugin_shutdown` | `()` | 关闭时清理资源 |

### 字符串所有权约定

- `plugin_name` / `plugin_version` / `plugin_handle_event` 返回的字符串**由插件分配**（约定用 `libc::malloc`），宿主在读取后**用 `libc::free` 释放**（`abi.rs::free_c_string`）。
- 宿主返回给 Dart 的字符串走宿主自己的 `free_string`（`CString::into_raw` 分配），两者互不混用。
- 因此插件与宿主必须使用**同一套 C 运行时**（Windows 上同为 MSVC CRT），不要用插件自身语言的 GC 分配器返回字符串。

### 事件类型

宿主派发的事件类型（`abi.rs::event_type`）：

| 事件 | 所需权限 |
|---|---|
| `instance.started` / `instance.stopped` / `server.ready` / `server.log` | `instance.read` |
| `backup.completed` / `backup.read` | `backup.read` |
| `backup.start` / `backup.write` | `backup.write` |
| 其它未登记事件 | 无需权限 |

权限门控在**调用插件之前**由宿主完成：所需权限未在 `manifest.permissions` 中声明时，宿主不调用该插件，直接返回 `status = "permission_denied"`。

---

## 4. 宿主 FFI 接口

`xmc_plugin_host` 向 Flutter 暴露（`lib.rs`，全部同步调用）：

| 函数 | 说明 |
|---|---|
| `plg_init(base_dir, host_version) -> i32` | 初始化：建目录 → 处理待删除队列 → 扫描并加载已启用插件 |
| `plg_list() -> *mut c_char` | 插件列表 JSON 数组（不含 README 正文） |
| `plg_detail(id) -> *mut c_char` | 单个插件详情 JSON |
| `plg_readme(id) -> *mut c_char` | 插件 `README.md` 内容 |
| `plg_install(zip_path) -> *mut c_char` | 安装插件包，返回 `{ok, id?, message, warning?}`（`warning` 表示已装好但加载失败，如平台缺库） |
| `plg_uninstall(id) -> i32` | 卸载 |
| `plg_toggle(id, enabled) -> i32` | 启用 / 禁用 |
| `plg_dispatch(event_type, payload) -> *mut c_char` | 向所有启用插件派发事件，返回结果数组 |
| `plg_shutdown()` | 关闭全部插件（应用退出前） |
| `get_last_error()` / `free_string()` | 错误读取与宿主字符串释放 |

Dart 侧封装：`lib/services/plugin_ffi.dart`（`PluginHostNative`）、`lib/services/plugin_service.dart`（业务入口）。

---

## 5. 生命周期

```
安装 install(zip)
  └─ 解压到 <root>/.install-<ts>（逐条目安全校验，拒绝 ../ 与绝对路径）
     → 读 manifest.json → 校验 id/name/version/type/entry → semver 兼容检查
     → 重命名为 <root>/<id> → 写 state.json{enabled:true} → 载入
  ├─ 包本身无效（zip 损坏 / manifest 非法 / 版本不兼容）→ 安装失败（ok=false），不落盘
  └─ 包有效但加载失败（当前平台无对应动态库 / plugin_init 失败）
     → 仍算安装成功（ok=true），原因作为 warning 返回，并记为插件 status/error

加载 load
  └─ 选平台库 lib/<entry>.<platform>.<ext> → libloading::Library::new
     → 解析 5 个符号 → plugin_init()（catch_unwind）
     └─ 缺当前平台的库 → status = not_supported（列表可见，不加载）

启用 / 禁用 toggle
  └─ 写 state.json → 启用时按需载入；禁用仅标记 disabled，不再派发事件
     （已加载的原生库保持驻留，不做热卸载）

卸载 uninstall
  ├─ 未加载：直接删除插件目录并从注册表移除
  └─ 已加载：标记 pending_restart + 写入 <root>/.pending-delete.json
             → 下次 plg_init 时（进程重启、插件未加载）真正删除目录
```

> 「安装成功」与「加载成功」是两件事：包只要结构合法就会落盘并在列表中可见，
> 加载结果用状态徽章（`已启用` / `平台不支持` / `错误`）与错误文本呈现，
> 便于用户判断是包的问题还是当前平台/版本的问题。

插件根目录：`AppPaths.pluginsRoot()` = `<数据根目录>/plugins/native`（Windows 下优先非系统盘）。

---

## 6. 权限与安全

- **权限声明**：`manifest.permissions` 由插件自行声明，宿主在派发事件前校验（见第 3 节映射表）。
- **无沙箱**：原生插件运行在宿主进程内，可访问文件系统、网络与全部进程内存。安装 UI 会弹出明确的风险确认对话框，要求用户确认「我了解风险，继续安装」。
- **zip 安全**：解压逐条目校验，拒绝绝对路径、`..`、根/前缀组件（防 zip-slip）。
- **错误隔离**：`plugin_init` / `plugin_handle_event` / `plugin_shutdown` 全部用 `catch_unwind` 包裹；调用出错或 panic 的插件被标记为 `crashed`，后续事件不再派发给它（其它插件与主流程不受影响）。
- **后续工作**：插件签名与完整性校验（防篡改）尚未实现。

---

## 7. 插件开发指南

以 Rust 为例，创建一个 `cdylib`：

```toml
# Cargo.toml
[package]
name = "irix_example_plugin"
version = "1.0.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
libc = "0.2"
serde_json = "1"
```

```rust
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use serde_json::json;

/// 用 libc::malloc 分配以 NUL 结尾的字符串（宿主用 libc::free 释放）。
fn alloc_c_string(s: &str) -> *const c_char {
    let bytes = s.as_bytes();
    unsafe {
        let ptr = libc::malloc(bytes.len() + 1) as *mut u8;
        if ptr.is_null() { return std::ptr::null(); }
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
        *ptr.add(bytes.len()) = 0;
        ptr as *const c_char
    }
}

fn read_param(ptr: *const c_char) -> String {
    if ptr.is_null() { return String::new(); }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
}

#[no_mangle]
pub extern "C" fn plugin_init() -> c_int { 0 }

#[no_mangle]
pub extern "C" fn plugin_name() -> *const c_char { alloc_c_string("Example Plugin") }

#[no_mangle]
pub extern "C" fn plugin_version() -> *const c_char { alloc_c_string("1.0.0") }

#[no_mangle]
pub extern "C" fn plugin_handle_event(
    event_type: *const c_char,
    payload: *const c_char,
) -> *const c_char {
    let event = read_param(event_type);
    let payload: serde_json::Value =
        serde_json::from_str(&read_param(payload)).unwrap_or(json!({}));
    alloc_c_string(&json!({ "handled_event": event, "payload": payload }).to_string())
}

#[no_mangle]
pub extern "C" fn plugin_shutdown() {}
```

打包（`myplugin.zip`）：

```
manifest.json          # entry = "plugin"
README.md
lib/plugin.windows-x64.dll   # 由 target/release/<crate>.dll 改名而来
```

完整可运行示例见 [`plugins/example_plugin/`](../plugins/example_plugin/)，其构建与打包脚本为 `build_and_package.ps1`（Windows）/ `build_and_package.sh`（Linux/macOS）。

仓库根还**入库**了一个可直接安装试用的示例包 `plugins/irix-example-plugin.zip`（内置 Windows 版动态库）；
它同时是 `test/plugin_ffi_test.dart` 的测试夹具。CI 会在跑测试前用 `build_and_package.sh`
按 runner 平台重新打包，从而在 Linux 上真正加载 `.so` 走完安装→加载→分发→权限过滤链路。

---

## 8. 前端界面

`lib/screens/plugins_screen.dart`，入口为实例页底部工具区的「插件」磁贴：

- **列表页** `PluginManagerScreen`：插件卡片（名称 / 版本 / 作者 / 状态徽章 / 启用开关），右上角安装（zip 选择 → 风险确认 → 安装）与刷新。
- **详情页** `PluginDetailScreen`：元数据（ID / 类型 / 入口 / 最低宿主版本）、权限标签、描述、卸载按钮，以及 README 的 Markdown 渲染。

状态徽章取值：`已启用` / `已禁用` / `平台不支持` / `错误` / `重启生效` / `已崩溃`。

---

## 9. 相关文件

| 路径 | 说明 |
|---|---|
| `rust/plugin_host/src/abi.rs` | C ABI 类型与函数指针、字符串读/释放 |
| `rust/plugin_host/src/loader.rs` | libloading 加载 + catch_unwind 包裹调用 |
| `rust/plugin_host/src/manifest.rs` | manifest 解析、semver 兼容、平台库选择、zip-slip 防护 |
| `rust/plugin_host/src/registry.rs` | 注册表：安装/加载/切换/卸载/分发/权限门控 |
| `rust/plugin_host/src/lib.rs` | `plg_*` FFI 导出 |
| `lib/services/plugin_ffi.dart` | Dart FFI 封装（`PluginHostNative`） |
| `lib/services/plugin_service.dart` | Dart 业务入口（`PluginService`） |
| `lib/screens/plugins_screen.dart` | 插件列表页与详情页 |
| `plugins/example_plugin/` | 示例插件（cdylib）+ 打包脚本 |
| `plugins/irix-example-plugin.zip` | 已入库的示例插件包（可直接安装试用；同时是 FFI 测试夹具） |
| `test/plugin_ffi_test.dart` | 端到端 FFI 集成测试 |

新增 crates 时需同步的构建清单（`rust/Cargo.toml`、`build_rust.*`、各平台 CMake/Xcode、两个 CI workflow）见 `CLAUDE.md` 的 “Adding a new Rust crate”，并用 `dart tool/ffi_dlls.dart lists` 自检。
