//! Linux/macOS 增量备份策略：`rsync --link-dest` 硬链接快照。
//!
//! 命令形如：
//!
//! ```text
//! rsync -rlpt --link-dest=<上一个快照绝对路径> <源>/ <新快照>/
//! ```
//!
//! - `-r` 递归、`-l` 保留符号链接、`-p` 权限、`-t` 时间戳（与 `-a` 相比
//!   不要求 root 才能保留 owner/group，普通用户可用；macOS 自带 rsync 2.6.9
//!   与 openrsync 都支持）；
//! - `--link-dest` 让内容未变化的文件硬链接到上一个快照，实现“只存增量”；
//! - rsync 3.1+ 额外加 `--info=progress2 --no-inc-recursive` 以回传整体百分比，
//!   老版本则退化为不确定进度（UI 显示转圈）。
//!
//! 进度通过把 rsync 输出重定向到仓库 `temp/` 下的日志文件、再轮询解析百分比
//! 得到（不开管道，避免子进程写满管道阻塞）；取消时直接 kill 子进程。

use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::OnceLock;
use std::time::Duration;

use crate::progress::{self, Progress};
use crate::repo::Repo;
use crate::util;

static AVAILABLE: OnceLock<bool> = OnceLock::new();
static VERSION: OnceLock<Option<String>> = OnceLock::new();

/// 是否检测到可用的 rsync 命令（结果缓存，避免每次都 spawn）。
pub(crate) fn available() -> bool {
    *AVAILABLE.get_or_init(|| version_string().is_some())
}

/// rsync 版本首行（如 `rsync  version 3.2.7  protocol version 31`）。
pub(crate) fn version_string() -> Option<String> {
    VERSION
        .get_or_init(|| {
            let output = Command::new("rsync")
                .arg("--version")
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .output()
                .ok()?;
            if !output.status.success() {
                return None;
            }
            let text = String::from_utf8_lossy(&output.stdout);
            text.lines()
                .next()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
        })
        .clone()
}

/// 解析版本号主次版本，用于判断是否支持 `--info=progress2`。
fn supports_progress2() -> bool {
    let Some(version) = version_string() else {
        return false;
    };
    let Some(pos) = version.find("version") else {
        return false;
    };
    let tail = &version[pos + "version".len()..];
    let mut parts = tail.trim().split('.').filter_map(|p| {
        p.chars()
            .take_while(|c| c.is_ascii_digit())
            .collect::<String>()
            .parse::<u32>()
            .ok()
    });
    match (parts.next(), parts.next()) {
        (Some(major), Some(minor)) => (major, minor) >= (3, 1),
        _ => false,
    }
}

/// 用 rsync 在 [dest] 生成硬链接快照。
///
/// [link_dest] 为上一个快照目录（可选）。`exclude` 用于跳过位于源目录内部的
/// 备份仓库，避免自我递归。
pub(crate) fn create_snapshot(
    repo: &Repo,
    src: &Path,
    dest: &Path,
    link_dest: Option<&Path>,
    exclude: Option<&Path>,
    progress: &Progress,
) -> io::Result<()> {
    if !available() {
        return Err(io::Error::new(io::ErrorKind::NotFound, "未找到 rsync 命令"));
    }

    fs::create_dir_all(dest)?;

    let mut args: Vec<String> = vec!["-rlpt".to_string()];
    if supports_progress2() {
        args.push("--info=progress2".to_string());
        args.push("--no-inc-recursive".to_string());
    }
    if let Some(parent_snapshot) = link_dest {
        // --link-dest 的相对路径是相对目标目录解释的，统一转绝对路径避免歧义。
        let absolute = parent_snapshot
            .canonicalize()
            .unwrap_or_else(|_| parent_snapshot.to_path_buf());
        args.push(format!("--link-dest={}", absolute.display()));
    }
    if let Some(excluded) = exclude {
        if let Some(rel) = relative_inside(src, excluded) {
            if !rel.is_empty() {
                args.push(format!("--exclude=/{rel}/"));
            }
        }
    }
    args.push(with_trailing_slash(src));
    args.push(with_trailing_slash(dest));

    run_with_fallback(repo, &args, progress)
}

/// 执行 rsync；遇到老版本不支持的进度参数时去掉后重试一次。
fn run_with_fallback(repo: &Repo, args: &[String], progress: &Progress) -> io::Result<()> {
    let (status, log_dir) = run(repo, args, progress)?;
    let stderr_text = util::read_tail_string(&log_dir.join("rsync.stderr.log"), 4096);
    let stdout_text = util::read_tail_string(&log_dir.join("rsync.stdout.log"), 8192);
    let _ = fs::remove_dir_all(&log_dir);

    if status.success() {
        return Ok(());
    }
    let unsupported = stderr_text.contains("unknown option")
        || stderr_text.contains("unrecognized option")
        || stderr_text.contains("illegal option");
    if unsupported && args.iter().any(|a| a.starts_with("--info=")) {
        let retry_args: Vec<String> = args
            .iter()
            .filter(|a| !a.starts_with("--info=") && !a.starts_with("--no-inc-recursive"))
            .cloned()
            .collect();
        let (status2, log_dir2) = run(repo, &retry_args, progress)?;
        let stderr2 = util::read_tail_string(&log_dir2.join("rsync.stderr.log"), 4096);
        let stdout2 = util::read_tail_string(&log_dir2.join("rsync.stdout.log"), 8192);
        let _ = fs::remove_dir_all(&log_dir2);
        if status2.success() {
            return Ok(());
        }
        return Err(rsync_error(status2, &stderr2, &stdout2));
    }

    Err(rsync_error(status, &stderr_text, &stdout_text))
}

fn rsync_error(status: ExitStatus, stderr_text: &str, stdout_text: &str) -> io::Error {
    let text = if stderr_text.trim().is_empty() {
        stdout_text
    } else {
        stderr_text
    };
    io::Error::new(
        io::ErrorKind::Other,
        format!("rsync 失败（退出码 {:?}）: {}", status.code(), first_line(text)),
    )
}

/// 执行一次 rsync，期间轮询日志文件回传进度；取消时 kill 子进程。
///
/// 返回退出状态与本次日志目录（调用方负责清理）。
fn run(repo: &Repo, args: &[String], progress: &Progress) -> io::Result<(ExitStatus, PathBuf)> {
    let log_dir = repo
        .temp_dir()
        .join(format!("rsync-{}", crate::next_temp_id()));
    fs::create_dir_all(&log_dir)?;
    let stdout_path = log_dir.join("rsync.stdout.log");
    let stderr_path = log_dir.join("rsync.stderr.log");
    let stdout_file = File::create(&stdout_path)?;
    let stderr_file = File::create(&stderr_path)?;

    let mut child: Child = Command::new("rsync")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout_file))
        .stderr(Stdio::from(stderr_file))
        .spawn()?;

    let with_progress = args.iter().any(|a| a.starts_with("--info="));
    let mut last_permille: Option<u64> = None;
    loop {
        if progress::is_cancelled() {
            let _ = child.kill();
            let _ = child.wait();
            let _ = fs::remove_dir_all(&log_dir);
            return Err(progress::cancelled_error());
        }
        if let Some(status) = child.try_wait()? {
            return Ok((status, log_dir));
        }
        if with_progress {
            let tail = util::read_tail_string(&stdout_path, 8192);
            if let Some(permille) = last_percent_permille(&tail) {
                if last_permille != Some(permille) {
                    last_permille = Some(permille);
                    progress.report_permille(permille);
                }
            }
        }
        std::thread::sleep(Duration::from_millis(120));
    }
}

/// 从 rsync `--info=progress2` 输出尾部解析最后一个百分比（换算成千分比）。
fn last_percent_permille(text: &str) -> Option<u64> {
    let mut best: Option<u64> = None;
    let bytes = text.as_bytes();
    for (idx, ch) in text.char_indices() {
        if ch != '%' {
            continue;
        }
        // 从 '%' 往前找连续的「数字 + 千分位逗号」
        let mut start = idx;
        while start > 0 {
            let b = bytes[start - 1];
            if b.is_ascii_digit() || b == b',' {
                start -= 1;
            } else {
                break;
            }
        }
        let digits: String = text[start..idx]
            .chars()
            .filter(|c| c.is_ascii_digit())
            .collect();
        if digits.is_empty() || digits.len() > 3 {
            continue;
        }
        if let Ok(value) = digits.parse::<u64>() {
            if value <= 100 {
                best = Some(value * 10);
            }
        }
    }
    best
}

fn first_line(text: &str) -> String {
    text.lines()
        .map(|l| l.trim())
        .find(|l| !l.is_empty())
        .unwrap_or("未知错误")
        .chars()
        .take(300)
        .collect()
}

fn with_trailing_slash(path: &Path) -> String {
    let mut s = path.display().to_string();
    if !s.ends_with('/') && !s.ends_with('\\') {
        s.push('/');
    }
    s
}

/// [target] 是否位于 [root] 内部，返回相对路径（`/` 分隔）。
fn relative_inside(root: &Path, target: &Path) -> Option<String> {
    let root = root.canonicalize().ok()?;
    let target = target.canonicalize().ok()?;
    let rel = target.strip_prefix(&root).ok()?;
    let mut parts: Vec<String> = Vec::new();
    for component in rel.components() {
        if let std::path::Component::Normal(part) = component {
            parts.push(part.to_string_lossy().to_string());
        }
    }
    Some(parts.join("/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_progress_percent() {
        let text = "     32,768   0%    0.00kB/s    0:00:00 (xfr#0, to-chk=128/128)\r\
                           1,048,576  42%    1.00MB/s    0:00:01 (xfr#12, to-chk=64/128)";
        assert_eq!(last_percent_permille(text), Some(420));
        assert_eq!(last_percent_permille("no progress here"), None);
        assert_eq!(last_percent_permille("  999,999 100%   1.0MB/s"), Some(1000));
    }

    #[test]
    fn trailing_slash_is_added() {
        let plain = with_trailing_slash(Path::new("/tmp/a"));
        assert!(plain.ends_with('/'), "应以分隔符结尾: {plain}");
        assert_eq!(with_trailing_slash(Path::new("/tmp/a/")), "/tmp/a/");
    }
}
