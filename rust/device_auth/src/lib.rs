//! IriX 客户端设备绑定密码学模块（对应 docs/device-binding.md v1.4.0）
//!
//! 独立编译为 `xmc_device_auth.dll` / `libxmc_device_auth.so|dylib`，由 Dart 侧
//! `lib/services/device_auth_ffi.dart` 通过 `dev_auth_request(op, args_json)` 调用。
//!
//! 设计要点：
//! - 私钥**不进入 Dart 堆内存**：密钥生成、落盘、读取、签名全部在本 crate 内完成，
//!   Dart 只拿到 `deviceId` / 公钥 / 签名值；
//! - 落盘保护：Windows 用 DPAPI（`CryptProtectData`）以当前用户身份加密整份
//!   密钥文件，`keyProtection` 如实上报 `os-keychain`；其他平台用 0600 权限文件，
//!   上报 `file`（TPM 2.0 载体属于后续版本，见协议 §10.1）；
//! - 密码学后端为 `ring`（rustls 已在 workspace 中引入，无新增 C 依赖、无 OpenSSL）：
//!   ed25519 原始 64 字节签名、ECDSA P-256 `r||s`（P1363，64 字节）、HMAC-SHA256、
//!   SHA-256、系统 CSPRNG；
//! - 所有入参/出参为 JSON，出错返回 `{"ok":false,"error":"..."}` 并写入
//!   thread-local 的 last_error，便于 Dart 侧读取可读原因。
//!
//! 协议对应关系（client 侧只负责「算」与「签」，网络与规范串拼接在 Dart 侧）：
//! | op | 协议用途 |
//! | --- | --- |
//! | `ensure_key` / `key_status` | §2 密钥、公钥编码、deviceId |
//! | `sign` | §4 注册签名、§5 登录签名 |
//! | `hmac_sha256` | §6 `X-Session-Proof` 逐请求证明 |
//! | `random_b64url` | §2 `proofKey`、挑战随机量 |
//! | `sha256` | §4 注册规范串里的 `hex(SHA-256(descriptor))` |
//! | `device_id` | §2 `deviceId = hex(SHA-256(公钥))[:32]` |

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::fs;
use std::io::Write;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::Mutex;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ring::signature::KeyPair;
use ring::{digest, hmac, rand, signature};
use serde_json::{json, Value};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// 密钥文件所在目录（由 `init` 设置，通常来自 Dart 的 `AppPaths`）。
static STORE_DIR: Mutex<Option<PathBuf>> = Mutex::new(None);

/// 设备密钥文件内的版本号，便于后续升级格式。
const KEY_FILE_VERSION: u32 = 1;

/// `keyType` 允许值。
const KEY_TYPE_ED25519: &str = "ed25519";
const KEY_TYPE_P256: &str = "p256";

// ---------------------------------------------------------------------------
// FFI 基础设施
// ---------------------------------------------------------------------------

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

/// 把结果字符串包装成 C 字符串指针返回（Dart 侧用 `free_string` 释放）。
fn cstring_out(s: String) -> *mut libc::c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => CString::new(r#"{"ok":false,"error":"结果字符串包含 nul 字节"}"#)
            .unwrap()
            .into_raw(),
    }
}

fn error_json(message: impl Into<String>) -> String {
    let message = message.into();
    set_last_error(&message);
    json!({ "ok": false, "error": message }).to_string()
}

fn ok_json(data: Value) -> String {
    json!({ "ok": true, "data": data }).to_string()
}

fn parse_args(raw: *const libc::c_char) -> Result<Value, String> {
    if raw.is_null() {
        return Ok(json!({}));
    }
    let text = unsafe { CStr::from_ptr(raw) }
        .to_str()
        .map_err(|_| "args 不是有效的 UTF-8".to_string())?;
    if text.trim().is_empty() {
        return Ok(json!({}));
    }
    serde_json::from_str(text).map_err(|e| format!("args JSON 解析失败: {e}"))
}

fn arg_str(args: &Value, key: &str) -> Option<String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// 读取「UTF-8 原文」或「base64 原始字节」形式的字节入参。
///
/// 协议要求签名输入按 UTF-8 字节逐字节拼接，Dart 侧统一传 `message`（原文），
/// 只有确实需要二进制时（例如 `sha256` 的 descriptor 已在 Dart 侧编码）才用
/// `*_b64` 变体。
fn arg_bytes(args: &Value, text_key: &str, b64_key: &str) -> Result<Vec<u8>, String> {
    if let Some(b64) = arg_str(args, b64_key) {
        return b64u_decode(&b64);
    }
    if let Some(text) = arg_str(args, text_key) {
        return Ok(text.into_bytes());
    }
    Err(format!(
        "缺少参数 {text_key}（UTF-8 原文）或 {b64_key}（base64）"
    ))
}

fn b64u_encode(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn b64u_decode(text: &str) -> Result<Vec<u8>, String> {
    // 兼容带尾部填充的输入（协议要求无填充，但宽松解码更稳）。
    URL_SAFE_NO_PAD
        .decode(text.trim().trim_end_matches('='))
        .map_err(|e| format!("base64url 解码失败: {e}"))
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn system_random() -> Result<rand::SystemRandom, String> {
    // ring 0.17 的 SystemRandom::new 不返回 Result（Windows/Unix 上均不会失败）。
    Ok(rand::SystemRandom::new())
}

// ---------------------------------------------------------------------------
// 设备密钥
// ---------------------------------------------------------------------------

/// 本机设备密钥（私钥以 PKCS#8 字节保存，仅存在于本进程与本 crate 内）。
#[derive(Clone)]
struct DeviceKey {
    key_type: String,
    key_protection: String,
    pkcs8: Vec<u8>,
    public_key: Vec<u8>,
    device_id: String,
    created_at: i64,
}

impl DeviceKey {
    fn to_json(&self) -> Value {
        json!({
            "version": KEY_FILE_VERSION,
            "keyType": self.key_type,
            "keyProtection": self.key_protection,
            "pkcs8": b64u_encode(&self.pkcs8),
            "publicKey": b64u_encode(&self.public_key),
            "deviceId": self.device_id,
            "createdAt": self.created_at,
        })
    }

    fn from_json(value: &Value) -> Result<Self, String> {
        let key_type = value
            .get("keyType")
            .and_then(|v| v.as_str())
            .ok_or("密钥文件缺少 keyType")?
            .to_string();
        if key_type != KEY_TYPE_ED25519 && key_type != KEY_TYPE_P256 {
            return Err(format!("不支持的密钥类型: {key_type}"));
        }
        let key_protection = value
            .get("keyProtection")
            .and_then(|v| v.as_str())
            .unwrap_or(default_key_protection())
            .to_string();
        let pkcs8 = b64u_decode(
            value
                .get("pkcs8")
                .and_then(|v| v.as_str())
                .ok_or("密钥文件缺少 pkcs8")?,
        )?;
        if pkcs8.is_empty() {
            return Err("密钥文件中的 pkcs8 为空".to_string());
        }
        let public_key = b64u_decode(
            value
                .get("publicKey")
                .and_then(|v| v.as_str())
                .ok_or("密钥文件缺少 publicKey")?,
        )?;
        let device_id = value
            .get("deviceId")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        // deviceId 必须由公钥推导（协议 §2），文件被改动时直接拒绝，避免
        // 用一个与公钥不匹配的 deviceId 去注册/登录。
        let expected = device_id_from_public_key(&public_key);
        if !device_id.is_empty() && device_id != expected {
            return Err(format!(
                "密钥文件中的 deviceId 与公钥不匹配（期望 {expected}，实际 {device_id}）"
            ));
        }
        Ok(Self {
            key_type,
            key_protection,
            pkcs8,
            public_key,
            device_id: expected,
            created_at: value
                .get("createdAt")
                .and_then(|v| v.as_i64())
                .unwrap_or_else(unix_now),
        })
    }

    fn status_json(&self) -> Value {
        json!({
            "exists": true,
            "deviceId": self.device_id,
            "publicKey": b64u_encode(&self.public_key),
            "keyType": self.key_type,
            "keyProtection": self.key_protection,
            "createdAt": self.created_at,
        })
    }
}

/// 设备密钥载体：Windows 为 DPAPI 保护的二进制文件，其他平台为 0600 JSON 文件。
fn default_key_protection() -> &'static str {
    if cfg!(windows) {
        "os-keychain"
    } else {
        "file"
    }
}

fn key_file_name() -> &'static str {
    if cfg!(windows) {
        "device_key.dpapi"
    } else {
        "device_key.json"
    }
}

fn store_dir() -> Result<PathBuf, String> {
    STORE_DIR
        .lock()
        .map_err(|_| "密钥目录状态锁被污染".to_string())?
        .clone()
        .ok_or_else(|| "设备密钥模块未初始化（请先调用 dev_auth_request(\"init\")）".to_string())
}

fn key_path() -> Result<PathBuf, String> {
    Ok(store_dir()?.join(key_file_name()))
}

fn load_key() -> Result<Option<DeviceKey>, String> {
    let path = key_path()?;
    let raw = match fs::read(&path) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("读取设备密钥失败（{}）: {e}", path.display())),
    };
    let plain = unprotect(&raw)?;
    let value: Value = serde_json::from_slice(&plain)
        .map_err(|e| format!("设备密钥文件已损坏（{}）: {e}", path.display()))?;
    Ok(Some(DeviceKey::from_json(&value)?))
}

fn save_key(key: &DeviceKey) -> Result<PathBuf, String> {
    let dir = store_dir()?;
    fs::create_dir_all(&dir).map_err(|e| format!("创建密钥目录失败（{}）: {e}", dir.display()))?;
    let path = dir.join(key_file_name());
    let payload = serde_json::to_vec(&key.to_json())
        .map_err(|e| format!("序列化设备密钥失败: {e}"))?;
    let sealed = protect(&payload)?;

    // 先写临时文件再原子替换，避免掉电/崩溃留下半截密钥文件。
    let tmp = dir.join(format!("{}.tmp", key_file_name()));
    {
        let mut options = fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options
            .open(&tmp)
            .map_err(|e| format!("写入设备密钥失败（{}）: {e}", tmp.display()))?;
        file.write_all(&sealed)
            .map_err(|e| format!("写入设备密钥失败（{}）: {e}", tmp.display()))?;
        file.flush()
            .map_err(|e| format!("刷新设备密钥失败（{}）: {e}", tmp.display()))?;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    }
    fs::rename(&tmp, &path)
        .map_err(|e| format!("替换设备密钥失败（{}）: {e}", path.display()))?;
    Ok(path)
}

fn delete_key() -> Result<bool, String> {
    let path = key_path()?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(format!("删除设备密钥失败（{}）: {e}", path.display())),
    }
}

fn normalize_key_type(raw: Option<String>) -> Result<String, String> {
    let key_type = raw.unwrap_or_else(|| KEY_TYPE_ED25519.to_string());
    let key_type = key_type.trim().to_ascii_lowercase();
    // 兼容 WebCrypto 习惯写法（P-256 / ECDSA）。
    let normalized = match key_type.as_str() {
        "ed25519" | "" => KEY_TYPE_ED25519,
        "p256" | "p-256" | "ecdsa-p256" | "ecdsa" => KEY_TYPE_P256,
        other => return Err(format!("不支持的 keyType: {other}")),
    };
    Ok(normalized.to_string())
}

fn generate_key(key_type: &str) -> Result<DeviceKey, String> {
    let rng = system_random()?;
    let (pkcs8, public_key) = match key_type {
        KEY_TYPE_ED25519 => {
            let document = signature::Ed25519KeyPair::generate_pkcs8(&rng)
                .map_err(|_| "生成 ed25519 密钥失败".to_string())?;
            let pair = signature::Ed25519KeyPair::from_pkcs8(document.as_ref())
                .map_err(|_| "解析新生成的 ed25519 密钥失败".to_string())?;
            (document.as_ref().to_vec(), pair.public_key().as_ref().to_vec())
        }
        KEY_TYPE_P256 => {
            let document = signature::EcdsaKeyPair::generate_pkcs8(
                &signature::ECDSA_P256_SHA256_FIXED_SIGNING,
                &rng,
            )
            .map_err(|_| "生成 P-256 密钥失败".to_string())?;
            let pair = signature::EcdsaKeyPair::from_pkcs8(
                &signature::ECDSA_P256_SHA256_FIXED_SIGNING,
                document.as_ref(),
                &rng,
            )
            .map_err(|_| "解析新生成的 P-256 密钥失败".to_string())?;
            (document.as_ref().to_vec(), pair.public_key().as_ref().to_vec())
        }
        other => return Err(format!("不支持的 keyType: {other}")),
    };
    if public_key.is_empty() {
        return Err("生成密钥后公钥为空".to_string());
    }
    Ok(DeviceKey {
        key_type: key_type.to_string(),
        key_protection: default_key_protection().to_string(),
        device_id: device_id_from_public_key(&public_key),
        pkcs8,
        public_key,
        created_at: unix_now(),
    })
}

/// §2：`deviceId = hex(SHA-256(公钥原始字节))[:32]`（32 位小写 hex）。
fn device_id_from_public_key(public_key: &[u8]) -> String {
    let sum = digest::digest(&digest::SHA256, public_key);
    let hex = hex_lower(sum.as_ref());
    hex[..32.min(hex.len())].to_string()
}

/// 用当前设备密钥签名（Ed25519 64 字节原始签名 / P-256 P1363 64 字节）。
fn sign_with_key(key: &DeviceKey, message: &[u8]) -> Result<Vec<u8>, String> {
    match key.key_type.as_str() {
        KEY_TYPE_ED25519 => {
            let pair = signature::Ed25519KeyPair::from_pkcs8(&key.pkcs8)
                .map_err(|e| format!("加载 ed25519 私钥失败: {e}"))?;
            Ok(pair.sign(message).as_ref().to_vec())
        }
        KEY_TYPE_P256 => {
            let rng = system_random()?;
            let pair = signature::EcdsaKeyPair::from_pkcs8(
                &signature::ECDSA_P256_SHA256_FIXED_SIGNING,
                &key.pkcs8,
                &rng,
            )
            .map_err(|e| format!("加载 P-256 私钥失败: {e}"))?;
            let sig = pair
                .sign(&rng, message)
                .map_err(|_| "P-256 签名失败".to_string())?;
            Ok(sig.as_ref().to_vec())
        }
        other => Err(format!("不支持的 keyType: {other}")),
    }
}

// ---------------------------------------------------------------------------
// 私钥落盘保护：Windows DPAPI / 其他平台 0600 文件
// ---------------------------------------------------------------------------

#[cfg(windows)]
fn protect(plain: &[u8]) -> Result<Vec<u8>, String> {
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{
        CryptProtectData, CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN,
    };

    let mut input = plain.to_vec();
    let mut in_blob = CRYPT_INTEGER_BLOB {
        cbData: input.len() as u32,
        pbData: input.as_mut_ptr(),
    };
    let mut out_blob = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };
    let ok = unsafe {
        CryptProtectData(
            &mut in_blob,
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut out_blob,
        )
    };
    if ok == 0 {
        return Err(format!(
            "DPAPI 加密设备密钥失败: {}",
            std::io::Error::last_os_error()
        ));
    }
    let sealed = unsafe {
        std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize).to_vec()
    };
    unsafe {
        LocalFree(out_blob.pbData as *mut std::ffi::c_void);
    }
    Ok(sealed)
}

#[cfg(windows)]
fn unprotect(sealed: &[u8]) -> Result<Vec<u8>, String> {
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{
        CryptUnprotectData, CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN,
    };

    let mut input = sealed.to_vec();
    let mut in_blob = CRYPT_INTEGER_BLOB {
        cbData: input.len() as u32,
        pbData: input.as_mut_ptr(),
    };
    let mut out_blob = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };
    let ok = unsafe {
        CryptUnprotectData(
            &mut in_blob,
            std::ptr::null_mut(),
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut out_blob,
        )
    };
    if ok == 0 {
        return Err(
            "无法解密设备密钥（DPAPI 失败：换了 Windows 账户/机器，或密钥文件被篡改）。\
             设备需要重新绑定"
                .to_string(),
        );
    }
    let plain = unsafe {
        std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize).to_vec()
    };
    unsafe {
        LocalFree(out_blob.pbData as *mut std::ffi::c_void);
    }
    Ok(plain)
}

#[cfg(not(windows))]
fn protect(plain: &[u8]) -> Result<Vec<u8>, String> {
    // 非 Windows 平台没有统一的系统密钥库，退化为 0600 文件（见 save_key）。
    Ok(plain.to_vec())
}

#[cfg(not(windows))]
fn unprotect(sealed: &[u8]) -> Result<Vec<u8>, String> {
    Ok(sealed.to_vec())
}

// ---------------------------------------------------------------------------
// 业务分发
// ---------------------------------------------------------------------------

fn op_init(args: &Value) -> Result<Value, String> {
    let dir = arg_str(args, "dir").ok_or("init 需要 dir 参数（密钥目录绝对路径）")?;
    let path = PathBuf::from(&dir);
    fs::create_dir_all(&path)
        .map_err(|e| format!("创建密钥目录失败（{}）: {e}", path.display()))?;
    // 目录可写性探测：没有写权限时尽早报错，而不是等到绑定设备时才失败。
    let probe = path.join(".write_probe");
    fs::write(&probe, b"ok")
        .map_err(|e| format!("密钥目录不可写（{}）: {e}", path.display()))?;
    let _ = fs::remove_file(&probe);
    *STORE_DIR
        .lock()
        .map_err(|_| "密钥目录状态锁被污染".to_string())? = Some(path.clone());
    Ok(json!({
        "dir": path.to_string_lossy(),
        "keyProtection": default_key_protection(),
        "keyFilePath": path.join(key_file_name()).to_string_lossy(),
    }))
}

fn op_key_status(_args: &Value) -> Result<Value, String> {
    match load_key()? {
        Some(key) => Ok(key.status_json()),
        None => Ok(json!({
            "exists": false,
            "keyProtection": default_key_protection(),
            "keyFilePath": key_path()?.to_string_lossy(),
        })),
    }
}

fn op_ensure_key(args: &Value) -> Result<Value, String> {
    let requested = normalize_key_type(arg_str(args, "keyType"))?;
    if let Some(existing) = load_key()? {
        let mut status = existing.status_json();
        status["created"] = json!(false);
        status["requestedKeyType"] = json!(requested);
        // 已存在不同类型的密钥时不静默替换：deviceId 会变，已绑定的设备会失效，
        // 必须由调用方显式 delete_key 后重建。
        if existing.key_type != requested {
            status["keyTypeMismatch"] = json!(true);
        }
        return Ok(status);
    }
    let key = generate_key(&requested)?;
    save_key(&key)?;
    let mut status = key.status_json();
    status["created"] = json!(true);
    Ok(status)
}

fn op_delete_key(_args: &Value) -> Result<Value, String> {
    Ok(json!({ "deleted": delete_key()? }))
}

fn op_sign(args: &Value) -> Result<Value, String> {
    let message = arg_bytes(args, "message", "message_b64")?;
    let key = load_key()?.ok_or("本机还没有设备密钥，请先调用 ensure_key")?;
    let signature = sign_with_key(&key, &message)?;
    Ok(json!({
        "signature": b64u_encode(&signature),
        "deviceId": key.device_id,
        "keyType": key.key_type,
        "messageLength": message.len(),
    }))
}

fn op_sha256(args: &Value) -> Result<Value, String> {
    let data = arg_bytes(args, "data", "data_b64")?;
    let sum = digest::digest(&digest::SHA256, &data);
    Ok(json!({
        "hex": hex_lower(sum.as_ref()),
        "b64url": b64u_encode(sum.as_ref()),
        "length": data.len(),
    }))
}

fn op_hmac_sha256(args: &Value) -> Result<Value, String> {
    let key_b64 = arg_str(args, "key_b64url")
        .or_else(|| arg_str(args, "key"))
        .ok_or("hmac_sha256 需要 key_b64url 参数")?;
    let key_bytes = b64u_decode(&key_b64)?;
    if key_bytes.is_empty() {
        return Err("hmac_sha256 的密钥为空".to_string());
    }
    let message = arg_bytes(args, "message", "message_b64")?;
    let key = hmac::Key::new(hmac::HMAC_SHA256, &key_bytes);
    let tag = hmac::sign(&key, &message);
    Ok(json!({
        "mac": b64u_encode(tag.as_ref()),
        "length": message.len(),
    }))
}

fn op_random_b64url(args: &Value) -> Result<Value, String> {
    let len = args.get("len").and_then(|v| v.as_u64()).unwrap_or(32);
    let len = len.clamp(1, 1024) as usize;
    let rng = system_random()?;
    let mut buf = vec![0u8; len];
    rand::SecureRandom::fill(&rng, &mut buf).map_err(|_| "系统随机数生成失败".to_string())?;
    Ok(json!({ "bytes": b64u_encode(&buf), "length": len }))
}

fn op_device_id(args: &Value) -> Result<Value, String> {
    let public_key = arg_bytes(args, "publicKey", "publicKey_b64")?;
    match public_key.len() {
        32 | 33 | 65 => {}
        other => {
            return Err(format!(
                "公钥长度非法（{other} 字节，ed25519 应为 32、P-256 应为 33/65）"
            ))
        }
    }
    Ok(json!({
        "deviceId": device_id_from_public_key(&public_key),
        "publicKeyLength": public_key.len(),
    }))
}

/// 自检：在内存中生成临时密钥并验证签名 / HMAC / deviceId，不落盘。
///
/// 供内部测试与 Dart 侧集成测试确认动态库确实可用（含 DPAPI 往返）。
fn op_self_test(_args: &Value) -> Result<Value, String> {
    let rng = system_random()?;
    let mut checks = Vec::new();

    // 1. ed25519 签名可被自身公钥验证。
    let document = signature::Ed25519KeyPair::generate_pkcs8(&rng)
        .map_err(|_| "ed25519 自检：生成密钥失败".to_string())?;
    let pair = signature::Ed25519KeyPair::from_pkcs8(document.as_ref())
        .map_err(|_| "ed25519 自检：加载密钥失败".to_string())?;
    let message = b"irix-device-self-test";
    let sig = pair.sign(message);
    let verified = signature::UnparsedPublicKey::new(
        &signature::ED25519,
        pair.public_key().as_ref(),
    )
    .verify(message, sig.as_ref())
    .is_ok();
    checks.push(json!({ "check": "ed25519_sign_verify", "ok": verified }));

    // 2. P-256 P1363 签名长度为 64 且可验证。
    let document = signature::EcdsaKeyPair::generate_pkcs8(
        &signature::ECDSA_P256_SHA256_FIXED_SIGNING,
        &rng,
    )
    .map_err(|_| "P-256 自检：生成密钥失败".to_string())?;
    let pair = signature::EcdsaKeyPair::from_pkcs8(
        &signature::ECDSA_P256_SHA256_FIXED_SIGNING,
        document.as_ref(),
        &rng,
    )
    .map_err(|_| "P-256 自检：加载密钥失败".to_string())?;
    let sig = pair
        .sign(&rng, message)
        .map_err(|_| "P-256 自检：签名失败".to_string())?;
    let p256_ok = sig.as_ref().len() == 64
        && signature::UnparsedPublicKey::new(
            &signature::ECDSA_P256_SHA256_FIXED,
            pair.public_key().as_ref(),
        )
        .verify(message, sig.as_ref())
        .is_ok();
    checks.push(json!({ "check": "p256_sign_verify_p1363", "ok": p256_ok }));

    // 3. HMAC-SHA256 已知向量："key" / "The quick brown fox jumps over the lazy dog"
    let key = hmac::Key::new(hmac::HMAC_SHA256, b"key");
    let tag = hmac::sign(&key, b"The quick brown fox jumps over the lazy dog");
    let hmac_hex = hex_lower(tag.as_ref());
    checks.push(json!({
        "check": "hmac_sha256_known_vector",
        "ok": hmac_hex == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
    }));

    // 4. deviceId 为 32 位小写 hex，且由公钥稳定推导。
    let public_key = pair.public_key().as_ref();
    let device_id = device_id_from_public_key(public_key);
    checks.push(json!({
        "check": "device_id_format",
        "ok": device_id.len() == 32
            && device_id.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
            && device_id == device_id_from_public_key(public_key),
    }));

    // 5. 落盘保护往返（DPAPI / 文件）。
    let probe = b"{\"probe\":true}";
    let roundtrip = match protect(probe) {
        Ok(sealed) => unprotect(&sealed).map(|p| p == probe).unwrap_or(false),
        Err(_) => false,
    };
    checks.push(json!({ "check": "key_protection_roundtrip", "ok": roundtrip }));

    let all_ok = checks
        .iter()
        .all(|c| c.get("ok").and_then(|v| v.as_bool()).unwrap_or(false));
    Ok(json!({
        "ok": all_ok,
        "keyProtection": default_key_protection(),
        "checks": checks,
    }))
}

fn dispatch(op: &str, args: &Value) -> Result<Value, String> {
    match op {
        "init" => op_init(args),
        "key_status" => op_key_status(args),
        "ensure_key" => op_ensure_key(args),
        "delete_key" => op_delete_key(args),
        "sign" => op_sign(args),
        "sha256" => op_sha256(args),
        "hmac_sha256" => op_hmac_sha256(args),
        "random_b64url" => op_random_b64url(args),
        "device_id" => op_device_id(args),
        "self_test" => op_self_test(args),
        other => Err(format!("未知操作: {other}")),
    }
}

// ---------------------------------------------------------------------------
// C ABI 导出
// ---------------------------------------------------------------------------

/// 统一入口：`dev_auth_request(op, args_json) -> JSON 字符串`。
///
/// 返回的字符串由 Rust 分配，Dart 侧必须用本库的 `free_string` 释放。
#[no_mangle]
pub extern "C" fn dev_auth_request(
    op: *const libc::c_char,
    args_json: *const libc::c_char,
) -> *mut libc::c_char {
    catch_unwind(AssertUnwindSafe(|| {
        if op.is_null() {
            return cstring_out(error_json("op 为空指针"));
        }
        let op = match unsafe { CStr::from_ptr(op) }.to_str() {
            Ok(s) => s,
            Err(_) => return cstring_out(error_json("op 不是有效的 UTF-8")),
        };
        let args = match parse_args(args_json) {
            Ok(v) => v,
            Err(e) => return cstring_out(error_json(e)),
        };
        match dispatch(op, &args) {
            Ok(data) => cstring_out(ok_json(data)),
            Err(e) => cstring_out(error_json(e)),
        }
    }))
    .unwrap_or_else(|_| cstring_out(error_json("Rust panic in dev_auth_request")))
}

/// 释放本库返回的字符串指针。
#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 最近一次错误文本（调试用）。
#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("未知错误").ok())
            .unwrap_or_else(|| CString::new("未知错误").unwrap())
            .into_raw()
    })
}

// ---------------------------------------------------------------------------
// 单元测试（`cargo test -p xmc_device_auth`）
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// 测试专用临时目录（不依赖 tempfile crate，避免新增依赖）。
    ///
    /// 注意：多个测试并行执行，目录名必须唯一 —— 曾经用「进程 id + 秒级时间戳」，
    /// 同一秒内并行的测试会共享同一目录，互相删除/替换密钥文件后出现假失败。
    fn temp_dir(label: &str) -> PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!(
            "xmc_device_auth_test_{label}_{}_{}_{}",
            std::process::id(),
            nanos,
            COUNTER.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn init(dir: &Path) {
        op_init(&json!({ "dir": dir.to_string_lossy() })).unwrap();
    }

    /// `STORE_DIR` 是进程级全局变量，而 cargo test 默认并行跑用例：
    /// 所有会读写密钥文件的用例必须先拿到这把锁，否则会互相覆盖目录。
    fn store_lock() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: Mutex<()> = Mutex::new(());
        LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    #[test]
    fn device_id_matches_protocol_formula() {
        // ed25519 公钥固定样本：deviceId 必须是 SHA-256 前 32 个 hex 字符。
        let public_key = [7u8; 32];
        let expected_hex = hex_lower(digest::digest(&digest::SHA256, &public_key).as_ref());
        assert_eq!(
            device_id_from_public_key(&public_key),
            expected_hex[..32].to_string()
        );
        assert_eq!(device_id_from_public_key(&public_key).len(), 32);
    }

    #[test]
    fn ed25519_key_roundtrip_and_signature() {
        let _guard = store_lock();
        let dir = temp_dir("ed25519");
        init(&dir);
        let created = op_ensure_key(&json!({ "keyType": "ed25519" })).unwrap();
        assert_eq!(created["created"], json!(true));
        let device_id = created["deviceId"].as_str().unwrap().to_string();
        assert_eq!(device_id.len(), 32);
        assert_eq!(created["keyType"], json!("ed25519"));

        // 再次 ensure 不重建密钥（deviceId 稳定）。
        let again = op_ensure_key(&json!({})).unwrap();
        assert_eq!(again["created"], json!(false));
        assert_eq!(again["deviceId"].as_str().unwrap(), device_id);

        let message = "irix-device-login-v1\nalice\n";
        let signature = op_sign(&json!({ "message": message })).unwrap();
        let sig_bytes = b64u_decode(signature["signature"].as_str().unwrap()).unwrap();
        assert_eq!(sig_bytes.len(), 64, "Ed25519 原始签名为 64 字节");

        let status = op_key_status(&json!({})).unwrap();
        let public_key = b64u_decode(status["publicKey"].as_str().unwrap()).unwrap();
        assert_eq!(public_key.len(), 32);
        assert!(signature::UnparsedPublicKey::new(&signature::ED25519, &public_key)
            .verify(message.as_bytes(), &sig_bytes)
            .is_ok());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn p256_signature_is_p1363() {
        let _guard = store_lock();
        let dir = temp_dir("p256");
        init(&dir);
        let created = op_ensure_key(&json!({ "keyType": "p256" })).unwrap();
        assert_eq!(created["created"], json!(true));
        let status = op_key_status(&json!({})).unwrap();
        let public_key = b64u_decode(status["publicKey"].as_str().unwrap()).unwrap();
        assert!(
            public_key.len() == 65 || public_key.len() == 33,
            "P-256 公钥应为未压缩 65 字节点"
        );
        if public_key.len() == 65 {
            assert_eq!(public_key[0], 0x04);
        }

        let signature = op_sign(&json!({ "message": "canonical" })).unwrap();
        let sig_bytes = b64u_decode(signature["signature"].as_str().unwrap()).unwrap();
        assert_eq!(sig_bytes.len(), 64, "P-256 应为 r||s 的 64 字节（P1363）");
        assert!(signature::UnparsedPublicKey::new(
            &signature::ECDSA_P256_SHA256_FIXED,
            &public_key
        )
        .verify(b"canonical", &sig_bytes)
        .is_ok());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_key_reports_actionable_error() {
        let _guard = store_lock();
        let dir = temp_dir("missing");
        init(&dir);
        let err = op_sign(&json!({ "message": "x" })).unwrap_err();
        assert!(err.contains("设备密钥"), "{err}");
        let status = op_key_status(&json!({})).unwrap();
        assert_eq!(status["exists"], json!(false));
    }

    #[test]
    fn corrupt_key_file_is_rejected() {
        let _guard = store_lock();
        let dir = temp_dir("corrupt");
        init(&dir);
        op_ensure_key(&json!({ "keyType": "ed25519" })).unwrap();
        // 改写密钥文件里的 publicKey → deviceId 不再匹配，必须拒绝加载。
        let path = dir.join(key_file_name());
        let raw = unprotect(&fs::read(&path).unwrap()).unwrap();
        let mut value: Value = serde_json::from_slice(&raw).unwrap();
        value["publicKey"] = json!(b64u_encode(&[9u8; 32]));
        fs::write(&path, protect(&serde_json::to_vec(&value).unwrap()).unwrap()).unwrap();
        let err = op_key_status(&json!({})).unwrap_err();
        assert!(err.contains("不匹配"), "{err}");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn hmac_matches_rfc4231_vector() {
        let mac = op_hmac_sha256(&json!({
            "key_b64url": b64u_encode(b"key"),
            "message": "The quick brown fox jumps over the lazy dog",
        }))
        .unwrap();
        assert_eq!(
            mac["mac"].as_str().unwrap(),
            "97yD9DBThCSxMpjmqm-xQ-9NWaFJRhdZl0edvC0aPNg"
        );
    }

    #[test]
    fn sha256_and_random_are_stable() {
        let sum = op_sha256(&json!({ "data": "abc" })).unwrap();
        assert_eq!(
            sum["hex"].as_str().unwrap(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        let random = op_random_b64url(&json!({ "len": 32 })).unwrap();
        assert_eq!(
            b64u_decode(random["bytes"].as_str().unwrap()).unwrap().len(),
            32
        );
        // base64url 无填充
        assert!(!random["bytes"].as_str().unwrap().contains('='));
    }

    #[test]
    fn delete_key_removes_file() {
        let _guard = store_lock();
        let dir = temp_dir("delete");
        init(&dir);
        assert_eq!(
            op_delete_key(&json!({})).unwrap()["deleted"],
            json!(false),
            "尚未生成密钥时删除应为 false"
        );
        op_ensure_key(&json!({})).unwrap();
        assert!(dir.join(key_file_name()).exists());
        assert_eq!(op_delete_key(&json!({})).unwrap()["deleted"], json!(true));
        assert!(!dir.join(key_file_name()).exists());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn self_test_passes() {
        let report = op_self_test(&json!({})).unwrap();
        assert_eq!(report["ok"], json!(true), "{report}");
    }

    #[test]
    fn unknown_op_and_bad_args() {
        let _guard = store_lock();
        assert!(dispatch("nope", &json!({})).unwrap_err().contains("未知操作"));
        op_init(&json!({ "dir": std::env::temp_dir().to_string_lossy() })).unwrap();
        assert!(dispatch("device_id", &json!({ "publicKey": "AAA" }))
            .unwrap_err()
            .contains("公钥长度非法"));
    }
}
