//! Windows 增量备份策略：哈希比对 + 内容寻址存储（CAS）。
//!
//! 流程：
//! 1. 并行计算每个文件的 SHA-256（**每次都按内容比对**：不做“大小 + mtime 相同
//!    就跳过”的快速路径，避免同秒同大小改写被漏判）；
//! 2. 内容对象写入 `<repo>/cas/<hash 前两位>/<hash>`，已存在则直接复用（跨快照去重）；
//! 3. 快照本身只是清单（`meta/<name>.manifest.json`），记录路径 → 哈希；
//! 4. 与父快照清单比对得出 新增 / 修改 / 未变 / 删除 统计。
//!
//! 相同内容只存一份，因此“增量”体现在 CAS 对象层面：未变化的文件不产生任何新数据。

use std::collections::{HashMap, HashSet};
use std::io;
use std::path::Path;
use std::sync::Mutex;

use rayon::prelude::*;

use crate::hash;
use crate::model::{Manifest, ManifestEntry, SnapshotStats};
use crate::progress::{self, Progress};
use crate::repo::Repo;
use crate::scan::ScanResult;

/// 创建 CAS 快照清单（不写文件树，只写内容对象 + 清单）。
pub(crate) fn build_manifest(
    repo: &Repo,
    scan: &ScanResult,
    parent: Option<&Manifest>,
    progress: &Progress,
) -> io::Result<(Manifest, SnapshotStats)> {
    progress.set_total(scan.total_bytes);

    // 本次运行真正新建的对象哈希（用于计算实际新增字节）。
    let created: Mutex<HashSet<String>> = Mutex::new(HashSet::new());

    let entries: Vec<ManifestEntry> = scan
        .files
        .par_iter()
        .map(|file| -> io::Result<ManifestEntry> {
            progress::check_cancel()?;
            let digest = hash::sha256_file(&file.abs)?;
            if repo.store_object(&digest, &file.abs)? {
                created.lock().unwrap().insert(digest.clone());
            }
            progress.add(file.size);
            Ok(ManifestEntry {
                path: file.rel.clone(),
                size: file.size,
                mtime: file.mtime,
                hash: Some(digest),
                linked: false,
            })
        })
        .collect::<io::Result<Vec<_>>>()?;

    let parent_index = parent.map(|m| m.index_by_path()).unwrap_or_default();

    // 每个哈希只按首次出现的文件大小计入（同一内容多路径只存一份）。
    let mut hash_size: HashMap<&str, u64> = HashMap::new();
    let mut stats = SnapshotStats {
        files_total: entries.len() as u64,
        dirs: scan.dirs.len() as u64,
        bytes_total: entries.iter().map(|e| e.size).sum(),
        symlinks_skipped: scan.symlinks,
        ..Default::default()
    };
    for entry in &entries {
        if let Some(h) = entry.hash.as_deref() {
            hash_size.entry(h).or_insert(entry.size);
        }
        match parent_index.get(entry.path.as_str()) {
            None => stats.files_new += 1,
            Some(old) if old.hash == entry.hash => stats.files_unchanged += 1,
            Some(_) => stats.files_modified += 1,
        }
    }

    let created_guard = created.lock().unwrap();
    stats.bytes_added = created_guard
        .iter()
        .filter_map(|h| hash_size.get(h.as_str()))
        .sum();
    stats.bytes_reused = stats.bytes_total.saturating_sub(stats.bytes_added);

    // 父快照有、本次没有的条目视为删除。
    if let Some(parent) = parent {
        let current: HashSet<&str> = entries.iter().map(|e| e.path.as_str()).collect();
        stats.files_deleted = parent
            .entries
            .iter()
            .filter(|e| !current.contains(e.path.as_str()))
            .count() as u64;
    }

    Ok((
        Manifest {
            dirs: scan.dirs.clone(),
            entries,
        },
        stats,
    ))
}

/// 把 CAS 对象还原到目标目录。
pub(crate) fn restore(
    repo: &Repo,
    manifest: &Manifest,
    target_root: &Path,
    progress: &Progress,
) -> io::Result<u64> {
    let total: u64 = manifest.entries.iter().map(|e| e.size).sum();
    progress.set_total(total);

    for dir in &manifest.dirs {
        std::fs::create_dir_all(target_root.join(dir))?;
    }
    let mut restored = 0u64;

    // 先整体检查对象完整性，避免恢复一半才发现缺对象（把实例目录写坏）。
    for entry in &manifest.entries {
        progress::check_cancel()?;
        let Some(digest) = entry.hash.as_deref() else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("清单条目缺少哈希: {}", entry.path),
            ));
        };
        let object = repo.cas_path(digest);
        let meta = std::fs::metadata(&object).map_err(|_| {
            io::Error::new(
                io::ErrorKind::NotFound,
                format!("内容对象缺失: {} ({})", digest, entry.path),
            )
        })?;
        if meta.len() != entry.size {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("内容对象大小不符: {} ({})", digest, entry.path),
            ));
        }
    }

    for entry in &manifest.entries {
        progress::check_cancel()?;
        let digest = entry
            .hash
            .as_deref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "清单条目缺少哈希"))?;
        let object = repo.cas_path(digest);
        let dest = target_root.join(&entry.path);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::copy(&object, &dest)?;
        restored += 1;
        progress.add(entry.size);
    }
    Ok(restored)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::scan_source;

    fn temp_root(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "xmc_cas_{}_{}_{}",
            tag,
            std::process::id(),
            crate::next_temp_id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn cas_dedupes_and_restores() {
        let tmp = temp_root("dedup");
        let src = tmp.join("src");
        let repo_root = tmp.join("repo");
        std::fs::create_dir_all(src.join("world")).unwrap();
        std::fs::write(src.join("server.properties"), b"motd=hello").unwrap();
        std::fs::write(src.join("world/level.dat"), b"same-content").unwrap();
        std::fs::write(src.join("backup.dat"), b"same-content").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let scan = scan_source(&src, Some(repo.root())).unwrap();
        let progress = Progress::none();

        let (manifest, stats) = build_manifest(&repo, &scan, None, &progress).unwrap();
        assert_eq!(manifest.entries.len(), 3);
        assert_eq!(stats.files_new, 3);
        assert_eq!(stats.files_unchanged, 0);
        // "motd=hello"(10) + "same-content"(12) + "same-content"(12)
        assert_eq!(stats.bytes_total, 10 + 12 + 12);
        // 相同内容两份只存一份：新增字节 = 10 + 12
        assert_eq!(stats.bytes_added, 10 + 12);
        assert_eq!(stats.bytes_reused, 12);

        // 第二次：只改一个文件，其余应判定为未变化且不新增对象
        std::fs::write(src.join("server.properties"), b"motd=world").unwrap();
        let scan2 = scan_source(&src, Some(repo.root())).unwrap();
        let (manifest2, stats2) =
            build_manifest(&repo, &scan2, Some(&manifest), &progress).unwrap();
        assert_eq!(stats2.files_modified, 1);
        assert_eq!(stats2.files_unchanged, 2);
        assert_eq!(stats2.files_deleted, 0);
        assert_eq!(stats2.bytes_added, 10);

        // 恢复
        let out = tmp.join("restore");
        restore(&repo, &manifest2, &out, &progress).unwrap();
        assert_eq!(
            std::fs::read(out.join("server.properties")).unwrap(),
            b"motd=world"
        );
        assert_eq!(std::fs::read(out.join("world/level.dat")).unwrap(), b"same-content");

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn cas_reports_deleted_files() {
        let tmp = temp_root("deleted");
        let src = tmp.join("src");
        let repo_root = tmp.join("repo");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("a.txt"), b"a").unwrap();
        std::fs::write(src.join("b.txt"), b"b").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let progress = Progress::none();
        let scan = scan_source(&src, Some(repo.root())).unwrap();
        let (manifest, _) = build_manifest(&repo, &scan, None, &progress).unwrap();

        std::fs::remove_file(src.join("b.txt")).unwrap();
        let scan2 = scan_source(&src, Some(repo.root())).unwrap();
        let (_manifest2, stats2) =
            build_manifest(&repo, &scan2, Some(&manifest), &progress).unwrap();
        assert_eq!(stats2.files_deleted, 1);
        assert_eq!(stats2.files_unchanged, 1);

        let _ = std::fs::remove_dir_all(&tmp);
    }
}
