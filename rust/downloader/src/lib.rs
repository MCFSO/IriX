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

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// 全局取消标志
static DOWNLOAD_CANCELLED: AtomicBool = AtomicBool::new(false);

/// 多线程下载全局累计已下载字节数（用于进度回调）
static MULTIPART_DOWNLOADED: AtomicU64 = AtomicU64::new(0);

/// 下载进度回调函数类型
/// 参数: (已下载字节数, 总字节数；总字节数未知时为 0)
type DownloadProgressCallback = extern "C" fn(u64, u64);

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

/// HTTP 下载文件到本地路径
///
/// # 参数
/// - `url`: 资源 URL (UTF-8 C 字符串)
/// - `target_path`: 本地保存路径 (UTF-8 C 字符串)
/// - `user_agent`: User-Agent 头 (UTF-8 C 字符串，可为 null)
/// - `progress_cb`: 进度回调函数
///
/// # 返回值
/// - 0: 成功
/// - 1: URL 或路径无效
/// - 2: 网络/IO 错误
/// - 3: 用户取消
/// - 4: HTTP 状态码非 2xx
/// - 5: 其他错误
#[no_mangle]
pub extern "C" fn download_file(
    url: *const libc::c_char,
    target_path: *const libc::c_char,
    user_agent: *const libc::c_char,
    progress_cb: DownloadProgressCallback,
) -> libc::c_int {
    // 重置取消标志
    DOWNLOAD_CANCELLED.store(false, Ordering::SeqCst);

    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("URL 不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let target = match unsafe { CStr::from_ptr(target_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("目标路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let ua = if user_agent.is_null() {
        "xmcserverlancher/1.0.0"
    } else {
        match unsafe { CStr::from_ptr(user_agent) }.to_str() {
            Ok(s) => s,
            Err(_) => "xmcserverlancher/1.0.0",
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

/// 取消正在进行的下载
#[no_mangle]
pub extern "C" fn cancel_download() {
    DOWNLOAD_CANCELLED.store(true, Ordering::SeqCst);
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

/// 下载实现：流式读取响应体并写入文件，定期回调进度
fn do_download(
    url: &str,
    target: &str,
    user_agent: &str,
    progress_cb: DownloadProgressCallback,
) -> io::Result<()> {
    // 确保父目录存在
    let target_path = Path::new(target);
    if let Some(parent) = target_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // 发起 HTTP GET 请求 (ureq 内部使用 rustls 处理 HTTPS)
    let agent = ureq::AgentBuilder::new()
        .user_agent(user_agent)
        .build();

    let response = match agent.get(url).call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("HTTP 状态码 {code}"),
            ));
        }
        Err(e) => {
            return Err(io::Error::new(io::ErrorKind::Other, e.to_string()));
        }
    };

    // 获取总大小 (Content-Length)，未知则 0
    let total_bytes: u64 = response
        .header("Content-Length")
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0);

    // 流式读取响应体并写入文件
    let mut reader = response.into_reader();
    let mut file = File::create(target_path)?;
    let mut downloaded: u64 = 0;
    let mut buf = [0u8; 64 * 1024]; // 64KB 缓冲区
    let mut last_reported: u64 = 0;

    loop {
        // 取消检查
        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            // 删除半成品文件
            let _ = std::fs::remove_file(target_path);
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }

        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        downloaded += n as u64;

        // 每 256KB 或完成时回调一次，减少 FFI 调用频率
        if downloaded - last_reported >= 256 * 1024 || (total_bytes > 0 && downloaded == total_bytes) {
            progress_cb(downloaded, total_bytes);
            last_reported = downloaded;
        }
    }

    file.flush()?;
    // 最终回调确保 100%
    progress_cb(downloaded, if total_bytes > 0 { total_bytes } else { downloaded });
    Ok(())
}

// ===================== 多线程断点续传下载 =====================

/// 多线程下载分片任务
struct ChunkTask {
    /// 分片起始偏移（含）
    start: u64,
    /// 分片结束偏移（含）
    end: u64,
    /// 分片对应的 .part 临时文件路径
    part_path: String,
}

/// 多线程断点续传下载入口（FFI）
///
/// # 参数
/// - `url`: 资源 URL
/// - `target_path`: 最终保存路径
/// - `user_agent`: UA（可为 null）
/// - `threads`: 线程数（1-32，超出会被钳制）
/// - `progress_cb`: 进度回调
///
/// # 工作流程
/// 1. HEAD/GET 探测总大小与是否支持 Range；
/// 2. 若不支持或无 Content-Length，回退到单线程流式下载；
/// 3. 将文件切分为 N 个分片，每个分片独立写入 `<target>.part<N>`；
/// 4. 已存在的 .part 文件按其当前大小继续下载（断点续传）；
/// 5. 全部分片完成后合并为目标文件并删除 .part；
/// 6. 中途取消会保留 .part 文件，下次继续。
///
/// # 返回值
/// 与 [`download_file`] 一致（0/1/2/3/4/5）。
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

    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("URL 不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let target = match unsafe { CStr::from_ptr(target_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("目标路径不是有效的 UTF-8 字符串");
            return 1;
        }
    };
    let ua = if user_agent.is_null() {
        "xmcserverlancher/1.0.0"
    } else {
        match unsafe { CStr::from_ptr(user_agent) }.to_str() {
            Ok(s) => s,
            Err(_) => "xmcserverlancher/1.0.0",
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

/// 多线程下载实现
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

    let agent = ureq::AgentBuilder::new().user_agent(user_agent).build();

    // 探测：使用 GET + Range 探测服务端能力（避免 HEAD 不可用的站点）。
    // 兼容性：很多 CDN 仅在 GET 请求返回 Content-Length。
    let probe = match agent.get(url).set("Range", "bytes=0-0").call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("HTTP 状态码 {code}"),
            ));
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
            probe
                .header("Content-Length")
                .and_then(|s| s.parse::<u64>().ok())
        })
        .unwrap_or(0);

    // 回退条件：服务端不支持 Range、未提供大小，或线程数为 1
    if !accepts_ranges || total_bytes == 0 || thread_count == 1 {
        return do_download_single_with_progress(url, target, &agent, total_bytes, progress_cb);
    }

    // 切划分片
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

    // 统计每个分片已存在字节数（断点续传起点）
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

    // 共享错误收编器：任一线程出错即终止整体下载
    let error: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    let progress_stop = Arc::new(AtomicBool::new(false));

    // 启动进度上报线程（每 200ms 回调一次）
    let progress_stop_clone = Arc::clone(&progress_stop);
    let progress_handle = thread::spawn(move || {
        while !progress_stop_clone.load(Ordering::SeqCst) {
            let downloaded = MULTIPART_DOWNLOADED.load(Ordering::SeqCst);
            progress_cb(downloaded, total_bytes);
            thread::sleep(std::time::Duration::from_millis(200));
        }
        let downloaded = MULTIPART_DOWNLOADED.load(Ordering::SeqCst);
        progress_cb(downloaded, total_bytes);
    });

    // 启动 worker 线程池
    let mut handles = Vec::with_capacity(tasks.len());
    for t in tasks {
        let url = url.to_string();
        let ua = user_agent.to_string();
        let err = Arc::clone(&error);
        handles.push(thread::spawn(move || -> io::Result<()> {
            download_chunk(&url, &t, &ua, &err)
        }));
    }

    // 等待所有 worker 完成
    let mut worker_err: Option<io::Error> = None;
    for h in handles {
        match h.join() {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                if worker_err.is_none() {
                    worker_err = Some(e);
                }
            }
            Err(_) => {
                if worker_err.is_none() {
                    worker_err = Some(io::Error::new(io::ErrorKind::Other, "工作线程 panic"));
                }
            }
        }
    }

    // 停止进度线程
    progress_stop.store(true, Ordering::SeqCst);
    let _ = progress_handle.join();

    if let Some(e) = worker_err {
        return Err(e);
    }

    // 取消检查：取消则不合并文件，保留 .part 供下次续传
    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    // 合并所有分片到目标文件
    let mut out = File::create(target_path)?;
    for i in 0..thread_count {
        let part_path = format!("{}.part{}", target, i);
        if let Ok(mut f) = File::open(&part_path) {
            io::copy(&mut f, &mut out)?;
        }
    }
    out.flush()?;

    // 清理 .part 文件
    for i in 0..thread_count {
        let part_path = format!("{}.part{}", target, i);
        let _ = std::fs::remove_file(&part_path);
    }

    progress_cb(total_bytes, total_bytes);
    Ok(())
}

/// 下载单个分片（支持断点续传）
fn download_chunk(
    url: &str,
    task: &ChunkTask,
    user_agent: &str,
    error: &Arc<Mutex<Option<String>>>,
) -> io::Result<()> {
    // 如果其他线程已失败则快速返回
    if error.lock().unwrap().is_some() {
        return Ok(());
    }
    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    // 计算续传起点
    let mut resume_from: u64 = 0;
    if let Ok(meta) = std::fs::metadata(&task.part_path) {
        let len = meta.len();
        if len <= (task.end - task.start + 1) {
            resume_from = len;
        }
    }

    let agent = ureq::AgentBuilder::new().user_agent(user_agent).build();

    let range = format!("bytes={}-{}", task.start + resume_from, task.end);
    let response = match agent.get(url).set("Range", &range).call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            let msg = format!("HTTP 状态码 {code}");
            *error.lock().unwrap() = Some(msg.clone());
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }
        Err(e) => {
            let msg = e.to_string();
            *error.lock().unwrap() = Some(msg.clone());
            return Err(io::Error::new(io::ErrorKind::Other, msg));
        }
    };

    let mut reader = response.into_reader();
    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .open(&task.part_path)?;
    file.seek(SeekFrom::Start(resume_from))?;

    let mut buf = [0u8; 64 * 1024];
    let mut written_this_session: u64 = 0;
    loop {
        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            file.flush()?;
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }
        if error.lock().unwrap().is_some() {
            file.flush()?;
            return Ok(());
        }
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        written_this_session += n as u64;
        MULTIPART_DOWNLOADED.fetch_add(n as u64, Ordering::SeqCst);
        // 定期刷盘以保证续传时元数据准确
        if written_this_session % (4 * 1024 * 1024) == 0 {
            let _ = file.flush();
        }
    }
    file.flush()?;
    Ok(())
}

/// 单线程流式下载（带进度回调），用于回退场景
fn do_download_single_with_progress(
    url: &str,
    target: &str,
    agent: &ureq::Agent,
    total_bytes: u64,
    progress_cb: DownloadProgressCallback,
) -> io::Result<()> {
    let response = match agent.get(url).call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("HTTP 状态码 {code}"),
            ));
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
    let mut file = File::create(target)?;
    let mut downloaded: u64 = 0;
    let mut buf = [0u8; 64 * 1024];
    let mut last_reported: u64 = 0;

    loop {
        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            let _ = std::fs::remove_file(target);
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
