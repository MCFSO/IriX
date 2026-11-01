//! 源目录扫描：增量备份的输入清单。
//!
//! 一次 walk 收集全部普通文件（相对路径、字节数、修改时间）与目录列表，
//! 供三种策略复用，避免重复 syscall。

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use walkdir::WalkDir;

use crate::progress;

/// 单个待备份文件。
#[derive(Clone, Debug)]
pub(crate) struct ScannedFile {
    /// 相对源根目录的路径（`/` 分隔）。
    pub(crate) rel: String,
    /// 绝对路径。
    pub(crate) abs: PathBuf,
    pub(crate) size: u64,
    /// 源文件最后修改时间（Unix 纳秒，见下方精度说明）。
    pub(crate) mtime: i64,
}

/// 扫描结果。
#[derive(Default, Debug)]
pub(crate) struct ScanResult {
    pub(crate) files: Vec<ScannedFile>,
    /// 相对路径的目录（含空目录），恢复时用于建目录。
    pub(crate) dirs: Vec<String>,
    pub(crate) total_bytes: u64,
    /// 被跳过的符号链接数量（不参与备份，避免循环与跨机无意义链接）。
    pub(crate) symlinks: u64,
}

/// 扫描 [root]，跳过 [exclude] 子树（备份仓库自身）。
pub(crate) fn scan_source(root: &Path, exclude: Option<&Path>) -> io::Result<ScanResult> {
    let root_canonical = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let exclude_canonical = exclude.and_then(|p| p.canonicalize().ok());

    let mut result = ScanResult::default();
    let walker = WalkDir::new(&root_canonical)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| {
            if entry.depth() == 0 {
                return true;
            }
            if let Some(ex) = exclude_canonical.as_deref() {
                if entry.path() == ex {
                    return false;
                }
                // 仓库位于源目录内部时（例如自定义数据根在实例目录下），整体跳过。
                if entry.path().starts_with(ex) {
                    return false;
                }
            }
            true
        });

    for entry in walker {
        progress::check_cancel()?;
        let entry = match entry {
            Ok(e) => e,
            // 单个条目无权限等错误不中断整个备份，跳过即可。
            Err(_) => continue,
        };
        let path = entry.path();
        if path == root_canonical {
            continue;
        }
        let rel = match path.strip_prefix(&root_canonical) {
            Ok(r) => crate::util::path_to_slash(r),
            Err(_) => continue,
        };
        if rel.is_empty() {
            continue;
        }
        let file_type = entry.file_type();
        if file_type.is_symlink() {
            result.symlinks += 1;
            continue;
        }
        if file_type.is_dir() {
            result.dirs.push(rel);
            continue;
        }
        if !file_type.is_file() {
            continue;
        }
        let meta = match fs::symlink_metadata(path) {
            Ok(m) => m,
            Err(_) => continue,
        };
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            // 纳秒精度：秒级 mtime 会把"同一秒内改写、大小不变"的文件误判为未变化，
            // 使增量快照漏掉真实改动（CI 上跑得快时必现）。i64 纳秒可表示到 2262 年。
            .map(|d| d.as_nanos().min(i64::MAX as u128) as i64)
            .unwrap_or(0);
        result.total_bytes += meta.len();
        result.files.push(ScannedFile {
            rel,
            abs: path.to_path_buf(),
            size: meta.len(),
            mtime,
        });
    }

    result.files.sort_by(|a, b| a.rel.cmp(&b.rel));
    result.dirs.sort();
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_skips_excluded_tree() {
        let tmp = std::env::temp_dir().join(format!("xmc_scan_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let src = tmp.join("src");
        fs::create_dir_all(src.join("sub")).unwrap();
        fs::create_dir_all(tmp.join("repo")).unwrap();
        fs::write(src.join("a.txt"), b"hello").unwrap();
        fs::write(src.join("sub/b.txt"), b"world").unwrap();
        fs::write(tmp.join("repo/keep.txt"), b"repo").unwrap();

        let result = scan_source(&src, Some(&tmp.join("repo"))).unwrap();
        assert_eq!(result.files.len(), 2, "应只扫描到 2 个文件");
        assert_eq!(result.total_bytes, 10);
        assert_eq!(result.dirs.len(), 1);
        assert_eq!(result.dirs[0], "sub");

        // 仓库不在源目录内时，排除项不应影响结果
        let result2 = scan_source(&src, None).unwrap();
        assert_eq!(result2.files.len(), 2);

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn mtime_has_sub_second_precision() {
        let tmp = std::env::temp_dir().join(format!(
            "xmc_scan_mtime_{}_{}",
            std::process::id(),
            crate::next_temp_id()
        ));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        fs::write(tmp.join("a.bin"), b"1234").unwrap();

        let result = scan_source(&tmp, None).unwrap();
        let mtime = result.files[0].mtime;
        // 秒级时间戳约 1.7e9，纳秒级约 1.7e18：后者大于 1.5e18 才算纳秒精度。
        assert!(
            mtime > 1_500_000_000_000_000_000,
            "mtime 应为 Unix 纳秒（同秒改写才能被识别），实际 {mtime}"
        );

        // 大小相同、仅内容与 mtime 变化的文件必须被判为"已修改"，
        // 这正是旧实现（秒级 mtime）在 CI 上偶发漏判的场景。
        // 睡 2ms 以跨过 Windows NTFS 的 100ns 时间戳粒度，避免测试自身抖动。
        std::thread::sleep(std::time::Duration::from_millis(2));
        fs::write(tmp.join("a.bin"), b"5678").unwrap();
        let result2 = scan_source(&tmp, None).unwrap();
        assert_eq!(result2.files[0].size, result.files[0].size);
        assert_ne!(
            result2.files[0].mtime, mtime,
            "同尺寸改写后 mtime 必须变化（纳秒精度）"
        );

        let _ = fs::remove_dir_all(&tmp);
    }
}
