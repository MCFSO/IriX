use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Sender};
use std::sync::Mutex;
use std::thread::JoinHandle;

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

struct LogEntry {
    instance_id: String,
    line: String,
}

/// 校验 instance_id 是否可安全用作文件名（L-4）。
///
/// 拒绝路径分隔符、`..`、空白与控制字符，防止 `../` 越界写/删 .log 文件。
fn valid_instance_id(id: &str) -> bool {
    !id.is_empty()
        && !id.contains('/')
        && !id.contains('\\')
        && !id.contains("..")
        && !id.chars().any(|c| c.is_whitespace() || c.is_control())
}

enum LogMsg {
    Entry(LogEntry),
    Flush(Sender<()>),
}

static LOG_TX: Mutex<Option<Sender<LogMsg>>> = Mutex::new(None);
static LOG_HANDLE: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);
static LOG_DIR: Mutex<Option<String>> = Mutex::new(None);

#[no_mangle]
pub extern "C" fn log_init(log_dir: *const libc::c_char) -> libc::c_int {
    if log_dir.is_null() {
        set_last_error("log_dir is null");
        return 1;
    }
    let dir_str = match unsafe { CStr::from_ptr(log_dir) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            set_last_error("log_dir is not valid UTF-8");
            return 1;
        }
    };

    if let Err(e) = fs::create_dir_all(&dir_str) {
        set_last_error(e.to_string());
        return 2;
    }

    let mut tx_guard = match LOG_TX.lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("failed to lock LOG_TX");
            return 4;
        }
    };
    if tx_guard.is_some() {
        set_last_error("logger already initialized");
        return 4;
    }

    let (tx, rx) = mpsc::channel::<LogMsg>();
    let dir = dir_str.clone();

    let handle = std::thread::spawn(move || {
        let mut writers: HashMap<String, BufWriter<File>> = HashMap::new();
        loop {
            match rx.recv() {
                Ok(LogMsg::Entry(entry)) => {
                    if !writers.contains_key(&entry.instance_id) {
                        let path = Path::new(&dir).join(format!("{}.log", entry.instance_id));
                        match std::fs::OpenOptions::new()
                            .create(true)
                            .append(true)
                            .open(&path)
                        {
                            Ok(file) => {
                                writers.insert(entry.instance_id.clone(), BufWriter::new(file));
                            }
                            Err(_) => continue,
                        }
                    }
                    if let Some(writer) = writers.get_mut(&entry.instance_id) {
                        // 原样写入服务器输出行（服务器日志自身已含时间戳，
                        // 不再添加 IriX 前缀）。
                        let _ = writeln!(writer, "{}", entry.line);
                    }
                }
                Ok(LogMsg::Flush(resp)) => {
                    for writer in writers.values_mut() {
                        let _ = writer.flush();
                    }
                    let _ = resp.send(());
                }
                Err(_) => {
                    for writer in writers.values_mut() {
                        let _ = writer.flush();
                    }
                    break;
                }
            }
        }
    });

    *tx_guard = Some(tx);
    drop(tx_guard);

    match LOG_DIR.lock() {
        Ok(mut g) => *g = Some(dir_str),
        Err(_) => {}
    }

    match LOG_HANDLE.lock() {
        Ok(mut g) => *g = Some(handle),
        Err(_) => {}
    }

    0
}

#[no_mangle]
pub extern "C" fn log_write(
    instance_id: *const libc::c_char,
    line: *const libc::c_char,
) -> libc::c_int {
    if instance_id.is_null() || line.is_null() {
        set_last_error("null pointer argument");
        return 1;
    }
    let id = match unsafe { CStr::from_ptr(instance_id) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            set_last_error("instance_id is not valid UTF-8");
            return 1;
        }
    };
    if !valid_instance_id(&id) {
        set_last_error("instance_id 含非法字符（路径分隔符/.. 等），已拒绝（L-4）");
        return 1;
    }
    let line_str = match unsafe { CStr::from_ptr(line) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            set_last_error("line is not valid UTF-8");
            return 1;
        }
    };

    let entry = LogEntry {
        instance_id: id,
        line: line_str,
    };

    let tx_guard = match LOG_TX.lock() {
        Ok(g) => g,
        Err(_) => {
            set_last_error("failed to lock LOG_TX");
            return 4;
        }
    };
    match tx_guard.as_ref() {
        Some(tx) => {
            if tx.send(LogMsg::Entry(entry)).is_err() {
                set_last_error("log channel closed");
                return 4;
            }
        }
        None => {
            set_last_error("logger not initialized");
            return 4;
        }
    }

    0
}

#[no_mangle]
pub extern "C" fn log_flush() -> libc::c_int {
    let (resp_tx, resp_rx) = mpsc::channel();

    {
        let tx_guard = match LOG_TX.lock() {
            Ok(g) => g,
            Err(_) => {
                set_last_error("failed to lock LOG_TX");
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
            None => {
                set_last_error("logger not initialized");
                return 4;
            }
        }
    }

    let _ = resp_rx.recv();
    0
}

#[no_mangle]
pub extern "C" fn log_shutdown() -> libc::c_int {
    match LOG_TX.lock() {
        Ok(mut g) => *g = None,
        Err(_) => {
            set_last_error("failed to lock LOG_TX");
            return 4;
        }
    }

    match LOG_HANDLE.lock() {
        Ok(mut g) => {
            if let Some(handle) = g.take() {
                let _ = handle.join();
            }
        }
        Err(_) => {
            set_last_error("failed to lock LOG_HANDLE");
            return 4;
        }
    }

    match LOG_DIR.lock() {
        Ok(mut g) => *g = None,
        Err(_) => {}
    }

    0
}

#[no_mangle]
pub extern "C" fn log_delete(instance_id: *const libc::c_char) -> libc::c_int {
    if instance_id.is_null() {
        set_last_error("null pointer argument");
        return 1;
    }
    let id = match unsafe { CStr::from_ptr(instance_id) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("instance_id is not valid UTF-8");
            return 1;
        }
    };
    if !valid_instance_id(id) {
        set_last_error("instance_id 含非法字符（路径分隔符/.. 等），已拒绝（L-4）");
        return 1;
    }

    let dir = match LOG_DIR.lock() {
        Ok(g) => match g.as_ref() {
            Some(d) => d.clone(),
            None => {
                set_last_error("logger not initialized");
                return 4;
            }
        },
        Err(_) => {
            set_last_error("failed to lock LOG_DIR");
            return 4;
        }
    };

    let path = Path::new(&dir).join(format!("{}.log", id));
    if path.exists() {
        if let Err(e) = fs::remove_file(&path) {
            set_last_error(e.to_string());
            return 2;
        }
    }

    0
}

// === 服务器进程托管 ===
//
// 以「stdout/stderr 重定向到日志文件、stdin 保留管道」的方式启动服务器进程。
// 与 Dart 的 Process.start 不同，子进程的写端是日志文件的 OS 句柄，
// 因此启动器（IriX）退出/崩溃后服务器仍可持续写入日志；
// 下次启动时可按 PID 接管并继续尾随该日志文件（终端接管）。
// 子进程句柄保存在进程内 HashMap，供 stdin 写入与退出回收使用。

/// 由本进程托管的服务器子进程，按 PID 索引。
static CHILDREN: Mutex<Option<HashMap<u32, Child>>> = Mutex::new(None);

/// 与 Dart 侧 [ServerProcessManager._parseCommand] 保持一致的命令行解析：
/// 按空格/Tab 分词，双引号包裹含空格的路径（引号本身不保留）。
fn parse_command(command: &str) -> Option<(String, Vec<String>)> {
    let trimmed = command.trim();
    if trimmed.is_empty() {
        return None;
    }
    let mut tokens: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    for ch in trimmed.chars() {
        if ch == '"' {
            in_quotes = !in_quotes;
        } else if (ch == ' ' || ch == '\t') && !in_quotes {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
        } else {
            current.push(ch);
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    if tokens.is_empty() {
        return None;
    }
    let exe = tokens.remove(0);
    Some((exe, tokens))
}

fn spawn_error(msg: String) -> i64 {
    set_last_error(msg);
    -1
}

/// 启动服务器进程：stdout/stderr 追加写入 [log_path]，stdin 保留管道。
///
/// 参数为启动命令原文（含引号）、工作目录与日志文件路径的 UTF-8 C 字符串。
/// 成功返回子进程 PID（>0），失败返回 -1 并可通过 get_last_error 获取原因。
#[no_mangle]
pub extern "C" fn spawn_with_log(
    command: *const libc::c_char,
    cwd: *const libc::c_char,
    log_path: *const libc::c_char,
) -> i64 {
    if command.is_null() || cwd.is_null() || log_path.is_null() {
        return spawn_error("null pointer argument".to_string());
    }
    let command_str = match unsafe { CStr::from_ptr(command) }.to_str() {
        Ok(s) => s,
        Err(_) => return spawn_error("command is not valid UTF-8".to_string()),
    };
    let cwd_str = match unsafe { CStr::from_ptr(cwd) }.to_str() {
        Ok(s) => s,
        Err(_) => return spawn_error("cwd is not valid UTF-8".to_string()),
    };
    let log_path_str = match unsafe { CStr::from_ptr(log_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return spawn_error("log_path is not valid UTF-8".to_string()),
    };

    let (exe, args) = match parse_command(command_str) {
        Some(parts) => parts,
        None => return spawn_error("empty command".to_string()),
    };

    let log_file = match fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path_str)
    {
        Ok(f) => f,
        Err(e) => return spawn_error(format!("failed to open log file: {e}")),
    };
    let log_clone = match log_file.try_clone() {
        Ok(f) => f,
        Err(e) => return spawn_error(format!("failed to clone log file: {e}")),
    };

    let mut builder = Command::new(exe);
    builder
        .args(&args)
        .current_dir(cwd_str)
        .stdin(Stdio::piped())
        .stdout(Stdio::from(log_file))
        .stderr(Stdio::from(log_clone));

    // 隐藏子进程控制台窗口：IriX 本身是 GUI 程序，服务器输出已重定向到日志文件，
    // 无需为控制台子系统的子进程（java.exe 等）弹出可见终端窗口。
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x08000000;
        builder.creation_flags(CREATE_NO_WINDOW);
    }

    match builder.spawn() {
        Ok(mut child) => {
            let pid = child.id();
            let mut guard = match CHILDREN.lock() {
                Ok(g) => g,
                Err(_) => {
                    let _ = child.kill();
                    return spawn_error("failed to lock CHILDREN".to_string());
                }
            };
            let map = guard.get_or_insert_with(HashMap::new);
            map.insert(pid, child);
            pid as i64
        }
        Err(e) => spawn_error(format!("failed to spawn server process: {e}")),
    }
}

/// 向托管进程的 stdin 写入一行（不自动加前导 `/`）。
/// 返回 0 表示成功；进程不存在或 stdin 已关闭返回 1。
#[no_mangle]
pub extern "C" fn spawn_send_stdin(pid: u32, line: *const libc::c_char) -> libc::c_int {
    if line.is_null() {
        set_last_error("null pointer argument".to_string());
        return 1;
    }
    let line_str = match unsafe { CStr::from_ptr(line) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            set_last_error("line is not valid UTF-8".to_string());
            return 1;
        }
    };
    let mut guard = match CHILDREN.lock() {
        Ok(g) => g,
        Err(_) => return 1,
    };
    let map = match guard.as_mut() {
        Some(m) => m,
        None => return 1,
    };
    match map.get_mut(&pid) {
        Some(child) => match child.stdin.as_mut() {
            Some(stdin) => match writeln!(stdin, "{line_str}") {
                Ok(_) => 0,
                Err(e) => {
                    set_last_error(format!("failed to write stdin: {e}"));
                    1
                }
            },
            None => 1,
        },
        None => 1,
    }
}

/// 回收托管进程的退出状态。
///
/// 返回 -1 表示 PID 不是本进程托管的子进程；-2 表示仍在运行；
/// 其余值为退出码（负数表示被信号终止）。
#[no_mangle]
pub extern "C" fn spawn_try_reap(pid: u32) -> i64 {
    let mut guard = match CHILDREN.lock() {
        Ok(g) => g,
        Err(_) => return -1,
    };
    let map = match guard.as_mut() {
        Some(m) => m,
        None => return -1,
    };
    let child = match map.get_mut(&pid) {
        Some(c) => c,
        None => return -1,
    };
    match child.try_wait() {
        Ok(Some(status)) => {
            map.remove(&pid);
            status.code().unwrap_or(-1) as i64
        }
        Ok(None) => -2,
        Err(_) => -1,
    }
}

/// 强制终止托管进程。返回 0 表示已发送终止信号；PID 未知返回 1。
#[no_mangle]
pub extern "C" fn spawn_kill(pid: u32) -> libc::c_int {
    let mut guard = match CHILDREN.lock() {
        Ok(g) => g,
        Err(_) => return 1,
    };
    let map = match guard.as_mut() {
        Some(m) => m,
        None => return 1,
    };
    match map.get_mut(&pid) {
        Some(child) => match child.kill() {
            Ok(_) => 0,
            Err(_) => 1,
        },
        None => 1,
    }
}
