# 压缩设置 + 配置CSV中文注释导入

## 概要

两个独立功能：
1. **实例设置页新增压缩级别调节** — 每个实例独立存储压缩级别 (0-9)，通过 Rust FFI 传递到 Deflate 压缩器，替换当前硬编码的级别 6。
2. **配置编辑器新增 CSV 导入中文注释** — 用户可导入 CSV 文件覆盖/扩充硬编码的配置项中文说明，全局生效。

---

## 当前状态分析

### 压缩
- Rust `backup_directory` FFI 签名 ([lib.rs:58-65](file:///d:/xmcserverlancher/rust/src/lib.rs#L58-L65))：`src_path, dst_path, files_to_backup, files_count, progress_cb` — **无压缩级别参数**
- Rust 内部硬编码 `Compression::new(6)` ([lib.rs:247](file:///d:/xmcserverlancher/rust/src/lib.rs#L247))
- Dart `BackupService.backup()` ([backup_ffi.dart:193-235](file:///d:/xmcserverlancher/lib/services/backup_ffi.dart#L193-L235)) 不接受压缩级别参数
- `_BackupTab._startBackup()` ([instance_detail_screen.dart:475-542](file:///d:/xmcserverlancher/lib/screens/instance_detail_screen.dart#L475-L542)) 直接调用 `backupService.backup()`
- `shared_preferences: ^2.3.0` 已在 pubspec.yaml 中，但 lib 内**未使用** (Grep 无匹配)

### 配置中文注释
- `lib/data/config_descriptions.dart` ([L1-L1684](file:///d:/xmcserverlancher/lib/data/config_descriptions.dart)) — 硬编码 `const Map<String, String> _descriptions`，键格式 `文件名.配置项路径`
- `getConfigDescription(fileName, keyPath)` ([L13-L15](file:///d:/xmcserverlancher/lib/data/config_descriptions.dart#L13-L15)) — 同步查找 const map
- `config_editor_screen.dart` 在 `_ConfigField` 中调用 `getConfigDescription` ([L584-585](file:///d:/xmcserverlancher/lib/screens/config_editor_screen.dart#L584-L585)) 显示中文说明
- 无 CSV 包依赖，无 CSV 功能

---

## 改动计划

### 1. Rust: 添加压缩级别参数

**文件：** [rust/src/lib.rs](file:///d:/xmcserverlancher/rust/src/lib.rs)

- `backup_directory` FFI 函数签名新增 `compression_level: u32` 参数（放在 `progress_cb` 之前）
- `do_backup` 和 `do_backup_inner` 函数签名新增 `compression_level: u32`
- 将 `do_backup_inner` 中的 `Compression::new(6)` 改为 `Compression::new(compression_level)`（在 [L247](file:///d:/xmcserverlancher/rust/src/lib.rs#L247) 附近）
- 添加级别校验：`compression_level.min(9)` 确保 0-9 范围

**文件：** [rust/Cargo.toml](file:///d:/xmcserverlancher/rust/Cargo.toml) — 无需修改

### 2. Dart FFI: 传递压缩级别

**文件：** [lib/services/backup_ffi.dart](file:///d:/xmcserverlancher/lib/services/backup_ffi.dart)

- `BackupDirectoryC` / `BackupDirectoryDart` typedef 新增 `IntPtr compressionLevel` 参数（在 `progressCb` 之前）
- `_BackupRequest` 新增 `int compressionLevel` 字段
- `BackupService.backup()` 新增 `int compressionLevel` 命名参数
- `_backupIsolate` 中调用 `backupDirectory()` 时传入 `req.compressionLevel`

### 3. Dart: 压缩设置存储 + UI

**新增文件：** `lib/services/backup_settings.dart`
- `BackupSettings` 类，使用 SharedPreferences
- `getLevel(String instanceId)` → `Future<int>`，默认 6
- `setLevel(String instanceId, int level)` → `Future<void>`
- Key 格式：`backup_compression_level_<instanceId>`

**修改文件：** [lib/screens/instance_detail_screen.dart](file:///d:/xmcserverlancher/lib/screens/instance_detail_screen.dart)

- `_BackupTab` 新增 `instanceId` 字段（当前只有 `rootPath`），在 Tab 构造处传入 ([L226](file:///d:/xmcserverlancher/lib/screens/instance_detail_screen.dart#L226))
- `_BackupTab._startBackup()` 读取 `BackupSettings.getLevel(instanceId)` 并传给 `backupService.backup(..., compressionLevel: level)`
- `_SettingsTab` 新增 `_CompressionSettingsCard`：
  - StatefulWidget，包含 `instanceId`
  - 读取当前级别 → Slider (0-9, 整数步长)
  - 标签映射：0=仅存储, 1=最快, 3=快速, 6=标准(默认), 9=最佳
  - 拖动结束时保存到 SharedPreferences
  - 副文本显示当前级别和说明
- 在 `_SettingsTab.build()` 的 ListView 中插入 `_CompressionSettingsCard` ([L848-L866](file:///d:/xmcserverlancher/lib/screens/instance_detail_screen.dart#L848-L866))

### 4. CSV 导入配置中文注释

**修改文件：** [pubspec.yaml](file:///d:/xmcserverlancher/pubspec.yaml)
- 添加 `csv: ^6.0.0` 依赖

**新增文件：** `lib/services/config_annotation_service.dart`
- 单例 `ConfigAnnotationService`
- `Map<String, String> _imported` — 从文件加载的导入注释
- `init()` — 异步加载 `config_annotations.json`（位于 path_provider 的 app documents dir）
- `get(String fileName, String keyPath)` — 先查 `_imported`，再回退硬编码
- `importCsv(String csvContent)` → 解析 CSV → 存入 `_imported` → 持久化为 JSON 文件
- CSV 格式（2 列）：
  ```
  key,description
  server.properties.max-players,最大玩家数
  bukkit.yml.settings.update-folder,插件更新文件夹
  ```
- 第一行可为表头（检测 `key` 字样则跳过）

**修改文件：** [lib/data/config_descriptions.dart](file:///d:/xmcserverlancher/lib/data/config_descriptions.dart)
- `getConfigDescription` 改为先查 `ConfigAnnotationService`，再查硬编码 `_descriptions`
- 保持同步接口（`ConfigAnnotationService._imported` 在 app 启动时已加载完毕）

**修改文件：** [lib/main.dart](file:///d:/xmcserverlancher/lib/main.dart)
- 在 `runApp` 前调用 `await ConfigAnnotationService.instance.init()`

**修改文件：** [lib/screens/config_editor_screen.dart](file:///d:/xmcserverlancher/lib/screens/config_editor_screen.dart)
- 在配置文件列表面板的顶部（搜索框附近）添加「导入CSV」图标按钮
- 点击 → `FilePicker.pickFiles(type: csv)` → 读取文件内容 → `ConfigAnnotationService.instance.importCsv(content)` → SnackBar 反馈导入数量
- 导入后刷新当前表单（setState 重绘以显示新注释）

---

## 假设与决策

1. **压缩级别范围**：Deflate 标准 0-9。0=不压缩(仅存储)，1=最快，6=默认，9=最佳压缩比。用单个 Slider 即可同时控制「压缩比率」和「压缩速度」（二者是 Deflate 级别的两面）。
2. **CSV 注释为全局**：配置项的键（如 `server.properties.max-players`）在所有 Minecraft 服务器实例中含义相同，因此 CSV 导入为全局生效，不按实例区分。
3. **导入覆盖硬编码**：CSV 导入的注释优先级高于硬编码，允许用户自定义覆盖。
4. **持久化方式**：CSV 导入后转为 JSON 存储（`config_annotations.json`），避免每次启动重新解析 CSV。
5. **插件 Tab 不变**：保持 "Coming Soon" 占位符。
6. **不支持 CSV 导出**：用户只要求导入，不额外添加导出功能。

---

## 验证步骤

1. **Rust 编译**：`cd rust && cargo build --release` 通过
2. **Rust 测试**：`cd rust && cargo test --release` 通过
3. **Flutter 分析**：`flutter analyze` 无错误
4. **功能验证 — 压缩级别**：
   - 进入实例设置 Tab → 看到压缩级别 Slider，默认 6
   - 拖到 0 → 开始备份 → 验证生成的 ZIP 文件可解压、内容正确
   - 拖到 9 → 开始备份 → 验证 ZIP 文件可解压、文件更小（或差不多，取决于数据类型）
5. **功能验证 — CSV 导入**：
   - 准备测试 CSV 文件（含 2-3 个配置项注释）
   - 进入配置编辑器 → 点击导入CSV按钮 → 选择文件
   - 验证对应配置项显示导入的中文注释（覆盖硬编码）
   - 重启应用 → 验证导入的注释仍然生效（持久化）
6. **DLL 部署**：编译后复制到 `windows/runner/` 和项目根目录
