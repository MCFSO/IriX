use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::path::Path;
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
    timestamp: String,
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
                        let _ = writeln!(writer, "[{}] {}", entry.timestamp, entry.line);
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

    let timestamp = chrono::Local::now()
        .format("%Y-%m-%d %H:%M:%S")
        .to_string();

    let entry = LogEntry {
        instance_id: id,
        line: line_str,
        timestamp,
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
