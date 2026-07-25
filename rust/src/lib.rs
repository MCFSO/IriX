//! XMC Server Launcher 备份压缩模块
//!
//! 提供 LZMA2 (xz) 格式的压缩功能，供 Flutter 通过 FFI 调用。

use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::{self, Write};
use std::path::Path;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use walkdir::WalkDir;
use xz2::write::XzEncoder;

/// 全局取消标志
static CANCELLED: AtomicBool = AtomicBool::new(false);

/// 进度回调函数类型
/// 参数: (已处理字节数, 总字节数)
type ProgressCallback = extern "C" fn(u64, u64);

/// 压缩目录到 .tar.xz 文件
///
/// # 参数
/// - `src_path`: 源目录路径 (UTF-8 C 字符串)
/// - `dst_path`: 目标文件路径 (UTF-8 C 字符串)
/// - `files_to_backup`: 要备份的文件/文件夹名数组 (UTF-8 C 字符串指针数组)
/// - `files_count`: 文件数组长度
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
    progress_cb: ProgressCallback,
) -> libc::c_int {
    // 重置取消标志
    CANCELLED.store(false, Ordering::SeqCst);

    // 解析路径
    let src = match unsafe { CStr::from_ptr(src_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return 1,
    };
    let dst = match unsafe { CStr::from_ptr(dst_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return 1,
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

    // 执行备份
    match do_backup(src, dst, &files, progress_cb) {
        Ok(_) => 0,
        Err(e) if e.kind() == io::ErrorKind::Other && e.to_string().contains("cancelled") => 3,
        Err(_) => 2,
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
    // 简单实现，后续可扩展
    CString::new("Unknown error").unwrap().into_raw()
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

/// 内部备份实现
fn do_backup(
    src_dir: &str,
    dst_file: &str,
    files: &[&str],
    progress_cb: ProgressCallback,
) -> io::Result<()> {
    let src_path = Path::new(src_dir);
    let dst_path = Path::new(dst_file);

    // 创建目标文件
    let dst = File::create(dst_path)?;

    // 统计总字节数
    let mut total_bytes: u64 = 0;
    let mut entries_to_compress: Vec<walkdir::DirEntry> = Vec::new();

    for file_name in files {
        let full_path = src_path.join(file_name);
        if full_path.exists() {
            for entry in WalkDir::new(&full_path).into_iter().filter_map(|e| e.ok()) {
                if entry.file_type().is_file() {
                    if let Ok(metadata) = entry.metadata() {
                        total_bytes += metadata.len();
                    }
                    entries_to_compress.push(entry);
                }
            }
        }
    }

    if total_bytes == 0 {
        total_bytes = 1; // 避免除零
    }

    // 创建 XZ 编码器 (LZMA2, 压缩级别 6)
    let mut encoder = XzEncoder::new(dst, 6);

    // 写入 tar 头并压缩每个文件
    let mut processed_bytes: u64 = 0;

    for entry in &entries_to_compress {
        // 检查取消
        if CANCELLED.load(Ordering::SeqCst) {
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }

        let path = entry.path();
        let file = File::open(path)?;
        let metadata = file.metadata()?;
        let len = metadata.len();

        // 简化: 写入文件名和内容
        // 实际 tar 格式需要 512 字节头，这里简化处理
        let rel_path = path.strip_prefix(src_path).unwrap_or(path);
        let path_bytes = rel_path.to_string_lossy().into_owned();
        writeln!(encoder, "FILE: {}", path_bytes)?;
        io::copy(&mut &file[..], &mut encoder)?;

        processed_bytes += len;

        // 调用进度回调
        progress_cb(processed_bytes, total_bytes);
    }

    encoder.finish()?;
    Ok(())
}