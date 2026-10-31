//! 内容哈希（SHA-256）。

use std::fs::File;
use std::io::{self, Read};
use std::path::Path;

use sha2::{Digest, Sha256};

use crate::progress;
use crate::util;

const CHUNK: usize = 1024 * 1024;

/// 计算文件内容 SHA-256（小写十六进制）。
///
/// 每读一块检查一次取消标志：大文件（上 GB）也能及时响应。
pub(crate) fn sha256_file(path: &Path) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; CHUNK];
    loop {
        progress::check_cancel()?;
        let read = file.read(&mut buf)?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    Ok(util::hex_lower(&hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_matches_known_vector() {
        let tmp = std::env::temp_dir().join(format!("xmc_hash_{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let file = tmp.join("a.txt");
        std::fs::write(&file, b"abc").unwrap();
        // echo -n abc | sha256sum
        assert_eq!(
            sha256_file(&file).unwrap(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
