// 插件包元数据解析 / 平台动态库选择 / 版本兼容性与 zip 安全路径
//
// 插件包结构（zip）：
//   myplugin.zip
//   ├── README.md
//   ├── manifest.json
//   └── lib/
//       ├── plugin.windows-x64.dll
//       ├── plugin.macos-arm64.dylib
//       ├── plugin.macos-x64.dylib
//       └── plugin.linux-x64.so
//
// manifest.json 由程序读取，字段见 [Manifest]。所有跨边界数据一律用 JSON
// 字符串传递，不直接传结构体。

use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

/// `manifest.json` 的字段结构（字段可缺省，取空值/默认值）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// 插件唯一 id，如 `com.example.myplugin`。
    pub id: String,
    /// 展示名称。
    pub name: String,
    /// 语义化版本（semver）。
    pub version: String,
    /// 作者。
    #[serde(default)]
    pub author: String,
    /// 给人看的描述。
    #[serde(default)]
    pub description: String,
    /// 插件类型，目前仅支持 `native`。
    #[serde(rename = "type", default = "default_type")]
    pub plugin_type: String,
    /// 产物文件名主干（不含平台后缀）。默认 `plugin`。
    #[serde(default = "default_entry")]
    pub entry: String,
    /// 主程序最低版本要求（semver）。为空表示不限。
    #[serde(default)]
    pub min_app_version: String,
    /// 声明的权限列表，如 `["instance.read", "backup.write"]`。
    #[serde(default)]
    pub permissions: Vec<String>,
}

fn default_type() -> String {
    "native".to_string()
}

fn default_entry() -> String {
    "plugin".to_string()
}

impl Manifest {
    /// 是否符合 host 支持的插件类型（目前仅 native）。
    pub fn is_native(&self) -> bool {
        self.plugin_type.eq_ignore_ascii_case("native")
    }

    /// 校验 manifest 的关键字段是否可用。
    pub fn validate(&self) -> Result<(), String> {
        if self.id.trim().is_empty() {
            return Err("manifest.id 为空".into());
        }
        if self.name.trim().is_empty() {
            return Err("manifest.name 为空".into());
        }
        if self.version.trim().is_empty() {
            return Err("manifest.version 为空".into());
        }
        if !self.is_native() {
            return Err(format!(
                "不支持的插件类型: {}（仅支持 native）",
                self.plugin_type
            ));
        }
        if self.entry.trim().is_empty() {
            return Err("manifest.entry 为空".into());
        }
        Ok(())
    }

    /// 与宿主版本比较：宿主 >= min_app_version 即兼容。
    pub fn compatible_with(&self, host_version: &str) -> Result<(), String> {
        if self.min_app_version.trim().is_empty() {
            return Ok(());
        }
        match (
            semver::Version::parse(host_version),
            semver::Version::parse(&self.min_app_version),
        ) {
            (Ok(host), Ok(min)) if host >= min => Ok(()),
            (Ok(_), Ok(min)) => Err(format!(
                "宿主版本 {host_version} 低于插件要求的最低版本 {}",
                min
            )),
            // 版本无法解析时保守放行，避免误拒合法插件。
            _ => Ok(()),
        }
    }
}

/// 解析 manifest.json 内容。
pub fn parse_manifest(bytes: &[u8]) -> Result<Manifest, String> {
    serde_json::from_slice(bytes).map_err(|e| format!("manifest.json 解析失败: {e}"))
}

/// 当前平台对应的插件动态库文件名（基于 manifest.entry）。
///
/// 只覆盖 IriX 支持的桌面目标；其它平台返回 None（插件标记为不支持）。
pub fn platform_lib_name(entry: &str) -> Option<String> {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("windows", "x86_64") => Some(format!("{entry}.windows-x64.dll")),
        ("macos", "aarch64") => Some(format!("{entry}.macos-arm64.dylib")),
        ("macos", "x86_64") => Some(format!("{entry}.macos-x64.dylib")),
        ("linux", "x86_64") => Some(format!("{entry}.linux-x64.so")),
        _ => None,
    }
}

/// 当前平台对应的目标三元组（用于展示 / 日志）。
pub fn platform_target() -> String {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("windows", "x86_64") => "windows-x64".into(),
        ("macos", "aarch64") => "macos-arm64".into(),
        ("macos", "x86_64") => "macos-x64".into(),
        ("linux", "x86_64") => "linux-x64".into(),
        (os, arch) => format!("{os}-{arch}"),
    }
}

/// 安全地把 zip 内的相对路径拼到解压根目录下。
///
/// 拒绝绝对路径、`..`、根/前缀组件，防止 zip-slip 越出目标目录。
/// 返回 None 表示该路径非法，应跳过该条目。
pub fn safe_entry_path(dest: &Path, name: &str) -> Option<PathBuf> {
    let rel = Path::new(name);
    if rel.as_os_str().is_empty() || rel.is_absolute() {
        return None;
    }
    for comp in rel.components() {
        match comp {
            Component::Normal(_) | Component::CurDir => {}
            _ => return None, // ParentDir / RootDir / Prefix
        }
    }
    Some(dest.join(rel))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_parse_and_validate() {
        let json = r#"{
            "id": "com.example.myplugin",
            "name": "我的插件",
            "version": "1.0.0",
            "author": "a",
            "description": "d",
            "type": "native",
            "entry": "plugin",
            "min_app_version": "0.1.0",
            "permissions": ["instance.read", "backup.write"]
        }"#;
        let m = parse_manifest(json.as_bytes()).unwrap();
        assert_eq!(m.id, "com.example.myplugin");
        assert!(m.is_native());
        assert_eq!(m.entry, "plugin");
        assert!(m.validate().is_ok());
        assert!(m.compatible_with("1.0.0").is_ok());
        assert!(m.compatible_with("0.0.1").is_err());
    }

    #[test]
    fn rejects_non_native() {
        let json = r#"{"id":"x","name":"y","version":"1.0.0","type":"js","entry":"a"}"#;
        let m = parse_manifest(json.as_bytes()).unwrap();
        assert!(m.validate().is_err());
    }

    #[test]
    fn safe_path_blocks_traversal() {
        let dest = Path::new("/tmp/plugin");
        assert_eq!(
            safe_entry_path(dest, "lib/plugin.dll"),
            Some(dest.join("lib/plugin.dll"))
        );
        assert!(safe_entry_path(dest, "../evil").is_none());
        assert!(safe_entry_path(dest, "/abs/path").is_none());
        assert!(safe_entry_path(dest, "a/../../evil").is_none());
    }

    #[test]
    fn platform_lib_names() {
        // 仅在此处确保命名规则稳定（具体返回值取决于运行平台）。
        let name = platform_lib_name("plugin");
        assert!(name.is_some());
        if cfg!(target_os = "windows") {
            assert_eq!(name.as_deref(), Some("plugin.windows-x64.dll"));
        }
    }
}
