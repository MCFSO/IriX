//! XMC Server Launcher 文件下载模块
//!
//! 基于 ureq + rustls 的 HTTPS 流式下载，供 Flutter 通过 FFI 调用。
//! 独立编译为 xmc_downloader.dll，与备份模块 (xmc_backup.dll) 解耦。
//!
//! 提供两种下载入口：
//! - [`download_file`]：单线程流式下载（向后兼容）
//! - [`download_file_multipart`]：多线程分片 + 断点续传下载

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::fs::{File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

static DOWNLOAD_CANCELLED: AtomicBool = AtomicBool::new(false);

static MULTIPART_DOWNLOADED: AtomicU64 = AtomicU64::new(0);

type DownloadProgressCallback = extern "C" fn(u64, u64);

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

#[no_mangle]
pub extern "C" fn download_file(
    url: *const libc::c_char,
    target_path: *const libc::c_char,
    user_agent: *const libc::c_char,
    progress_cb: DownloadProgressCallback,
) -> libc::c_int {
    DOWNLOAD_CANCELLED.store(false, Ordering::SeqCst);

    if url.is_null() {
        set_last_error("URL 为空指针");
        return 1;
    }
    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("URL 不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    if target_path.is_null() {
        set_last_error("目标路径为空指针");
        return 1;
    }
    let target = match unsafe { CStr::from_ptr(target_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("目标路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let ua = if user_agent.is_null() {
        "IriX/1.0.0 (https://github.com/MCFSO/IriX)"
    } else {
        match unsafe { CStr::from_ptr(user_agent) }.to_str() {
            Ok(s) => s,
            Err(_) => "IriX/1.0.0 (https://github.com/MCFSO/IriX)",
        }
    };

    match do_download(url_str, target, ua, progress_cb) {
        Ok(_) => 0,
        Err(e) if e.kind() == io::ErrorKind::Other && e.to_string() == "cancelled" => 3,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn cancel_download() {
    DOWNLOAD_CANCELLED.store(true, Ordering::SeqCst);
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

fn build_agent(user_agent: &str) -> ureq::Agent {
    ureq::AgentBuilder::new()
        .user_agent(user_agent)
        .timeout_connect(Duration::from_secs(30))
        .timeout_read(Duration::from_secs(60))
        .build()
}

fn do_download(
    url: &str,
    target: &str,
    user_agent: &str,
    progress_cb: DownloadProgressCallback,
) -> io::Result<()> {
    let agent = build_agent(user_agent);
    do_download_with_agent(url, target, &agent, 0, progress_cb)
}

struct ChunkTask {
    start: u64,
    end: u64,
    part_path: String,
}

struct SharedError {
    flag: AtomicBool,
    message: Mutex<Option<String>>,
}

impl SharedError {
    fn new() -> Self {
        Self {
            flag: AtomicBool::new(false),
            message: Mutex::new(None),
        }
    }

    fn is_set(&self) -> bool {
        self.flag.load(Ordering::Relaxed)
    }

    fn set(&self, msg: String) {
        if let Ok(mut lock) = self.message.lock() {
            *lock = Some(msg);
        }
        self.flag.store(true, Ordering::Release);
    }
}

#[no_mangle]
pub extern "C" fn download_file_multipart(
    url: *const libc::c_char,
    target_path: *const libc::c_char,
    user_agent: *const libc::c_char,
    threads: libc::c_int,
    progress_cb: DownloadProgressCallback,
) -> libc::c_int {
    DOWNLOAD_CANCELLED.store(false, Ordering::SeqCst);
    MULTIPART_DOWNLOADED.store(0, Ordering::SeqCst);

    if url.is_null() {
        set_last_error("URL 为空指针");
        return 1;
    }
    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("URL 不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    if target_path.is_null() {
        set_last_error("目标路径为空指针");
        return 1;
    }
    let target = match unsafe { CStr::from_ptr(target_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("目标路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let ua = if user_agent.is_null() {
        "IriX/1.0.0 (https://github.com/MCFSO/IriX)"
    } else {
        match unsafe { CStr::from_ptr(user_agent) }.to_str() {
            Ok(s) => s,
            Err(_) => "IriX/1.0.0 (https://github.com/MCFSO/IriX)",
        }
    };
    let thread_count = threads.clamp(1, 32) as usize;

    match do_download_multipart(url_str, target, ua, thread_count, progress_cb) {
        Ok(_) => 0,
        Err(e) if e.kind() == io::ErrorKind::Other && e.to_string() == "cancelled" => 3,
        Err(e) => {
            set_last_error(e.to_string());
            2
        }
    }
}

fn do_download_multipart(
    url: &str,
    target: &str,
    user_agent: &str,
    thread_count: usize,
    progress_cb: DownloadProgressCallback,
) -> io::Result<()> {
    let target_path = Path::new(target);
    if let Some(parent) = target_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let agent = Arc::new(build_agent(user_agent));

    let probe = match agent.get(url).set("Range", "bytes=0-0").call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(io::ErrorKind::Other, format!("HTTP 状态码 {code}")));
        }
        Err(e) => {
            return Err(io::Error::new(io::ErrorKind::Other, e.to_string()));
        }
    };

    let accepts_ranges = probe
        .header("Accept-Ranges")
        .map(|v| v.eq_ignore_ascii_case("bytes"))
        .unwrap_or(false);

    let total_bytes: u64 = probe
        .header("Content-Range")
        .and_then(|cr| cr.split('/').nth(1))
        .and_then(|s| s.trim().parse::<u64>().ok())
        .or_else(|| {
            probe.header("Content-Length").and_then(|s| s.parse::<u64>().ok())
        })
        .unwrap_or(0);

    if !accepts_ranges || total_bytes == 0 || thread_count == 1 {
        return do_download_with_agent(url, target, &agent, total_bytes, progress_cb);
    }

    let chunk_size = (total_bytes + thread_count as u64 - 1) / thread_count as u64;
    let mut tasks: Vec<ChunkTask> = Vec::with_capacity(thread_count);
    for i in 0..thread_count {
        let start = i as u64 * chunk_size;
        if start >= total_bytes {
            break;
        }
        let end = (start + chunk_size - 1).min(total_bytes - 1);
        let part_path = format!("{}.part{}", target, i);
        tasks.push(ChunkTask { start, end, part_path });
    }

    let mut initial_downloaded: u64 = 0;
    for t in &tasks {
        if let Ok(meta) = std::fs::metadata(&t.part_path) {
            let len = meta.len();
            if len <= (t.end - t.start + 1) {
                initial_downloaded += len;
            }
        }
    }
    MULTIPART_DOWNLOADED.store(initial_downloaded, Ordering::SeqCst);

    let error = Arc::new(SharedError::new());
    let progress_stop = Arc::new(AtomicBool::new(false));

    let url_arc: Arc<str> = Arc::from(url);
    let ua_arc: Arc<str> = Arc::from(user_agent);

    let progress_stop_clone = Arc::clone(&progress_stop);
    let progress_handle = thread::spawn(move || {
        while !progress_stop_clone.load(Ordering::Relaxed) {
            let downloaded = MULTIPART_DOWNLOADED.load(Ordering::Relaxed);
            progress_cb(downloaded, total_bytes);
            thread::sleep(Duration::from_millis(200));
        }
        let downloaded = MULTIPART_DOWNLOADED.load(Ordering::Relaxed);
        progress_cb(downloaded, total_bytes);
    });

    let mut handles = Vec::with_capacity(tasks.len());
    for t in tasks {
        let agent = Arc::clone(&agent);
        let url = Arc::clone(&url_arc);
        let ua = Arc::clone(&ua_arc);
        let err = Arc::clone(&error);
        handles.push(thread::spawn(move || -> io::Result<()> {
            download_chunk(&url, &t, &ua, &agent, &err)
        }));
    }

    let mut worker_err: Option<io::Error> = None;
    for h in handles {
        match h.join() {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                worker_err.get_or_insert(e);
            }
            Err(_) => {
                worker_err.get_or_insert(io::Error::new(
                    io::ErrorKind::Other,
                    "工作线程 panic",
                ));
            }
        }
    }

    progress_stop.store(true, Ordering::Release);
    let _ = progress_handle.join();

    let part_paths: Vec<String> = (0..thread_count)
        .map(|i| format!("{}.part{}", target, i))
        .collect();

    if let Some(e) = worker_err {
        for part_path in &part_paths {
            let _ = std::fs::remove_file(part_path);
        }
        return Err(e);
    }
    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        for part_path in &part_paths {
            let _ = std::fs::remove_file(part_path);
        }
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        for part_path in &part_paths {
            let _ = std::fs::remove_file(part_path);
        }
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    let mut out = File::create(target_path)?;
    let mut merge_buf = vec![0u8; 256 * 1024];
    for part_path in &part_paths {
        if let Ok(mut f) = File::open(part_path) {
            loop {
                let n = f.read(&mut merge_buf)?;
                if n == 0 {
                    break;
                }
                out.write_all(&merge_buf[..n])?;
            }
        }
    }
    out.flush()?;

    for part_path in &part_paths {
        let _ = std::fs::remove_file(part_path);
    }

    progress_cb(total_bytes, total_bytes);
    Ok(())
}

fn download_chunk(
    url: &str,
    task: &ChunkTask,
    _user_agent: &str,
    agent: &ureq::Agent,
    error: &SharedError,
) -> io::Result<()> {
    if error.is_set() {
        return Ok(());
    }
    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    let mut resume_from: u64 = 0;
    if let Ok(meta) = std::fs::metadata(&task.part_path) {
        let len = meta.len();
        if len <= (task.end - task.start + 1) {
            resume_from = len;
        }
    }

    let range = format!("bytes={}-{}", task.start + resume_from, task.end);
    let response = match agent.get(url).set("Range", &range).call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            let msg = format!("HTTP 状态码 {code}");
            error.set(msg.clone());
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }
        Err(e) => {
            let msg = e.to_string();
            error.set(msg.clone());
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }
    };

    let mut reader = response.into_reader();
    let mut raw_file = OpenOptions::new()
        .create(true)
        .write(true)
        .open(&task.part_path)?;
    raw_file.seek(SeekFrom::Start(resume_from))?;
    let mut file = io::BufWriter::with_capacity(256 * 1024, raw_file);

    let mut buf = [0u8; 64 * 1024];
    let mut written_this_session: u64 = 0;
    loop {
        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            file.flush()?;
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }
        if error.is_set() {
            file.flush()?;
            return Ok(());
        }
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        written_this_session += n as u64;
        MULTIPART_DOWNLOADED.fetch_add(n as u64, Ordering::Relaxed);
        if written_this_session % (4 * 1024 * 1024) == 0 {
            file.flush()?;
        }
    }
    file.flush()?;
    Ok(())
}

fn do_download_with_agent(
    url: &str,
    target: &str,
    agent: &ureq::Agent,
    total_bytes: u64,
    progress_cb: DownloadProgressCallback,
) -> io::Result<()> {
    let target_path = Path::new(target);
    if let Some(parent) = target_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let response = match agent.get(url).call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(io::ErrorKind::Other, format!("HTTP 状态码 {code}")));
        }
        Err(e) => {
            return Err(io::Error::new(io::ErrorKind::Other, e.to_string()));
        }
    };

    let total = if total_bytes > 0 {
        total_bytes
    } else {
        response
            .header("Content-Length")
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0)
    };

    let mut reader = response.into_reader();
    let mut file = File::create(target_path)?;
    let mut downloaded: u64 = 0;
    let mut buf = [0u8; 64 * 1024];
    let mut last_reported: u64 = 0;

    loop {
        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            let _ = std::fs::remove_file(target_path);
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        downloaded += n as u64;
        if downloaded - last_reported >= 256 * 1024 || (total > 0 && downloaded == total) {
            progress_cb(downloaded, total);
            last_reported = downloaded;
        }
    }
    file.flush()?;
    progress_cb(downloaded, if total > 0 { total } else { downloaded });
    Ok(())
}
