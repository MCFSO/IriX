//! 增量快照的创建 / 恢复 / 校验。
//!
//! 策略按平台选择，写入 `SnapshotMeta.strategy`：
//! - Windows：`cas`（SHA-256 哈希比对 + 内容寻址存储）；
//! - Linux/macOS：`rsync-hardlink`（`rsync --link-dest` 硬链接快照），
//!   rsync 不可用或执行失败时回退为 `hardlink`（Rust 原生硬链接快照）。

use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::Path;
use std::time::Instant;

use crate::hash;
use crate::model::{
    Manifest, RestoreOutcome, SnapshotMeta, SnapshotStats, VerifyReport, KIND_SNAPSHOT, STRATEGY_CAS,
    STRATEGY_HARDLINK, STRATEGY_RSYNC,
};
use crate::progress::{self, Progress, ProgressCallback};
use crate::repo::Repo;
use crate::{cas, hardlink, rsync, scan, util};

/// 策略的存储形态：true = 内容寻址存储（无文件树），false = 快照文件树。
fn uses_cas(strategy: &str) -> bool {
    strategy == STRATEGY_CAS
}

/// 创建增量快照。
///
/// [parent_arg] 为空时自动取最新快照作为增量基线（首个快照即全量落盘）。
pub(crate) fn create(
    repo: &Repo,
    source_root: &Path,
    preferred_name: &str,
    parent_arg: Option<&str>,
    label: Option<&str>,
    cb: Option<ProgressCallback>,
) -> io::Result<SnapshotMeta> {
    if !source_root.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("实例目录不存在: {}", source_root.display()),
        ));
    }
    util::validate_name(preferred_name)
        .map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;

    let name = repo.unique_snapshot_name(preferred_name);
    if repo.snapshot_exists(&name) {
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            format!("快照已存在: {name}"),
        ));
    }

    // 增量基线：显式指定 > 最新快照；存储形态不同（CAS vs 文件树）时忽略基线，
    // 避免仓库被跨平台拷贝后出现“父快照无文件树”的错误增量。
    let requested_parent = match parent_arg {
        Some(p) if !p.trim().is_empty() => {
            if repo.read_snapshot_meta(p)?.is_some() {
                Some(p.to_string())
            } else {
                None
            }
        }
        _ => repo.latest_snapshot(Some(&name)),
    };
    let expected_cas = cfg!(windows);
    let parent = match requested_parent {
        Some(p) => match repo.read_snapshot_meta(&p)? {
            Some(meta) if uses_cas(&meta.strategy) == expected_cas => Some(p),
            _ => None,
        },
        None => None,
    };
    let parent_manifest: Option<Manifest> = match parent.as_deref() {
        Some(p) => repo.read_manifest(p)?.or_else(|| Some(Manifest::default())),
        None => None,
    };

    let started = Instant::now();
    let scan_result = scan::scan_source(source_root, Some(repo.root()))?;
    let progress = Progress::new(cb, scan_result.total_bytes);

    let mut strategy = if expected_cas {
        STRATEGY_CAS.to_string()
    } else if rsync::available() {
        STRATEGY_RSYNC.to_string()
    } else {
        STRATEGY_HARDLINK.to_string()
    };
    let mut note: Option<String> = None;
    if !expected_cas && !rsync::available() {
        note = Some("未找到 rsync 命令，已改用 Rust 原生硬链接快照".to_string());
    }

    let manifest_result = if expected_cas {
        cas::build_manifest(repo, &scan_result, parent_manifest.as_ref(), &progress)
    } else {
        build_tree_snapshot(
            repo,
            &name,
            source_root,
            &scan_result,
            parent.as_deref(),
            parent_manifest.as_ref(),
            &progress,
            &mut strategy,
            &mut note,
        )
    };

    let (manifest, stats) = match manifest_result {
        Ok(v) => v,
        Err(e) => {
            // 失败/取消：清掉可能残留的半成品快照
            let _ = util::remove_dir_all_if_exists(&repo.snapshot_dir(&name));
            let _ = fs::remove_file(repo.meta_path(&name));
            let _ = fs::remove_file(repo.manifest_path(&name));
            return Err(e);
        }
    };

    progress.finish();

    let duration_ms = started.elapsed().as_millis() as u64;
    let meta = SnapshotMeta {
        name: name.clone(),
        created_at: util::now_secs(),
        parent,
        strategy,
        label: label.map(|s| s.to_string()),
        note,
        source_root: util::path_to_slash(source_root),
        files_total: stats.files_total,
        files_new: stats.files_new,
        files_modified: stats.files_modified,
        files_deleted: stats.files_deleted,
        files_unchanged: stats.files_unchanged,
        bytes_total: stats.bytes_total,
        bytes_added: stats.bytes_added,
        bytes_reused: stats.bytes_reused,
        duration_ms,
        // 快照自身占用 = 本次实际新增落盘的字节数（硬链接/CAS 都不重复占空间）
        stored_bytes: stats.bytes_added,
        dirs: stats.dirs,
        symlinks_skipped: stats.symlinks_skipped,
    };
    repo.write_manifest(&name, &manifest)?;
    if let Err(e) = repo.write_snapshot_meta(&meta) {
        // 元数据落盘失败：清掉半成品，避免出现“有文件树但列表里看不到”的孤儿快照。
        let _ = util::remove_dir_all_if_exists(&repo.snapshot_dir(&name));
        let _ = fs::remove_file(repo.manifest_path(&name));
        let _ = fs::remove_file(repo.meta_path(&name));
        return Err(e);
    }
    Ok(meta)
}

/// 文件树型快照（rsync 优先，失败回退原生硬链接）。
#[allow(clippy::too_many_arguments)]
fn build_tree_snapshot(
    repo: &Repo,
    name: &str,
    source_root: &Path,
    scan_result: &scan::ScanResult,
    parent: Option<&str>,
    parent_manifest: Option<&Manifest>,
    progress: &Progress,
    strategy: &mut String,
    note: &mut Option<String>,
) -> io::Result<(Manifest, SnapshotStats)> {
    let dest = repo.snapshot_dir(name);
    let parent_dir = parent.map(|p| repo.snapshot_dir(p));

    if rsync::available() {
        match rsync::create_snapshot(
            repo,
            source_root,
            &dest,
            parent_dir.as_deref(),
            Some(repo.root()),
            progress,
        ) {
            Ok(()) => {
                *strategy = STRATEGY_RSYNC.to_string();
                return Ok(hardlink::manifest_from_scan(scan_result, parent_manifest));
            }
            Err(e) if progress::is_cancel_error(&e) => return Err(e),
            Err(e) => {
                // rsync 失败（权限、路径过长、老版本不兼容等）→ 回退原生实现，
                // 原生实现会再次覆盖同样的错误，因此不会掩盖真实问题。
                let _ = util::remove_dir_all_if_exists(&dest);
                *strategy = STRATEGY_HARDLINK.to_string();
                *note = Some(format!("rsync 失败，已回退原生硬链接快照：{e}"));
            }
        }
    }

    fs::create_dir_all(&dest)?;
    hardlink::build_tree(
        &dest,
        scan_result,
        parent_dir.as_deref(),
        parent_manifest,
        progress,
    )
}

/// 恢复增量快照到 [target_root]（覆盖同名文件；[prune] 时删除快照中不存在的文件）。
pub(crate) fn restore(
    repo: &Repo,
    name: &str,
    target_root: &Path,
    prune: bool,
    cb: Option<ProgressCallback>,
) -> io::Result<RestoreOutcome> {
    util::validate_name(name).map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;
    let started = Instant::now();
    let Some(meta) = repo.read_snapshot_meta(name)? else {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("快照不存在: {name}"),
        ));
    };
    let Some(manifest) = repo.read_manifest(name)? else {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("快照清单缺失: {name}"),
        ));
    };
    fs::create_dir_all(target_root)?;
    let progress = Progress::new(cb, 0);

    let files = if uses_cas(&meta.strategy) {
        cas::restore(repo, &manifest, target_root, &progress)?
    } else {
        restore_tree(repo, name, &manifest, target_root, &progress)?
    };
    let pruned = if prune {
        prune_extraneous(repo, &manifest, target_root)?
    } else {
        0
    };
    progress.finish();

    Ok(RestoreOutcome {
        name: name.to_string(),
        kind: KIND_SNAPSHOT.to_string(),
        strategy: meta.strategy,
        files,
        bytes: manifest.entries.iter().map(|e| e.size).sum(),
        pruned,
        duration_ms: started.elapsed().as_millis() as u64,
    })
}

/// 从快照文件树拷回目标目录。
fn restore_tree(
    repo: &Repo,
    name: &str,
    manifest: &Manifest,
    target_root: &Path,
    progress: &Progress,
) -> io::Result<u64> {
    let snapshot_dir = repo.snapshot_dir(name);
    for dir in &manifest.dirs {
        fs::create_dir_all(target_root.join(dir))?;
    }

    // 先确认快照文件齐全，避免恢复一半才发现缺文件。
    for entry in &manifest.entries {
        progress::check_cancel()?;
        let source = snapshot_dir.join(&entry.path);
        if !source.exists() {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                format!("快照文件缺失: {}", entry.path),
            ));
        }
    }

    let mut restored = 0u64;
    for entry in &manifest.entries {
        progress::check_cancel()?;
        let source = snapshot_dir.join(&entry.path);
        let dest = target_root.join(&entry.path);
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(&source, &dest)?;
        restored += 1;
        progress.add(entry.size);
    }
    Ok(restored)
}

/// 删除快照中没有的文件（仅 prune 模式）。
fn prune_extraneous(repo: &Repo, manifest: &Manifest, target_root: &Path) -> io::Result<u64> {
    let keep: HashSet<&str> = manifest.entries.iter().map(|e| e.path.as_str()).collect();
    let root = target_root.to_path_buf();
    let repo_root = repo.root().canonicalize().ok();
    let mut pruned = 0u64;
    let walker = walkdir::WalkDir::new(&root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| {
            if entry.depth() == 0 {
                return true;
            }
            match repo_root.as_deref() {
                Some(repo_root) => !entry.path().starts_with(repo_root),
                None => true,
            }
        });
    for entry in walker.filter_map(|e| e.ok()) {
        if !entry.file_type().is_file() {
            continue;
        }
        progress::check_cancel()?;
        let Ok(rel) = entry.path().strip_prefix(&root) else {
            continue;
        };
        let rel = util::path_to_slash(rel);
        if !keep.contains(rel.as_str()) && fs::remove_file(entry.path()).is_ok() {
            pruned += 1;
        }
    }
    Ok(pruned)
}

/// 校验快照完整性（[deep] 时逐个比对内容哈希，较慢）。
pub(crate) fn verify(
    repo: &Repo,
    name: &str,
    deep: bool,
    cb: Option<ProgressCallback>,
) -> io::Result<VerifyReport> {
    util::validate_name(name).map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;
    let Some(meta) = repo.read_snapshot_meta(name)? else {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("快照不存在: {name}"),
        ));
    };
    let manifest = repo.read_manifest(name)?.unwrap_or_default();
    let total: u64 = manifest.entries.iter().map(|e| e.size).sum();
    let progress = Progress::new(cb, total);

    let mut report = VerifyReport {
        name: name.to_string(),
        strategy: meta.strategy.clone(),
        ..Default::default()
    };

    for entry in &manifest.entries {
        progress::check_cancel()?;
        report.checked += 1;
        let target = if uses_cas(&meta.strategy) {
            match entry.hash.as_deref() {
                Some(h) => repo.cas_path(h),
                None => {
                    report.missing += 1;
                    push_problem(&mut report.problems, format!("{} 缺少哈希", entry.path));
                    continue;
                }
            }
        } else {
            repo.snapshot_dir(name).join(&entry.path)
        };

        let meta_file = match fs::symlink_metadata(&target) {
            Ok(m) => m,
            Err(_) => {
                report.missing += 1;
                push_problem(&mut report.problems, format!("{} 缺失", entry.path));
                progress.add(entry.size);
                continue;
            }
        };
        if meta_file.len() != entry.size {
            report.size_mismatch += 1;
            push_problem(
                &mut report.problems,
                format!("{} 大小不匹配（{} ≠ {}）", entry.path, meta_file.len(), entry.size),
            );
        }
        if deep {
            if let Some(expected) = entry.hash.as_deref() {
                let actual = hash::sha256_file(&target)?;
                report.hashed += 1;
                if actual != expected {
                    report.hash_mismatch += 1;
                    push_problem(&mut report.problems, format!("{} 内容哈希不匹配", entry.path));
                }
            }
        }
        progress.add(entry.size);
    }
    progress.finish();
    Ok(report)
}

fn push_problem(problems: &mut Vec<String>, message: String) {
    if problems.len() < 20 {
        problems.push(message);
    }
}

/// 删除快照并回收未被引用的 CAS 对象。
pub(crate) fn delete(repo: &Repo, name: &str) -> io::Result<(u64, u64)> {
    util::validate_name(name).map_err(|m| io::Error::new(io::ErrorKind::InvalidInput, m))?;
    if repo.read_snapshot_meta(name)?.is_none() && !repo.snapshot_dir(name).exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("快照不存在: {name}"),
        ));
    }
    repo.delete_snapshot(name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::progress::Progress;

    fn temp_root(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "xmc_snapshot_{}_{}_{}",
            tag,
            std::process::id(),
            crate::next_temp_id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn create_list_restore_verify_delete() {
        let tmp = temp_root("lifecycle");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(src.join("world")).unwrap();
        fs::write(src.join("server.properties"), b"motd=hello").unwrap();
        fs::write(src.join("world/level.dat"), b"level-data").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let meta = create(&repo, &src, "20260101-000000", None, Some("manual"), None).unwrap();
        assert_eq!(meta.files_total, 2);
        assert_eq!(meta.files_new, 2);
        assert!(meta.parent.is_none());
        assert!(repo.snapshot_exists(&meta.name));

        // 第二次快照：改一个文件
        fs::write(src.join("server.properties"), b"motd=world").unwrap();
        let meta2 = create(&repo, &src, "20260101-000100", Some(&meta.name), None, None).unwrap();
        assert_eq!(meta2.files_modified, 1);
        assert_eq!(meta2.files_unchanged, 1);
        // 同一秒同名会追加序号
        let meta3 = create(&repo, &src, "20260101-000100", Some(&meta2.name), None, None).unwrap();
        assert_eq!(meta3.name, "20260101-000100-2");

        let list = repo.list_snapshots().unwrap();
        assert_eq!(list.len(), 3);
        assert_eq!(list[0].name, meta3.name, "列表应按时间倒序");

        let report = verify(&repo, &meta2.name, true, None).unwrap();
        assert!(report.is_ok(), "校验失败: {:?}", report.problems);
        assert_eq!(report.checked, 2);

        let restore_dir = tmp.join("restored");
        let outcome = restore(&repo, &meta2.name, &restore_dir, false, None).unwrap();
        assert_eq!(outcome.files, 2);
        assert_eq!(
            fs::read(restore_dir.join("server.properties")).unwrap(),
            b"motd=world"
        );
        assert_eq!(
            fs::read(restore_dir.join("world/level.dat")).unwrap(),
            b"level-data"
        );

        let (objects_removed, _) = delete(&repo, &meta3.name).unwrap();
        // 非 CAS 策略没有对象可回收
        assert_eq!(objects_removed, 0);
        assert!(!repo.snapshot_exists(&meta3.name));
        let list = repo.list_snapshots().unwrap();
        assert_eq!(list.len(), 2);

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn restore_prune_removes_extra_files() {
        let tmp = temp_root("prune");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        fs::write(src.join("a.txt"), b"a").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let meta = create(&repo, &src, "20260101-010000", None, None, None).unwrap();

        let target = tmp.join("target");
        fs::create_dir_all(&target).unwrap();
        fs::write(target.join("stale.txt"), b"old").unwrap();
        let outcome = restore(&repo, &meta.name, &target, true, None).unwrap();
        assert_eq!(outcome.pruned, 1);
        assert!(!target.join("stale.txt").exists());
        assert_eq!(fs::read(target.join("a.txt")).unwrap(), b"a");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn verify_reports_missing_and_mismatch() {
        let tmp = temp_root("verify");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        fs::write(src.join("a.txt"), b"hello").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let meta = create(&repo, &src, "20260101-020000", None, None, None).unwrap();

        // 篡改快照文件
        let strategy = meta.strategy.clone();
        if uses_cas(&strategy) {
            // CAS：直接破坏对象内容
            let manifest = repo.read_manifest(&meta.name).unwrap().unwrap();
            let h = manifest.entries[0].hash.clone().unwrap();
            fs::write(repo.cas_path(&h), b"tampered!").unwrap();
        } else {
            fs::write(repo.snapshot_dir(&meta.name).join("a.txt"), b"tampered!").unwrap();
        }
        let report = verify(&repo, &meta.name, true, None).unwrap();
        if uses_cas(&strategy) {
            assert_eq!(report.size_mismatch, 1, "CAS 篡改应表现为大小不匹配");
        } else {
            assert_eq!(report.size_mismatch, 1);
        }

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn create_rejects_traversal_name() {
        let tmp = temp_root("name");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        let repo = Repo::open(&repo_root).unwrap();
        let err = create(&repo, &src, "../evil", None, None, None).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn restore_verify_delete_reject_traversal_name() {
        let tmp = temp_root("trav");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        let repo = Repo::open(&repo_root).unwrap();
        let target = tmp.join("target");

        for result in [
            restore(&repo, "../evil", &target, false, None).map(|_| ()),
            verify(&repo, "../evil", false, None).map(|_| ()),
            delete(&repo, "../evil").map(|_| ()),
        ] {
            let err = result.unwrap_err();
            assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        }
        assert!(!tmp.join("evil").exists());
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn deleting_latest_snapshot_reclaims_cas_objects() {
        let tmp = temp_root("gc");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        fs::write(src.join("a.txt"), b"first-content").unwrap();

        let repo = Repo::open(&repo_root).unwrap();
        let first = create(&repo, &src, "20260101-040000", None, None, None).unwrap();
        fs::write(src.join("a.txt"), b"second-content").unwrap();
        let second = create(&repo, &src, "20260101-050000", Some(&first.name), None, None).unwrap();
        assert_eq!(second.files_modified, 1);

        let (objects_removed, bytes_freed) = delete(&repo, &second.name).unwrap();
        if uses_cas(&first.strategy) {
            let digest = crate::hash::sha256_file(&src.join("a.txt")).unwrap();
            // 第二个快照独占的内容对象应被回收
            assert!(objects_removed > 0, "CAS 应回收孤立对象");
            assert!(bytes_freed > 0, "CAS 应释放空间");
            assert!(!repo.cas_path(&digest).exists(), "孤立对象应已删除");
        } else {
            // 硬链接快照：数据由第一个快照继续引用，无需回收
            assert_eq!(objects_removed, 0);
        }

        // 第一个快照仍可校验/恢复
        assert!(verify(&repo, &first.name, true, None).unwrap().is_ok());
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn progress_callback_is_invoked() {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEEN: AtomicU64 = AtomicU64::new(0);
        extern "C" fn cb(_done: u64, _total: u64) {
            SEEN.fetch_add(1, Ordering::Relaxed);
        }

        let tmp = temp_root("progress");
        let src = tmp.join("instance");
        let repo_root = tmp.join("repo");
        fs::create_dir_all(&src).unwrap();
        for i in 0..8 {
            fs::write(src.join(format!("f{i}.bin")), vec![b'x'; 4096]).unwrap();
        }
        let repo = Repo::open(&repo_root).unwrap();
        let _meta = super::create(&repo, &src, "20260101-030000", None, None, Some(cb)).unwrap();
        assert!(SEEN.load(Ordering::Relaxed) > 0, "进度回调应被调用");
        let _ = fs::remove_dir_all(&tmp);
        let _ = Progress::none();
    }
}
