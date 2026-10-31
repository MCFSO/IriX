//! XMC Server Launcher 备份模块
//!
//! 提供两类备份能力，供 Flutter 通过 FFI 调用（全部在 Rust 侧实现）：
//!
//! 1. **全量备份**（原备份功能）：把整个实例目录用 rayon 并行 Deflate 压缩成标准
//!    ZIP 归档，可被任意标准工具解压（[`do_backup`] / `backup_directory`）。
//! 2. **增量备份**：Linux/macOS 用 `rsync --link-dest` 硬链接快照（rsync 不可用时
//!    回退到 Rust 原生硬链接快照），Windows 用 SHA-256 哈希比对 + 内容寻址存储（CAS）；
//!    统一入口为 `backup_request(op, argsJson, progressCb)`，返回 JSON。
//!
//! 两类备份都落在同一个“备份仓库”里（布局见 `repo.rs`），
//! Dart 侧通过 `lib/services/backup_manager.dart` 使用。

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

use crc32fast::Hasher;
use flate2::write::DeflateEncoder;
use flate2::Compression;
use rayon::prelude::*;
use walkdir::WalkDir;

mod api;
mod cas;
mod full;
mod hardlink;
mod hash;
mod model;
mod progress;
mod repo;
mod rsync;
mod scan;
mod snapshot;
mod util;

use progress::ProgressCallback;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

static CANCELLED: AtomicBool = AtomicBool::new(false);
static TEMP_ID: AtomicU64 = AtomicU64::new(0);

/// 是否已请求取消（供各策略轮询）。
pub(crate) fn cancel_requested() -> bool {
    CANCELLED.load(Ordering::SeqCst)
}

/// 清空取消标志（每个新任务开始时调用）。
pub(crate) fn clear_cancel() {
    CANCELLED.store(false, Ordering::SeqCst);
}

/// 生成本进程内唯一的临时文件序号。
pub(crate) fn next_temp_id() -> u64 {
    TEMP_ID.fetch_add(1, Ordering::Relaxed)
}

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

#[no_mangle]
pub extern "C" fn backup_directory(
    src_path: *const libc::c_char,
    dst_path: *const libc::c_char,
    files_to_backup: *const *const libc::c_char,
    files_count: usize,
    compression_level: u32,
    progress_cb: ProgressCallback,
) -> libc::c_int {
    // L-6：catch_unwind 防止内部 panic 跨 FFI unwind（UB/进程终止）。
    catch_unwind(AssertUnwindSafe(|| {
        backup_directory_impl(
            src_path,
            dst_path,
            files_to_backup,
            files_count,
            compression_level,
            progress_cb,
        )
    }))
    .unwrap_or_else(|_| {
        set_last_error("Rust 侧 panic，已捕获（L-6）");
        2
    })
}

fn backup_directory_impl(
    src_path: *const libc::c_char,
    dst_path: *const libc::c_char,
    files_to_backup: *const *const libc::c_char,
    files_count: usize,
    compression_level: u32,
    progress_cb: ProgressCallback,
) -> libc::c_int {
    clear_cancel();

    if src_path.is_null() {
        set_last_error("源路径为空指针");
        return 1;
    }
    let src = match unsafe { CStr::from_ptr(src_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("源路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    if dst_path.is_null() {
        set_last_error("目标路径为空指针");
        return 1;
    }
    let dst = match unsafe { CStr::from_ptr(dst_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("目标路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    let mut files: Vec<&str> = Vec::with_capacity(files_count);
    if !files_to_backup.is_null() && files_count > 0 {
        for i in 0..files_count {
            let ptr = unsafe { *files_to_backup.add(i) };
            if ptr.is_null() {
                continue;
            }
            match unsafe { CStr::from_ptr(ptr) }.to_str() {
                Ok(s) => files.push(s),
                Err(_) => continue,
            }
        }
    }

    let level = compression_level.min(9);
    match do_backup(src, dst, &files, level, Some(progress_cb), None) {
        Ok(_) => 0,
        Err(e) if progress::is_cancel_error(&e) => 3,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn cancel_backup() {
    CANCELLED.store(true, Ordering::SeqCst);
}

#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        let cstr = borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("未知错误").ok());
        cstr
            .unwrap_or_else(|| CString::new("未知错误").unwrap())
            .into_raw()
    })
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 全量备份统计（压缩文件数 + 源字节数）。
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct ZipStats {
    pub(crate) files: u64,
    pub(crate) bytes_total: u64,
}

struct Entry {
    name: String,
    compressed: Vec<u8>,
    uncompressed_size: u64,
    crc32: u32,
    dos_time: u16,
    dos_date: u16,
}

/// 文件元数据预收集结构，避免并行阶段重复 syscall。
struct FileToCompress {
    path_buf: std::path::PathBuf,
    size: u64,
    modified: Option<std::time::SystemTime>,
}

/// 全量备份：把 [src_dir] 下 [files] 指定的条目（文件/目录）压缩为 ZIP。
///
/// [exclude] 用于跳过位于源目录内部的备份仓库（避免把自己打包进去）。
pub(crate) fn do_backup(
    src_dir: &str,
    dst_file: &str,
    files: &[&str],
    compression_level: u32,
    progress_cb: Option<ProgressCallback>,
    exclude: Option<&Path>,
) -> io::Result<ZipStats> {
    let result = do_backup_inner(
        src_dir,
        dst_file,
        files,
        compression_level,
        progress_cb,
        exclude,
    );
    if matches!(&result, Err(e) if progress::is_cancel_error(e)) {
        let _ = fs::remove_file(dst_file);
    }
    result
}

fn do_backup_inner(
    src_dir: &str,
    dst_file: &str,
    files: &[&str],
    compression_level: u32,
    progress_cb: Option<ProgressCallback>,
    exclude: Option<&Path>,
) -> io::Result<ZipStats> {
    let src_path = Path::new(src_dir);
    let dst_path = Path::new(dst_file);
    // Windows 上 canonicalize 会返回 `\\?\` verbatim 前缀，必须让遍历路径与
    // 排除路径处于同一形态（都 canonicalize），前缀比较才成立。
    let src_canonical = src_path
        .canonicalize()
        .unwrap_or_else(|_| src_path.to_path_buf());
    let exclude = exclude.and_then(|p| p.canonicalize().ok());

    // 1. 收集所有待压缩文件并预取 metadata（一次 syscall 完成）
    let mut to_compress: Vec<FileToCompress> = Vec::new();
    let mut estimated_total: u64 = 0;
    for file_name in files {
        let full_path = src_canonical.join(file_name);
        if full_path.exists() {
            let walker = WalkDir::new(&full_path).into_iter().filter_entry(|entry| {
                if entry.depth() == 0 {
                    return true;
                }
                match exclude.as_deref() {
                    Some(ex) => {
                        let path = entry.path();
                        !(path == ex || path.starts_with(ex))
                    }
                    None => true,
                }
            });
            for entry in walker.filter_map(|e| e.ok()) {
                if entry.file_type().is_file() {
                    let meta = entry.metadata();
                    let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
                    let modified = meta.ok().and_then(|m| m.modified().ok());
                    estimated_total += size;
                    to_compress.push(FileToCompress {
                        path_buf: entry.path().to_path_buf(),
                        size,
                        modified,
                    });
                }
            }
        }
    }
    let stats = ZipStats {
        files: to_compress.len() as u64,
        bytes_total: estimated_total,
    };
    let total_bytes = AtomicU64::new(estimated_total);
    let processed_bytes = AtomicU64::new(0);

    // 2. 带 BufWriter 的输出文件 + 预分配中央目录缓冲区
    let raw_file = File::create(dst_path)?;
    let mut writer = io::BufWriter::with_capacity(256 * 1024, raw_file);
    let buffer = &mut writer;
    let mut central_dir: Vec<u8> = Vec::with_capacity(to_compress.len() * 80);
    let mut offset: u64 = 0;

    // 3. 并行压缩
    let entries: Vec<Entry> = to_compress
        .par_iter()
        .map(|fc| -> io::Result<Entry> {
            if cancel_requested() {
                return Err(progress::cancelled_error());
            }

            let path = &fc.path_buf;
            let rel_path = strip_prefix_fast(path, &src_canonical);
            let name = path_to_zip_name(&rel_path);

            let mut file = File::open(path)?;
            let mut data = Vec::with_capacity(fc.size as usize);
            file.read_to_end(&mut data)?;
            let real_size = data.len() as u64;

            if real_size > fc.size {
                total_bytes.fetch_add(real_size - fc.size, Ordering::Relaxed);
            }

            let crc32 = {
                let mut hasher = Hasher::new();
                hasher.update(&data);
                hasher.finalize()
            };

            let mut encoder = DeflateEncoder::new(
                Vec::with_capacity(data.len() / 2),
                Compression::new(compression_level),
            );
            encoder.write_all(&data)?;
            let compressed = encoder.finish()?;

            let (dos_time, dos_date) = fc
                .modified
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| epoch_to_dos(d.as_secs()))
                .unwrap_or((0, 0x0021));

            let new_processed = processed_bytes.fetch_add(real_size, Ordering::Relaxed) + real_size;
            if let Some(cb) = progress_cb {
                cb(
                    new_processed.min(total_bytes.load(Ordering::Relaxed)),
                    total_bytes.load(Ordering::Relaxed),
                );
            }

            Ok(Entry {
                name,
                compressed,
                uncompressed_size: real_size,
                crc32,
                dos_time,
                dos_date,
            })
        })
        .collect::<Result<_, _>>()?;

    // 4. 串行写入 ZIP
    for entry in &entries {
        if cancel_requested() {
            return Err(progress::cancelled_error());
        }
        write_entry(buffer, entry, &mut offset, &mut central_dir)?;
    }

    let entry_count = entries.len() as u64;

    // 5. 中央目录
    let cd_offset = offset;
    let cd_size = central_dir.len() as u64;
    buffer.write_all(&central_dir)?;

    // 6. ZIP64 EOCD
    let entries_overflow = entry_count > 0xFFFF;
    let cd_size_overflow = cd_size > 0xFFFFFFFF;
    let cd_offset_overflow = cd_offset > 0xFFFFFFFF;
    let needs_zip64 = entries_overflow || cd_size_overflow || cd_offset_overflow;

    if needs_zip64 {
        let zip64_eocd_offset = cd_offset + cd_size;
        buffer.write_all(&0x06064b50u32.to_le_bytes())?;
        buffer.write_all(&44u64.to_le_bytes())?;
        buffer.write_all(&45u16.to_le_bytes())?;
        buffer.write_all(&45u16.to_le_bytes())?;
        buffer.write_all(&0u32.to_le_bytes())?;
        buffer.write_all(&0u32.to_le_bytes())?;
        buffer.write_all(&entry_count.to_le_bytes())?;
        buffer.write_all(&entry_count.to_le_bytes())?;
        buffer.write_all(&cd_size.to_le_bytes())?;
        buffer.write_all(&cd_offset.to_le_bytes())?;
        // ZIP64 EOCD 定位器
        buffer.write_all(&0x07064b50u32.to_le_bytes())?;
        buffer.write_all(&0u32.to_le_bytes())?;
        buffer.write_all(&zip64_eocd_offset.to_le_bytes())?;
        buffer.write_all(&1u32.to_le_bytes())?;
    }

    // 7. 普通 EOCD
    buffer.write_all(&0x06054b50u32.to_le_bytes())?;
    buffer.write_all(&0u16.to_le_bytes())?;
    buffer.write_all(&0u16.to_le_bytes())?;
    buffer.write_all(
        &(if entries_overflow {
            0xFFFF
        } else {
            entry_count as u16
        })
        .to_le_bytes(),
    )?;
    buffer.write_all(
        &(if entries_overflow {
            0xFFFF
        } else {
            entry_count as u16
        })
        .to_le_bytes(),
    )?;
    buffer.write_all(
        &(if cd_size_overflow {
            0xFFFFFFFF
        } else {
            cd_size as u32
        })
        .to_le_bytes(),
    )?;
    buffer.write_all(
        &(if cd_offset_overflow {
            0xFFFFFFFF
        } else {
            cd_offset as u32
        })
        .to_le_bytes(),
    )?;
    buffer.write_all(&0u16.to_le_bytes())?;

    buffer.flush()?;
    Ok(stats)
}

fn write_entry(
    writer: &mut impl Write,
    entry: &Entry,
    offset: &mut u64,
    central_dir: &mut Vec<u8>,
) -> io::Result<()> {
    let lfh_offset = *offset;
    let comp_size = entry.compressed.len() as u64;
    let uncomp_size = entry.uncompressed_size;
    let needs_entry_zip64 = comp_size > 0xFFFFFFFF || uncomp_size > 0xFFFFFFFF;

    let comp_field = if needs_entry_zip64 {
        0xFFFFFFFF
    } else {
        comp_size as u32
    };
    let uncomp_field = if needs_entry_zip64 {
        0xFFFFFFFF
    } else {
        uncomp_size as u32
    };

    // 本地文件头 ZIP64 extra（最多 20 字节，栈分配）
    let mut lfh_extra = [0u8; 20];
    let lfh_extra_len = if needs_entry_zip64 {
        lfh_extra[0..2].copy_from_slice(&0x0001u16.to_le_bytes());
        lfh_extra[2..4].copy_from_slice(&16u16.to_le_bytes());
        lfh_extra[4..12].copy_from_slice(&uncomp_size.to_le_bytes());
        lfh_extra[12..20].copy_from_slice(&comp_size.to_le_bytes());
        20usize
    } else {
        0usize
    };

    writer.write_all(&0x04034b50u32.to_le_bytes())?;
    writer.write_all(&(if needs_entry_zip64 { 45u16 } else { 20u16 }).to_le_bytes())?;
    writer.write_all(&0u16.to_le_bytes())?;
    writer.write_all(&8u16.to_le_bytes())?;
    writer.write_all(&entry.dos_time.to_le_bytes())?;
    writer.write_all(&entry.dos_date.to_le_bytes())?;
    writer.write_all(&entry.crc32.to_le_bytes())?;
    writer.write_all(&comp_field.to_le_bytes())?;
    writer.write_all(&uncomp_field.to_le_bytes())?;
    writer.write_all(&(entry.name.len() as u16).to_le_bytes())?;
    writer.write_all(&(lfh_extra_len as u16).to_le_bytes())?;
    writer.write_all(entry.name.as_bytes())?;
    if lfh_extra_len > 0 {
        writer.write_all(&lfh_extra[..lfh_extra_len])?;
    }

    *offset += 30 + entry.name.len() as u64 + lfh_extra_len as u64;

    writer.write_all(&entry.compressed)?;
    *offset += entry.compressed.len() as u64;

    // 中央目录头 ZIP64 extra（最多 4 + 16 + 8 = 28 字节，栈分配）
    let needs_cd_offset_zip64 = lfh_offset > 0xFFFFFFFF;
    let any_cd_zip64 = needs_entry_zip64 || needs_cd_offset_zip64;
    let mut cdh_extra_buf = [0u8; 32];
    let cdh_extra_len: usize = if any_cd_zip64 {
        let mut data_len = 0usize;
        if needs_entry_zip64 {
            data_len += 16;
        }
        if needs_cd_offset_zip64 {
            data_len += 8;
        }
        cdh_extra_buf[0..2].copy_from_slice(&0x0001u16.to_le_bytes());
        cdh_extra_buf[2..4].copy_from_slice(&(data_len as u16).to_le_bytes());
        let mut pos = 4;
        if needs_entry_zip64 {
            cdh_extra_buf[pos..pos + 8].copy_from_slice(&uncomp_size.to_le_bytes());
            pos += 8;
            cdh_extra_buf[pos..pos + 8].copy_from_slice(&comp_size.to_le_bytes());
            pos += 8;
        }
        if needs_cd_offset_zip64 {
            cdh_extra_buf[pos..pos + 8].copy_from_slice(&lfh_offset.to_le_bytes());
            pos += 8;
        }
        pos
    } else {
        0
    };

    let cdh_comp = if needs_entry_zip64 {
        0xFFFFFFFF
    } else {
        comp_size as u32
    };
    let cdh_uncomp = if needs_entry_zip64 {
        0xFFFFFFFF
    } else {
        uncomp_size as u32
    };
    let cdh_off = if needs_cd_offset_zip64 {
        0xFFFFFFFF
    } else {
        lfh_offset as u32
    };

    central_dir.extend_from_slice(&0x02014b50u32.to_le_bytes());
    central_dir.extend_from_slice(&(if any_cd_zip64 { 45u16 } else { 20u16 }).to_le_bytes());
    central_dir.extend_from_slice(&(if any_cd_zip64 { 45u16 } else { 20u16 }).to_le_bytes());
    central_dir.extend_from_slice(&0u16.to_le_bytes());
    central_dir.extend_from_slice(&8u16.to_le_bytes());
    central_dir.extend_from_slice(&entry.dos_time.to_le_bytes());
    central_dir.extend_from_slice(&entry.dos_date.to_le_bytes());
    central_dir.extend_from_slice(&entry.crc32.to_le_bytes());
    central_dir.extend_from_slice(&cdh_comp.to_le_bytes());
    central_dir.extend_from_slice(&cdh_uncomp.to_le_bytes());
    central_dir.extend_from_slice(&(entry.name.len() as u16).to_le_bytes());
    central_dir.extend_from_slice(&(cdh_extra_len as u16).to_le_bytes());
    central_dir.extend_from_slice(&0u16.to_le_bytes());
    central_dir.extend_from_slice(&0u16.to_le_bytes());
    central_dir.extend_from_slice(&0u16.to_le_bytes());
    central_dir.extend_from_slice(&0u32.to_le_bytes());
    central_dir.extend_from_slice(&cdh_off.to_le_bytes());
    central_dir.extend_from_slice(entry.name.as_bytes());
    if cdh_extra_len > 0 {
        central_dir.extend_from_slice(&cdh_extra_buf[..cdh_extra_len]);
    }

    Ok(())
}

/// 高效去前缀，不额外分配。
fn strip_prefix_fast<'a>(path: &'a Path, prefix: &Path) -> &'a Path {
    path.strip_prefix(prefix).unwrap_or(path)
}

/// 路径转 ZIP 归档名（正斜杠），仅在含反斜杠时才分配。
fn path_to_zip_name(path: &Path) -> String {
    let s = path.to_string_lossy();
    if s.contains('\\') {
        s.replace('\\', "/")
    } else {
        s.into_owned()
    }
}

fn epoch_to_dos(secs: u64) -> (u16, u16) {
    let days = (secs / 86400) as i64;
    let secs = secs % 86400;
    let hour = secs / 3600;
    let minute = (secs % 3600) / 60;
    let second = secs % 60;

    let (y, m, d) = civil_from_days(days);
    let dos_date = if y >= 1980 {
        (((y - 1980) as u16) << 9) | ((m as u16) << 5) | (d as u16)
    } else {
        0x0021
    };
    let dos_time = ((hour as u16) << 11) | ((minute as u16) << 5) | ((second / 2) as u16);
    (dos_time, dos_date)
}

pub(crate) fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as i64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn noop_cb(_: u64, _: u64) {}

    #[test]
    fn parallel_backup_produces_valid_zip() {
        let tmp = std::env::temp_dir().join("xmc_backup_test");
        let _ = fs::remove_dir_all(&tmp);
        let src = tmp.join("src");
        fs::create_dir_all(&src).unwrap();

        let content_a = b"hello world from file A ".repeat(500);
        let content_b = b"file B content chunk ".repeat(300);
        fs::write(src.join("a.txt"), &content_a).unwrap();
        fs::write(src.join("b.txt"), &content_b).unwrap();

        let dst = tmp.join("out.zip");
        let stats = do_backup(
            src.to_str().unwrap(),
            dst.to_str().unwrap(),
            &["a.txt", "b.txt"],
            6,
            Some(noop_cb),
            None,
        )
        .expect("do_backup 失败");
        assert_eq!(stats.files, 2);
        assert_eq!(stats.bytes_total, (content_a.len() + content_b.len()) as u64);

        let file = File::open(&dst).unwrap();
        let mut archive = zip::ZipArchive::new(file).expect("生成的 zip 无法被 zip crate 读取");

        assert_eq!(archive.len(), 2, "条目数应为 2，实际 {}", archive.len());

        let buf_a = {
            let mut a = archive.by_name("a.txt").expect("找不到 a.txt");
            let mut buf = Vec::new();
            std::io::Read::read_to_end(&mut a, &mut buf).unwrap();
            buf
        };
        assert_eq!(buf_a, content_a, "a.txt 内容/CRC 不匹配");

        let buf_b = {
            let mut b = archive.by_name("b.txt").expect("找不到 b.txt");
            let mut buf = Vec::new();
            std::io::Read::read_to_end(&mut b, &mut buf).unwrap();
            buf
        };
        assert_eq!(buf_b, content_b, "b.txt 内容/CRC 不匹配");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn do_backup_excludes_repo_subtree() {
        let tmp = std::env::temp_dir().join(format!("xmc_backup_exclude_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let src = tmp.join("src");
        let repo = src.join("backups");
        fs::create_dir_all(&repo).unwrap();
        fs::write(src.join("a.txt"), b"a").unwrap();
        fs::write(repo.join("old.zip"), b"zip").unwrap();

        let dst = tmp.join("out.zip");
        let stats = do_backup(
            src.to_str().unwrap(),
            dst.to_str().unwrap(),
            &["a.txt", "backups"],
            6,
            None,
            Some(&repo),
        )
        .unwrap();
        assert_eq!(stats.files, 1, "仓库目录应被排除");

        let file = File::open(&dst).unwrap();
        let archive = zip::ZipArchive::new(file).unwrap();
        assert_eq!(archive.len(), 1);

        let _ = fs::remove_dir_all(&tmp);
    }
}
