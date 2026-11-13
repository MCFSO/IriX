//! ADB reverse / 本机 TCP 的 GNSS 时间桥。
//!
//! 手机上的 Android App 通过 `adb reverse tcp:47820 tcp:47820` 连接到本机
//! `127.0.0.1:47820`；本服务解析 NDJSON 的 `gnss_hello` / `gnss_ping` /
//! `gnss_sample`，用 `rtt_ns` 估算单程延迟，再交给 `Service::ingest_gnss`。
//!
//! 只应绑定 `127.0.0.1`（ADB reverse 场景）。不要把它暴露到公网。

use std::io::{BufRead, BufReader, BufWriter, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use serde::Serialize;
use serde_json::{json, Value};

use crate::service::{GnssSample, Service};

#[derive(Clone, Debug, Default, Serialize)]
pub struct BridgeStatus {
    pub running: bool,
    pub addr: String,
    pub clients: u64,
    pub samples: u64,
    pub pings: u64,
    pub errors: u64,
    pub last_error: Option<String>,
}

#[derive(Default)]
struct Counters {
    clients: AtomicU64,
    samples: AtomicU64,
    pings: AtomicU64,
    errors: AtomicU64,
}

struct Inner {
    running: bool,
    addr: String,
    token: String,
    stop: Option<Arc<AtomicBool>>,
    handle: Option<JoinHandle<()>>,
}

pub struct GnssBridge {
    inner: Mutex<Inner>,
    counters: Arc<Counters>,
    last_error: Arc<Mutex<Option<String>>>,
}

impl GnssBridge {
    fn new() -> Self {
        Self {
            inner: Mutex::new(Inner {
                running: false,
                addr: String::new(),
                token: String::new(),
                stop: None,
                handle: None,
            }),
            counters: Arc::new(Counters::default()),
            last_error: Arc::new(Mutex::new(None)),
        }
    }

    pub fn start(&self, svc: Arc<Service>, addr: &str, token: &str) -> Result<BridgeStatus, String> {
        if token.len() < 4 {
            return Err("token 至少 4 个字符".to_string());
        }
        let mut inner = self.inner.lock().map_err(|_| "bridge 状态锁损坏")?;
        if inner.running {
            return Ok(self.status_locked(&inner));
        }
        let listener = TcpListener::bind(addr).map_err(|e| format!("绑定 {addr} 失败: {e}"))?;
        listener
            .set_nonblocking(true)
            .map_err(|e| format!("设置 nonblocking 失败: {e}"))?;
        let local_addr = listener
            .local_addr()
            .map_err(|e| format!("读取本地地址失败: {e}"))?
            .to_string();
        let stop = Arc::new(AtomicBool::new(false));
        inner.running = true;
        inner.addr = local_addr;
        inner.token = token.to_string();
        inner.stop = Some(stop.clone());
        *self.last_error.lock().unwrap_or_else(|p| p.into_inner()) = None;

        let token = token.to_string();
        let counters = self.counters.clone();
        let last_error = self.last_error.clone();
        let svc = svc.clone();
        let handle = thread::Builder::new()
            .name("xmc-gnss-bridge".to_string())
            .spawn(move || run(listener, svc, token, stop, counters, last_error))
            .map_err(|e| format!("启动 bridge 线程失败: {e}"))?;
        inner.handle = Some(handle);
        Ok(self.status_locked(&inner))
    }

    pub fn stop(&self) -> BridgeStatus {
        let handle = {
            let mut inner = self.inner.lock().unwrap_or_else(|p| p.into_inner());
            if let Some(stop) = inner.stop.take() {
                stop.store(true, Ordering::SeqCst);
            }
            inner.running = false;
            inner.handle.take()
        };
        if let Some(handle) = handle {
            let _ = handle.join();
        }
        self.status()
    }

    pub fn status(&self) -> BridgeStatus {
        let inner = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        self.status_locked(&inner)
    }

    fn status_locked(&self, inner: &Inner) -> BridgeStatus {
        BridgeStatus {
            running: inner.running,
            addr: inner.addr.clone(),
            clients: self.counters.clients.load(Ordering::Relaxed),
            samples: self.counters.samples.load(Ordering::Relaxed),
            pings: self.counters.pings.load(Ordering::Relaxed),
            errors: self.counters.errors.load(Ordering::Relaxed),
            last_error: self
                .last_error
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .clone(),
        }
    }
}

fn run(
    listener: TcpListener,
    svc: Arc<Service>,
    token: String,
    stop: Arc<AtomicBool>,
    counters: Arc<Counters>,
    last_error: Arc<Mutex<Option<String>>>,
) {
    while !stop.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, _peer)) => {
                counters.clients.fetch_add(1, Ordering::Relaxed);
                let result = handle_client(&stream, &svc, &token, &stop, &counters);
                counters.clients.fetch_sub(1, Ordering::Relaxed);
                if let Err(e) = result {
                    counters.errors.fetch_add(1, Ordering::Relaxed);
                    *last_error.lock().unwrap_or_else(|p| p.into_inner()) = Some(e);
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
            }
            Err(e) => {
                counters.errors.fetch_add(1, Ordering::Relaxed);
                *last_error.lock().unwrap_or_else(|p| p.into_inner()) =
                    Some(format!("accept 失败: {e}"));
                thread::sleep(Duration::from_millis(200));
            }
        }
    }
}

fn handle_client(
    stream: &TcpStream,
    svc: &Arc<Service>,
    token: &str,
    stop: &Arc<AtomicBool>,
    counters: &Arc<Counters>,
) -> Result<(), String> {
    // Windows may inherit the listener's nonblocking mode on accepted sockets;
    // force blocking I/O with a read timeout for this connection.
    stream
        .set_nonblocking(false)
        .map_err(|e| format!("设置 blocking 失败: {e}"))?;
    stream
        .set_read_timeout(Some(Duration::from_millis(500)))
        .map_err(|e| format!("设置读超时失败: {e}"))?;
    stream
        .set_nodelay(true)
        .map_err(|e| format!("设置 TCP_NODELAY 失败: {e}"))?;
    let reader_stream = stream.try_clone().map_err(|e| format!("复制 socket 失败: {e}"))?;
    let mut reader = BufReader::new(reader_stream);
    let mut writer = BufWriter::new(stream);
    let mut authenticated = false;
    let mut line = String::new();

    while !stop.load(Ordering::SeqCst) {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => return Ok(()),
            Ok(_) => {}
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                continue;
            }
            Err(e) => return Err(format!("读 socket 失败: {e}")),
        }
        if line.len() > 65_536 {
            return Err("单行 JSON 超过 64KiB".to_string());
        }
        if line.trim().is_empty() {
            continue;
        }
        let value: Value = serde_json::from_str(line.trim()).map_err(|e| format!("JSON 解析失败: {e}"))?;
        let op = value.get("op").and_then(Value::as_str).unwrap_or("");
        let args = value.get("args").cloned().unwrap_or_else(|| json!({}));
        let response = match op {
            "gnss_hello" => {
                let protocol = args.get("protocol").and_then(Value::as_i64).unwrap_or(1);
                let supplied = args.get("token").and_then(Value::as_str).unwrap_or("");
                if supplied != token {
                    counters.errors.fetch_add(1, Ordering::Relaxed);
                    error("token 不匹配")
                } else if protocol != 1 {
                    error("不支持的 gnss 协议版本")
                } else {
                    svc.gnss_hello(protocol, true)
                        .map(|mut data| {
                            data["server_time_ns"] = json!(svc.clock.now_ns() as i64);
                            data["mono_ns"] = json!(svc.clock.mono_ns());
                            authenticated = true;
                            ok(data)
                        })
                        .unwrap_or_else(error)
                }
            }
            "gnss_ping" => {
                if !authenticated {
                    error("先发送 gnss_hello")
                } else {
                    counters.pings.fetch_add(1, Ordering::Relaxed);
                    let id = args.get("id").cloned().unwrap_or(Value::Null);
                    let t0 = args.get("t0_ns").cloned().unwrap_or(Value::Null);
                    ok(json!({ "pong": true, "id": id, "t0_ns": t0 }))
                }
            }
            "gnss_sample" => {
                if !authenticated {
                    error("先发送 gnss_hello")
                } else {
                    match ingest_sample(svc, &args) {
                        Ok(result) => {
                            counters.samples.fetch_add(1, Ordering::Relaxed);
                            ok(result)
                        }
                        Err(e) => {
                            counters.errors.fetch_add(1, Ordering::Relaxed);
                            error(e)
                        }
                    }
                }
            }
            "gnss_bye" => return Ok(()),
            _ => error(format!("未知 op: {op}")),
        };
        let text = serde_json::to_string(&response).map_err(|e| e.to_string())?;
        writer
            .write_all(text.as_bytes())
            .and_then(|_| writer.write_all(b"\n"))
            .and_then(|_| writer.flush())
            .map_err(|e| format!("写 socket 失败: {e}"))?;
    }
    Ok(())
}

fn ingest_sample(svc: &Arc<Service>, args: &Value) -> Result<serde_json::Value, String> {
    let rtt_ns = args
        .get("rtt_ns")
        .and_then(Value::as_i64)
        .ok_or("缺少 rtt_ns（手机需先 ping）")?;
    if !(100_000..=500_000_000).contains(&rtt_ns) {
        return Err(format!("rtt_ns 超出 0.1ms~500ms: {rtt_ns}"));
    }
    let mut sample = GnssSample::from_json(args)?;
    // 手机和桌面是两条 BOOTTIME 轴：绝对不能把手机的 mono_ns 拿到桌面减。
    // 用桌面“收到样本”的单调时刻做本地对齐，手机 age_ms 保留在样本里。
    sample.mono_ns = svc.clock.mono_ns();
    sample.alignment = Some("adb_reverse".to_string());
    sample.transport_delay_ns = Some(rtt_ns / 2);
    sample.transport_delay_uncertainty_ns = Some((rtt_ns / 4).max(100_000));
    serde_json::to_value(svc.ingest_gnss(sample)).map_err(|e| e.to_string())
}

fn ok(data: Value) -> Value {
    json!({ "ok": true, "data": data })
}

fn error(message: impl Into<String>) -> Value {
    json!({ "ok": false, "error": message.into() })
}

static GLOBAL: OnceLock<Arc<GnssBridge>> = OnceLock::new();

pub fn global() -> &'static Arc<GnssBridge> {
    GLOBAL.get_or_init(|| Arc::new(GnssBridge::new()))
}

pub fn start(svc: Arc<Service>, addr: &str, token: &str) -> Result<BridgeStatus, String> {
    global().start(svc, addr, token)
}

pub fn stop() -> BridgeStatus {
    global().stop()
}

pub fn status() -> BridgeStatus {
    global().status()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpStream;

    #[test]
    fn adb_reverse_hello_ping_and_sample() {
        let svc = Arc::new(Service::new());
        let status = start(svc.clone(), "127.0.0.1:0", "test-token").expect("start bridge");
        assert!(status.running);
        let mut stream = TcpStream::connect(&status.addr).expect("connect");
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let mut reader = BufReader::new(stream.try_clone().unwrap());
        let mut writer = stream;
        let mut exchange = |line: String| -> Value {
            writer.write_all(line.as_bytes()).unwrap();
            writer.write_all(b"\n").unwrap();
            writer.flush().unwrap();
            let mut out = String::new();
            reader.read_line(&mut out).unwrap();
            serde_json::from_str(out.trim()).unwrap()
        };

        let hello = exchange(
            json!({"op":"gnss_hello","args":{"protocol":1,"token":"test-token"}}).to_string(),
        );
        assert_eq!(hello["ok"], true, "{hello}");
        let ping = exchange(json!({"op":"gnss_ping","args":{"id":1,"t0_ns":42}}).to_string());
        assert_eq!(ping["data"]["pong"], true);

        let mono = svc.clock.mono_ns();
        let utc = svc.clock.raw_now_ns() + 1_000_000_000;
        let sample = exchange(
            json!({
                "op":"gnss_sample",
                "args":{
                    "utc_ns": utc,
                    "mono_ns": mono,
                    "uncertainty_ns": 500,
                    "constellation": "gps",
                    "sv_count": 12,
                    "fix": "3d",
                    "source": "raw",
                    "age_ms": 0,
                    "rtt_ns": 1_000_000
                }
            })
            .to_string(),
        );
        assert_eq!(sample["ok"], true, "{sample}");
        assert_eq!(sample["data"]["accepted"], true, "{sample}");

        drop(svc);
        stop();
    }
}
