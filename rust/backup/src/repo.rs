//! 备份仓库（Repository）布局与读写。
//!
//! 每个实例一个仓库目录（由 Dart 侧 `AppPaths` 决定，通常是
//! `<数据根>/backups/<实例 id>/`）：
//!
//! ```text
//! <repo>/
//! ├── full/                全量备份：<name>.zip + <name>.json（摘要）
//! ├── snapshots/           增量快照：<name>/（硬链接文件树，Linux/macOS）
//! ├── cas/<xx>/<sha256>    增量快照内容寻址对象（Windows）
//! ├── meta/<name>.json     增量快照摘要
//! ├── meta/<name>.manifest.json  增量快照文件清单
//! └── temp/                rsync 日志、CAS 临时文件
//! ```

use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use crate::model::{
    FullMeta, Manifest, SnapshotMeta, STRATEGY_CAS, STRATEGY_HARDLINK, STRATEGY_RSYNC,
};
use crate::util;

pub(crate) const DIR_FULL: &str = "full";
pub(crate) const DIR_SNAPSHOTS: &str = "snapshots";
pub(crate) const DIR_CAS: &str = "cas";
pub(crate) const DIR_META: &str = "meta";
pub(crate) const DIR_TEMP: &str = "temp";

/// 备份仓库句柄。
pub(crate) struct Repo {
    root: PathBuf,
}

impl Repo {
    /// 打开（不存在则创建）仓库目录。
    pub(crate) fn open(root: &Path) -> io::Result<Self> {
        for sub in [DIR_FULL, DIR_SNAPSHOTS, DIR_CAS, DIR_META, DIR_TEMP] {
            fs::create_dir_all(root.join(sub))?;
        }
        Ok(Self {
            root: root.to_path_buf(),
        })
    }

    pub(crate) fn root(&self) -> &Path {
        &self.root
    }

    pub(crate) fn temp_dir(&self) -> PathBuf {
        self.root.join(DIR_TEMP)
    }

    pub(crate) fn snapshot_dir(&self, name: &str) -> PathBuf {
        self.root.join(DIR_SNAPSHOTS).join(name)
    }

    pub(crate) fn meta_path(&self, name: &str) -> PathBuf {
        self.root.join(DIR_META).join(format!("{name}.json"))
    }

    pub(crate) fn manifest_path(&self, name: &str) -> PathBuf {
        self.root
            .join(DIR_META)
            .join(format!("{name}.manifest.json"))
    }

    pub(crate) fn full_zip_path(&self, name: &str) -> PathBuf {
        self.root.join(DIR_FULL).join(format!("{name}.zip"))
    }

    pub(crate) fn full_meta_path(&self, name: &str) -> PathBuf {
        self.root.join(DIR_FULL).join(format!("{name}.json"))
    }

    /// 内容寻址对象路径：`cas/<hash 前两位>/<hash>`。
    pub(crate) fn cas_path(&self, hash: &str) -> PathBuf {
        let prefix = hash.get(0..2).unwrap_or("xx");
        self.root.join(DIR_CAS).join(prefix).join(hash)
    }

    /// 快照名是否已被占用（目录或摘要任一存在即视为占用）。
    pub(crate) fn snapshot_exists(&self, name: &str) -> bool {
        self.snapshot_dir(name).exists() || self.meta_path(name).exists()
    }

    pub(crate) fn full_exists(&self, name: &str) -> bool {
        self.full_zip_path(name).exists() || self.full_meta_path(name).exists()
    }

    /// 生成不冲突的快照名（同一秒内多次备份时追加 `-2`、`-3`……）。
    pub(crate) fn unique_snapshot_name(&self, preferred: &str) -> String {
        util::unique_dir_name(|n| self.snapshot_exists(n), preferred)
    }

    /// 生成不冲突的全量备份名。
    pub(crate) fn unique_full_name(&self, preferred: &str) -> String {
        util::unique_dir_name(|n| self.full_exists(n), preferred)
    }

    // ======================== 元数据 ========================

    pub(crate) fn write_snapshot_meta(&self, meta: &SnapshotMeta) -> io::Result<()> {
        util::write_json_atomic(&self.meta_path(&meta.name), meta)
    }

    pub(crate) fn read_snapshot_meta(&self, name: &str) -> io::Result<Option<SnapshotMeta>> {
        util::read_json(&self.meta_path(name))
    }

    pub(crate) fn write_manifest(&self, name: &str, manifest: &Manifest) -> io::Result<()> {
        util::write_json_atomic(&self.manifest_path(name), manifest)
    }

    pub(crate) fn read_manifest(&self, name: &str) -> io::Result<Option<Manifest>> {
        util::read_json(&self.manifest_path(name))
    }

    pub(crate) fn write_full_meta(&self, meta: &FullMeta) -> io::Result<()> {
        util::write_json_atomic(&self.full_meta_path(&meta.name), meta)
    }

    pub(crate) fn read_full_meta(&self, name: &str) -> io::Result<Option<FullMeta>> {
        util::read_json(&self.full_meta_path(name))
    }

    /// 列出全部增量快照摘要（按创建时间倒序，最新在前）。
    pub(crate) fn list_snapshots(&self) -> io::Result<Vec<SnapshotMeta>> {
        let mut list = Vec::new();
        let dir = self.root.join(DIR_META);
        let Ok(entries) = fs::read_dir(&dir) else {
            return Ok(list);
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(file_name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            // 跳过清单文件 `<name>.manifest.json`
            if !file_name.ends_with(".json") || file_name.ends_with(".manifest.json") {
                continue;
            }
            let name = file_name.trim_end_matches(".json").to_string();
            match util::read_json::<SnapshotMeta>(&path) {
                Ok(Some(mut meta)) => {
                    // 以文件名为准，避免手工改动导致名字不一致。
                    meta.name = name;
                    list.push(meta);
                }
                Ok(None) => {}
                Err(_) => continue,
            }
        }
        list.sort_by(|a, b| {
            b.created_at
                .cmp(&a.created_at)
                .then_with(|| b.name.cmp(&a.name))
        });
        Ok(list)
    }

    /// 列出全部全量备份摘要（按创建时间倒序）。
    ///
    /// 以 `full/*.zip` 为准：有摘要文件就合并摘要信息，没有摘要（例如被中断、
    /// 或用户手工放进来的 ZIP）就用文件元数据兜底，保证备份不会“看不见”。
    pub(crate) fn list_full(&self) -> io::Result<Vec<FullMeta>> {
        let mut list = Vec::new();
        let dir = self.root.join(DIR_FULL);
        let Ok(entries) = fs::read_dir(&dir) else {
            return Ok(list);
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("zip") {
                continue;
            }
            let Some(name) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            // 摘要缺失/损坏都退化为文件元数据，保证备份不会“看不见”
            let meta = match self.read_full_meta(name) {
                Ok(Some(meta)) => meta,
                _ => {
                    let file_meta = fs::metadata(&path).ok();
                    let stored = file_meta.as_ref().map(|m| m.len()).unwrap_or(0);
                    let created_at = file_meta
                        .and_then(|m| m.modified().ok())
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs() as i64)
                        .unwrap_or_else(util::now_secs);
                    FullMeta {
                        name: name.to_string(),
                        created_at,
                        source_root: String::new(),
                        compression_level: 0,
                        files: 0,
                        bytes_total: 0,
                        stored_bytes: stored,
                        duration_ms: 0,
                    }
                }
            };
            list.push(meta);
        }
        list.sort_by(|a, b| {
            b.created_at
                .cmp(&a.created_at)
                .then_with(|| b.name.cmp(&a.name))
        });
        Ok(list)
    }

    /// 最新快照名（增量基线），[`exclude`] 用于排除正在创建的那一个。
    pub(crate) fn latest_snapshot(&self, exclude: Option<&str>) -> Option<String> {
        self.list_snapshots()
            .ok()?
            .into_iter()
            .find(|m| Some(m.name.as_str()) != exclude)
            .map(|m| m.name)
    }

    // ======================== 内容寻址存储 ========================

    /// 把文件内容写入 CAS（已存在则跳过），返回是否新建对象。
    pub(crate) fn store_object(&self, hash: &str, source: &Path) -> io::Result<bool> {
        let dst = self.cas_path(hash);
        if dst.exists() {
            return Ok(false);
        }
        if let Some(parent) = dst.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = self.temp_dir().join(format!(
            "cas-{}-{}",
            std::process::id(),
            crate::next_temp_id()
        ));
        {
            let mut input = File::open(source)?;
            let mut output = File::create(&tmp)?;
            let mut buf = vec![0u8; 1024 * 1024];
            loop {
                let read = input.read(&mut buf)?;
                if read == 0 {
                    break;
                }
                output.write_all(&buf[..read])?;
            }
            output.flush()?;
        }
        match util::replace_file(&tmp, &dst) {
            Ok(()) => Ok(true),
            Err(e) => {
                let _ = fs::remove_file(&tmp);
                if dst.exists() {
                    Ok(false)
                } else {
                    Err(e)
                }
            }
        }
    }

    /// 清理没有被任何快照清单引用的 CAS 对象（删除快照后回收空间）。
    ///
    /// 返回 `(删除对象数, 释放字节数)`。
    ///
    /// 只要有一个 CAS 快照的清单读不出来就整体放弃回收（返回错误）：
    /// 读不到清单就不知道它引用了哪些对象，此时删除会有丢数据风险。
    pub(crate) fn gc_objects(&self) -> io::Result<(u64, u64)> {
        let mut referenced: HashSet<String> = HashSet::new();
        for meta in self.list_snapshots()? {
            if meta.strategy != STRATEGY_CAS {
                continue;
            }
            match self.read_manifest(&meta.name)? {
                Some(manifest) => {
                    for entry in manifest.entries {
                        if let Some(hash) = entry.hash {
                            referenced.insert(hash);
                        }
                    }
                }
                None => {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!("快照清单缺失，已跳过空间回收: {}", meta.name),
                    ));
                }
            }
        }
        let mut removed = 0u64;
        let mut freed = 0u64;
        let cas_root = self.root.join(DIR_CAS);
        let Ok(dirs) = fs::read_dir(&cas_root) else {
            return Ok((0, 0));
        };
        for dir in dirs.flatten() {
            let path = dir.path();
            if !path.is_dir() {
                continue;
            }
            let Ok(objects) = fs::read_dir(&path) else {
                continue;
            };
            for object in objects.flatten() {
                let obj_path = object.path();
                let Some(name) = obj_path.file_name().and_then(|n| n.to_str()) else {
                    continue;
                };
                if referenced.contains(name) {
                    continue;
                }
                let size = object.metadata().map(|m| m.len()).unwrap_or(0);
                if fs::remove_file(&obj_path).is_ok() {
                    removed += 1;
                    freed += size;
                }
            }
        }
        Ok((removed, freed))
    }

    // ======================== 删除 ========================

    /// 删除一个增量快照（含清单/摘要；CAS 策略下顺带回收孤立对象）。
    pub(crate) fn delete_snapshot(&self, name: &str) -> io::Result<(u64, u64)> {
        util::remove_dir_all_if_exists(&self.snapshot_dir(name))?;
        let _ = fs::remove_file(self.manifest_path(name));
        let _ = fs::remove_file(self.meta_path(name));
        // 硬链接快照删除后数据由其它快照继续引用，无需额外处理。
        self.gc_objects()
    }

    /// 删除一个全量备份（ZIP + 摘要）。
    pub(crate) fn delete_full(&self, name: &str) -> io::Result<()> {
        let _ = fs::remove_file(self.full_zip_path(name));
        let _ = fs::remove_file(self.full_meta_path(name));
        Ok(())
    }

    /// 策略说明（返回给 UI 展示当前平台使用的增量方案）。
    pub(crate) fn strategy_note(&self) -> &'static str {
        if cfg!(target_os = "windows") {
            STRATEGY_CAS
        } else if crate::rsync::available() {
            STRATEGY_RSYNC
        } else {
            STRATEGY_HARDLINK
        }
    }
}
