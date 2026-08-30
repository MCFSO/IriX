// 开发者日志动态库 (xmc_devlog)
//
// 把应用的"一切"（运行日志流、操作轨迹、网络请求明细、启动与崩溃堆栈）
// 记录到「可执行文件所在目录 / logs」下的会话日志文件：
// 每次 app_log_init 新建一个带精确时间戳的文件 dev-YYYYMMDD-HHMMSS.log，
// 无限增长、不滚动、不截断、不清理，每个开启时段一个独立文件。
//
// 写盘在独立后台线程进行（mpsc 通道 + BufWriter），不阻塞调用方（Dart/UI）。
// 通道消息为已格式化好的整行文本，调用方（Dart）负责提供等级/标签/消息，
// 本库只负责加时间戳并落盘。

use std::cell::RefCell;
use std::fs::{self, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::mpsc::{self, Sender};
use std::sync::Mutex;
use std::thread::JoinHandle;
use std::time::{SystemTime, UNIX_EPOCH};

use std::ffi::{CStr, CString};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("error message contains nul byte").ok(),
        };
    });
}

#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        let cstr = borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("unknown error").ok());
        cstr.unwrap_or_else(|| CString::new("unknown error").unwrap())
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

/// 通道消息：一个已格式化好的整行日志文本。
enum LogMsg {
    Line(String),
    Flush(Sender<()>),
}

static TX: Mutex<Option<Sender<LogMsg>>> = Mutex::new(None);
static HANDLE: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);

/// 本地时区时间戳：YYYY-MM-DD HH:MM:SS.mmm
fn local_timestamp() -> String {
    // Rust 标准库无跨平台本地时区 API，这里用 UTC（带日期计算）保证可移植；
    // 文件名时间戳同理。按 UTC 对齐排障即可。
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now.as_secs();
    let millis = now.subsec_millis();

    // 将 Unix 秒拆为 (年-月-日 时:分:秒)，用 Howard Hinnant 的 civil_from_days
    // 算法（准确处理闰年，不依赖 chrono）。
    let days = (secs / 86_400) as i64;
    let secs_of_day = (secs % 86_400) as i64;
    let (y, mo, d) = civil_from_days(days);
    let h = (secs_of_day / 3600) as u32;
    let mi = ((secs_of_day % 3600) / 60) as u32;
    let s = (secs_of_day % 60) as u32;
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
        y, mo, d, h, mi, s, millis
    )
}

/// days_from_civil 的逆：自 1970-01-01 起的天数 -> (年, 月, 日)。
/// 来源：Howard Hinnant "date" 算法。
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as i64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// 格式化一行：时间戳 + [LEVEL] + [TAG] + 消息。
fn format_line(level: &str, tag: &str, msg: &str) -> String {
    format!("[{}] [{}] [{}] {}", local_timestamp(), level, tag, msg)
}

/// 初始化开发者日志：在 [dir]/logs 下新建会话文件并启动后台写线程。
///
/// [dir] 为可执行文件所在目录（由 Dart 侧传入 Platform.resolvedExecutable 的目录）。
/// 成功返回 0；失败返回非 0（用 get_last_error 取原因）。重复调用会先关闭旧会话。
#[no_mangle]
pub extern "C" fn app_log_init(dir: *const libc::c_char) -> libc::c_int {
    if dir.is_null() {
        set_last_error("dir is null");
        return 1;
    }
    let dir_str = match unsafe { CStr::from_ptr(dir) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            set_last_error("dir is not valid UTF-8");
            return 1;
        }
    };

    let logs_dir = Path::new(&dir_str).join("logs");
    if let Err(e) = fs::create_dir_all(&logs_dir) {
        set_last_error(format!("failed to create logs dir: {e}"));
        return 2;
    }

    let stamp = local_timestamp().replace([' ', ':'], "-");
    let path = logs_dir.join(format!("dev-{stamp}.log"));

    let file = match OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        Ok(f) => f,
        Err(e) => {
            set_last_error(format!("failed to open log file: {e}"));
            return 2;
        }
    };

    // 先关闭可能已存在的旧会话。
    shutdown_internal();

    let (tx, rx) = mpsc::channel::<LogMsg>();
    let starter = format_line("INFO", "session", &format!("开发者日志会话开始，文件: {}", path.display()));

    let handle = std::thread::spawn(move || {
        let mut writer = BufWriter::new(file);
        let _ = writeln!(writer, "{starter}");
        let _ = writer.flush();
        loop {
            match rx.recv() {
                Ok(LogMsg::Line(line)) => {
                    let _ = writeln!(writer, "{line}");
                    let _ = writer.flush();
                }
                Ok(LogMsg::Flush(resp)) => {
                    let _ = writer.flush();
                    let _ = resp.send(());
                }
                Err(_) => {
                    let _ = writer.flush();
                    break;
                }
            }
        }
    });

    *TX.lock().unwrap() = Some(tx);
    *HANDLE.lock().unwrap() = Some(handle);
    0
}

/// 写入一条日志（level/tag/msg 均为 UTF-8 C 字符串，可为空）。
/// 成功返回 0；未初始化返回 4；发送失败返回 4。
#[no_mangle]
pub extern "C" fn app_log_write(
    level: *const libc::c_char,
    tag: *const libc::c_char,
    msg: *const libc::c_char,
) -> libc::c_int {
    let level_str = if level.is_null() {
        String::new()
    } else {
        match unsafe { CStr::from_ptr(level) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                set_last_error("level is not valid UTF-8");
                return 1;
            }
        }
    };
    let tag_str = if tag.is_null() {
        String::new()
    } else {
        match unsafe { CStr::from_ptr(tag) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                set_last_error("tag is not valid UTF-8");
                return 1;
            }
        }
    };
    let msg_str = if msg.is_null() {
        String::new()
    } else {
        match unsafe { CStr::from_ptr(msg) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                set_last_error("msg is not valid UTF-8");
                return 1;
            }
        }
    };

    let line = format_line(&level_str, &tag_str, &msg_str);

    let tx_guard = match TX.lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("failed to lock TX");
            return 4;
        }
    };
    match tx_guard.as_ref() {
        Some(tx) => {
            if tx.send(LogMsg::Line(line)).is_err() {
                set_last_error("log channel closed");
                return 4;
            }
        }
        None => {
            set_last_error("devlog not initialized");
            return 4;
        }
    }
    0
}

/// 刷新后台写缓冲（同步等待落盘）。
#[no_mangle]
pub extern "C" fn app_log_flush() -> libc::c_int {
    let (resp_tx, resp_rx) = mpsc::channel();
    {
        let tx_guard = match TX.lock() {
            Ok(g) => g,
            Err(_) => {
                set_last_error("failed to lock TX");
                return 4;
            }
        };
        match tx_guard.as_ref() {
            Some(tx) => {
                if tx.send(LogMsg::Flush(resp_tx)).is_err() {
                    set_last_error("log channel closed");
                    return 4;
                }
            }
            None => return 0,
        }
    }
    let _ = resp_rx.recv();
    0
}

/// 内部关闭：发关闭信号并 join 写线程（不重置全局状态，供重复 init 复用）。
fn shutdown_internal() {
    {
        let mut tx_guard = match TX.lock() {
            Ok(g) => g,
            Err(_) => return,
        };
        if tx_guard.is_none() {
            return;
        }
        *tx_guard = None;
    }
    if let Some(handle) = HANDLE.lock().ok().and_then(|mut g| g.take()) {
        let _ = handle.join();
    }
}

/// 关闭开发者日志：flush 并回收写线程。
#[no_mangle]
pub extern "C" fn app_log_shutdown() -> libc::c_int {
    shutdown_internal();
    0
}
