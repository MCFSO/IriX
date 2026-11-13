//! NTPv4 客户端。
//!
//! 协议编解码、偏移/时延运算全部来自 `rusty_time-core`（rusty_time 的 NTP 引擎），
//! 本模块只负责：DNS/套接字 I/O、时间戳采样、报文合法性校验（防欺骗/KoD/未同步）、
//! 以及把结果转换成纪律环需要的 `Sample`。
//!
//! 安全校验（缺一不可）：
//! - 响应源地址必须是我们 connect 的服务器（UDP connect 已由内核过滤）；
//! - `origin_ts` 必须等于我们发出的随机 nonce（防 off-path 伪造）；
//! - mode 必须是 Server、版本 3/4、stratum 1..=15；
//! - leap=3（unsynchronized）、transmit/receive 为 0、RTT 为负或过大 → 丢弃；
//! - stratum=0 视为 Kiss-o'-Death，读取 reference id 并退避。
//!
//! 精度：
//! - nonce 与 t1 分离：nonce 用 CSPRNG，t1 用应用时钟在 send 前一刻采样；
//! - t1/t4 走 `precise`（TSC 插值）时间轴，降低发送/接收系统调用的量化误差；
//! - 一次 poll 可发多个样本（burst），交给 rusty_time 的加权回归滤波。

use std::io;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::time::Duration;

use rusty_time_core::ntp::{offset_delay, LeapIndicator, Mode, NtpPacket, NtpTimestamp, UNIX_EPOCH_OFFSET};

use crate::clock::AppClock;

const NTP_PORT: u16 = 123;
const MAX_RESPONSE: usize = 1024;

#[derive(Clone, Debug)]
pub struct NtpSample {
    /// 本地单调时间轴上的交换中点（秒），给纪律环做回归。
    pub t_mono_s: f64,
    /// 需要加到本地时钟上的偏移（秒，RFC 5905 θ）。
    pub offset_s: f64,
    /// 往返时延（秒）。
    pub delay_s: f64,
    /// 累积离散度（秒）。
    pub dispersion_s: f64,
    /// t1/t4 批量时间戳的合成不确定度（秒）。
    pub timestamp_uncertainty_s: f64,
    pub stratum: u8,
    pub leap: i8,
    pub root_delay_s: f64,
    pub root_dispersion_s: f64,
    pub server_unix_s: f64,
    pub version: u8,
    pub precision_s: f64,
}

#[derive(Clone, Debug)]
pub struct NtpError {
    pub message: String,
    pub kind: NtpErrorKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NtpErrorKind {
    Resolve,
    Io,
    Timeout,
    Protocol,
    KissOfDeath,
    Unsynchronized,
}

impl NtpError {
    fn new(kind: NtpErrorKind, msg: impl Into<String>) -> Self {
        NtpError {
            message: msg.into(),
            kind,
        }
    }
}

impl std::fmt::Display for NtpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

/// 解析 "host"、"host:port"、"1.2.3.4:123"、"[::1]:123"。
pub fn parse_server(server: &str) -> Result<(String, u16), NtpError> {
    let s = server.trim();
    if s.is_empty() {
        return Err(NtpError::new(NtpErrorKind::Resolve, "NTP 服务器为空"));
    }
    if let Ok(sa) = s.parse::<SocketAddr>() {
        return Ok((sa.ip().to_string(), sa.port()));
    }
    if let Some(rest) = s.strip_prefix('[') {
        // [v6]:port 或 [v6]
        if let Some((host, tail)) = rest.split_once(']') {
            let port = tail
                .strip_prefix(':')
                .and_then(|p| p.parse::<u16>().ok())
                .unwrap_or(NTP_PORT);
            return Ok((host.to_string(), port));
        }
    }
    if let Some((host, port)) = s.rsplit_once(':') {
        if !host.contains(':') {
            if let Ok(port) = port.parse::<u16>() {
                return Ok((host.to_string(), port));
            }
        }
    }
    Ok((s.to_string(), NTP_PORT))
}

fn resolve(server: &str) -> Result<SocketAddr, NtpError> {
    let (host, port) = parse_server(server)?;
    let addrs: Vec<SocketAddr> = (host.as_str(), port)
        .to_socket_addrs()
        .map_err(|e| NtpError::new(NtpErrorKind::Resolve, format!("解析 {host}:{port} 失败: {e}")))?
        .collect();
    addrs.into_iter().next().ok_or_else(|| {
        NtpError::new(
            NtpErrorKind::Resolve,
            format!("{host}:{port} 没有可用地址"),
        )
    })
}

fn nonce() -> u64 {
    for _ in 0..4 {
        if let Ok(n) = getrandom::u64() {
            if n != 0 {
                return n;
            }
        }
    }
    // 极端情况下 getrandom 不可用：至少保证每次不同。
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(1);
    let t = xmc_time_base::mono::now_ns();
    let s = SEQ.fetch_add(1, Ordering::Relaxed);
    (t ^ (s.wrapping_mul(0x9E37_79B9_7F4A_7C15))) | 1
}

/// NTP 32.32 时间戳 → Unix 秒（f64），按 68 年窗口自动选择纪元（2036 回绕）。
fn ntp_to_unix(ts: NtpTimestamp, approx_unix_s: f64) -> Option<f64> {
    if ts.is_zero() {
        return None;
    }
    let frac = ts.fraction() as f64 / 4_294_967_296.0;
    let base = ts.seconds() as i64 - UNIX_EPOCH_OFFSET as i64;
    let era = 1i64 << 32;
    let approx = approx_unix_s.round() as i64;
    let mut best = base;
    let mut best_diff = (base - approx).abs();
    for k in -1i64..=2 {
        let cand = base + k * era;
        let diff = (cand - approx).abs();
        if diff < best_diff {
            best = cand;
            best_diff = diff;
        }
    }
    Some(best as f64 + frac)
}

fn kod_name(packet: &NtpPacket) -> String {
    let id = String::from_utf8_lossy(&packet.reference_id).to_string();
    if id.chars().all(|c| c.is_ascii_graphic() || c == ' ') {
        id.trim().to_string()
    } else {
        String::new()
    }
}

/// 单次 NTP 交换。
pub fn query(server: &str, timeout: Duration, clock: &AppClock) -> Result<NtpSample, NtpError> {
    let addr = resolve(server)?;
    let bind_addr: SocketAddr = if addr.is_ipv4() {
        "0.0.0.0:0".parse().unwrap()
    } else {
        "[::]:0".parse().unwrap()
    };
    let socket = UdpSocket::bind(bind_addr)
        .map_err(|e| NtpError::new(NtpErrorKind::Io, format!("绑定 UDP 套接字失败: {e}")))?;
    socket
        .connect(addr)
        .map_err(|e| NtpError::new(NtpErrorKind::Io, format!("连接 {addr} 失败: {e}")))?;
    socket
        .set_read_timeout(Some(timeout))
        .map_err(|e| NtpError::new(NtpErrorKind::Io, format!("设置超时失败: {e}")))?;
    socket
        .set_write_timeout(Some(timeout))
        .map_err(|e| NtpError::new(NtpErrorKind::Io, format!("设置超时失败: {e}")))?;

    let n = nonce();
    let request = NtpPacket::client_request(4, NtpTimestamp(n)).to_bytes();

    let generation = clock.generation();
    // 批量采样 + 鲁棒拟合：剔除被调度器打断的离群点，并把残差作为时间戳
    // 不确定度传给后面的卡尔曼滤波，而不是假设 t1/t4 没有误差。
    let stamp1 = crate::precise::batch_stamp(9);
    let m1 = stamp1.mono_ns;
    let t1 = clock.raw_at(m1) as f64 / 1e9;
    socket
        .send(&request)
        .map_err(|e| NtpError::new(NtpErrorKind::Io, format!("发送到 {addr} 失败: {e}")))?;

    let mut buf = [0u8; MAX_RESPONSE];
    let len = match socket.recv(&mut buf) {
        Ok(len) => len,
        Err(e)
            if matches!(
                e.kind(),
                io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
            ) =>
        {
            return Err(NtpError::new(
                NtpErrorKind::Timeout,
                format!("等待 {server} 响应超时（{}ms）", timeout.as_millis()),
            ));
        }
        Err(e) => {
            return Err(NtpError::new(
                NtpErrorKind::Io,
                format!("从 {server} 接收失败: {e}"),
            ));
        }
    };
    let stamp4 = crate::precise::batch_stamp(9);
    let m4 = stamp4.mono_ns;
    let t4 = clock.raw_at(m4) as f64 / 1e9;

    // 交换期间应用时钟被步进/改速率：本次样本不可信。
    if clock.generation() != generation {
        return Err(NtpError::new(
            NtpErrorKind::Protocol,
            "交换期间应用时钟被调整，样本丢弃",
        ));
    }

    let packet = NtpPacket::parse(&buf[..len])
        .map_err(|e| NtpError::new(NtpErrorKind::Protocol, format!("{server} 响应解析失败: {e}")))?;

    if packet.mode != Mode::Server {
        return Err(NtpError::new(
            NtpErrorKind::Protocol,
            format!("{server} 返回模式 {:?}，不是 Server", packet.mode),
        ));
    }
    if packet.origin_ts.0 != n {
        return Err(NtpError::new(
            NtpErrorKind::Protocol,
            format!("{server} origin 时间戳校验失败（可能的伪造响应）"),
        ));
    }
    if packet.stratum == 0 {
        let kod = kod_name(&packet);
        return Err(NtpError::new(
            NtpErrorKind::KissOfDeath,
            format!(
                "{server} 返回 Kiss-o'-Death{}，应降低轮询频率",
                if kod.is_empty() {
                    String::new()
                } else {
                    format!("（{kod}）")
                }
            ),
        ));
    }
    if packet.stratum > 15 {
        return Err(NtpError::new(
            NtpErrorKind::Unsynchronized,
            format!("{server} 未同步（stratum={}）", packet.stratum),
        ));
    }
    if packet.leap == LeapIndicator::Unsynchronized {
        return Err(NtpError::new(
            NtpErrorKind::Unsynchronized,
            format!("{server} 宣告自身未同步（leap=3）"),
        ));
    }
    if packet.receive_ts.is_zero() || packet.transmit_ts.is_zero() {
        return Err(NtpError::new(
            NtpErrorKind::Protocol,
            format!("{server} receive/transmit 时间戳为 0"),
        ));
    }

    let t2 = ntp_to_unix(packet.receive_ts, t1)
        .ok_or_else(|| NtpError::new(NtpErrorKind::Protocol, "服务器接收时间戳无效"))?;
    let t3 = ntp_to_unix(packet.transmit_ts, t1)
        .ok_or_else(|| NtpError::new(NtpErrorKind::Protocol, "服务器发送时间戳无效"))?;
    let (offset, delay) = offset_delay(t1, t2, t3, t4);

    if !offset.is_finite() || !delay.is_finite() {
        return Err(NtpError::new(NtpErrorKind::Protocol, "偏移/时延不是有限值"));
    }
    // 负时延允许极小的时钟噪声；超过 2ms 视为异常。上限 5s 拒绝跨洋异常路径。
    if !(-0.002..=5.0).contains(&delay) {
        return Err(NtpError::new(
            NtpErrorKind::Protocol,
            format!("{server} 往返时延异常: {:.3}ms", delay * 1000.0),
        ));
    }
    let precision_s = 2f64
        .powi(i32::from(packet.precision).clamp(-30, 0))
        .min(1e-3);
    let root_delay_s = packet.root_delay.to_seconds();
    let root_dispersion_s = packet.root_dispersion.to_seconds();
    let timestamp_uncertainty_s =
        (stamp1.uncertainty_ns + stamp4.uncertainty_ns) as f64 * 1e-9;
    let dispersion = (root_dispersion_s + precision_s + timestamp_uncertainty_s + 1e-6).min(1.0);
    let mid_mono_s = (m1 as f64 + m4 as f64) * 0.5e-9;

    Ok(NtpSample {
        t_mono_s: mid_mono_s,
        offset_s: offset,
        delay_s: delay.max(0.0),
        dispersion_s: dispersion,
        timestamp_uncertainty_s,
        stratum: packet.stratum,
        leap: packet.leap as i8,
        root_delay_s,
        root_dispersion_s,
        server_unix_s: t3,
        version: packet.version,
        precision_s,
    })
}

#[derive(Debug, Default)]
pub struct Burst {
    pub samples: Vec<NtpSample>,
    pub errors: Vec<String>,
    pub address: String,
}

/// 对一个服务器连续发 `count` 个样本（间隔 20ms），任何一个失败即停止，
/// 避免对限速服务器雪上加霜。
pub fn exchange_burst(
    server: &str,
    count: u32,
    timeout: Duration,
    clock: &AppClock,
) -> Burst {
    let mut burst = Burst {
        address: server.to_string(),
        ..Default::default()
    };
    for i in 0..count.max(1) {
        match query(server, timeout, clock) {
            Ok(sample) => burst.samples.push(sample),
            Err(e) => {
                burst.errors.push(e.message);
                break;
            }
        }
        if i + 1 < count.max(1) {
            std::thread::sleep(Duration::from_millis(20));
        }
    }
    burst
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    fn spawn_mock_ntp(offset_s: f64, kod: Option<&'static str>) -> (SocketAddr, Arc<AtomicBool>) {
        let socket = UdpSocket::bind("127.0.0.1:0").unwrap();
        let addr = socket.local_addr().unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        std::thread::spawn(move || {
            socket
                .set_read_timeout(Some(Duration::from_millis(500)))
                .ok();
            let mut buf = [0u8; 1024];
            while !stop2.load(Ordering::Relaxed) {
                let Ok((len, peer)) = socket.recv_from(&mut buf) else {
                    continue;
                };
                let Ok(req) = NtpPacket::parse(&buf[..len]) else {
                    continue;
                };
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap();
                let fake = now.as_secs_f64() + offset_s;
                let secs = fake.floor() as i64;
                let nanos = ((fake - secs as f64) * 1e9) as u32;
                let ts = NtpTimestamp::from_unix(secs, nanos);
                let mut resp = NtpPacket::client_request(4, req.transmit_ts);
                resp.mode = Mode::Server;
                resp.origin_ts = req.transmit_ts;
                resp.receive_ts = ts;
                resp.transmit_ts = ts;
                if let Some(code) = kod {
                    resp.stratum = 0;
                    let mut id = [b' '; 4];
                    for (i, b) in code.as_bytes().iter().take(4).enumerate() {
                        id[i] = *b;
                    }
                    resp.reference_id = id;
                } else {
                    resp.stratum = 2;
                }
                resp.precision = -20;
                let bytes = resp.to_bytes();
                let _ = socket.send_to(&bytes, peer);
            }
        });
        (addr, stop)
    }

    #[test]
    fn round_trip_against_mock_server() {
        let (addr, stop) = spawn_mock_ntp(2.5, None);
        let clock = AppClock::new();
        let sample = query(&addr.to_string(), Duration::from_millis(800), &clock).unwrap();
        assert!(
            (sample.offset_s - 2.5).abs() < 0.05,
            "offset {}",
            sample.offset_s
        );
        assert!(sample.delay_s < 0.05, "delay {}", sample.delay_s);
        assert_eq!(sample.stratum, 2);
        stop.store(true, Ordering::Relaxed);
    }

    #[test]
    fn kiss_of_death_is_reported() {
        let (addr, stop) = spawn_mock_ntp(0.0, Some("RATE"));
        let clock = AppClock::new();
        let err = query(&addr.to_string(), Duration::from_millis(800), &clock).unwrap_err();
        assert_eq!(err.kind, NtpErrorKind::KissOfDeath);
        assert!(err.message.contains("RATE"), "{}", err.message);
        stop.store(true, Ordering::Relaxed);
    }

    #[test]
    fn ntp_era_wrap_is_handled() {
        // 2036-02-07 之后 NTP 秒数回绕到 era 1：unix 2085978596 对应 32 位 NTP 秒 100。
        let unix = 2_085_978_496i64 + 100;
        let ts = NtpTimestamp(100u64 << 32);
        let got = ntp_to_unix(ts, unix as f64).unwrap();
        assert!((got - unix as f64).abs() < 1e-6, "{got} vs {unix}");
    }

    #[test]
    fn parses_server_forms() {
        assert_eq!(parse_server("ntp.aliyun.com").unwrap(), ("ntp.aliyun.com".into(), 123));
        assert_eq!(parse_server("127.0.0.1:12345").unwrap(), ("127.0.0.1".into(), 12345));
        assert_eq!(parse_server("[::1]:123").unwrap(), ("::1".into(), 123));
    }
}
