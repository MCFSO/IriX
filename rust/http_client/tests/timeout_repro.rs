//! 超时行为复现测试（定位 CI Linux 上 timeout_read 不生效问题）
//!
//! 场景：本地 TCP 服务器 accept 连接、读完请求后延迟 3 秒才响应；
//! 客户端使用 1 秒读超时，期望 2 秒内报错。
//! 与 Dart 侧 http_ffi_test.dart 的 /slow 用例完全一致。
//!
//! - `ffi_timeout_honored` 走与 Dart 完全相同的 FFI 入口 http_request
//! - `ureq_timeout_read_honored` 直接验证 ureq timeout_read

use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;
use std::time::{Duration, Instant};

use xmc_http_client::{free_string, http_request};

/// 启动一个"收到请求后延迟 delay 秒再返回 200 slow"的服务器，返回地址。
fn start_delayed_server(delay: Duration) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            // 读完请求头
            let mut buf = [0u8; 4096];
            let _ = stream.read(&mut buf);
            thread::sleep(delay);
            let resp = "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nslow";
            let _ = stream.write_all(resp.as_bytes());
            let _ = stream.flush();
        }
    });
    format!("http://{addr}/slow")
}

/// 与 Dart 侧一致的 FFI 调用：timeout_secs=1，期望 1 秒左右报网络错误。
#[test]
fn ffi_timeout_honored() {
    let url = start_delayed_server(Duration::from_secs(3));
    let c_url = std::ffi::CString::new(url).unwrap();
    let c_method = std::ffi::CString::new("GET").unwrap();
    let c_headers = std::ffi::CString::new("{}").unwrap();

    let start = Instant::now();
    let result_ptr = http_request(
        c_method.as_ptr(),
        c_url.as_ptr(),
        c_headers.as_ptr(),
        std::ptr::null(),
        0,
        1, // 1 秒超时
        5,
    );
    let elapsed = start.elapsed();

    assert!(!result_ptr.is_null(), "http_request 返回空指针");
    let result = unsafe { std::ffi::CStr::from_ptr(result_ptr) }
        .to_string_lossy()
        .to_string();
    free_string(result_ptr);

    println!("ffi result after {elapsed:?}: {result}");
    assert!(
        elapsed < Duration::from_secs(2),
        "1s 读超时未生效，请求等了 {elapsed:?} 才返回"
    );
    assert!(
        result.contains("\"ok\":false"),
        "期望网络错误，实际成功: {result}"
    );
}

/// 直接验证 ureq 的 timeout_read 行为。
#[test]
fn ureq_timeout_read_honored() {
    let url = start_delayed_server(Duration::from_secs(3));

    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(30))
        .timeout_read(Duration::from_secs(1))
        .build();

    let start = Instant::now();
    let result = agent.get(&url).call();
    let elapsed = start.elapsed();

    println!("ureq result after {elapsed:?}: {result:?}");
    assert!(
        elapsed < Duration::from_secs(2),
        "ureq timeout_read(1s) 未生效，请求等了 {elapsed:?} 才返回"
    );
    assert!(result.is_err(), "期望超时错误，实际成功: {result:?}");
}
