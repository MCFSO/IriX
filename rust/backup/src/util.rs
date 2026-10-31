//! 备份模块的通用工具：时间、十六进制、名称校验、JSON 原子写入、目录体积统计。

use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::de::DeserializeOwned;
use serde::Serialize;

/// 当前 Unix 秒。
pub(crate) fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// 小写十六进制编码（避免为 CAS 对象键引入额外依赖）。
pub(crate) fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

/// 校验快照/备份名：只允许 `[A-Za-z0-9._-]`，禁止空名、`.`、`..`。
///
/// 名称会直接作为目录名/文件名使用，必须挡住路径穿越。
pub(crate) fn validate_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("名称不能为空".to_string());
    }
    if name.len() > 96 {
        return Err("名称过长".to_string());
    }
    if name == "." || name == ".." {
        return Err("名称非法".to_string());
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
    {
        return Err(format!("名称含非法字符: {name}"));
    }
    Ok(())
}

/// 把路径统一成 `/` 分隔的字符串（清单/JSON 里统一正斜杠）。
pub(crate) fn path_to_slash(path: &Path) -> String {
    let s = path.to_string_lossy();
    if s.contains('\\') {
        s.replace('\\', "/")
    } else {
        s.into_owned()
    }
}

/// 原子替换文件：先写临时文件再改名。
pub(crate) fn replace_file(tmp: &Path, dst: &Path) -> io::Result<()> {
    #[cfg(windows)]
    {
        // Windows 上 rename 不能覆盖已存在文件。
        if dst.exists() {
            let _ = fs::remove_file(dst);
        }
    }
    fs::rename(tmp, dst)
}

/// 原子写入 JSON（临时文件 + rename，避免半截文件）。
pub(crate) fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let bytes = serde_json::to_vec(value)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;
    let tmp = path.with_extension(format!("tmp{}", std::process::id()));
    {
        let mut file = File::create(&tmp)?;
        file.write_all(&bytes)?;
        file.flush()?;
    }
    replace_file(&tmp, path)
}

/// 读取 JSON；文件不存在时返回 `Ok(None)`。
pub(crate) fn read_json<T: DeserializeOwned>(path: &Path) -> io::Result<Option<T>> {
    match fs::read(path) {
        Ok(bytes) => match serde_json::from_slice(&bytes) {
            Ok(v) => Ok(Some(v)),
            Err(e) => Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("{}: {e}", path.display()),
            )),
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e),
    }
}

/// 删除目录（存在才删）。
pub(crate) fn remove_dir_all_if_exists(path: &Path) -> io::Result<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

/// 生成 UTC 时间戳名（`YYYYMMDD-HHMMSS`），仅在 Dart 未提供名称时兜底。
pub(crate) fn utc_name_from_secs(secs: i64) -> String {
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    let (y, m, d) = crate::civil_from_days(days);
    format!(
        "{:04}{:02}{:02}-{:02}{:02}{:02}",
        y,
        m,
        d,
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60
    )
}

/// 把用户给出的目录名唯一化：已存在时追加 `-2`、`-3`……
pub(crate) fn unique_dir_name(mut exists: impl FnMut(&str) -> bool, preferred: &str) -> String {
    if !exists(preferred) {
        return preferred.to_string();
    }
    for i in 2..10_000u32 {
        let candidate = format!("{preferred}-{i}");
        if !exists(&candidate) {
            return candidate;
        }
    }
    format!("{preferred}-{}", now_secs())
}

/// 顶层目录列表（用于全量备份：逐项 walk 压缩）。
pub(crate) fn top_level_entries(root: &Path, exclude: Option<&Path>) -> io::Result<Vec<String>> {
    let mut names = Vec::new();
    let canonical_root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let canonical_exclude = exclude.and_then(|p| p.canonicalize().ok());
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if let Some(ex) = canonical_exclude.as_deref() {
            let canonical = path.canonicalize().unwrap_or_else(|_| path.clone());
            if canonical == ex {
                continue;
            }
        }
        // 只取相对路径名，保持与旧 backup_directory 的入参语义一致。
        if path.parent() == Some(canonical_root.as_path()) || path.starts_with(root) {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                names.push(name.to_string());
            }
        }
    }
    Ok(names)
}

/// 读取文件前 4KiB 文本（用于 rsync 日志解析/错误信息），不阻塞。
pub(crate) fn read_tail_string(path: &Path, max_bytes: u64) -> String {
    let Ok(meta) = fs::metadata(path) else {
        return String::new();
    };
    let len = meta.len();
    let offset = len.saturating_sub(max_bytes);
    let Ok(mut file) = File::open(path) else {
        return String::new();
    };
    use std::io::{Seek, SeekFrom};
    if file.seek(SeekFrom::Start(offset)).is_err() {
        return String::new();
    }
    let mut buf = Vec::new();
    let _ = file.take(max_bytes).read_to_end(&mut buf);
    String::from_utf8_lossy(&buf).to_string()
}
