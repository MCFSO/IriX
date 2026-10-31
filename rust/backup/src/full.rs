//! 全量备份（原备份功能）：整个实例目录 → 单个 ZIP 归档。
//!
//! 仍然使用 crate 根部的并行 Deflate 压缩实现（[`crate::do_backup`]），
//! 归档放在备份仓库的 `full/` 子目录，并附带一份摘要 JSON 供列表展示。
//! 恢复 = 把 ZIP 解包回实例目录（`zip` crate，带 zip-slip 防护）。

use std::fs::{self, File};
use std::io::{self, Write};
use std::path::Path;
use std::time::Instant;

use zip::ZipArchive;

use crate::model::{DeleteOutcome, FullMeta, RestoreOutcome, KIND_FULL};
use crate::progress::{self, Progress, ProgressCallback};
use crate::repo::Repo;
use crate::util;

/// 创建全量备份。
pub(crate) fn create(
    repo: &Repo,
    source_root: &Path,
    preferred_name: &str,
    compression_level: u32,
    cb: Option<ProgressCallback>,
) -> io::Result<FullMeta> {
    if !source_root.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("实例目录不存在: {}", source_root.display()),
        ));
    }
    util::validate_name(preferred_name)
        .map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;

    let name = repo.unique_full_name(preferred_name);
    let zip_path = repo.full_zip_path(&name);
    let level = compression_level.min(9);
    let started = Instant::now();

    let names = util::top_level_entries(source_root, Some(repo.root()))?;
    let refs: Vec<&str> = names.iter().map(|s| s.as_str()).collect();

    let stats = match crate::do_backup(
        &source_root.to_string_lossy(),
        &zip_path.to_string_lossy(),
        &refs,
        level,
        cb,
        Some(repo.root()),
    ) {
        Ok(stats) => stats,
        Err(e) => {
            let _ = fs::remove_file(&zip_path);
            return Err(e);
        }
    };

    let stored_bytes = fs::metadata(&zip_path).map(|m| m.len()).unwrap_or(0);
    let meta = FullMeta {
        name: name.clone(),
        created_at: util::now_secs(),
        source_root: util::path_to_slash(source_root),
        compression_level: level,
        files: stats.files,
        bytes_total: stats.bytes_total,
        stored_bytes,
        duration_ms: started.elapsed().as_millis() as u64,
    };
    repo.write_full_meta(&meta)?;
    Ok(meta)
}

/// 用全量备份覆盖恢复 [target_root]。
pub(crate) fn restore(
    repo: &Repo,
    name: &str,
    target_root: &Path,
    cb: Option<ProgressCallback>,
) -> io::Result<RestoreOutcome> {
    util::validate_name(name).map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;
    let zip_path = repo.full_zip_path(name);
    if !zip_path.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("全量备份不存在: {name}"),
        ));
    }
    let started = Instant::now();
    fs::create_dir_all(target_root)?;
    let file = File::open(&zip_path)?;
    let mut archive = ZipArchive::new(file)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("ZIP 解析失败: {e}")))?;

    let progress = Progress::new(cb, archive.len() as u64);
    let mut files = 0u64;
    let mut bytes = 0u64;
    for index in 0..archive.len() {
        progress::check_cancel()?;
        let mut entry = archive
            .by_index(index)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("ZIP 条目损坏: {e}")))?;
        // enclosed_name 会拒绝绝对路径与 `..`，防 zip-slip。
        let Some(rel) = entry.enclosed_name() else {
            let label = entry
                .name()
                .map(|n| n.into_owned())
                .unwrap_or_else(|_| String::from("<无法解码的条目名>"));
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("ZIP 条目路径非法: {label}"),
            ));
        };
        let dest = target_root.join(&rel);
        if entry.is_dir() {
            fs::create_dir_all(&dest)?;
            progress.add(1);
            continue;
        }
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut output = File::create(&dest)?;
        let copied = io::copy(&mut entry, &mut output)?;
        output.flush()?;
        files += 1;
        bytes += copied;
        progress.add(1);
    }
    progress.finish();

    Ok(RestoreOutcome {
        name: name.to_string(),
        kind: KIND_FULL.to_string(),
        strategy: "zip".to_string(),
        files,
        bytes,
        pruned: 0,
        duration_ms: started.elapsed().as_millis() as u64,
    })
}

/// 删除全量备份（ZIP + 摘要）。
pub(crate) fn delete(repo: &Repo, name: &str) -> io::Result<DeleteOutcome> {
    util::validate_name(name).map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;
    let zip_path = repo.full_zip_path(name);
    let has_meta = repo.read_full_meta(name).ok().flatten().is_some();
    if !zip_path.exists() && !has_meta {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("全量备份不存在: {name}"),
        ));
    }
    let bytes = fs::metadata(&zip_path).map(|m| m.len()).unwrap_or(0);
    repo.delete_full(name)?;
    Ok(DeleteOutcome {
        name: name.to_string(),
        kind: KIND_FULL.to_string(),
        objects_removed: if bytes > 0 { 1 } else { 0 },
        bytes_freed: bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_root(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "xmc_full_{}_{}_{}",
            tag,
            std::process::id(),
            crate::next_temp_id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn full_backup_roundtrip() {
        let tmp = temp_root("roundtrip");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(src.join("world/region")).unwrap();
        fs::write(src.join("server.properties"), b"motd=hello").unwrap();
        fs::write(src.join("world/region/r.0.0.mca"), vec![b'a'; 8192]).unwrap();
        fs::write(src.join("empty-dir-marker"), b"x").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let meta = create(&repo, &src, "20260101-000000", 6, None).unwrap();
        assert_eq!(meta.files, 3);
        assert!(repo.full_zip_path(&meta.name).exists());
        assert_eq!(repo.list_full().unwrap().len(), 1);

        let target = tmp.join("restored");
        let outcome = restore(&repo, &meta.name, &target, None).unwrap();
        assert_eq!(outcome.files, 3);
        assert_eq!(
            fs::read(target.join("server.properties")).unwrap(),
            b"motd=hello"
        );
        assert_eq!(
            fs::read(target.join("world/region/r.0.0.mca")).unwrap(),
            vec![b'a'; 8192]
        );
        assert_eq!(fs::read(target.join("empty-dir-marker")).unwrap(), b"x");

        let deleted = delete(&repo, &meta.name).unwrap();
        assert!(deleted.bytes_freed > 0);
        assert!(!repo.full_zip_path(&meta.name).exists());
        assert!(repo.list_full().unwrap().is_empty());

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn full_backup_name_is_unique() {
        let tmp = temp_root("unique");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        fs::write(src.join("a.txt"), b"a").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let first = create(&repo, &src, "20260101-000000", 1, None).unwrap();
        let second = create(&repo, &src, "20260101-000000", 1, None).unwrap();
        assert_eq!(first.name, "20260101-000000");
        assert_eq!(second.name, "20260101-000000-2");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn zip_without_meta_is_still_listed() {
        let tmp = temp_root("orphan");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        fs::write(src.join("a.txt"), b"a").unwrap();
        let repo = Repo::open(&repo_root).unwrap();
        let meta = create(&repo, &src, "20260101-060000", 1, None).unwrap();

        // 模拟被中断/手工放入的 ZIP：只有归档，没有摘要
        fs::remove_file(repo.full_meta_path(&meta.name)).unwrap();
        let list = repo.list_full().unwrap();
        assert_eq!(list.len(), 1, "缺少摘要的 ZIP 也应在列表中");
        assert_eq!(list[0].name, meta.name);
        assert!(list[0].stored_bytes > 0);
        // 仍可恢复与删除
        let target = tmp.join("restored");
        restore(&repo, &meta.name, &target, None).unwrap();
        assert_eq!(fs::read(target.join("a.txt")).unwrap(), b"a");
        delete(&repo, &meta.name).unwrap();
        assert!(repo.list_full().unwrap().is_empty());

        let _ = fs::remove_dir_all(&tmp);
    }
}
