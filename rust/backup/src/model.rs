//! 备份仓库的数据模型。
//!
//! 所有结构体统一 camelCase 序列化（Dart 侧 `Map<String, dynamic>` 直接读取），
//! 落盘位置见 `repo.rs`：
//! - `<repo>/meta/<name>.json`           —— 增量快照摘要（[`SnapshotMeta`]）
//! - `<repo>/meta/<name>.manifest.json`  —— 增量快照文件清单（[`Manifest`]）
//! - `<repo>/full/<name>.json`           —— 全量备份摘要（[`FullMeta`]）
//! - `<repo>/full/<name>.zip`            —— 全量备份 ZIP 归档
//! - `<repo>/snapshots/<name>/`          —— 硬链接快照文件树（Linux/macOS）
//! - `<repo>/cas/<xx>/<sha256>`          —— 内容寻址对象（Windows）

use serde::{Deserialize, Serialize};

/// 增量备份策略：Rsync 硬链接快照（Linux/macOS 首选）。
pub(crate) const STRATEGY_RSYNC: &str = "rsync-hardlink";
/// 增量备份策略：Rust 原生硬链接快照（rsync 不可用时的回退）。
pub(crate) const STRATEGY_HARDLINK: &str = "hardlink";
/// 增量备份策略：哈希比对 + 内容寻址存储（Windows）。
pub(crate) const STRATEGY_CAS: &str = "cas";

/// 备份类型标识（返回给 Dart 侧用于列表展示）。
pub(crate) const KIND_FULL: &str = "full";
pub(crate) const KIND_SNAPSHOT: &str = "snapshot";

/// 清单中的单个文件条目。
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ManifestEntry {
    /// 相对实例根目录的路径（统一使用 `/` 分隔）。
    pub path: String,
    /// 源文件字节数。
    pub size: u64,
    /// 源文件最后修改时间（Unix 秒）。
    pub mtime: i64,
    /// 内容 SHA-256（CAS 策略必然存在；硬链接策略不计算，避免全量读取）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hash: Option<String>,
    /// 硬链接策略：该文件是上一个快照的硬链接（内容未变化）。
    #[serde(default)]
    pub linked: bool,
}

/// 单个增量快照的完整文件清单。
///
/// 用结构体而非裸数组，便于后续增加字段（例如权限、符号链接）。
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Manifest {
    /// 快照内的目录相对路径（含空目录），恢复时先建目录。
    #[serde(default)]
    pub dirs: Vec<String>,
    /// 文件条目。
    #[serde(default)]
    pub entries: Vec<ManifestEntry>,
}

impl Manifest {
    /// 以相对路径建立索引，便于与上一个快照做差集比较。
    pub(crate) fn index_by_path(&self) -> std::collections::HashMap<&str, &ManifestEntry> {
        self.entries
            .iter()
            .map(|e| (e.path.as_str(), e))
            .collect()
    }
}

/// 增量快照摘要（列表页数据源，不含文件清单）。
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SnapshotMeta {
    /// 快照名（`<本地时间 YYYYMMDD-HHMMSS>`，由 Dart 侧生成，Rust 侧去重）。
    pub name: String,
    /// 创建时间（Unix 秒，列表按此倒序）。
    pub created_at: i64,
    /// 父快照名（增量基线）；首个快照为 null。
    #[serde(default)]
    pub parent: Option<String>,
    /// 实际使用的策略，见 `STRATEGY_*`。
    pub strategy: String,
    /// 用户备注（当前固定为 "manual"）。
    #[serde(default)]
    pub label: Option<String>,
    /// 策略回退说明（例如 rsync 不可用/失败时回退到原生硬链接）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// 备份源目录（绝对路径）。
    pub source_root: String,
    /// 文件统计。
    pub files_total: u64,
    pub files_new: u64,
    pub files_modified: u64,
    pub files_deleted: u64,
    pub files_unchanged: u64,
    /// 本次快照包含的总字节数（源文件之和）。
    pub bytes_total: u64,
    /// 相对父快照新增的字节数（需要实写或硬链接新文件的部分）。
    pub bytes_added: u64,
    /// 相对父快照复用（硬链接/已存在对象）的字节数。
    pub bytes_reused: u64,
    /// 本次操作耗时（毫秒）。
    pub duration_ms: u64,
    /// 快照自身占用的物理字节数。
    pub stored_bytes: u64,
    /// 空目录/普通目录数量。
    #[serde(default)]
    pub dirs: u64,
    /// 跳过的符号链接数量（不参与备份）。
    #[serde(default)]
    pub symlinks_skipped: u64,
}

/// 全量备份摘要。
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FullMeta {
    pub name: String,
    pub created_at: i64,
    pub source_root: String,
    /// 压缩级别（0-9）。
    pub compression_level: u32,
    pub files: u64,
    /// 源文件总字节数。
    pub bytes_total: u64,
    /// ZIP 归档字节数。
    pub stored_bytes: u64,
    pub duration_ms: u64,
}

/// 创建一个快照后的统计结果（写入 [`SnapshotMeta`] 并返回给 Dart）。
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SnapshotStats {
    pub files_total: u64,
    pub files_new: u64,
    pub files_modified: u64,
    pub files_deleted: u64,
    pub files_unchanged: u64,
    pub bytes_total: u64,
    pub bytes_added: u64,
    pub bytes_reused: u64,
    pub dirs: u64,
    pub symlinks_skipped: u64,
}

/// 校验结果。
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub(crate) struct VerifyReport {
    pub name: String,
    pub strategy: String,
    pub checked: u64,
    /// 实际做过内容哈希比对的条目数（硬链接策略可能为 0）。
    pub hashed: u64,
    pub missing: u64,
    pub size_mismatch: u64,
    pub hash_mismatch: u64,
    /// 前若干个问题条目，避免 JSON 过大。
    pub problems: Vec<String>,
}

impl VerifyReport {
    /// 全部条目通过校验（无缺失、无大小/哈希不一致）。
    #[cfg(test)]
    pub(crate) fn is_ok(&self) -> bool {
        self.missing == 0 && self.size_mismatch == 0 && self.hash_mismatch == 0
    }
}

/// 恢复结果（全量/增量共用）。
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RestoreOutcome {
    pub name: String,
    /// `full` / `snapshot`
    pub kind: String,
    pub strategy: String,
    pub files: u64,
    pub bytes: u64,
    /// 清理掉的额外文件数（prune 模式）。
    pub pruned: u64,
    pub duration_ms: u64,
}

/// 删除结果（含 CAS 空间回收）。
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DeleteOutcome {
    pub name: String,
    pub kind: String,
    pub objects_removed: u64,
    pub bytes_freed: u64,
}
