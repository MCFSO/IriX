use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::fs;
use std::io::{BufReader, BufWriter, Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use chrono::{Utc, Duration};
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;
use serde_json::Value;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

static FILE_OP_CANCELLED: AtomicBool = AtomicBool::new(false);

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

/// L-6：捕获 FFI 函数体中的 panic，避免跨 FFI unwind（UB/进程终止）。
///
/// 返回码约定：panic 时按通用 IO 错误码 2 处理。
fn ffi_guard(f: impl FnOnce() -> libc::c_int) -> libc::c_int {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| {
        set_last_error("Rust 侧 panic，已捕获（L-6）");
        2
    })
}

#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        let cstr = borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("未知错误").ok());
        cstr.unwrap_or_else(|| CString::new("未知错误").unwrap())
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

#[derive(Serialize)]
struct DirEntry {
    name: String,
    path: String,
    is_dir: bool,
    size: u64,
    modified: String,
}

#[no_mangle]
pub extern "C" fn scan_dir(path: *const libc::c_char) -> *mut libc::c_char {
    if path.is_null() {
        set_last_error("路径为空指针");
        return std::ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return std::ptr::null_mut();
        }
    };

    let entries: Vec<DirEntry> = WalkDir::new(path_str)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|entry| {
            let name = entry
                .file_name()
                .to_str()
                .unwrap_or("")
                .to_string();
            let path = entry.path().to_string_lossy().into_owned();
            let is_dir = entry.file_type().is_dir();
            let meta = entry.metadata().ok();
            let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
            let modified = meta
                .as_ref()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs().to_string())
                .unwrap_or_default();
            DirEntry {
                name,
                path,
                is_dir,
                size,
                modified,
            }
        })
        .collect();

    match serde_json::to_string(&entries) {
        Ok(json) => match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => {
                set_last_error("JSON 包含 nul 字节");
                std::ptr::null_mut()
            }
        },
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

#[derive(Serialize)]
struct FileInfo {
    name: String,
    size: u64,
    is_dir: bool,
    modified: String,
    is_symlink: bool,
}

#[no_mangle]
pub extern "C" fn get_file_info(path: *const libc::c_char) -> *mut libc::c_char {
    if path.is_null() {
        set_last_error("路径为空指针");
        return std::ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return std::ptr::null_mut();
        }
    };

    let p = Path::new(path_str);
    let meta = match fs::symlink_metadata(p) {
        Ok(m) => m,
        Err(e) => {
            set_last_error(e.to_string());
            return std::ptr::null_mut();
        }
    };

    let name = p
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_string();
    let is_dir = meta.is_dir();
    let size = if is_dir { 0 } else { meta.len() };
    let is_symlink = meta.file_type().is_symlink();
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs().to_string())
        .unwrap_or_default();

    let info = FileInfo {
        name,
        size,
        is_dir,
        modified,
        is_symlink,
    };

    match serde_json::to_string(&info) {
        Ok(json) => match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => {
                set_last_error("JSON 包含 nul 字节");
                std::ptr::null_mut()
            }
        },
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

struct ClipboardEntry {
    path: String,
    is_cut: bool,
}

static CLIPBOARD: Mutex<Option<ClipboardEntry>> = Mutex::new(None);

#[no_mangle]
pub extern "C" fn clipboard_set(path: *const libc::c_char, is_cut: libc::c_int) -> libc::c_int {
    if path.is_null() {
        set_last_error("路径为空指针");
        return 1;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    let is_cut_bool = is_cut != 0;
    match CLIPBOARD.lock() {
        Ok(mut clip) => {
            *clip = Some(ClipboardEntry {
                path: path_str,
                is_cut: is_cut_bool,
            });
            0
        }
        Err(_) => {
            set_last_error("无法获取剪贴板锁");
            1
        }
    }
}

#[no_mangle]
pub extern "C" fn clipboard_get() -> *mut libc::c_char {
    match CLIPBOARD.lock() {
        Ok(clip) => match clip.as_ref() {
            Some(entry) => {
                #[derive(Serialize)]
                struct ClipboardJson {
                    path: String,
                    is_cut: bool,
                }
                let json = ClipboardJson {
                    path: entry.path.clone(),
                    is_cut: entry.is_cut,
                };
                match serde_json::to_string(&json) {
                    Ok(s) => match CString::new(s) {
                        Ok(cstr) => cstr.into_raw(),
                        Err(_) => {
                            set_last_error("JSON 包含 nul 字节");
                            std::ptr::null_mut()
                        }
                    },
                    Err(e) => {
                        set_last_error(e.to_string());
                        std::ptr::null_mut()
                    }
                }
            }
            None => std::ptr::null_mut(),
        },
        Err(_) => {
            set_last_error("无法获取剪贴板锁");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn clipboard_clear() {
    if let Ok(mut clip) = CLIPBOARD.lock() {
        *clip = None;
    }
}

#[no_mangle]
pub extern "C" fn cancel_file_op() {
    FILE_OP_CANCELLED.store(true, Ordering::SeqCst);
}

type ProgressCallback = extern "C" fn(current: u64, total: u64);

fn is_small_file(path: &str) -> bool {
    match fs::metadata(path) {
        Ok(meta) => meta.len() < 1048576,
        Err(_) => false,
    }
}

extern "C" fn noop_progress(_current: u64, _total: u64) {}

fn copy_file_stream(src: &str, dst: &str, progress_cb: ProgressCallback) -> Result<(), libc::c_int> {
    let total = fs::metadata(src).map_err(|_| 2)?.len();
    let src_file = fs::File::open(src).map_err(|_| 2)?;
    let dst_file = fs::File::create(dst).map_err(|_| 2)?;
    let mut reader = BufReader::new(src_file);
    let mut writer = BufWriter::new(dst_file);
    let mut buf = [0u8; 256 * 1024];
    let mut copied: u64 = 0;
    let mut last_cb: u64 = 0;
    let mb: u64 = 1024 * 1024;

    loop {
        let n = reader.read(&mut buf).map_err(|_| 2)?;
        if n == 0 {
            break;
        }
        writer.write_all(&buf[..n]).map_err(|_| 2)?;
        copied += n as u64;
        if copied - last_cb >= mb || copied == total {
            progress_cb(copied, total);
            last_cb = copied;
        }
        if FILE_OP_CANCELLED.load(Ordering::SeqCst) {
            drop(writer);
            drop(reader);
            let _ = fs::remove_file(dst);
            return Err(3);
        }
    }
    writer.flush().map_err(|_| 2)?;
    if copied > last_cb {
        progress_cb(copied, total);
    }
    Ok(())
}

#[no_mangle]
pub extern "C" fn copy_file(
    src: *const libc::c_char,
    dst: *const libc::c_char,
    progress_cb: Option<ProgressCallback>,
) -> libc::c_int {
    if src.is_null() || dst.is_null() {
        set_last_error("路径为空指针");
        return 1;
    }
    let src_str = match unsafe { CStr::from_ptr(src) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let dst_str = match unsafe { CStr::from_ptr(dst) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    FILE_OP_CANCELLED.store(false, Ordering::SeqCst);

    if is_small_file(src_str) {
        match fs::copy(src_str, dst_str) {
            Ok(_) => 0,
            Err(e) => {
                set_last_error(e.to_string());
                2
            }
        }
    } else {
        if let Some(parent) = Path::new(dst_str).parent() {
            if let Err(e) = fs::create_dir_all(parent) {
                set_last_error(e.to_string());
                return 2;
            }
        }
        let cb = progress_cb.unwrap_or(noop_progress as ProgressCallback);
        match copy_file_stream(src_str, dst_str, cb) {
            Ok(()) => 0,
            Err(code) => code,
        }
    }
}

#[no_mangle]
pub extern "C" fn move_file(
    src: *const libc::c_char,
    dst: *const libc::c_char,
    progress_cb: Option<ProgressCallback>,
) -> libc::c_int {
    if src.is_null() || dst.is_null() {
        set_last_error("路径为空指针");
        return 1;
    }
    let src_str = match unsafe { CStr::from_ptr(src) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let dst_str = match unsafe { CStr::from_ptr(dst) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    FILE_OP_CANCELLED.store(false, Ordering::SeqCst);

    if fs::rename(src_str, dst_str).is_ok() {
        return 0;
    }

    if let Some(parent) = Path::new(dst_str).parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            set_last_error(e.to_string());
            return 2;
        }
    }

    let cb = progress_cb.unwrap_or(noop_progress as ProgressCallback);
    let copy_result: Result<(), libc::c_int> = if is_small_file(src_str) {
        fs::copy(src_str, dst_str).map(|_| ()).map_err(|e| {
            set_last_error(e.to_string());
            2i32
        })
    } else {
        copy_file_stream(src_str, dst_str, cb)
    };

    match copy_result {
        Ok(()) => {
            let _ = fs::remove_file(src_str);
            0
        }
        Err(3) => 3,
        Err(other) => {
            let _ = fs::remove_file(dst_str);
            other
        }
    }
}

#[derive(Serialize, Deserialize)]
struct TrashEntry {
    id: String,
    original_path: String,
    file_name: String,
    size: u64,
    deleted_at: String,
}

#[no_mangle]
pub extern "C" fn delete_to_trash(
    root_path: *const libc::c_char,
    file_path: *const libc::c_char,
) -> libc::c_int {
    ffi_guard(|| {
    if root_path.is_null() || file_path.is_null() {
        set_last_error("路径为空指针");
        return 2;
    }
    let root_str = match unsafe { CStr::from_ptr(root_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 2;
        }
    };
    let file_str = match unsafe { CStr::from_ptr(file_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 2;
        }
    };

    let trash_dir = Path::new(root_str).join("xmc_trash");
    if let Err(e) = fs::create_dir_all(&trash_dir) {
        set_last_error(e.to_string());
        return 2;
    }

    let file_path_obj = Path::new(file_str);
    let original_name = file_path_obj
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");

    let file_size = match fs::metadata(file_str) {
        Ok(m) => m.len(),
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    };

    let uuid = format!(
        "{:x}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let unique_name = format!("{}_{}", uuid, original_name);
    let trash_path = trash_dir.join(&unique_name);

    if let Err(e) = fs::rename(file_str, &trash_path) {
        set_last_error(e.to_string());
        return 2;
    }

    let meta_path = trash_dir.join("trash_meta.json");
    let entry = TrashEntry {
        id: uuid,
        original_path: file_str.to_string(),
        file_name: original_name.to_string(),
        size: file_size,
        deleted_at: Utc::now().to_rfc3339(),
    };

    let mut entries: Vec<TrashEntry> = match fs::read_to_string(&meta_path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => Vec::new(),
    };
    entries.push(entry);

    match serde_json::to_string(&entries) {
        Ok(json) => {
            if let Err(e) = fs::write(&meta_path, json) {
                set_last_error(e.to_string());
                return 2;
            }
        }
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    }

    0
    })
}

#[no_mangle]
pub extern "C" fn delete_permanently(path: *const libc::c_char) -> libc::c_int {
    ffi_guard(|| {
    if path.is_null() {
        set_last_error("路径为空指针");
        return 2;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 2;
        }
    };

    let p = Path::new(path_str);
    let result = if p.is_dir() {
        fs::remove_dir_all(p)
    } else {
        fs::remove_file(p)
    };

    match result {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
    })
}

#[no_mangle]
pub extern "C" fn create_directory(path: *const libc::c_char) -> libc::c_int {
    if path.is_null() {
        set_last_error("路径为空指针");
        return 2;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 2;
        }
    };

    match fs::create_dir_all(path_str) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn rename_entry(
    old_path: *const libc::c_char,
    new_path: *const libc::c_char,
) -> libc::c_int {
    if old_path.is_null() || new_path.is_null() {
        set_last_error("路径为空指针");
        return 2;
    }
    let old_str = match unsafe { CStr::from_ptr(old_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 2;
        }
    };
    let new_str = match unsafe { CStr::from_ptr(new_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 2;
        }
    };

    match fs::rename(old_str, new_str) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn list_trash(root_path: *const libc::c_char) -> *mut libc::c_char {
    if root_path.is_null() {
        set_last_error("路径为空指针");
        return std::ptr::null_mut();
    }
    let root_str = match unsafe { CStr::from_ptr(root_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return std::ptr::null_mut();
        }
    };

    let meta_path = Path::new(root_str).join("xmc_trash").join("trash_meta.json");
    let content = match fs::read_to_string(&meta_path) {
        Ok(c) => c,
        Err(_) => {
            match CString::new("[]") {
                Ok(cstr) => return cstr.into_raw(),
                Err(_) => return std::ptr::null_mut(),
            }
        }
    };

    let entries: Vec<Value> = serde_json::from_str(&content).unwrap_or_default();

    match serde_json::to_string(&entries) {
        Ok(json) => match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => {
                set_last_error("JSON 包含 nul 字节");
                std::ptr::null_mut()
            }
        },
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn restore_from_trash(
    root_path: *const libc::c_char,
    entry_id: *const libc::c_char,
) -> libc::c_int {
    ffi_guard(|| {
    if root_path.is_null() || entry_id.is_null() {
        set_last_error("路径为空指针");
        return 1;
    }
    let root_str = match unsafe { CStr::from_ptr(root_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let id_str = match unsafe { CStr::from_ptr(entry_id) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    let trash_dir = Path::new(root_str).join("xmc_trash");
    let meta_path = trash_dir.join("trash_meta.json");

    let content = match fs::read_to_string(&meta_path) {
        Ok(c) => c,
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    };

    let mut entries: Vec<Value> = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    };

    let entry_index = match entries.iter().position(|e| e["id"].as_str() == Some(id_str)) {
        Some(i) => i,
        None => return 4,
    };

    let original_path = entries[entry_index]["original_path"]
        .as_str()
        .unwrap_or("")
        .to_string();
    let file_name = entries[entry_index]["file_name"]
        .as_str()
        .unwrap_or("")
        .to_string();

    // L-3：trash_meta.json 可被篡改，恢复前校验——
    // 1) original_path 必须位于 root 之下（拒绝指向任意路径）；
    // 2) file_name 不得含路径分隔符（防止越出回收站目录）。
    let root_norm = Path::new(root_str)
        .canonicalize()
        .unwrap_or_else(|_| Path::new(root_str).to_path_buf());
    if file_name.contains('/') || file_name.contains('\\') || file_name.contains("..") {
        set_last_error("回收站元数据 file_name 含非法字符，已拒绝恢复（L-3）");
        return 4;
    }
    if original_path.is_empty() {
        set_last_error("回收站元数据 original_path 为空，已拒绝恢复（L-3）");
        return 4;
    }
    if !Path::new(&original_path).starts_with(&root_norm) {
        set_last_error("回收站元数据 original_path 越出根目录，已拒绝恢复（L-3）");
        return 4;
    }

    let trash_file_path = trash_dir.join(format!("{}_{}", id_str, file_name));
    let original = Path::new(&original_path);

    if let Some(parent) = original.parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            set_last_error(e.to_string());
            return 2;
        }
    }

    if let Err(e) = fs::rename(&trash_file_path, &original_path) {
        set_last_error(e.to_string());
        return 2;
    }

    entries.remove(entry_index);

    match serde_json::to_string(&entries) {
        Ok(json) => {
            let _ = fs::write(&meta_path, json);
        }
        Err(_) => {}
    }

    0
    })
}

#[no_mangle]
pub extern "C" fn purge_trash(root_path: *const libc::c_char) -> libc::c_int {
    if root_path.is_null() {
        set_last_error("路径为空指针");
        return 1;
    }
    let root_str = match unsafe { CStr::from_ptr(root_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    let trash_dir = Path::new(root_str).join("xmc_trash");
    if !trash_dir.exists() {
        return 0;
    }

    if let Err(e) = fs::remove_dir_all(&trash_dir) {
        set_last_error(e.to_string());
        return 2;
    }

    0
}

#[no_mangle]
pub extern "C" fn purge_trash_entry(
    root_path: *const libc::c_char,
    entry_id: *const libc::c_char,
) -> libc::c_int {
    ffi_guard(|| {
    if root_path.is_null() || entry_id.is_null() {
        set_last_error("路径为空指针");
        return 1;
    }
    let root_str = match unsafe { CStr::from_ptr(root_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let id_str = match unsafe { CStr::from_ptr(entry_id) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };

    let trash_dir = Path::new(root_str).join("xmc_trash");
    let meta_path = trash_dir.join("trash_meta.json");

    let content = match fs::read_to_string(&meta_path) {
        Ok(c) => c,
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    };

    let mut entries: Vec<Value> = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    };

    let entry_index = match entries.iter().position(|e| e["id"].as_str() == Some(id_str)) {
        Some(i) => i,
        None => return 4,
    };

    let file_name = entries[entry_index]["file_name"]
        .as_str()
        .unwrap_or("")
        .to_string();

    // L-3：元数据可被篡改，拒绝含路径分隔符的 file_name。
    if file_name.contains('/') || file_name.contains('\\') || file_name.contains("..") {
        set_last_error("回收站元数据 file_name 含非法字符，已拒绝清理（L-3）");
        return 4;
    }

    let trash_file_path = trash_dir.join(format!("{}_{}", id_str, file_name));
    if trash_file_path.exists() {
        let result = if trash_file_path.is_dir() {
            fs::remove_dir_all(&trash_file_path)
        } else {
            fs::remove_file(&trash_file_path)
        };
        if let Err(e) = result {
            set_last_error(e.to_string());
            return 2;
        }
    }

    entries.remove(entry_index);

    let json = match serde_json::to_string(&entries) {
        Ok(j) => j,
        Err(e) => {
            set_last_error(e.to_string());
            return 2;
        }
    };

    if let Err(e) = fs::write(&meta_path, json) {
        set_last_error(e.to_string());
        return 2;
    }

    0
    })
}

#[no_mangle]
pub extern "C" fn auto_clean_trash(root_path: *const libc::c_char) -> libc::c_int {
    if root_path.is_null() {
        set_last_error("路径为空指针");
        return -1;
    }
    let root_str = match unsafe { CStr::from_ptr(root_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("路径不是有效的 UTF-8 字符串");
            return -1;
        }
    };

    let trash_dir = Path::new(root_str).join("xmc_trash");
    let meta_path = trash_dir.join("trash_meta.json");

    let content = match fs::read_to_string(&meta_path) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    let mut entries: Vec<Value> = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return 0,
    };

    let cutoff = Utc::now() - Duration::days(7);
    let mut purged_count: i32 = 0;

    entries.retain(|entry| {
        let id = entry["id"].as_str().unwrap_or("");
        let file_name = entry["file_name"].as_str().unwrap_or("");
        let deleted_str = entry["deleted_at"].as_str().unwrap_or("");

        let should_purge = match chrono::DateTime::parse_from_rfc3339(deleted_str) {
            Ok(dt) => dt.with_timezone(&Utc) < cutoff,
            Err(_) => false,
        };

        if should_purge {
            let trash_file_path = trash_dir.join(format!("{}_{}", id, file_name));
            if trash_file_path.exists() {
                let _ = if trash_file_path.is_dir() {
                    fs::remove_dir_all(&trash_file_path)
                } else {
                    fs::remove_file(&trash_file_path)
                };
            }
            purged_count += 1;
            false
        } else {
            true
        }
    });

    if purged_count > 0 {
        if let Ok(json) = serde_json::to_string(&entries) {
            let _ = fs::write(&meta_path, json);
        }
    }

    purged_count
}
