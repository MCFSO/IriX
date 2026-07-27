//! XMC Server Launcher 备份压缩模块
//!
//! 提供 ZIP (Deflate) 格式的压缩功能，供 Flutter 通过 FFI 调用。
//! 使用 rayon 并行压缩多个文件，再串行写入标准 ZIP 归档，
//! 输出可被任意标准工具解压的 .zip 文件。

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::{self, Read, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

use crc32fast::Hasher;
use flate2::write::DeflateEncoder;
use flate2::Compression;
use rayon::prelude::*;
use walkdir::WalkDir;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// 全局取消标志
static CANCELLED: AtomicBool = AtomicBool::new(false);

/// 进度回调函数类型
/// 参数: (已处理字节数, 总字节数)
type ProgressCallback = extern "C" fn(u64, u64);

/// 设置最后的错误信息
fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        // 若消息含 nul 字节 (罕见)，回退到占位提示，避免错误信息完全丢失
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

/// 压缩目录到 .zip 文件
///
/// # 参数
/// - `src_path`: 源目录路径 (UTF-8 C 字符串)
/// - `dst_path`: 目标文件路径 (UTF-8 C 字符串)
/// - `files_to_backup`: 要备份的文件/文件夹名数组 (UTF-8 C 字符串指针数组)
/// - `files_count`: 文件数组长度
/// - `compression_level`: Deflate 压缩级别 (0-9, 0=仅存储, 6=标准, 9=最佳)
/// - `progress_cb`: 进度回调函数
///
/// # 返回值
/// - 0: 成功
/// - 1: 路径无效
/// - 2: IO 错误
/// - 3: 用户取消
/// - 4: 其他错误
#[no_mangle]
pub extern "C" fn backup_directory(
    src_path: *const libc::c_char,
    dst_path: *const libc::c_char,
    files_to_backup: *const *const libc::c_char,
    files_count: usize,
    compression_level: u32,
    progress_cb: ProgressCallback,
) -> libc::c_int {
    // 重置取消标志
    CANCELLED.store(false, Ordering::SeqCst);

    // 解析路径
    let src = match unsafe { CStr::from_ptr(src_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("源路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let dst = match unsafe { CStr::from_ptr(dst_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("目标路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    // 解析要备份的文件列表
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

    // 执行备份 (级别限制在 0-9)
    let level = compression_level.min(9);
    match do_backup(src, dst, &files, level, progress_cb) {
        Ok(_) => 0,
        Err(e) if e.kind() == io::ErrorKind::Other && e.to_string() == "cancelled" => 3,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
}

/// 取消正在进行的备份
#[no_mangle]
pub extern "C" fn cancel_backup() {
    CANCELLED.store(true, Ordering::SeqCst);
}

/// 获取最后的错误信息
///
/// 返回 UTF-8 C 字符串指针，需要调用者释放 (使用 free_string)
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

/// 释放由 FFI 分配的字符串
#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 已压缩的文件条目 (用于串行写入 ZIP)
struct Entry {
    /// 归档内路径 (正斜杠分隔)
    name: String,
    /// 压缩后数据
    compressed: Vec<u8>,
    /// 原始大小
    uncompressed_size: u64,
    /// CRC32 校验值
    crc32: u32,
    /// DOS 时间
    dos_time: u16,
    /// DOS 日期
    dos_date: u16,
}

/// 内部备份实现
///
/// 使用 rayon 分批并行压缩 (CPU 密集部分)，每批压缩完立即顺序写入磁盘
/// 并释放内存，避免全部压缩数据驻留 RAM。支持 ZIP64 (大归档/大文件/多条目)。
fn do_backup(
    src_dir: &str,
    dst_file: &str,
    files: &[&str],
    compression_level: u32,
    progress_cb: ProgressCallback,
) -> io::Result<()> {
    let result = do_backup_inner(src_dir, dst_file, files, compression_level, progress_cb);
    // 取消时删除半成品文件
    if is_cancelled_err(&result) {
        let _ = std::fs::remove_file(dst_file);
    }
    result
}

fn is_cancelled_err(result: &io::Result<()>) -> bool {
    matches!(result, Err(e) if e.kind() == io::ErrorKind::Other && e.to_string() == "cancelled")
}

fn do_backup_inner(
    src_dir: &str,
    dst_file: &str,
    files: &[&str],
    compression_level: u32,
    progress_cb: ProgressCallback,
) -> io::Result<()> {
    let src_path = Path::new(src_dir);
    let dst_path = Path::new(dst_file);

    // 1. 收集所有待压缩文件 + 估算总字节数 (metadata 失败按 0 计，后续在并行阶段校正)
    let mut entries_to_compress: Vec<walkdir::DirEntry> = Vec::new();
    let mut estimated_total: u64 = 0;
    for file_name in files {
        let full_path = src_path.join(file_name);
        if full_path.exists() {
            for entry in WalkDir::new(&full_path).into_iter().filter_map(|e| e.ok()) {
                if entry.file_type().is_file() {
                    let est = entry.metadata().map(|m| m.len()).unwrap_or(0);
                    estimated_total += est;
                    entries_to_compress.push(entry);
                }
            }
        }
    }
    let total_bytes = AtomicU64::new(estimated_total);
    let processed_bytes = AtomicU64::new(0);

    // 2. 创建输出文件 + 中央目录累加器
    let mut writer = File::create(dst_path)?;
    let mut central_dir: Vec<u8> = Vec::new();
    let mut offset: u64 = 0;

    // 3. 并行压缩所有文件 (rayon 自动用满所有 CPU 核心)
    //    所有压缩数据驻留内存直到写盘，换取最大并行吞吐
    let entries: Vec<Entry> = entries_to_compress
        .par_iter()
        .map(|entry| -> io::Result<Entry> {
            // 文件级取消检查
            if CANCELLED.load(Ordering::SeqCst) {
                return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
            }

            let path = entry.path();
            // 归档内相对路径：去掉源目录前缀，并转为正斜杠
            let rel_path = path.strip_prefix(src_path).unwrap_or(path);
            let name = rel_path.to_string_lossy().replace('\\', "/");

            // 读取文件内容
            let mut file = File::open(path)?;
            let mut data = Vec::new();
            file.read_to_end(&mut data)?;
            let real_size = data.len() as u64;

            // 校正总量：若实际大小 > 估算 (文件增长或 metadata 曾失败)，补差
            // 避免进度回调 >100%
            let est = entry.metadata().ok().map(|m| m.len()).unwrap_or(0);
            if real_size > est {
                total_bytes.fetch_add(real_size - est, Ordering::Relaxed);
            }

            // CRC32 (ZIP 规范要求)
            let mut hasher = Hasher::new();
            hasher.update(&data);
            let crc32 = hasher.finalize();

            // Deflate 压缩 (raw deflate, 无 zlib header, 级别由调用方指定)
            let mut encoder = DeflateEncoder::new(Vec::new(), Compression::new(compression_level));
            encoder.write_all(&data)?;
            let compressed = encoder.finish()?;

            // DOS 时间戳 (ZIP 规范) - 元数据失败回退 1980-01-01
            let (dos_time, dos_date) = entry
                .metadata()
                .ok()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| epoch_to_dos(d.as_secs()))
                .unwrap_or((0, 0x0021)); // 1980-01-01 作为回退

            // 进度 (原子累加)
            processed_bytes.fetch_add(real_size, Ordering::Relaxed);
            progress_cb(
                processed_bytes.load(Ordering::Relaxed),
                total_bytes.load(Ordering::Relaxed),
            );

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

    // 4. 串行写入 ZIP 归档 (写盘阶段也响应取消)
    for entry in &entries {
        if CANCELLED.load(Ordering::SeqCst) {
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }
        write_entry(&mut writer, entry, &mut offset, &mut central_dir)?;
    }

    let entry_count = entries.len() as u64;

    // 5. 写入中央目录
    let cd_offset = offset;
    let cd_size = central_dir.len() as u64;
    writer.write_all(&central_dir)?;

    // 6. ZIP64 结尾记录 (任一字段溢出 32/16 位时需要)
    let entries_overflow = entry_count > 0xFFFF;
    let cd_size_overflow = cd_size > 0xFFFFFFFF;
    let cd_offset_overflow = cd_offset > 0xFFFFFFFF;
    let needs_zip64 = entries_overflow || cd_size_overflow || cd_offset_overflow;

    if needs_zip64 {
        let zip64_eocd_offset = cd_offset + cd_size;
        // ZIP64 EOCD (固定部分 44 字节)
        writer.write_all(&0x06064b50u32.to_le_bytes())?; // 签名
        writer.write_all(&44u64.to_le_bytes())?; // 记录大小 (后续固定字段)
        writer.write_all(&45u16.to_le_bytes())?; // 生成版本 (4.5)
        writer.write_all(&45u16.to_le_bytes())?; // 需求版本 (4.5)
        writer.write_all(&0u32.to_le_bytes())?; // 盘号
        writer.write_all(&0u32.to_le_bytes())?; // 中央目录所在盘
        writer.write_all(&entry_count.to_le_bytes())?; // 本盘条目数
        writer.write_all(&entry_count.to_le_bytes())?; // 总条目数
        writer.write_all(&cd_size.to_le_bytes())?; // 中央目录大小
        writer.write_all(&cd_offset.to_le_bytes())?; // 中央目录偏移
        // ZIP64 EOCD 定位器
        writer.write_all(&0x07064b50u32.to_le_bytes())?; // 签名
        writer.write_all(&0u32.to_le_bytes())?; // ZIP64 EOCD 所在盘
        writer.write_all(&zip64_eocd_offset.to_le_bytes())?; // 偏移
        writer.write_all(&1u32.to_le_bytes())?; // 总盘数
    }

    // 7. 普通 EOCD (溢出字段填 0xFFFF/0xFFFFFFFF 指示查 ZIP64)
    writer.write_all(&0x06054b50u32.to_le_bytes())?; // 签名
    writer.write_all(&0u16.to_le_bytes())?; // 盘号
    writer.write_all(&0u16.to_le_bytes())?; // 中央目录所在盘
    writer.write_all(
        &(if entries_overflow {
            0xFFFF
        } else {
            entry_count as u16
        })
        .to_le_bytes(),
    )?; // 本盘条目数
    writer.write_all(
        &(if entries_overflow {
            0xFFFF
        } else {
            entry_count as u16
        })
        .to_le_bytes(),
    )?; // 总条目数
    writer.write_all(
        &(if cd_size_overflow {
            0xFFFFFFFF
        } else {
            cd_size as u32
        })
        .to_le_bytes(),
    )?; // 中央目录大小
    writer.write_all(
        &(if cd_offset_overflow {
            0xFFFFFFFF
        } else {
            cd_offset as u32
        })
        .to_le_bytes(),
    )?; // 中央目录偏移
    writer.write_all(&0u16.to_le_bytes())?; // 注释长度

    writer.flush()?;
    Ok(())
}

/// 写入单个条目的本地文件头 + 数据，并累积中央目录头。
/// 支持 ZIP64 (单文件 >4GB 或本地头偏移 >4GB)。
fn write_entry(
    writer: &mut File,
    entry: &Entry,
    offset: &mut u64,
    central_dir: &mut Vec<u8>,
) -> io::Result<()> {
    let lfh_offset = *offset;
    let comp_size = entry.compressed.len() as u64;
    let uncomp_size = entry.uncompressed_size;
    let needs_entry_zip64 = comp_size > 0xFFFFFFFF || uncomp_size > 0xFFFFFFFF;

    // --- 本地文件头 ---
    // LFH 的 ZIP64 extra (仅含 uncomp_size + comp_size, 8+8=16 字节)
    let mut lfh_extra: Vec<u8> = Vec::new();
    if needs_entry_zip64 {
        lfh_extra.extend_from_slice(&0x0001u16.to_le_bytes()); // ZIP64 头 ID
        lfh_extra.extend_from_slice(&16u16.to_le_bytes()); // 数据长度
        lfh_extra.extend_from_slice(&uncomp_size.to_le_bytes());
        lfh_extra.extend_from_slice(&comp_size.to_le_bytes());
    }
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

    writer.write_all(&0x04034b50u32.to_le_bytes())?; // 签名
    writer.write_all(&(if needs_entry_zip64 { 45u16 } else { 20u16 }).to_le_bytes())?; // 需求版本
    writer.write_all(&0u16.to_le_bytes())?; // 通用标志位
    writer.write_all(&8u16.to_le_bytes())?; // 压缩方法: Deflate
    writer.write_all(&entry.dos_time.to_le_bytes())?;
    writer.write_all(&entry.dos_date.to_le_bytes())?;
    writer.write_all(&entry.crc32.to_le_bytes())?; // CRC32 始终为实际值
    writer.write_all(&comp_field.to_le_bytes())?; // 压缩大小
    writer.write_all(&uncomp_field.to_le_bytes())?; // 未压缩大小
    writer.write_all(&(entry.name.len() as u16).to_le_bytes())?; // 文件名长度
    writer.write_all(&(lfh_extra.len() as u16).to_le_bytes())?; // 额外字段长度
    writer.write_all(entry.name.as_bytes())?;
    writer.write_all(&lfh_extra)?;

    *offset += 30 + entry.name.len() as u64 + lfh_extra.len() as u64;

    // 压缩数据
    writer.write_all(&entry.compressed)?;
    *offset += entry.compressed.len() as u64;

    // --- 中央目录头 ---
    let needs_cd_offset_zip64 = lfh_offset > 0xFFFFFFFF;
    let any_cd_zip64 = needs_entry_zip64 || needs_cd_offset_zip64;
    // CDH 的 ZIP64 extra: 仅包含被掩码的字段 (uncomp, comp, offset 按需)
    let mut cdh_extra: Vec<u8> = Vec::new();
    if any_cd_zip64 {
        let mut data: Vec<u8> = Vec::new();
        if needs_entry_zip64 {
            data.extend_from_slice(&uncomp_size.to_le_bytes());
            data.extend_from_slice(&comp_size.to_le_bytes());
        }
        if needs_cd_offset_zip64 {
            data.extend_from_slice(&lfh_offset.to_le_bytes());
        }
        cdh_extra.extend_from_slice(&0x0001u16.to_le_bytes());
        cdh_extra.extend_from_slice(&(data.len() as u16).to_le_bytes());
        cdh_extra.extend_from_slice(&data);
    }
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

    central_dir.extend_from_slice(&0x02014b50u32.to_le_bytes()); // 签名
    central_dir.extend_from_slice(&(if any_cd_zip64 { 45u16 } else { 20u16 }).to_le_bytes()); // 生成版本
    central_dir.extend_from_slice(&(if any_cd_zip64 { 45u16 } else { 20u16 }).to_le_bytes()); // 需求版本
    central_dir.extend_from_slice(&0u16.to_le_bytes()); // 标志位
    central_dir.extend_from_slice(&8u16.to_le_bytes()); // 压缩方法
    central_dir.extend_from_slice(&entry.dos_time.to_le_bytes());
    central_dir.extend_from_slice(&entry.dos_date.to_le_bytes());
    central_dir.extend_from_slice(&entry.crc32.to_le_bytes());
    central_dir.extend_from_slice(&cdh_comp.to_le_bytes());
    central_dir.extend_from_slice(&cdh_uncomp.to_le_bytes());
    central_dir.extend_from_slice(&(entry.name.len() as u16).to_le_bytes());
    central_dir.extend_from_slice(&(cdh_extra.len() as u16).to_le_bytes());
    central_dir.extend_from_slice(&0u16.to_le_bytes()); // 注释
    central_dir.extend_from_slice(&0u16.to_le_bytes()); // 起始盘号
    central_dir.extend_from_slice(&0u16.to_le_bytes()); // 内部属性
    central_dir.extend_from_slice(&0u32.to_le_bytes()); // 外部属性
    central_dir.extend_from_slice(&cdh_off.to_le_bytes()); // 本地头偏移
    central_dir.extend_from_slice(entry.name.as_bytes());
    central_dir.extend_from_slice(&cdh_extra);

    Ok(())
}

/// Unix epoch 秒数 -> DOS 时间戳 (time, date)
/// ZIP 规范使用 MS-DOS 时间格式 (16 位时间 + 16 位日期)
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
        0x0021 // 1980-01-01 (ZIP 不支持更早的日期)
    };
    let dos_time = ((hour as u16) << 11) | ((minute as u16) << 5) | ((second / 2) as u16);
    (dos_time, dos_date)
}

/// 天数 (自 1970-01-01) -> 公历 (年, 月, 日)
/// H. Hinnant 算法, 见 http://howardhinnant.github.io/date_algorithms.html
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as i64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// 测试用的空进度回调
    extern "C" fn noop_cb(_: u64, _: u64) {}

    /// 验证并行压缩生成的 zip 可被标准 zip 库正确读取，且内容/CRC 完整。
    #[test]
    fn parallel_backup_produces_valid_zip() {
        let tmp = std::env::temp_dir().join("xmc_backup_test");
        let _ = fs::remove_dir_all(&tmp);
        let src = tmp.join("src");
        fs::create_dir_all(&src).unwrap();

        // 写两个测试文件 (内容可压缩且足够长以体现并行)
        let content_a = b"hello world from file A ".repeat(500);
        let content_b = b"file B content chunk ".repeat(300);
        fs::write(src.join("a.txt"), &content_a).unwrap();
        fs::write(src.join("b.txt"), &content_b).unwrap();

        let dst = tmp.join("out.zip");
        let result = do_backup(
            src.to_str().unwrap(),
            dst.to_str().unwrap(),
            &["a.txt", "b.txt"],
            6,
            noop_cb,
        );
        assert!(result.is_ok(), "do_backup 失败: {:?}", result.err());

        // 用 zip crate 读取验证格式合法性
        let file = File::open(&dst).unwrap();
        let mut archive = zip::ZipArchive::new(file).expect("生成的 zip 无法被 zip crate 读取");

        // 条目数
        assert_eq!(archive.len(), 2, "条目数应为 2，实际 {}", archive.len());

        // 名称与内容 (ZipFile 持有 archive 的可变借用，用块限制作用域)
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
}
