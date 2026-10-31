# 实例备份：全量备份与增量备份

本文档描述 IriX 实例备份的完整设计：**全量备份（原备份功能）** 与 **增量备份（新增）**，
两者全部由 Rust（`rust/backup`，产物 `xmc_backup`）实现，Dart 侧只负责调用与展示。

## 1. 产品形态

实例详情页「备份」Tab（`lib/screens/instance_backup_tab.dart`）：

- 主操作区**只有两个按钮**：
  - **全量备份**：整个实例目录打包为一个 ZIP 归档；
  - **增量备份**：只保存相对上一次快照的变化内容。
- 下方是**备份历史**（全量 + 增量按时间倒序）。列表行不是操作按钮，
  点按后在弹窗中查看详情并执行「恢复 / 校验 / 删除」。
- 备份进行时展示进度卡片（百分比 / 不确定进度 + 已用时间 + 取消）。
- 备份仓库路径与当前平台的增量方式在顶部只读展示。

## 2. 备份仓库

每个实例一个仓库，路径由 `AppPaths.instanceBackupsRoot(instanceId)` 决定：
`<数据根>/backups/<实例 id>/`。

```text
<repo>/
├── full/
│   ├── <name>.zip            # 全量备份归档（标准 ZIP，可用任意工具解压）
│   └── <name>.json           # 全量备份摘要（文件数/字节数/压缩级别/耗时）
├── snapshots/
│   └── <name>/               # 增量快照文件树（Linux/macOS：硬链接快照）
├── cas/
│   └── <xx>/<sha256>         # 内容寻址对象（Windows：相同内容只存一份）
├── meta/
│   ├── <name>.json           # 增量快照摘要
│   └── <name>.manifest.json  # 增量快照文件清单（路径/大小/时间/哈希）
└── temp/                     # rsync 日志、CAS 临时文件（自动清理）
```

备份名由 Dart 生成（本地时间 `YYYYMMDD-HHMMSS`），Rust 侧发现重名时自动追加
`-2`、`-3`……并把最终名称写回摘要；名称只允许 `[A-Za-z0-9._-]`，
Rust 会对所有接收到的名称做校验（防路径穿越）。

## 3. 全量备份（原备份功能）

- 实现：`rust/backup/src/lib.rs` 的并行 Deflate 压缩器（rayon 并行压缩 +
  串行写 ZIP + ZIP64 支持），入口 `full::create`。
- 保留旧 FFI `backup_directory`（兼容其它调用方），实例备份页走
  `backup_request` 的 `full_create`。
- 备份内容：实例根目录下**全部**条目（不再让用户勾选）；位于实例目录内部的
  备份仓库会被自动排除，避免自我递归。
- 恢复（`full_restore`）：用 `zip` crate 解包回实例目录，`enclosed_name()`
  拦截绝对路径与 `..`（zip-slip 防护）。
- 删除（`full_delete`）：删除 ZIP 与摘要。

## 4. 增量备份

策略在 Rust 内按平台选择，并记录在快照摘要的 `strategy` 字段：
`cas`（Windows）、`rsync-hardlink`（Linux/macOS）、`hardlink`（rsync 缺失/失败时的回退）。

### 4.1 Linux/macOS：Rsync 硬链接快照

```text
rsync -rlpt \
      --link-dest=<上一个快照绝对路径> \
      [--info=progress2 --no-inc-recursive]   # 仅 rsync >= 3.1
      [--exclude=/<仓库相对路径>/]             # 仓库位于实例目录内部时
      <源目录>/ <新快照>/
```

- `-rlpt`：递归、保留符号链接、权限、时间戳。与 `-a` 的区别是不保留
  owner/group，普通用户（非 root）可直接使用；macOS 自带的 rsync 2.6.9 与
  openrsync 都支持这些参数。
- `--link-dest`：内容未变化的文件在新快照中**硬链接**到上一个快照的同一路径，
  不占额外空间；新增/修改的文件才真正复制。
- 快照文件树自包含（可单独浏览/复制），删除旧快照不会破坏新快照。
- 进度：rsync 输出重定向到 `temp/rsync-*/rsync.stdout.log`，主循环每 120ms
  轮询解析 `--info=progress2` 的百分比并回传（千分比）；老版本 rsync 不带进度
  参数，UI 显示不确定进度。取消时直接 `kill` 子进程。
- 老版本 rsync 不支持进度参数时（`unknown option`），自动去掉这两个参数重试一次。
- rsync 不可用或执行失败：**回退 Rust 原生硬链接快照**（`hardlink.rs`），
  语义相同（内容未变化的文件硬链接到父快照），并在摘要 `note` 中记录回退原因。

### 4.2 Windows：哈希比对 + 内容寻址存储（CAS）

1. 扫描源目录得到文件清单（相对路径、大小、mtime）；
2. rayon 并行计算每个文件的 **SHA-256**；
3. 内容对象写入 `<repo>/cas/<hash 前两位>/<hash>`（临时文件 + rename，已存在
   则跳过）→ 相同内容（含跨快照）只存一份；
4. 快照本身是清单：`meta/<name>.manifest.json` 记录路径 → 哈希/大小/mtime；
5. 与父快照清单比对得到 新增 / 修改 / 未变 / 删除 统计；
6. 恢复时按清单把 CAS 对象复制回实例目录（对象是只读共享内容，绝不做硬链接，
   否则改文件会污染存储）；
7. 删除快照后执行 GC：扫描全部清单，删除无人引用的对象并统计释放空间。

> 每次都按内容重新比对（不做「大小 + mtime 相同就跳过」的快速路径）：
> 同一秒内改写、大小不变的文件也能被正确识别为「修改」。
> 代价是需要重新读一遍文件内容，rayon 多线程 + 流式分块读取，
> 同时取消检查按 1 MiB 分块进行，大实例也能随时取消。

## 5. FFI 契约

```c
// 统一入口（api.rs）
char *backup_request(const char *op, const char *args_json,
                     void (*progress_cb)(uint64_t done, uint64_t total));
void  cancel_backup(void);
char *get_last_error(void);
void  free_string(char *s);
```

返回值（UTF-8 JSON，Dart 侧用 `free_string` 释放）：

```json
{ "ok": true,  "data": { } }
{ "ok": false, "error": "…", "cancelled": false }
```

| op | 参数 | 说明 |
|----|------|------|
| `status` | `repoRoot` | 仓库概览：平台、策略、rsync 版本、全量与增量列表、占用统计 |
| `full_create` | `repoRoot`、`sourceRoot`、`name?`、`compressionLevel?` | 全量备份 → ZIP |
| `full_restore` | `repoRoot`、`name`、`targetRoot` | ZIP 解包覆盖恢复 |
| `full_delete` | `repoRoot`、`name` | 删除全量备份 |
| `snapshot_create` | `repoRoot`、`sourceRoot`、`name?`、`parent?`、`label?` | 创建增量快照（`parent` 缺省取最新快照） |
| `snapshot_restore` | `repoRoot`、`name`、`targetRoot`、`prune?` | 恢复增量快照（`prune=true` 删除快照中不存在的文件） |
| `snapshot_verify` | `repoRoot`、`name`、`deep?` | 校验快照（`deep=true` 逐文件比对哈希） |
| `snapshot_delete` | `repoRoot`、`name` | 删除快照并回收 CAS 空间 |
| `gc` | `repoRoot` | 仅回收未被引用的 CAS 对象 |

进度回调语义：`(已完成, 总量)`，二者单位一致即可（字节或条目），
`total == 0` 表示无法预估。取消由 Dart 调 `cancel_backup()` 置全局标志，
Rust 各长任务轮询该标志（rsync 场景直接 kill 子进程），返回 `cancelled: true`。

## 6. Dart 分层

| 层 | 文件 | 职责 |
|----|------|------|
| FFI | `lib/services/backup_ffi.dart` | 打开动态库、后台 isolate 调用、`NativeCallable` 进度、`free_string` |
| 业务 | `lib/services/backup_manager.dart` | 仓库路径、模型（`BackupEntry`/`BackupRepositoryStatus`/`BackupVerifyResult`）、进度换算、异常 |
| UI | `lib/screens/instance_backup_tab.dart` | 两个操作按钮 + 进度卡片 + 备份历史 + 详情/恢复/校验/删除弹窗 |

所有耗时调用都在后台 isolate 执行，主 isolate 只处理进度与 UI，不阻塞渲染。

## 7. 测试

- Rust 单元测试：`cargo test -p xmc_backup`
  - ZIP 并行压缩与仓库排除、名称唯一化；
  - CAS：跨快照去重、删除统计、孤对象回收、恢复内容；
  - 硬链接快照：第二次快照只新增变化字节、`linked` 标记、删除统计；
  - 恢复（含 prune）、校验（缺失/大小不符）、路径穿越拒绝、进度回调。
- Dart：
  - `test/backup_manager_test.dart`：JSON → 模型、排序、备份名、校验结果；
  - `test/backup_ffi_test.dart`：真实动态库端到端（全量 roundtrip、增量 dedupe、
    恢复、校验、删除、参数校验），未编译动态库时自动跳过。

## 8. 运维提示

- 恢复会覆盖同名文件；实例运行中恢复可能被服务器改写或锁定，UI 会提示先停止实例。
- Linux/macOS 删除旧快照不会影响新快照（硬链接各自独立）；Windows 删除快照会
  自动回收未被引用的内容对象，`gc` 可手动触发。
- 备份仓库位于数据根目录；切换数据根（`data_root.txt`）不会迁移备份仓库，
  如需保留请手动拷贝 `backups/` 目录。
