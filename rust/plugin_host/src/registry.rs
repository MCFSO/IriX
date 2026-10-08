// 插件注册表：扫描 / 安装 / 加载 / 启用禁用 / 卸载 / 事件分发 / 权限检查
//
// 生命周期约定（与产品约束一致）：
// - 原生库加载后常驻，不支持热卸载；"禁用" 只是标记状态，不再派发事件。
// - "卸载" 对已加载插件只做标记（pending_restart），真正删文件在下次启动
//   （进程重启后插件未被加载，可直接删除）时完成。
// - 每次外部调用都用 catch_unwind 包裹，插件异常只影响自身，不拖垮主进程。

use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::loader::LoadedPlugin;
use crate::manifest::{self, Manifest};

/// 插件运行状态（用于 UI 展示）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum PluginStatus {
    /// 已加载并启用，可接收事件。
    Loaded,
    /// 已禁用（不派发事件，但仍驻留）。
    Disabled,
    /// 当前平台没有对应动态库。
    NotSupported,
    /// 初始化/加载失败。
    Error,
    /// 已安排卸载，重启后生效。
    PendingRestart,
    /// 事件调用中崩溃，已标记不再调用。
    Crashed,
}

impl PluginStatus {
    fn as_str(&self) -> &'static str {
        match self {
            PluginStatus::Loaded => "loaded",
            PluginStatus::Disabled => "disabled",
            PluginStatus::NotSupported => "not_supported",
            PluginStatus::Error => "error",
            PluginStatus::PendingRestart => "pending_restart",
            PluginStatus::Crashed => "crashed",
        }
    }
}

/// 单个插件条目（目录 + manifest + 运行时句柄）。
pub struct PluginEntry {
    pub manifest: Manifest,
    pub dir: PathBuf,
    /// 用户意图（是否启用），持久化在 `<dir>/state.json`。
    pub enabled: bool,
    /// 已加载的运行时句柄；为 None 表示未加载/禁用/不支持/失败。
    pub loaded: Option<LoadedPlugin>,
    pub status: PluginStatus,
    pub error: Option<String>,
    /// 是否已安排卸载（重启后生效）。
    pub pending_restart: bool,
}

/// 单个事件派发结果（返回给 Flutter 的 JSON）。
#[derive(Serialize)]
pub struct DispatchResult {
    pub id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// success / permission_denied / panic
    pub status: String,
}

impl PluginEntry {
    /// 插件展示信息（列表 / 详情用）。readme 单独读取。
    pub fn info(&self) -> serde_json::Value {
        serde_json::json!({
            "id": self.manifest.id,
            "name": self.manifest.name,
            "version": self.manifest.version,
            "author": self.manifest.author,
            "description": self.manifest.description,
            "type": self.manifest.plugin_type,
            "entry": self.manifest.entry,
            "min_app_version": self.manifest.min_app_version,
            "permissions": self.manifest.permissions,
            "enabled": self.enabled,
            "loaded": self.loaded.is_some(),
            "status": self.status.as_str(),
            "error": self.error,
            "pending_restart": self.pending_restart,
            "dir": self.dir.to_string_lossy(),
        })
    }
}

/// 插件注册表。
pub struct PluginRegistry {
    pub base_dir: PathBuf,
    pub host_version: String,
    pub plugins: BTreeMap<String, PluginEntry>,
}

impl PluginRegistry {
    /// 初始化：创建目录、处理待删除队列、扫描并加载已启用插件。
    pub fn init(base_dir: PathBuf, host_version: String) -> Result<Self, String> {
        fs::create_dir_all(&base_dir).map_err(|e| format!("创建插件目录失败: {e}"))?;

        let mut registry = Self {
            base_dir,
            host_version,
            plugins: BTreeMap::new(),
        };
        registry.process_pending_deletes()?;
        registry.scan()?;
        Ok(registry)
    }

    /// 扫描插件根目录下的每个子目录，读取 manifest 并加载。
    fn scan(&mut self) -> Result<(), String> {
        let entries = match fs::read_dir(&self.base_dir) {
            Ok(it) => it,
            Err(_) => return Ok(()),
        };
        for dir in entries.flatten() {
            let path = dir.path();
            if !path.is_dir() {
                continue;
            }
            let name = dir.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                continue; // 跳过隐藏/临时目录
            }
            if let Some(entry) = self.load_entry_from_dir(&path)? {
                self.plugins.insert(entry.manifest.id.clone(), entry);
            }
        }
        Ok(())
    }

    /// 从单个插件目录加载条目（读取 manifest 与启用状态）。
    fn load_entry_from_dir(&self, dir: &Path) -> Result<Option<PluginEntry>, String> {
        let manifest_path = dir.join("manifest.json");
        if !manifest_path.exists() {
            return Ok(None);
        }
        let bytes =
            fs::read(&manifest_path).map_err(|e| format!("读取 manifest.json 失败: {e}"))?;
        let manifest = match manifest::parse_manifest(&bytes) {
            Ok(m) => m,
            Err(e) => {
                return Err(format!("{}: {e}", dir.display()));
            }
        };
        if manifest.validate().is_err() {
            // manifest 无效但目录存在：保留条目以便 UI 提示，但不加载。
            return Ok(Some(Self::make_entry(
                dir.to_path_buf(),
                manifest,
                None,
                PluginStatus::Error,
                Some("manifest 校验失败".into()),
            )));
        }
        let enabled = read_state_enabled(dir).unwrap_or(true);
        let mut entry =
            Self::make_entry(dir.to_path_buf(), manifest, None, PluginStatus::Disabled, None);
        entry.enabled = enabled;

        if enabled {
            Self::try_load(&mut entry);
        }
        Ok(Some(entry))
    }

    fn make_entry(
        dir: PathBuf,
        manifest: Manifest,
        loaded: Option<LoadedPlugin>,
        status: PluginStatus,
        error: Option<String>,
    ) -> PluginEntry {
        let enabled = read_state_enabled(&dir).unwrap_or(true);
        PluginEntry {
            manifest,
            dir,
            enabled,
            loaded,
            status,
            error,
            pending_restart: false,
        }
    }

    /// 尝试加载一个条目：选平台库 + libloading + plugin_init。
    /// 失败时更新 status/error，但不抛错（不拖垮其它插件）。
    pub fn try_load(entry: &mut PluginEntry) {
        let lib_name = match manifest::platform_lib_name(&entry.manifest.entry) {
            Some(n) => n,
            None => {
                entry.status = PluginStatus::NotSupported;
                entry.error = Some(format!(
                    "当前平台没有对应动态库（{}）",
                    manifest::platform_target()
                ));
                return;
            }
        };
        let lib_path = entry.dir.join("lib").join(&lib_name);
        if !lib_path.exists() {
            entry.status = PluginStatus::NotSupported;
            entry.error = Some(format!("缺少动态库 {}", lib_name));
            return;
        }
        match LoadedPlugin::load(&lib_path) {
            Ok(loaded) => match loaded.init() {
                Ok(()) => {
                    entry.loaded = Some(loaded);
                    entry.status = PluginStatus::Loaded;
                    entry.error = None;
                }
                Err(e) => {
                    entry.status = PluginStatus::Error;
                    entry.error = Some(format!("plugin_init 失败: {e}"));
                }
            },
            Err(e) => {
                entry.status = PluginStatus::Error;
                entry.error = Some(e);
            }
        }
    }

    /// 立即尝试验载（用于启动时/启用时），失败返回错误但保留字段状态。
    #[allow(dead_code)]
    pub fn load_enabled(&mut self, id: &str) -> Result<(), String> {
        let entry = self
            .plugins
            .get_mut(id)
            .ok_or_else(|| "插件不存在".to_string())?;
        if entry.status == PluginStatus::Loaded {
            return Ok(());
        }
        Self::try_load(entry);
        if entry.error.is_some() {
            return Err(entry.error.clone().unwrap_or_default());
        }
        Ok(())
    }

    /// 安装：解压 zip → 校验 manifest → 落目录 → 写 state → 加载。
    ///
    /// 返回 `(插件 id, 可选加载告警)`。只要**包本身有效**（zip 可解、manifest 合法、
    /// 版本兼容）就算安装成功；若随后加载失败（当前平台缺对应动态库、plugin_init
    /// 失败等），不视为安装失败，而是把原因作为 warning 返回并记录在插件的
    /// status/error 上——UI 用状态徽章展示，也便于用户排查。
    pub fn install(&mut self, zip_path: &str) -> Result<(String, Option<String>), String> {
        let zip_file = Path::new(zip_path);
        if !zip_file.exists() {
            return Err("安装包不存在".into());
        }

        // 1. 解压到一个临时目录（需防 zip-slip）。
        let temp = self.base_dir.join(format!(".install-{}", rand_suffix()));
        fs::create_dir_all(&temp).map_err(|e| format!("创建临时目录失败: {e}"))?;
        if let Err(e) = self.extract_zip_safe(zip_file, &temp) {
            let _ = fs::remove_dir_all(&temp);
            return Err(e);
        }

        // 2. 读取并校验 manifest。
        let manifest_path = temp.join("manifest.json");
        if !manifest_path.exists() {
            let _ = fs::remove_dir_all(&temp);
            return Err("安装包缺少 manifest.json".into());
        }
        let bytes = fs::read(&manifest_path).map_err(|e| format!("读取 manifest 失败: {e}"))?;
        let m = match manifest::parse_manifest(&bytes) {
            Ok(m) => m,
            Err(e) => {
                let _ = fs::remove_dir_all(&temp);
                return Err(e);
            }
        };
        if let Err(e) = m.validate() {
            let _ = fs::remove_dir_all(&temp);
            return Err(e);
        }
        if let Err(e) = m.compatible_with(&self.host_version) {
            let _ = fs::remove_dir_all(&temp);
            return Err(e);
        }

        // 3. 目标目录 = 插件根 / <id>。已存在则视为升级/重装：先删除（若被加载会失败）。
        let id = m.id.clone();
        let target = self.base_dir.join(&id);
        if target.exists() {
            if let Some(existing) = self.plugins.get(&id) {
                if existing.loaded.is_some() {
                    let _ = fs::remove_dir_all(&temp);
                    return Err("插件已加载，无法覆盖安装，请先禁用或重启".into());
                }
            }
            fs::remove_dir_all(&target).map_err(|e| format!("移除旧插件目录失败: {e}"))?;
        }
        fs::rename(&temp, &target).map_err(|e| format!("移动到插件目录失败: {e}"))?;

        // 4. 写状态（默认启用）。
        write_state_enabled(&target, true)?;

        // 5. 更新注册表并尝试加载。加载失败只作为 warning 返回（包已装好，
        //    状态/原因记录在 entry 上，UI 用状态徽章展示）。
        let mut entry = Self::make_entry(target, m, None, PluginStatus::Disabled, None);
        entry.enabled = true;
        Self::try_load(&mut entry);
        let warning = entry.error.clone();
        self.plugins.insert(id.clone(), entry);

        Ok((id, warning))
    }

    /// 安全解压：逐条目读取，遇到越出目标目录的路径直接拒绝。
    fn extract_zip_safe(&self, zip_path: &Path, dest: &Path) -> Result<(), String> {
        let file = fs::File::open(zip_path).map_err(|e| format!("打开 zip 失败: {e}"))?;
        let mut archive = zip::ZipArchive::new(file).map_err(|e| format!("解析 zip 失败: {e}"))?;
        for i in 0..archive.len() {
            let mut entry = archive
                .by_index(i)
                .map_err(|e| format!("读取 zip 条目失败: {e}"))?;
            let name = entry.name().to_string();
            let out_path = manifest::safe_entry_path(dest, &name)
                .ok_or_else(|| format!("zip 内含非法路径，已拒绝: {name}"))?;
            if entry.is_dir() {
                fs::create_dir_all(&out_path)
                    .map_err(|e| format!("创建目录失败 {out_path:?}: {e}"))?;
                continue;
            }
            if let Some(parent) = out_path.parent() {
                fs::create_dir_all(parent)
                    .map_err(|e| format!("创建父目录失败 {parent:?}: {e}"))?;
            }
            let mut out = fs::File::create(&out_path)
                .map_err(|e| format!("创建文件失败 {out_path:?}: {e}"))?;
            io::copy(&mut entry, &mut out)
                .map_err(|e| format!("写入文件失败 {out_path:?}: {e}"))?;
        }
        Ok(())
    }

    /// 卸载：已加载 → 标记 pending，入删除队列；未加载 → 直接删除。
    pub fn uninstall(&mut self, id: &str) -> Result<(), String> {
        // 先从插件表取出；若不存在则直接尝试删除目录（容错）。
        let entry_opt = self.plugins.get(id);
        let dir = if let Some(e) = entry_opt {
            e.dir.clone()
        } else {
            self.base_dir.join(id)
        };

        if let Some(entry) = self.plugins.get_mut(id) {
            if entry.loaded.is_some() {
                // 无法安全卸载：标记重启后生效，并写入待删除队列。
                entry.pending_restart = true;
                entry.enabled = false;
                entry.status = PluginStatus::PendingRestart;
                self.queue_pending_delete(id)?;
                return Ok(());
            }
        }

        // 未加载：直接删除目录并移除注册条目。
        if dir.exists() {
            fs::remove_dir_all(&dir).map_err(|e| format!("删除插件目录失败: {e}"))?;
        }
        self.plugins.remove(id);
        Ok(())
    }

    /// 启用/禁用（持久化 + 按需载入/标记）。返回结果，加载失败时给出错误。
    pub fn toggle(&mut self, id: &str, enabled: bool) -> Result<(), String> {
        if !self.plugins.contains_key(id) {
            return Err("插件不存在".into());
        }
        let entry = self.plugins.get_mut(id).unwrap();
        if entry.pending_restart {
            return Err("插件已安排卸载，不能切换".into());
        }
        entry.enabled = enabled;
        write_state_enabled(&entry.dir, enabled)?;

        if enabled {
            if entry.loaded.is_none() {
                Self::try_load(entry);
            }
            if entry.status != PluginStatus::Loaded {
                return Err(entry.error.clone().unwrap_or("加载失败".into()));
            }
        } else {
            // 保持驻留，仅标记状态。
            entry.status = PluginStatus::Disabled;
            entry.error = None;
        }
        Ok(())
    }

    /// 派发事件到所有已启用且已加载的插件（带权限过滤）。
    pub fn dispatch(&mut self, event_type: &str, payload: &str) -> Vec<DispatchResult> {
        let required = event_required_permissions(event_type);
        let mut results = Vec::new();

        let ids: Vec<String> = self.plugins.keys().cloned().collect();
        for id in ids {
            let entry = match self.plugins.get_mut(&id) {
                Some(e) => e,
                None => continue,
            };
            // 跳过未启用 / 未加载 / 已崩溃 / 待卸载。
            if !entry.enabled
                || entry.pending_restart
                || entry.status == PluginStatus::Crashed
                || entry.loaded.is_none()
            {
                continue;
            }
            // 权限过滤：所需权限必须全部声明。
            if !required.is_empty() {
                let granted = required
                    .iter()
                    .all(|p| entry.manifest.permissions.iter().any(|x| x == p));
                if !granted {
                    results.push(DispatchResult {
                        id: id.clone(),
                        ok: false,
                        result: None,
                        error: Some(format!("缺少权限: {}", required.join(", "))),
                        status: "permission_denied".into(),
                    });
                    continue;
                }
            }

            let loaded = entry.loaded.as_ref().unwrap();
            match loaded.handle_event(event_type, payload) {
                Ok(s) => {
                    results.push(DispatchResult {
                        id,
                        ok: true,
                        result: Some(s),
                        error: None,
                        status: "success".into(),
                    });
                }
                Err(e) => {
                    // 崩溃或出错：标记该插件为异常，后续不再调用。
                    entry.status = PluginStatus::Crashed;
                    entry.error = Some(e.clone());
                    results.push(DispatchResult {
                        id,
                        ok: false,
                        result: None,
                        error: Some(e),
                        status: "panic".into(),
                    });
                }
            }
        }
        results
    }

    /// 关闭所有已加载插件（应用退出时调用）。
    pub fn shutdown_all(&mut self) {
        for entry in self.plugins.values_mut() {
            if let Some(loaded) = entry.loaded.take() {
                loaded.shutdown();
            }
        }
    }

    /// 读 README 内容（插件详情预览用）。
    pub fn readme(&self, id: &str) -> String {
        let Some(entry) = self.plugins.get(id) else {
            return String::new();
        };
        let readme = entry.dir.join("README.md");
        if readme.exists() {
            fs::read_to_string(&readme).unwrap_or_default()
        } else {
            String::new()
        }
    }

    // ===== 待删除队列 =====

    fn pending_deletes_path(&self) -> PathBuf {
        self.base_dir.join(".pending-delete.json")
    }

    fn queue_pending_delete(&mut self, id: &str) -> Result<(), String> {
        let path = self.pending_deletes_path();
        let mut list: Vec<String> = if path.exists() {
            fs::read_to_string(&path)
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default()
        } else {
            Vec::new()
        };
        if !list.iter().any(|x| x == id) {
            list.push(id.to_string());
        }
        let json = serde_json::to_string(&list).map_err(|e| e.to_string())?;
        write_file(&path, json.as_bytes())?;
        Ok(())
    }

    /// 启动时处理上次标记为待删除的插件：删除目录并清空队列。
    fn process_pending_deletes(&mut self) -> Result<(), String> {
        let path = self.pending_deletes_path();
        if !path.exists() {
            return Ok(());
        }
        let list: Vec<String> = fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        for id in &list {
            let dir = self.base_dir.join(id);
            if dir.exists() {
                let _ = fs::remove_dir_all(&dir);
            }
            self.plugins.remove(id);
        }
        let _ = fs::remove_file(&path);
        Ok(())
    }
}

/// 事件 → 所需权限映射。未登记的事件默认不需权限。
fn event_required_permissions(event_type: &str) -> Vec<&'static str> {
    match event_type {
        "instance.started" | "instance.stopped" | "server.ready" | "server.log" => {
            vec!["instance.read"]
        }
        "backup.completed" | "backup.read" => vec!["backup.read"],
        "backup.start" | "backup.write" => vec!["backup.write"],
        _ => vec![],
    }
}

// ===== state.json 读写 =====

#[derive(Serialize, Deserialize)]
struct PluginState {
    #[serde(default = "default_enabled")]
    enabled: bool,
}

fn default_enabled() -> bool {
    true
}

fn read_state_enabled(dir: &Path) -> Option<bool> {
    let path = dir.join("state.json");
    let bytes = fs::read(path).ok()?;
    let state: PluginState = serde_json::from_slice(&bytes).ok()?;
    Some(state.enabled)
}

fn write_state_enabled(dir: &Path, enabled: bool) -> Result<(), String> {
    let state = PluginState { enabled };
    let json = serde_json::to_string(&state).map_err(|e| e.to_string())?;
    write_file(&dir.join("state.json"), json.as_bytes())
}

fn write_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let mut f = fs::File::create(path).map_err(|e| format!("写文件失败 {:?}: {e}", path))?;
    f.write_all(bytes).map_err(|e| e.to_string())?;
    Ok(())
}

fn rand_suffix() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let ns = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{ns:x}")
}
