//! Minecraft Server List Ping（Server Status 协议）
//!
//! 用于弹性扩缩容的在线人数数据源与存活探测：
//! TCP 连接 → handshake(状态=1) → status request → 解析 JSON 响应
//! （players.online / players.max / version.name / description）。
//! 纯 std::net 实现，无外部依赖。

use serde::Serialize;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};

/// MC 服务器状态。
#[derive(Debug, Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct McStatus {
    /// 服务器可达且响应合法。
    pub online: bool,
    /// 在线人数。
    pub players: i64,
    /// 人数上限。
    pub max_players: i64,
    /// 延迟（毫秒）。
    pub latency_ms: u64,
    /// 版本名（可空）。
    #[serde(default)]
    pub version: Option<String>,
    /// MOTD 描述文本（可空）。
    #[serde(default)]
    pub motd: Option<String>,
}

impl McStatus {
    fn unreachable() -> Self {
        McStatus { online: false, ..Default::default() }
    }
}

/// 探测 MC 服务器（Server List Ping）。
///
/// [host] 服务器地址，[port] 端口（默认 25565），[timeout_ms] 超时（默认 3000）。
pub fn ping(host: &str, port: u16, timeout_ms: u64) -> McStatus {
    let timeout = Duration::from_millis(if timeout_ms == 0 { 3000 } else { timeout_ms });
    let started = Instant::now();
    let mut stream = match TcpStream::connect((host, port)) {
        Ok(s) => s,
        Err(_) => return McStatus::unreachable(),
    };
    if stream.set_read_timeout(Some(timeout)).is_err()
        || stream.set_write_timeout(Some(timeout)).is_err()
    {
        return McStatus::unreachable();
    }

    // handshake: packet id 0x00, protocol -1, host, port, next state 1
    let mut handshake = Vec::new();
    write_varint(&mut handshake, 0x00);
    write_varint(&mut handshake, -1);
    write_string(&mut handshake, host);
    handshake.extend_from_slice(&port.to_be_bytes());
    write_varint(&mut handshake, 0x01); // next state: status

    // status request: packet id 0x00（空体）
    let mut request = Vec::new();
    write_varint(&mut request, 0x00);

    let mut packet = Vec::with_capacity(handshake.len() + request.len() + 10);
    write_varint(&mut packet, handshake.len() as i32);
    packet.extend_from_slice(&handshake);
    write_varint(&mut packet, request.len() as i32);
    packet.extend_from_slice(&request);

    if stream.write_all(&packet).is_err() || stream.flush().is_err() {
        return McStatus::unreachable();
    }

    // 响应: 总长度 varint + packet id 0x00 + JSON 长度 varint + JSON
    let frame_len = match read_varint(&mut stream) {
        Some(v) => v as usize,
        None => return McStatus::unreachable(),
    };
    if frame_len == 0 || frame_len > 1 << 20 {
        return McStatus::unreachable();
    }
    let mut frame = vec![0u8; frame_len];
    if read_exact(&mut stream, &mut frame).is_err() {
        return McStatus::unreachable();
    }
    let mut cursor = std::io::Cursor::new(frame.as_slice());
    let packet_id = read_varint_from(&mut cursor).unwrap_or(-1);
    if packet_id != 0x00 {
        return McStatus::unreachable();
    }
    let json_len = read_varint_from(&mut cursor).unwrap_or(0) as usize;
    if json_len == 0 || json_len > frame_len {
        return McStatus::unreachable();
    }
    let start = cursor.position() as usize;
    let end = (start + json_len).min(frame.len());
    let raw = String::from_utf8_lossy(&frame[start..end]).to_string();

    let latency_ms = started.elapsed().as_millis() as u64;
    match serde_json::from_str::<serde_json::Value>(&raw) {
        Ok(json) => {
            let players = json
                .pointer("/players/online")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let max_players = json
                .pointer("/players/max")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let version = json
                .pointer("/version/name")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let motd = json
                .pointer("/description/text")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .or_else(|| {
                    json.pointer("/description")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                });
            McStatus {
                online: true,
                players,
                max_players,
                latency_ms,
                version,
                motd,
            }
        }
        Err(_) => McStatus::unreachable(),
    }
}

// ======================== 协议编码 ========================

/// 写 VarInt（i32）。
fn write_varint(buf: &mut Vec<u8>, value: i32) {
    let mut v = value as u32;
    loop {
        let mut byte = (v & 0x7F) as u8;
        v >>= 7;
        if v != 0 {
            byte |= 0x80;
        }
        buf.push(byte);
        if v == 0 {
            break;
        }
    }
}

/// 写字符串（长度 varint + UTF-8）。
fn write_string(buf: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    write_varint(buf, bytes.len() as i32);
    buf.extend_from_slice(bytes);
}

/// 从流读 VarInt。
fn read_varint(stream: &mut TcpStream) -> Option<i32> {
    let mut value: u32 = 0;
    for i in 0..5 {
        let mut byte = [0u8; 1];
        if stream.read_exact(&mut byte).is_err() {
            return None;
        }
        value |= ((byte[0] & 0x7F) as u32) << (7 * i);
        if byte[0] & 0x80 == 0 {
            return Some(value as i32);
        }
    }
    None
}

/// 从字节游标读 VarInt。
fn read_varint_from(cursor: &mut std::io::Cursor<&[u8]>) -> Option<i32> {
    let mut value: u32 = 0;
    for i in 0..5 {
        let mut byte = [0u8; 1];
        if cursor.read_exact(&mut byte).is_err() {
            return None;
        }
        value |= ((byte[0] & 0x7F) as u32) << (7 * i);
        if byte[0] & 0x80 == 0 {
            return Some(value as i32);
        }
    }
    None
}

/// 读满缓冲区（TCP 分片兜底）。
fn read_exact(stream: &mut TcpStream, buf: &mut [u8]) -> std::io::Result<()> {
    let mut filled = 0;
    while filled < buf.len() {
        let n = stream.read(&mut buf[filled..])?;
        if n == 0 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "连接提前关闭",
            ));
        }
        filled += n;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn varint_roundtrip() {
        for value in [0i32, 1, 127, 128, 25565, 2147483647, -1] {
            let mut buf = Vec::new();
            write_varint(&mut buf, value);
            let mut cursor = std::io::Cursor::new(buf.as_slice());
            assert_eq!(read_varint_from(&mut cursor), Some(value), "varint {value}");
        }
    }

    #[test]
    fn string_writes_length_prefixed() {
        let mut buf = Vec::new();
        write_string(&mut buf, "hello");
        assert_eq!(buf[0], 5);
        assert_eq!(&buf[1..], b"hello");
    }

    #[test]
    fn unreachable_host_returns_offline() {
        let status = ping("127.0.0.1", 1, 500);
        assert!(!status.online);
    }
}
