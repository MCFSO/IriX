// JAR 元数据扫描（插件 / Mod）
//
// 背景：Dart 侧 `ZipDecoder` 是纯 Dart 同步 CPU 操作，在 UI isolate 上解压
// 上百个 jar 会直接卡住帧。这里把「打开 zip + 解压描述文件 + 读图标」搬到
// Rust，Dart 侧只需在后台 isolate 里调用一次即可。
//
// 解析优先级与 Dart 旧实现保持一致：
//   fabric.mod.json > META-INF/mods.toml > paper-plugin.yml > plugin.yml
//
// 输出为 JSON 数组，字段见 [JarMeta]；单个文件失败不影响整批。

use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::Read;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::Serialize;
use serde_json::Value;
use zip::ZipArchive;

/// 单个 jar 的元数据（JSON 字段名为 snake_case，与 Dart 侧对齐）。
#[derive(Serialize, Default, Debug, PartialEq)]
pub struct JarMeta {
    pub name: Option<String>,
    pub description: Option<String>,
    /// `fabric` / `forge` / `plugin` / `unknown`
    pub kind: String,
    /// 图标 PNG 的 base64；无图标为 null。
    pub icon_base64: Option<String>,
}

/// 扫描单个 jar；任何失败都返回 `kind = unknown` 的空元数据。
pub fn scan_one(path: &str) -> JarMeta {
    match scan_inner(path) {
        Ok(meta) => meta,
        Err(_) => JarMeta {
            kind: "unknown".to_string(),
            ..Default::default()
        },
    }
}

fn scan_inner(path: &str) -> Result<JarMeta, Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let mut archive = ZipArchive::new(file)?;

    if let Some(meta) = parse_fabric(&mut archive) {
        return Ok(meta);
    }
    if let Some(meta) = parse_forge(&mut archive) {
        return Ok(meta);
    }
    if let Some(meta) = parse_bukkit(&mut archive, "paper-plugin.yml") {
        return Ok(meta);
    }
    if let Some(meta) = parse_bukkit(&mut archive, "plugin.yml") {
        return Ok(meta);
    }
    Ok(JarMeta {
        kind: "unknown".to_string(),
        ..Default::default()
    })
}

/// 读取归档内某个条目的原始字节；找不到返回 None。
fn read_entry_bytes(archive: &mut ZipArchive<File>, name: &str) -> Option<Vec<u8>> {
    let mut entry = archive.by_name(name).ok()?;
    let mut buf = Vec::with_capacity(entry.size() as usize);
    entry.read_to_end(&mut buf).ok()?;
    Some(buf)
}

/// 大小写不敏感地查找条目（jar 内路径大小写并不总是规范）。
fn read_entry_bytes_ci(archive: &mut ZipArchive<File>, name: &str) -> Option<Vec<u8>> {
    if let Some(bytes) = read_entry_bytes(archive, name) {
        return Some(bytes);
    }
    let lower = name.to_lowercase();
    let matched = (0..archive.len()).find(|i| {
        archive
            .by_index(*i)
            .map(|f| f.name().to_lowercase() == lower)
            .unwrap_or(false)
    })?;
    let mut entry = archive.by_index(matched).ok()?;
    let mut buf = Vec::with_capacity(entry.size() as usize);
    entry.read_to_end(&mut buf).ok()?;
    Some(buf)
}

fn read_text(archive: &mut ZipArchive<File>, name: &str) -> Option<String> {
    let bytes = read_entry_bytes(archive, name)?;
    Some(String::from_utf8_lossy(&bytes).into_owned())
}

fn read_icon(archive: &mut ZipArchive<File>, path: &str) -> Option<String> {
    let bytes = read_entry_bytes_ci(archive, path)?;
    Some(STANDARD.encode(bytes))
}

/// Fabric：fabric.mod.json，icon 支持字符串或 {尺寸: 路径} 映射。
fn parse_fabric(archive: &mut ZipArchive<File>) -> Option<JarMeta> {
    let text = read_text(archive, "fabric.mod.json")?;
    let value: Value = serde_json::from_str(&text).unwrap_or(Value::Null);

    let name = value
        .get("name")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let description = value
        .get("description")
        .and_then(|v| v.as_str())
        .map(str::to_string);

    let icon_path = match value.get("icon") {
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Object(map)) => map
            .iter()
            .filter_map(|(k, v)| Some((k.parse::<u32>().ok()?, v.as_str()?.to_string())))
            .max_by_key(|(size, _)| *size)
            .map(|(_, path)| path),
        _ => None,
    };

    let icon_base64 = icon_path.and_then(|p| read_icon(archive, &p));
    Some(JarMeta {
        name,
        description,
        kind: "fabric".to_string(),
        icon_base64,
    })
}

/// Forge / NeoForge：META-INF/mods.toml，取第一个 `key = "value"`。
fn parse_forge(archive: &mut ZipArchive<File>) -> Option<JarMeta> {
    let text = read_text(archive, "META-INF/mods.toml")?;
    let name = toml_value(&text, "name");
    let description = toml_value(&text, "description");
    let logo = toml_value(&text, "logoFile")
        .map(|v| v.trim_start_matches("./").to_string())
        .filter(|v| !v.is_empty());

    let icon_base64 = logo.and_then(|p| read_icon(archive, &p));
    Some(JarMeta {
        name,
        description,
        kind: "forge".to_string(),
        icon_base64,
    })
}

/// Bukkit / Paper：plugin.yml 或 paper-plugin.yml（仅取顶层 name / description）。
fn parse_bukkit(archive: &mut ZipArchive<File>, entry: &str) -> Option<JarMeta> {
    let text = read_text(archive, entry)?;
    Some(JarMeta {
        name: yaml_top_level(&text, "name"),
        description: yaml_top_level(&text, "description"),
        kind: "plugin".to_string(),
        icon_base64: None,
    })
}

/// 提取 TOML 中第一条 `key = "value"`。
fn toml_value(content: &str, key: &str) -> Option<String> {
    for line in content.lines() {
        let line = line.trim();
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        if k.trim() != key {
            continue;
        }
        let v = v.trim();
        let v = v.strip_prefix('"')?;
        if let Some(end) = v.find('"') {
            return Some(v[..end].to_string());
        }
    }
    None
}

/// 提取顶层（无缩进）`key: value`，去掉引号与行尾注释。
fn yaml_top_level(content: &str, key: &str) -> Option<String> {
    for line in content.lines() {
        if line.starts_with(char::is_whitespace) || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once(':') else {
            continue;
        };
        if k.trim() != key {
            continue;
        }
        let mut v = v.trim().to_string();
        // 去掉行尾注释（引号内的 # 不处理，插件元数据几乎不会出现）
        if let Some(idx) = v.find(" #") {
            v.truncate(idx);
        }
        let v = v.trim().trim_matches('"').trim_matches('\'').trim();
        if v.is_empty() {
            return None;
        }
        return Some(v.to_string());
    }
    None
}

/// 批量扫描：入参为 JSON 字符串数组，返回 JSON 数组。
///
/// # Safety
/// `paths_json` 必须是合法的 NUL 结尾 UTF-8 字符串指针；返回值需由调用方
/// 通过 `free_string` 释放。
#[no_mangle]
pub extern "C" fn scan_jar_meta(paths_json: *const libc::c_char) -> *mut libc::c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if paths_json.is_null() {
            crate::set_last_error("路径列表为空指针");
            return ptr::null_mut();
        }
        let input = match unsafe { CStr::from_ptr(paths_json) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                crate::set_last_error("路径列表不是有效的 UTF-8");
                return ptr::null_mut();
            }
        };
        let paths: Vec<String> = match serde_json::from_str(input) {
            Ok(v) => v,
            Err(e) => {
                crate::set_last_error(format!("路径列表解析失败: {e}"));
                return ptr::null_mut();
            }
        };

        let metas: Vec<JarMeta> = paths.iter().map(|p| scan_one(p)).collect();
        match serde_json::to_string(&metas).ok().and_then(|json| CString::new(json).ok()) {
            Some(cstr) => cstr.into_raw(),
            None => {
                crate::set_last_error("序列化元数据失败");
                ptr::null_mut()
            }
        }
    }));

    match result {
        Ok(ptr) => ptr,
        Err(_) => {
            crate::set_last_error("Rust 侧 panic，已捕获");
            ptr::null_mut()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use zip::write::SimpleFileOptions;

    fn make_jar(path: &std::path::Path, files: &[(&str, &[u8])]) {
        let file = File::create(path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options =
            SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
        for (name, content) in files {
            writer.start_file(*name, options).unwrap();
            writer.write_all(content).unwrap();
        }
        writer.finish().unwrap();
    }

    #[test]
    fn scans_bukkit_plugin_yml() {
        let dir = std::env::temp_dir().join("xmc_jar_meta_test_bukkit");
        let _ = std::fs::create_dir_all(&dir);
        let jar = dir.join("demo.jar");
        make_jar(
            &jar,
            &[(
                "plugin.yml",
                b"name: DemoPlugin\ndescription: \"Demo description\"\nversion: 1.0\n"
                    as &[u8],
            )],
        );

        let meta = scan_one(jar.to_str().unwrap());
        assert_eq!(meta.kind, "plugin");
        assert_eq!(meta.name.as_deref(), Some("DemoPlugin"));
        assert_eq!(meta.description.as_deref(), Some("Demo description"));
        let _ = std::fs::remove_file(&jar);
    }

    #[test]
    fn scans_fabric_json_with_icon() {
        let dir = std::env::temp_dir().join("xmc_jar_meta_test_fabric");
        let _ = std::fs::create_dir_all(&dir);
        let jar = dir.join("fabric.jar");
        make_jar(
            &jar,
            &[
                (
                    "fabric.mod.json",
                    br#"{"name":"Demo Mod","description":"Desc","icon":{"64":"assets/icon64.png","128":"assets/icon128.png"}}"#
                        as &[u8],
                ),
                ("assets/icon64.png", b"PNG64"),
                ("assets/icon128.png", b"PNG128"),
            ],
        );

        let meta = scan_one(jar.to_str().unwrap());
        assert_eq!(meta.kind, "fabric");
        assert_eq!(meta.name.as_deref(), Some("Demo Mod"));
        // 取最大尺寸图标
        assert_eq!(meta.icon_base64.as_deref(), Some("UE5HMTI4"));
        let _ = std::fs::remove_file(&jar);
    }

    #[test]
    fn broken_jar_returns_unknown() {
        let dir = std::env::temp_dir().join("xmc_jar_meta_test_broken");
        let _ = std::fs::create_dir_all(&dir);
        let jar = dir.join("broken.jar");
        std::fs::write(&jar, b"not a zip").unwrap();

        let meta = scan_one(jar.to_str().unwrap());
        assert_eq!(meta.kind, "unknown");
        assert!(meta.name.is_none());
        let _ = std::fs::remove_file(&jar);
    }

    #[test]
    fn parses_forge_toml() {
        let dir = std::env::temp_dir().join("xmc_jar_meta_test_forge");
        let _ = std::fs::create_dir_all(&dir);
        let jar = dir.join("forge.jar");
        make_jar(
            &jar,
            &[(
                "META-INF/mods.toml",
                b"modLoader=\"javafml\"\n[[mods]]\nmodId=\"demo\"\nname=\"Demo Forge\"\ndescription=\"Forge desc\"\nlogoFile=\"./logo.png\"\n"
                    as &[u8],
            ), ("logo.png", b"PNG")],
        );

        let meta = scan_one(jar.to_str().unwrap());
        assert_eq!(meta.kind, "forge");
        assert_eq!(meta.name.as_deref(), Some("Demo Forge"));
        assert!(meta.icon_base64.is_some());
        let _ = std::fs::remove_file(&jar);
    }
}
