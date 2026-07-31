# 重构计划

## Task 1: 市场"加载器"改名为"核心"并精简选项

**目标文件**: `lib/screens/marketplace_screen.dart`

**改动**:
- 所有 UI 中将"加载器"标签改为"核心"
- `_loaders` 列表精简：移除 liteloader、risugami's modloader 等已废弃加载器（已有这部分过滤逻辑，确认生效）
- 加载器筛选 chip 只在 Modrinth 源显示（Hangar 只下载插件，无需加载器筛选）
- 确保搜素请求中 loader 参数传递正确

---

## Task 2: 删除全局设置中的"动画效果"开关

**目标文件**:
- `lib/screens/home_screen.dart` — 删除 `_SettingsDialog` 中的 `SwitchListTile("动画效果")`
- `lib/state/app_state.dart` — 删除 `animationsEnabled` 字段、getter、setter、`notifyListeners()` 调用
- `lib/services/download_settings.dart` — 删除 `setAnimationsEnabled()`/`getAnimationsEnabled()` 方法
- `lib/utils/apple_widgets.dart` — 删除所有 `animationsEnabled` 判断，始终执行动画（弹簧缩放、页面过渡、对话框淡入）

---

## Task 3: 配置文件编辑器添加行号

**目标文件**: `lib/screens/config_editor_screen.dart`

**改动**:
- 在 `_buildTextEditor()` 方法中，将现有 `TextField` 替换为带行号的自定义组件
- 左侧添加固定宽度的行号列（等宽字体、灰色、右对齐），与编辑区滚动同步
- 行号列和编辑区使用同一个 `ScrollController` 保证同步

---

## Task 4: 文件管理器集成编辑器入口（支持编辑、保存、撤回）

**目标文件**: `lib/screens/file_manager_screen.dart`、`lib/services/config_service.dart`

**改动**:
- 文件管理器保留所有文件类型展示（.jar、.zip、.yml 等都正常显示，图标不变）
- 对配置文件（`.yml`、`.yaml`、`.properties`、`.json`、`.toml`、`.conf`、`.cfg`），双击或右键菜单增加"编辑"选项
- 点击编辑后跳转到 `ConfigEditorScreen`，自动打开该文件（带行号、保存、语法高亮）
- 编辑器需要支持撤回（undo）功能
- **ConfigService 扩展**: `_tryAddConfig()` 增加对 `.json`、`.toml`、`.conf`、`.cfg` 的识别；`readConfig()` 增加 JSON decode 解析；`writeConfig()` 增加 JSON encode 序列化（`code_highlight.dart` 已支持 JSON/TOML 高亮，无需改动）

---

## Task 5: JAR 文件默认以压缩包形式打开

**目标文件**:
- `lib/screens/file_manager_screen.dart` — 双击 .jar 时不再无操作，改为打开压缩包浏览视图
- 新增 `lib/screens/archive_viewer_screen.dart` — 压缩包内容浏览页面

**改动**:
- 在 `file_manager_screen.dart` 中，.jar / .zip 文件双击时导航到 `ArchiveViewerScreen`
- `ArchiveViewerScreen`：读取 zip 内容，以列表形式展示文件名、大小、修改日期
- 支持从压缩包中提取单个文件到指定目录
