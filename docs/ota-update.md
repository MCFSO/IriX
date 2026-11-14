# 应用内更新（OTA）

IriX 可以从 GitHub Releases（或自建 Cloudflare Worker 更新源）检查新版本、
下载安装包、校验并安装；启动时自动检查（可关闭、限频 6 小时），也可以在
「设置 → 软件更新」里手动检查。

## 1. 组成

| 文件 | 职责 |
|------|------|
| `lib/services/app_version.dart` | 应用版本唯一真源（`kIrixAppVersion`）+ `SemVersion` 解析与比较 |
| `lib/models/update_info.dart` | GitHub Release / Asset 解析、`UpdateInfo`、字节格式化 |
| `lib/services/update_service.dart` | 更新源串联、选包、下载、校验、安装、打开链接（单例） |
| `lib/services/update_settings.dart` | 设置持久化（settings 表） |
| `lib/widgets/update_dialog.dart` | 更新提醒窗（更新说明 + 进度 + 安装） |
| `lib/screens/settings_screen.dart` | 「软件更新」分区（版本、开关、更新源、手动检查） |
| `lib/screens/home_screen.dart` | 启动后自动检查（延时 3s，失败静默） |
| `workers/update-feed/` | 可选：Cloudflare Worker 更新源 + 安装包分发（见 §9） |

HTTP 全部走 Rust（`http_ffi.dart` 检查更新、`downloader.dart` 下载安装包），
“现在”一律走 `TimeService`，落盘目录走 `AppPaths.updatesRoot()`
（`<数据根>/updates/`，安装包约 20–120 MB，不放系统临时目录以免被清理）。

## 2. 更新源与检查流程

更新源有三级，按顺序尝试，任一成功即止（全失败才报错）：

1. **设置里的自定义源**（`update_feed_url`）—— 用户可在
   「设置 → 软件更新 → 更新源」填写，优先级最高（临时换镜像/排障用）；
2. **构建期内置源**（`--dart-define=IRIX_UPDATE_FEED=https://...`）——
   默认值就是项目自建 Worker `https://update.mcfso.org`（见 §9）；
   传空字符串则不内置任何自建源；
3. **GitHub 官方 API**（`api.github.com/repos/MCFSO/IriX/releases?per_page=30`）兜底。

`UpdateService.normalizeFeedUrl()` 会把只填域名/根地址的值补成 `/api/releases`，
`feedCandidates()` 负责排序与去重（GitHub 的 `?per_page=` 查询串不会被规范化掉）。
每个源的响应都交给 `parseReleasesPayload()` 解析，兼容三种形态：

- GitHub Releases 原始数组 `[{tag_name, assets: [...]}, ...]`；
- `{"releases": [...]}` / `{"data": [...]}`（Worker 用的形态，可附 `generated_at`）；
- `{"release": {...}}`（只给最新一条）。

逐条解析的规则：

1. 跳过 `draft`、跳过 tag 解析不出版本号的条目（仓库里存在 `Stable` 这类 tag）；
2. `prerelease == true` 或版本号自带 `-rc.1` 时视为预发布，默认过滤
   （设置里可开启“包含预发布版本”）；
3. 取版本号最高者，与 `kIrixAppVersion` 用 `SemVersion.compareTo` 比较
   （`Stable-v1.3.0` / `v1.3.0` 会自动归一为 `1.3.0`；`1.4.0-rc.1 < 1.4.0`）；
4. 有更新时 `selectAsset()` 选安装包，写入 `update_last_check_at_ms` 与
   `update_last_known_latest`。

未认证的 GitHub API 限流为 **60 次/小时/IP**，因此：

- 启动自动检查受限频约束：距上次检查不足 `UpdateSettings.autoCheckInterval`
  （6 小时）直接跳过；
- 命中 403/429 时抛出带 `rateLimited` 的 `UpdateException`，并在错误文案里
  带出 `x-ratelimit-reset` 换算的剩余等待时间；
- 用 Worker 源时，Worker 侧还有 5 分钟列表缓存，能把这部分配额消耗降下来。

## 3. 安装包选择（打分）

`UpdateService.selectAsset()` 按平台 + 架构给每个 asset 打分，取最高分：

| 平台 | 加分顺序（同名架构优先 +20，其它架构 −50） |
|------|-----------|
| Windows | `.exe` 100 → `.msix` 40 → `.zip` 10 |
| macOS | `.dmg` 100 → `.zip` 10 |
| Linux | 运行在 AppImage 内：`.AppImage` 100；否则 Debian 系 `.deb` 80 / RPM 系 `.rpm` 80 → `.AppImage` 60 → `.deb`/`.rpm` 50 → `.zip` 10 |

架构标签由 `Abi.current()` 得出（`x64`/`arm64`/`arm`/`ia32`），文件名里
`x64`/`x86_64`/`amd64` 与 `arm64`/`aarch64` 分别匹配；`SHA256SUMS-*.txt`
等校验和清单永远不作为安装包。

## 4. 下载与校验

- 目标：`<数据根>/updates/<asset 文件名>`，并在同目录写 `<文件名>.sha256`
  记录本次下载时校验过的哈希（下次启动可直接复用，不再重复下载几十 MB）；
- 哈希来源优先级：asset 的 `digest`（GitHub 计算的 `sha256:<hex>`）→
  发布里的 `SHA256SUMS-<版本>.txt` 清单；
- 校验由 Rust `download_file` 完成（`sha256` 参数），不匹配会删除文件并抛错；
- 下载前会清掉 `<目标>`、`<目标>.part`、`<目标>.sha256`，避免上一次的
  分片断点续传文件污染新版本（`.part` 是 Rust 多线程下载的续传文件）；
- 进度通过 `Downloader.downloadFile` 的 NativeCallable 回调换算成
  `UpdateProgress`（百分比 / 速度 / 已下载字节）。

## 5. 安装（按平台能力分层）

| 平台 / 包型 | 行为 | `UpdateInstallResult.mode` |
|------|------|------|
| Windows `.exe`（Inno Setup） | `Process.start` 静默安装：`/SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /NORESTART /SP-`；遇到 `ERROR_ELEVATION_REQUIRED`（740）回退 `powershell Start-Process -Verb RunAs` 提权 | `automatic`（`appMustExit = true`） |
| Windows `.msix` | 定位到文件，由“应用安装程序”确认（需可信签名） | `manual` |
| Windows `.zip`（便携版） | 解压覆盖，供便携用户手动更新 | `manual` |
| Linux `.AppImage` | 写 `apply_update.sh`：等当前进程退出 → `cp` 到 `<dst>.irix-new` → `chmod +x` → `mv` 原子替换 → 启动新版本；目录不可写则放弃 | `automatic`（`appMustExit = true`） |
| Linux `.deb` / `.rpm` | `xdg-open` 交给系统包管理器 | `assisted` |
| macOS `.dmg` | `open` 挂载，提示把 `lrix.app` 拖进“应用程序”覆盖 | `assisted` |

`appMustExit = true` 时，对话框倒计时 3 秒后 `exit(0)`，让安装程序替换正在使用的
可执行文件；IriX 重启后由 `AppState._adoptOrphanedProcesses()` 重新接管仍在运行的
服务器进程。有实例在运行时对话框会先给出提示。

## 6. 设置项（settings 表）

| key | 含义 | 默认 |
|-----|------|------|
| `update_auto_check` | 启动时自动检查更新 | `1` |
| `update_include_prerelease` | 是否包含预发布版本 | `0` |
| `update_skipped_version` | 「跳过此版本」的版本号 | 空 |
| `update_last_check_at_ms` | 上次检查时间（Unix 毫秒，TimeService） | `0` |
| `update_last_known_latest` | 上次检查到的最新版本 | 空 |
| `update_feed_url` | 自定义更新源（Worker 地址，已规范化） | 空（用内置源 / GitHub） |

「跳过此版本」只抑制**不高于**该版本的提示；出现更高版本会重新提醒，
设置页可「取消跳过」。

## 7. 发布要求（发版 checklist）

1. `pubspec.yaml` 的 `version:` 与 `lib/services/app_version.dart` 的
   `kIrixAppVersion` **一起改**（`test/app_version_test.dart` 会校验，不一致 CI 失败）；
2. git tag 使用 `Stable-vX.Y.Z`（或 `vX.Y.Z`），发布正文写更新说明
   （会原样作为 Markdown 显示在提醒窗里）；
3. 资产命名保持 `irix-<版本>-<平台>-<架构>.<ext>`，平台 `windows` / `linux` /
   `macOS`，架构 `x64` / `arm64`，扩展名 `.exe` / `.msix` / `.zip` /
   `.AppImage` / `.deb` / `.rpm` / `.dmg`；
4. 资产尽量用 GitHub 上传（会自动生成 `digest` 供客户端校验）；手工上传到别处
   的包请附 `SHA256SUMS-<版本>.txt`；
5. 预发布测试版本在 GitHub 上勾选 “pre-release”，客户端默认不会提示。

## 8. 测试

```bash
flutter test test/app_version_test.dart test/update_service_test.dart \
             test/update_settings_test.dart test/update_screen_test.dart \
             test/update_dialog_test.dart

# Worker 自身的冒烟测试（不需要 wrangler / 网络）
node --test workers/update-feed/test/smoke.test.mjs
```

覆盖：tag 归一化（含 `Stable-v1.3.0`）、SemVer 比较（含预发布、缺段）、
draft/预发布过滤、digest 只接受 sha256、校验和清单识别、三平台 × 架构的
安装包选择、字节格式化、`kIrixAppVersion` 与 `pubspec.yaml` 的一致性、
设置的默认值与持久化、设置页分区的渲染与开关落库、提醒窗渲染与「稍后提醒」、
更新源规范化与优先级、`{releases:[...]}` / `{data:[...]}` / 单条 `{release}`
三种负载形态，以及 Worker 的列表改写、缓存、`/dl` 代理与 Range、R2 优先、
路径校验。

真实网络与 FFI 下载由 `test/http_ffi_test.dart`、`test/backup_ffi_test.dart`
一类需要 Rust 动态库的集成测试覆盖；OTA 的端到端验证建议在虚拟机上用手工
构造的低版本号构建（例如 `--dart-define=IRIX_VERSION=1.2.0`）跑一遍
—— 用它可以真实走完「检查到 v1.3.0 → 选中 `irix-1.3.0-windows-x64.exe`
→ 下载 → 校验 → 安装」。

## 9. 用 Cloudflare Workers 分发

`workers/update-feed/` 是一个零依赖的 Worker，用来替代「客户端直连 GitHub」。
**已部署上线**：`https://update.mcfso.org`（Worker 名 `irix-update-feed`），
客户端 `UpdateService.defaultFeedUrl` 默认就指向它。

| 路由 | 作用 |
|------|------|
| `GET /api/releases` | GitHub Releases 摘要，`assets[].browser_download_url` 改写成 `<worker>/dl/<tag>/<asset>`，保留 `digest` |
| `GET /api/latest` | 同上，只留最新一条 |
| `GET/HEAD /dl/<tag>/<asset>` | 安装包分发：优先 R2，其次代理 GitHub；支持 Range，边缘缓存 24h |
| `GET /health` | 健康检查 |

要点：

- **必须绑自有域名**：`*.workers.dev` 在国内 DNS 被污染（实测解析到
  Facebook 的 `69.63.176.59` / `2a03:2880:f112:83:face:b00c:0:25de`），
  直连只会超时；绑 `update.mcfso.org` 后走 Cloudflare 正常边缘 IP，实测可用
  （`/health` 200、`/api/latest` 200、`/dl` Range 206、完整 26 MB 下载
  SHA-256 与 GitHub digest 一致）；
- Worker 只做**搬运**，发布仍然在 GitHub 打 tag + 上传资产，客户端解析逻辑完全不变
  （只是 `feed_url` 换了），因此 GitHub 兜底链路始终有效；
- `digest` 原样透传，客户端仍会用 SHA-256 校验安装包；Worker 侧不缓存
  `/api/*` 之外的动态内容超过 `CACHE_TTL`；安装包按 tag 不可变长缓存，
  **同一 tag 重传同名资产需要清缓存或换 tag**；
- 部署与配置（`GITHUB_TOKEN` 提高限额、自定义域名、可选 R2 自托管）以及
  既有的部署/验证记录见 `workers/update-feed/README.md`。

客户端接入方式（默认已内置，一般无需额外参数即可用）：

```bash
# 用默认内置源（https://update.mcfso.org）
flutter build windows --release

# 换成自己的 Worker
flutter build windows --release --dart-define=IRIX_UPDATE_FEED=https://my-worker.example.com

# 不内置任何自建源（只用 GitHub 官方 API）
flutter build windows --release --dart-define=IRIX_UPDATE_FEED=
```

运行时也可让用户在「设置 → 软件更新 → 更新源」里填写（优先级最高）。

### 客户端侧的 IPv6 陷阱（已修）

绑好自定义域名后，第一次实测客户端仍然退回了 GitHub，原因是**更新源请求要 23 秒**：

- `update.mcfso.org` 同时有 A（`104.21.40.167` 等）与 AAAA（`2606:4700:…`）记录；
- ureq 按 DNS 返回顺序逐个 connect，本机没有可用 IPv6 路由时，先连 AAAA 要等
  系统 SYN 超时（Windows 实测 21s）才回落 IPv4；
- 客户端检查更新的超时是 20s，于是 Worker 源"超时失败"、静默回退 GitHub。

修法（`rust/http_client` 与 `rust/downloader` 各一份 `Ipv4FirstResolver`）：
把解析结果按 **IPv4 优先、IPv6 兜底** 重排，并把 `timeout_connect` 从 30s 降到 10s。
实测同一台机器：`/health` 23.8s → 0.9s，`/api/latest`（14 KB）→ 1.0–4.4s，
客户端整体检查 41s → 3s，且 asset URL 正确指向 `update.mcfso.org/dl/…`。

> 这个坑对国内用户普遍存在（大量家宽/办公网没有可用 IPv6），所以修在 Rust
> HTTP 栈里，所有请求（市场、节点、AI、下载）一起受益，而不是只给更新检查调超时。

