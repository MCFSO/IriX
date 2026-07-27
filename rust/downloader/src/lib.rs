//! XMC Server Launcher 鏂囦欢涓嬭浇妯″潡
//!
//! 鍩轰簬 ureq + rustls 鐨?HTTPS 娴佸紡涓嬭浇锛屼緵 Flutter 閫氳繃 FFI 璋冪敤銆?//! 鐙珛缂栬瘧涓?xmc_downloader.dll锛屼笌澶囦唤妯″潡 (xmc_backup.dll) 瑙ｈ€︺€?//!
//! 鎻愪緵涓ょ涓嬭浇鍏ュ彛锛?//! - [`download_file`]锛氬崟绾跨▼娴佸紡涓嬭浇锛堝悜鍚庡吋瀹癸級
//! - [`download_file_multipart`]锛氬绾跨▼鍒嗙墖 + 鏂偣缁紶涓嬭浇

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

/// 鍏ㄥ眬鍙栨秷鏍囧織
static DOWNLOAD_CANCELLED: AtomicBool = AtomicBool::new(false);

/// 澶氱嚎绋嬩笅杞藉叏灞€绱宸蹭笅杞藉瓧鑺傛暟锛堢敤浜庤繘搴﹀洖璋冿級
static MULTIPART_DOWNLOADED: AtomicU64 = AtomicU64::new(0);

/// 涓嬭浇杩涘害鍥炶皟鍑芥暟绫诲瀷
/// 鍙傛暟: (宸蹭笅杞藉瓧鑺傛暟, 鎬诲瓧鑺傛暟锛涙€诲瓧鑺傛暟鏈煡鏃朵负 0)
type DownloadProgressCallback = extern "C" fn(u64, u64);

/// 璁剧疆鏈€鍚庣殑閿欒淇℃伅
fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        // 鑻ユ秷鎭惈 nul 瀛楄妭 (缃曡)锛屽洖閫€鍒板崰浣嶆彁绀猴紝閬垮厤閿欒淇℃伅瀹屽叏涓㈠け
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("閿欒娑堟伅鍖呭惈 nul 瀛楄妭").ok(),
        };
    });
}

/// HTTP 涓嬭浇鏂囦欢鍒版湰鍦拌矾寰?///
/// # 鍙傛暟
/// - `url`: 璧勬簮 URL (UTF-8 C 瀛楃涓?
/// - `target_path`: 鏈湴淇濆瓨璺緞 (UTF-8 C 瀛楃涓?
/// - `user_agent`: User-Agent 澶?(UTF-8 C 瀛楃涓诧紝鍙负 null)
/// - `progress_cb`: 杩涘害鍥炶皟鍑芥暟
///
/// # 杩斿洖鍊?/// - 0: 鎴愬姛
/// - 1: URL 鎴栬矾寰勬棤鏁?/// - 2: 缃戠粶/IO 閿欒
/// - 3: 鐢ㄦ埛鍙栨秷
/// - 4: HTTP 鐘舵€佺爜闈?2xx
/// - 5: 鍏朵粬閿欒
#[no_mangle]
pub extern "C" fn download_file(
    url: *const libc::c_char,
    target_path: *const libc::c_char,
    user_agent: *const libc::c_char,
    progress_cb: DownloadProgressCallback,
) -> libc::c_int {
    // 閲嶇疆鍙栨秷鏍囧織
    DOWNLOAD_CANCELLED.store(false, Ordering::SeqCst);

    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("URL 涓嶆槸鏈夋晥鐨?UTF-8 瀛楃涓?);
            return 1;
        }
    };
    let target = match unsafe { CStr::from_ptr(target_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("鐩爣璺緞涓嶆槸鏈夋晥鐨?UTF-8 瀛楃涓?);
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

/// 鍙栨秷姝ｅ湪杩涜鐨勪笅杞?#[no_mangle]
pub extern "C" fn cancel_download() {
    DOWNLOAD_CANCELLED.store(true, Ordering::SeqCst);
}

/// 鑾峰彇鏈€鍚庣殑閿欒淇℃伅
///
/// 杩斿洖 UTF-8 C 瀛楃涓叉寚閽堬紝闇€瑕佽皟鐢ㄨ€呴噴鏀?(浣跨敤 free_string)
#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        let cstr = borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("鏈煡閿欒").ok());
        cstr
            .unwrap_or_else(|| CString::new("鏈煡閿欒").unwrap())
            .into_raw()
    })
}

/// 閲婃斁鐢?FFI 鍒嗛厤鐨勫瓧绗︿覆
#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 涓嬭浇瀹炵幇锛氭祦寮忚鍙栧搷搴斾綋骞跺啓鍏ユ枃浠讹紝瀹氭湡鍥炶皟杩涘害
fn do_download(
    url: &str,
    target: &str,
    user_agent: &str,
    progress_cb: DownloadProgressCallback,
) -> io::Result<()> {
    // 纭繚鐖剁洰褰曞瓨鍦?    let target_path = Path::new(target);
    if let Some(parent) = target_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // 鍙戣捣 HTTP GET 璇锋眰 (ureq 鍐呴儴浣跨敤 rustls 澶勭悊 HTTPS)
    let agent = ureq::AgentBuilder::new()
        .user_agent(user_agent)
        .build();

    let response = match agent.get(url).call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("HTTP 鐘舵€佺爜 {code}"),
            ));
        }
        Err(e) => {
            return Err(io::Error::new(io::ErrorKind::Other, e.to_string()));
        }
    };

    // 鑾峰彇鎬诲ぇ灏?(Content-Length)锛屾湭鐭ュ垯 0
    let total_bytes: u64 = response
        .header("Content-Length")
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0);

    // 娴佸紡璇诲彇鍝嶅簲浣撳苟鍐欏叆鏂囦欢
    let mut reader = response.into_reader();
    let mut file = File::create(target_path)?;
    let mut downloaded: u64 = 0;
    let mut buf = [0u8; 64 * 1024]; // 64KB 缂撳啿鍖?    let mut last_reported: u64 = 0;

    loop {
        // 鍙栨秷妫€鏌?        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            // 鍒犻櫎鍗婃垚鍝佹枃浠?            let _ = std::fs::remove_file(target_path);
            return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
        }

        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        downloaded += n as u64;

        // 姣?256KB 鎴栧畬鎴愭椂鍥炶皟涓€娆★紝鍑忓皯 FFI 璋冪敤棰戠巼
        if downloaded - last_reported >= 256 * 1024 || (total_bytes > 0 && downloaded == total_bytes) {
            progress_cb(downloaded, total_bytes);
            last_reported = downloaded;
        }
    }

    file.flush()?;
    // 鏈€缁堝洖璋冪‘淇?100%
    progress_cb(downloaded, if total_bytes > 0 { total_bytes } else { downloaded });
    Ok(())
}

// ===================== 澶氱嚎绋嬫柇鐐圭画浼犱笅杞?=====================

/// 澶氱嚎绋嬩笅杞藉垎鐗囦换鍔?struct ChunkTask {
    /// 鍒嗙墖璧峰鍋忕Щ锛堝惈锛?    start: u64,
    /// 鍒嗙墖缁撴潫鍋忕Щ锛堝惈锛?    end: u64,
    /// 鍒嗙墖瀵瑰簲鐨?.part 涓存椂鏂囦欢璺緞
    part_path: String,
}

/// 澶氱嚎绋嬫柇鐐圭画浼犱笅杞藉叆鍙ｏ紙FFI锛?///
/// # 鍙傛暟
/// - `url`: 璧勬簮 URL
/// - `target_path`: 鏈€缁堜繚瀛樿矾寰?/// - `user_agent`: UA锛堝彲涓?null锛?/// - `threads`: 绾跨▼鏁帮紙1-32锛岃秴鍑轰細琚挸鍒讹級
/// - `progress_cb`: 杩涘害鍥炶皟
///
/// # 宸ヤ綔娴佺▼
/// 1. HEAD/GET 鎺㈡祴鎬诲ぇ灏忎笌鏄惁鏀寔 Range锛?/// 2. 鑻ヤ笉鏀寔鎴栨棤 Content-Length锛屽洖閫€鍒板崟绾跨▼娴佸紡涓嬭浇锛?/// 3. 灏嗘枃浠跺垏鍒嗕负 N 涓垎鐗囷紝姣忎釜鍒嗙墖鐙珛鍐欏叆 `<target>.part<N>`锛?/// 4. 宸插瓨鍦ㄧ殑 .part 鏂囦欢鎸夊叾褰撳墠澶у皬缁х画涓嬭浇锛堟柇鐐圭画浼狅級锛?/// 5. 鍏ㄩ儴鍒嗙墖瀹屾垚鍚庡悎骞朵负鐩爣鏂囦欢骞跺垹闄?.part锛?/// 6. 涓€斿彇娑堜細淇濈暀 .part 鏂囦欢锛屼笅娆＄户缁€?///
/// # 杩斿洖鍊?/// 涓?[`download_file`] 涓€鑷达紙0/1/2/3/4/5锛夈€?#[no_mangle]
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
            set_last_error("URL 涓嶆槸鏈夋晥鐨?UTF-8 瀛楃涓?);
            return 1;
        }
    };
    let target = match unsafe { CStr::from_ptr(target_path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_last_error("鐩爣璺緞涓嶆槸鏈夋晥鐨?UTF-8 瀛楃涓?);
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

/// 澶氱嚎绋嬩笅杞藉疄鐜?fn do_download_multipart(
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

    // 鎺㈡祴锛氫娇鐢?GET + Range 鎺㈡祴鏈嶅姟绔兘鍔涳紙閬垮厤 HEAD 涓嶅彲鐢ㄧ殑绔欑偣锛夈€?    // 鍏煎鎬э細寰堝 CDN 浠呭湪 GET 璇锋眰杩斿洖 Content-Length銆?    let probe = match agent.get(url).set("Range", "bytes=0-0").call() {
        Ok(r) => r,
        Err(ureq::Error::Status(code, _)) => {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("HTTP 鐘舵€佺爜 {code}"),
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

    // 鍥為€€鏉′欢锛氭湇鍔＄涓嶆敮鎸?Range銆佹湭鎻愪緵澶у皬锛屾垨绾跨▼鏁颁负 1
    if !accepts_ranges || total_bytes == 0 || thread_count == 1 {
        return do_download_single_with_progress(url, target, &agent, total_bytes, progress_cb);
    }

    // 鍒囧垎鍒嗙墖
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

    // 缁熻姣忎釜鍒嗙墖宸插瓨鍦ㄥ瓧鑺傛暟锛堟柇鐐圭画浼犺捣鐐癸級
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

    // 鍏变韩閿欒鏀堕泦鍣細浠讳竴绾跨▼鍑洪敊鍗崇粓姝㈡暣浣撲笅杞?    let error: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    let progress_stop = Arc::new(AtomicBool::new(false));

    // 鍚姩杩涘害涓婃姤绾跨▼锛堟瘡 200ms 鍥炶皟涓€娆★級
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

    // 鍚姩 worker 绾跨▼姹?    let mut handles = Vec::with_capacity(tasks.len());
    for t in tasks {
        let url = url.to_string();
        let ua = user_agent.to_string();
        let err = Arc::clone(&error);
        handles.push(thread::spawn(move || -> io::Result<()> {
            download_chunk(&url, &t, &ua, &err)
        }));
    }

    // 绛夊緟鎵€鏈?worker 瀹屾垚
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
                    worker_err = Some(io::Error::new(io::ErrorKind::Other, "宸ヤ綔绾跨▼ panic"));
                }
            }
        }
    }

    // 鍋滄杩涘害绾跨▼
    progress_stop.store(true, Ordering::SeqCst);
    let _ = progress_handle.join();

    if let Some(e) = worker_err {
        return Err(e);
    }

    // 鍙栨秷妫€鏌ワ細鍙栨秷鍒欎笉鍚堝苟鏂囦欢锛屼繚鐣?.part 渚涗笅娆＄画浼?    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    // 鍚堝苟鎵€鏈夊垎鐗囧埌鐩爣鏂囦欢
    let mut out = File::create(target_path)?;
    for i in 0..thread_count {
        let part_path = format!("{}.part{}", target, i);
        if let Ok(mut f) = File::open(&part_path) {
            io::copy(&mut f, &mut out)?;
        }
    }
    out.flush()?;

    // 娓呯悊 .part 鏂囦欢
    for i in 0..thread_count {
        let part_path = format!("{}.part{}", target, i);
        let _ = std::fs::remove_file(&part_path);
    }

    progress_cb(total_bytes, total_bytes);
    Ok(())
}

/// 涓嬭浇鍗曚釜鍒嗙墖锛堟敮鎸佹柇鐐圭画浼狅級
fn download_chunk(
    url: &str,
    task: &ChunkTask,
    user_agent: &str,
    error: &Arc<Mutex<Option<String>>>,
) -> io::Result<()> {
    // 濡傛灉鍏朵粬绾跨▼宸插け璐ュ垯蹇€熻繑鍥?    if error.lock().unwrap().is_some() {
        return Ok(());
    }
    if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
        return Err(io::Error::new(io::ErrorKind::Other, "cancelled"));
    }

    // 璁＄畻缁紶璧风偣
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
            let e = io::Error::new(io::ErrorKind::Other, format!("HTTP 鐘舵€佺爜 {code}"));
            *error.lock().unwrap() = Some(e.clone());
            return Err(e);
        }
        Err(e) => {
            let e = io::Error::new(io::ErrorKind::Other, e.to_string());
            *error.lock().unwrap() = Some(e.clone());
            return Err(e);
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
        // 瀹氭湡鍒风洏浠ヤ繚璇佺画浼犳椂鍏冩暟鎹噯纭?        if written_this_session % (4 * 1024 * 1024) == 0 {
            let _ = file.flush();
        }
    }
    file.flush()?;
    Ok(())
}

/// 鍗曠嚎绋嬫祦寮忎笅杞斤紙甯﹁繘搴﹀洖璋冿級锛岀敤浜庡洖閫€鍦烘櫙
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
                format!("HTTP 鐘舵€佺爜 {code}"),
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
