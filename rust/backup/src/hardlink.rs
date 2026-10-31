//! Linux/macOS 增量备份的 Rust 原生回退策略：硬链接快照。
//!
//! 与 `rsync --link-dest` 语义一致：内容未变化的文件在新快照中直接硬链接到
//! 上一个快照的同一路径（不占额外空间），新增/修改的文件才真正复制。
//! 该实现不依赖外部命令，rsync 缺失（或失败）时由它兜底；
//! 同时它也是 rsync 路径的跨平台可测试实现。

use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::Path;

use crate::model::{Manifest, ManifestEntry, SnapshotStats};
use crate::progress::{self, Progress};
use crate::scan::ScanResult;

/// 在 [dest] 生成硬链接快照文件树。
///
/// [parent_dir] / [parent_manifest] 为空表示这是一个全新快照（全部复制）。
pub(crate) fn build_tree(
    dest: &Path,
    scan: &ScanResult,
    parent_dir: Option<&Path>,
    parent_manifest: Option<&Manifest>,
    progress: &Progress,
) -> io::Result<(Manifest, SnapshotStats)> {
    progress.set_total(scan.total_bytes);
    fs::create_dir_all(dest)?;

    // 目录：先建出来（含空目录），保证快照可直接被浏览/恢复。
    for dir in &scan.dirs {
        fs::create_dir_all(dest.join(dir))?;
    }

    let parent_index = parent_manifest
        .map(|m| m.index_by_path())
        .unwrap_or_default();

    let mut entries = Vec::with_capacity(scan.files.len());
    let mut stats = SnapshotStats {
        files_total: scan.files.len() as u64,
        dirs: scan.dirs.len() as u64,
        bytes_total: scan.total_bytes,
        symlinks_skipped: scan.symlinks,
        ..Default::default()
    };

    for file in &scan.files {
        progress::check_cancel()?;
        let dest_path = dest.join(&file.rel);
        if let Some(parent) = dest_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let parent_entry = parent_index.get(file.rel.as_str()).copied();
        let unchanged = parent_entry
            .map(|e| e.size == file.size && e.mtime == file.mtime)
            .unwrap_or(false);

        let mut linked = false;
        if unchanged {
            if let Some(parent_dir) = parent_dir {
                let source = parent_dir.join(&file.rel);
                if source.exists() && fs::hard_link(&source, &dest_path).is_ok() {
                    linked = true;
                }
            }
        }

        if linked {
            stats.bytes_reused += file.size;
        } else {
            // 新增、修改，或未变化但硬链接失败（跨卷/父快照缺失）→ 复制实体。
            fs::copy(&file.abs, &dest_path)?;
            stats.bytes_added += file.size;
        }

        match parent_entry {
            None => stats.files_new += 1,
            Some(_) if unchanged => stats.files_unchanged += 1,
            Some(_) => stats.files_modified += 1,
        }

        progress.add(file.size);
        entries.push(ManifestEntry {
            path: file.rel.clone(),
            size: file.size,
            mtime: file.mtime,
            hash: None,
            linked,
        });
    }

    if let Some(parent) = parent_manifest {
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

/// 根据源目录扫描结果生成清单（rsync 已经写好文件树时使用，只做统计不做复制）。
///
/// `rsync` 自己负责硬链接/复制，这里只需要把“哪些文件未变化”算出来，
/// 供统计与后续校验使用。
pub(crate) fn manifest_from_scan(
    scan: &ScanResult,
    parent_manifest: Option<&Manifest>,
) -> (Manifest, SnapshotStats) {
    let parent_index = parent_manifest
        .map(|m| m.index_by_path())
        .unwrap_or_default();
    let mut entries = Vec::with_capacity(scan.files.len());
    let mut stats = SnapshotStats {
        files_total: scan.files.len() as u64,
        dirs: scan.dirs.len() as u64,
        bytes_total: scan.total_bytes,
        symlinks_skipped: scan.symlinks,
        ..Default::default()
    };

    for file in &scan.files {
        let parent_entry = parent_index.get(file.rel.as_str()).copied();
        let unchanged = parent_entry
            .map(|e| e.size == file.size && e.mtime == file.mtime)
            .unwrap_or(false);
        match parent_entry {
            None => {
                stats.files_new += 1;
                stats.bytes_added += file.size;
            }
            Some(_) if unchanged => {
                stats.files_unchanged += 1;
                stats.bytes_reused += file.size;
            }
            Some(_) => {
                stats.files_modified += 1;
                stats.bytes_added += file.size;
            }
        }
        entries.push(ManifestEntry {
            path: file.rel.clone(),
            size: file.size,
            mtime: file.mtime,
            hash: None,
            linked: unchanged,
        });
    }

    if let Some(parent) = parent_manifest {
        let current: HashSet<&str> = entries.iter().map(|e| e.path.as_str()).collect();
        stats.files_deleted = parent
            .entries
            .iter()
            .filter(|e| !current.contains(e.path.as_str()))
            .count() as u64;
    }

    (
        Manifest {
            dirs: scan.dirs.clone(),
            entries,
        },
        stats,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::scan_source;

    fn temp_root(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "xmc_hardlink_{}_{}_{}",
            tag,
            std::process::id(),
            crate::next_temp_id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn second_snapshot_links_unchanged_files() {
        let tmp = temp_root("links");
        let src = tmp.join("src");
        std::fs::create_dir_all(src.join("logs")).unwrap();
        std::fs::write(src.join("server.jar"), b"jar-bytes").unwrap();
        std::fs::write(src.join("logs/latest.log"), b"log-line").unwrap();

        let progress = Progress::none();
        let scan1 = scan_source(&src, None).unwrap();
        let snap1 = tmp.join("snap1");
        let (manifest1, stats1) = build_tree(&snap1, &scan1, None, None, &progress).unwrap();
        assert_eq!(stats1.files_new, 2);
        assert_eq!(stats1.bytes_added, scan1.total_bytes);
        assert_eq!(stats1.bytes_reused, 0);

        // 只改日志文件：jar 应硬链接复用
        std::fs::write(src.join("logs/latest.log"), b"log-line-2").unwrap();
        let scan2 = scan_source(&src, None).unwrap();
        let snap2 = tmp.join("snap2");
        let (manifest2, stats2) = build_tree(
            &snap2,
            &scan2,
            Some(snap1.as_path()),
            Some(&manifest1),
            &progress,
        )
        .unwrap();
        assert_eq!(stats2.files_new, 0);
        assert_eq!(stats2.files_modified, 1);
        assert_eq!(stats2.files_unchanged, 1);
        // log-line-2 = 10 字节，未变化的 server.jar("jar-bytes") = 9 字节
        assert_eq!(stats2.bytes_added, 10);
        assert_eq!(stats2.bytes_reused, 9);

        let jar_entry = manifest2
            .entries
            .iter()
            .find(|e| e.path == "server.jar")
            .unwrap();
        assert!(jar_entry.linked, "未变化的文件应为硬链接");
        let log_entry = manifest2
            .entries
            .iter()
            .find(|e| e.path == "logs/latest.log")
            .unwrap();
        assert!(!log_entry.linked);
        assert_eq!(fs::read(snap2.join("logs/latest.log")).unwrap(), b"log-line-2");
        assert_eq!(fs::read(snap1.join("logs/latest.log")).unwrap(), b"log-line");

        // 删除源文件：新快照不再包含它，且统计为 deleted
        std::fs::remove_file(src.join("server.jar")).unwrap();
        let scan3 = scan_source(&src, None).unwrap();
        let snap3 = tmp.join("snap3");
        let (_manifest3, stats3) = build_tree(
            &snap3,
            &scan3,
            Some(snap2.as_path()),
            Some(&manifest2),
            &progress,
        )
        .unwrap();
        assert_eq!(stats3.files_deleted, 1);
        assert!(!snap3.join("server.jar").exists());

        let _ = fs::remove_dir_all(&tmp);
    }
}
