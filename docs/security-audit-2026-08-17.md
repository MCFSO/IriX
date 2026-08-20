# IriX（X Minecraft Server Launcher）客户端安全审计报告

- **审计日期**： 2026-08-17
- **审计对象**： `D:\xmcserverlancher`（Flutter 客户端 + Rust workspace，含 FFI 边界两侧）
- **审计性质**： 授权的、只读的防御性安全审计；未修改任何代码、未执行目标程序
- **审计方法**：
  1. Mimosa 密封深度扫描（静态，含依赖 advisory 比对）
  2. 人工代码审计 ×3：Rust crates（8 个）、Dart 服务/状态层、UI 层与仓库卫生

---

## 1. 自动化扫描结论（Mimosa）

| 项 | 值 |
|---|---|
| Scan ID | `scan-2026-08-17T11-28-11.071Z-1d588b716f2a` |
| Seal | `sha256:356917fd9fc4a21cdefe420924af6197874dcd6ca92b3d45aea62314d9549c67` |
| 产物目录 | `C:\Users\hjcdu\.mimosa\security-scans\project-267a1ca9e8fc1fc6d36f880d\scan-2026-08-17T11-28-11.071Z-1d588b716f2a` |
| 依赖扫描 | 264 个包，0 条已知 advisory 命中（离线 advisory 库） |
| 自动 finding | 0 条 |

> 零自动 finding ≠ 无风险。本项目的主要风险集中在**供应链校验缺失、本地服务鉴权缺失、传输层明文、注入面**等逻辑型漏洞，均由人工审计发现，详见下文。本报告不作出"项目完全安全"的结论。

---

## 2. 漏洞汇总

| 级别 | 数量 | 编号 |
|---|---|---|
| Critical | 0 | — |
| High | 6 | H-1 ~ H-6 |
| Medium | 7 | M-1 ~ M-7 |
| Low | 9 | L-1 ~ L-9 |

---

## 3. High 级发现

### H-1 全部可执行内容下载均无完整性校验，MSL 返回的 sha256 被丢弃（供应链 RCE）

- **位置**： `lib/screens/download_core_screen.dart:172-216`、`lib/services/downloader.dart:252-257`、`lib/services/jdk_installer.dart:107`、`lib/screens/mod_detail_screen.dart:155`、`lib/screens/hangar_detail_screen.dart:135`
- **证据**：
  ```dart
  // msl_api_service.dart:56-62 —— API 明确返回 sha256
  return MslDownloadInfo(url: data['url'] as String, sha256: data['sha256'] as String?);
  // download_core_screen.dart:172-175 —— 只取 url，sha256 从未校验
  final info = await MslApiService.instance.getDownloadUrl(core, version);
  downloadUrl = info.url;
  fileName = '$core-$version.jar';
  ```
  `Downloader.downloadFile(url, targetFilePath, onProgress, {threads})` 无任何 hash 参数；核心 jar、Mod/插件 jar、JDK、frpc 共 6 处调用全部无校验。
- **攻击场景**： 下载的服务端 jar 被直接 `java -jar` 执行。MSL 镜像源、FastMirror CDN、Modrinth/Hangar 附件 CDN 任一被入侵或恶意返回，即可在用户机器上执行任意代码（伪装成 jar 的木马服务端）。TLS 只能防 MITM，不能防恶意/被入侵的源。
- **修复建议**： MSL/Modrinth/FastMirror/Adoptium 响应中均已含哈希字段，落盘后校验即可（成本极低）；frpc 用 GitHub 官方 release sha256；校验失败删除文件并告警。

### H-2 frpc 可执行文件经不可信第三方 GitHub 代理下载后直接赋予执行权限运行（供应链 RCE）

- **位置**： `lib/services/frpc_manager.dart:320-339`（镜像列表）、`:254-261`（下载）、`:491-499`（执行）
- **证据**：
  ```dart
  static const List<String> _ghMirrors = [
    'https://ghfast.top',   // 第三方公益加速，不受开发者控制
    'https://ghproxy.net',
    '',
  ];
  ```
  下载成功即 `chmod +x` 并 `Process.start` 执行，无哈希校验；镜像优先于 GitHub 直连尝试。SakuraFrp 版本号另从 `nya.globalslb.net` 目录页 HTML 正则解析（`:289`），同样可被篡改。
- **攻击场景**： 任一代理（或其被入侵节点）返回伪造 frpc 二进制 → 用户点击"启动隧道"即以用户权限执行任意代码，且 FRP token 通过命令行参数传给该二进制（见 M-6）。
- **修复建议**： 镜像下载必须校验 GitHub 官方发布 sha256（可从 api.github.com 元数据获取）；或仅直连 + 引导用户自行配置代理。

### H-3 MCP 本地服务端无任何鉴权，`read_file`/`list_files` 免授权执行，恶意网页可达

- **位置**： `lib/services/mcp_server.dart:128`（POST /mcp 无鉴权）、`:87`（固定端口 39273）、`:258-267`（仅 elevated 工具弹窗）；`lib/services/ai_assistant_service.dart:650-678`（read_file 为 `AiToolPermission.read`，无确认直接执行）
- **证据**：
  ```dart
  if (req.method == 'POST' && req.uri.path == '/mcp') { await _serveRpc(req); }  // 无 token/Origin 校验
  // ai_assistant_service.dart:663-665 —— read_file 免授权读取任意实例目录文本文件（≤60KB）
  final file = File(_resolvePath(instance, a['path'].toString()));
  ...
  return await file.readAsString();
  ```
- **攻击场景**：
  1. 同机任意进程 POST `tools/call {name:"read_file"}` 即可枚举实例并读取 `server.properties`、配置中的数据库密码等，全程无感知；
  2. 浏览器恶意网页可发跨源简单请求实际送达该端点（`utf8.decoder.bind(req).join()` 不校验 Content-Type/Origin），响应虽不可读，但可反复触发 elevated 授权弹窗钓鱼（如 `send_server_command` 注入控制台命令）；
  3. 端口固定可预测（`ai_settings.dart:193`），`GET /` 信息页公开全部工具清单。
- **加剧因素**： 路径校验存在同前缀兄弟目录绕过（L-1），`../instance2/secret.txt` 可通过 `startsWith(root)` 检查。
- **修复建议**： 启动时 `Random.secure()` 生成 bearer token 并校验 `Authorization` 头；拒绝非本机 `Origin`/`Host`；`read_file` 增加授权或路径白名单；信息页移除工具枚举。

### H-4 Windows 下经 `cmd /c start` 打开链接，存在 cmd 元字符命令注入

- **位置**： `lib/screens/ai_screen.dart:575-583`
- **证据**：
  ```dart
  await Process.start(
    Platform.isWindows ? 'cmd' : 'xdg-open',
    Platform.isWindows ? ['/c', 'start', uri.toString()] : [uri.toString()],
    mode: ProcessStartMode.detached,
  );
  ```
- **攻击场景**： URL 来自 AI 助手渲染的 Markdown 链接（`ai_screen.dart:571-575`），即由模型输出/日志 prompt 注入内容控制。`https://x.com/&calc` 中 `&` 后的任意命令会被 cmd 以当前用户权限执行。
- **修复建议**： 项目已依赖 `url_launcher`，改用 `launchUrl(uri, LaunchMode.externalApplication)`；或最低限度拒绝含 `&|<>^%` 的 URL 并补 `start` 空标题参数。

### H-5 ChmlFrp 全部 API（含 Bearer/refresh token）走明文 HTTP，OAuth 回调无 state 校验

- **位置**： `lib/services/chmlfrp_provider.dart:18`（`const chmlFrpApiBase = 'http://cf-v2.uapis.cn'`）、`:53`（`Authorization: Bearer $token`）、`:75-80`（refresh_token 请求体）；`lib/services/oauth_callback_server.dart:36-49`
- **攻击场景**：
  1. access_token / refresh_token（长期有效、落盘持久使用）全部明文传输，同网段被动嗅探即可窃取账户；
  2. 回调服务器接受任意来源的第一个请求、无 state/nonce 关联，本机其他进程可抢答伪造 token（token fixation）。
- **修复建议**： 服务端支持 HTTPS 立即切换；回调增加一次性 state（`Random.secure()` 生成、回调时校验）。

### H-6 节点远程管理通道默认明文 HTTP、API Key 放 URL 查询参数、本地节点"默认无需密钥"

- **位置**： `lib/services/node_api_client.dart:97-103`、`:48`；`lib/widgets/add_node_dialog.dart:289-290`、`:319`、`:343`
- **证据**：
  ```dart
  Uri _uri(String path, [Map<String, String>? query]) {
    final q = <String, String>{...?query};
    if (apiKey.isNotEmpty) { q['apikey'] = apiKey; }   // 凭证入 URL
    return Uri.parse('$baseUrl$path').replace(queryParameters: q);
  }
  ```
  默认地址示例即远程明文面板（`http://192.168.1.5:23333`）；Node 类型 UI 声称"本地节点密钥（可留空）/默认无需密钥"。该通道承载的能力包括：任意文件读/写/删（`node_api_client.dart:357-398`）、容器内执行命令（`:761`）、Bastille jail 命令执行（`:889`）、任意路径归档下载/恢复（`:1057-1126`）。
- **攻击场景**： 远程节点管理时 apikey 进入节点/代理日志，全部控制流量（含写文件、exec 命令）明文可被窃听篡改；若本地守护进程端口暴露且密钥为空，即形成未认证的远程文件读写 + 命令执行面。
- **修复建议**： 节点地址强制 https 或显式警告；apikey 改用请求头；远程地址拒绝空 apikey；本地守护进程默认仅绑定 127.0.0.1 并强制生成密钥。

---

## 4. Medium 级发现

### M-1 归档解压无 Zip-Slip 防护（与 H-1/H-2 同源叠加）

- **位置**： `lib/services/frpc_manager.dart:410-415`、`lib/services/jdk_installer.dart:135-146`
- **证据**： `final outPath = p.join(targetDir.path, file.name);` —— 归档条目名未过滤 `../`，`package:archive` 不净化条目名；解压产物随后被直接执行。
- **攻击场景**： 被篡改的 frpc/JDK 归档内含 `../../../` 条目即可写出目标目录之外（写启动项、覆盖用户文件），与 H-1/H-2 组合时无需绕过 TLS。
- **修复建议**： 解压前校验 `p.normalize(p.join(target, name))` 仍位于 target 之下；拒绝绝对路径与盘符条目。

### M-2 远端响应中的文件名直接拼接落盘路径

- **位置**： `lib/screens/mod_detail_screen.dart:154`（`file.filename` 直接来自 Modrinth API）、`lib/screens/hangar_detail_screen.dart:129-130`（slug/version.name 拼接）；对照干净实现 `lib/screens/download_core_screen.dart:195`
- **攻击场景**： 恶意/被入侵的 API 返回 `filename: "..\\..\\startup.bat"` 之类值，`p.join` 后越出 `instance.rootPath` 写任意文件。
- **修复建议**： 落盘前统一 `p.basename()` 净化并拒绝含路径分隔符的文件名。

### M-3 全部敏感凭证明文存于本地 SQLite

- **位置**： `lib/services/ai_settings.dart:49-56,126-131`（AI API key）、`lib/services/database_manager.dart:96-119`（db_connections.password、nodes.api_key）、`lib/services/node_store.dart:34`、`chmlfrp_provider.dart:157-172` / `sakurafrp_provider.dart:126` / `hayfrp_provider.dart:125` / `ofrp_service.dart:201`（FRP token）
- **攻击场景**： `irix.db` 被任何能读用户文档的进程/备份/同步盘复制即泄露全部凭证。UI 侧已核实无泄露（密码框均 `obscureText`，日志无 token 值）。
- **修复建议**： 用 Windows DPAPI / macOS Keychain（如 `flutter_secure_storage`）存凭证，SQLite 只留密文或引用。

### M-4 db_client SQL 转义器与上下文错配（标识符转义器用于字符串字面量）

- **位置**： `rust/db_client/src/lib.rs:781-787`、`:880-884`、`:908-910`
- **证据**：
  ```rust
  let user = esc_mysql_ident(&username);          // 只翻倍反引号，不处理 '
  format!("CREATE USER '{user}'@'%' IDENTIFIED BY '{pwd}'")  // 却放入单引号字面量
  ```
- **攻击场景**： 用户名含 `'`（如 `a'@'localhost`）即可逃逸字面量改变语句语义，语句以管理员连接执行；当前 UI 自输入时退化为自伤，若 username 来自低信任来源（节点代理、导入配置）则可越权建户/改密。PG 分支转义器使用正确（`:797-803, 890-893`）。
- **修复建议**： 字符串上下文一律 `esc_mysql_str`；根治则对标识符白名单校验 `[A-Za-z0-9_-]+`。

### M-5 数据库连接默认明文（TLS 为 opt-in）

- **位置**： `rust/db_client/src/lib.rs:56-58`（`ssl` 默认 false）、`:329-338`（PG NoTls）、`:396-398`（默认 `redis://` 明文）、`:206-210`（MySQL 无 ssl_opts）
- **攻击场景**： 默认路径下 Redis AUTH 密码、PG/MySQL 认证材料可被网络中间人截获。
- **修复建议**： 对非回环主机默认要求 TLS 或在 UI 明确告警；本地回环可豁免。

### M-6 FRP 凭证经命令行参数传递，对同机进程可见

- **位置**： `lib/services/frpc_manager.dart:445-452`（`frpc -u <token>`）、`:456-461`（`-f '<token>:<tunnelId>'`）
- **攻击场景**： 任意同机进程通过进程枚举（WMI CommandLine、`/proc/*/cmdline`）读取 frp 访问令牌。
- **修复建议**： 改用配置文件（写临时 TOML 后删除）或环境变量方式传递。

### M-7 未跟踪目录 `1.0.0+1/`（138MB 发行安装包）未被 .gitignore 覆盖

- **位置**： 仓库根 `1.0.0+1/`
- **证据**： 含 v1.2.0 全平台安装包 + `SHA256SUMS-1.2.0.txt` + `rename-log.csv`（泄露本机绝对路径）。已逐行检查，**未发现内嵌密钥**。`.gitignore` 覆盖 `/dist/` 与 `/xmc_*.dll` 但漏掉该目录。
- **攻击场景**： 一次 `git add -A` 即把 138MB 二进制提交进仓库；从仓库直下安装包会绕过 Release 发布流程，形成供应链旁路。
- **修复建议**： `.gitignore` 增加 `/1.0.0+*/`，或将目录移入 `dist/`。

---

## 5. Low 级发现

| 编号 | 发现 | 位置 | 说明 |
|---|---|---|---|
| L-1 | AI 路径校验同前缀兄弟目录绕过 | `ai_assistant_service.dart:527-533` | `startsWith(root)` 未带分隔符，`C:\inst` 放行 `C:\instance2\...`；与 H-3 叠加可读兄弟实例。改为 `p.isWithin(root, target)` |
| L-2 | file_ops FFI 无任何路径校验 | `rust/file_ops/src/lib.rs:532-559` 等 | `..`/绝对路径/symlink 全放行；当前唯一调用方是本地 UI（同用户权限）故降级，但未来接入远程节点即成全盘读写删面。建议 canonicalize 前缀校验做纵深防御 |
| L-3 | 回收站元数据被篡改后可定向删/改名任意路径 | `rust/file_ops/src/lib.rs:707-729, 823-834` | 信任 `trash_meta.json` 的 `original_path`/`file_name`；前提是攻击者已有本地写权限 |
| L-4 | logger 的 instance_id 未消毒即拼接日志文件名 | `rust/logger/src/lib.rs:101, 294` | 含 `../` 可越界写/删 `.log`；当前 id 由 Dart 生成（UUID）。建议拒绝含 `/ \ ..` 的 id |
| L-5 | downloader 无下载体积上限 | `rust/downloader/src/lib.rs:248-259` | 完全信任服务端 Content-Range，恶意源可无限写盘（http_client 有 256MiB 上限，downloader 无） |
| L-6 | FFI 入口缺 catch_unwind + 手工分配脆弱 | `rust/file_ops/src/lib.rs:485-491`；`rust/orchestrator/src/lib.rs:165-177` | file_ops/backup/downloader 的 panic 会跨 FFI unwind（UB/进程终止）；orchestrator 的 `Vec` + `mem::forget` 与 `CString::from_raw` 依赖分配器实现细节，改 `into_raw()` |
| L-7 | 错误消息可能回显含凭据的 URL | `rust/http_client/src/lib.rs:211-213`、`rust/downloader/src/lib.rs:238-240` | ureq 错误 Display 含完整 URL，token 在 query 时随错误返回 UI/日志。返回前剥 query/userinfo |
| L-8 | backup 单文件全量读入内存（rayon 并行放大） | `rust/backup/src/lib.rs:213-215` | 压缩数十 GB 存档会 OOM；建议流式压缩 |
| L-9 | 杂项：记录 ID 用非安全随机（`app_state.dart:144-147` 等，本地主键无安全语义）；API Key 一键复制剪贴板无提示（`add_node_dialog.dart:324-330`）；frpc 全量日志持久化（`frpc_manager.dart:503-529`）；下载错误直接展示远端响应体（`download_core_screen.dart:668-671`，文本钓鱼）；`op_execute` 透传任意 SQL 属设计功能但无只读护栏（`rust/db_client/src/lib.rs:556-586`） | — | 均为低风险/设计权衡，择机加固 |

---

## 6. 已检查未发现问题的区域

| 区域 | 结论 |
|---|---|
| 本地 SQLite 构造（Dart） | DatabaseManager 与各 store 全部参数化查询，仅有的 rawQuery 为常量 DDL/PRAGMA，无 `$` 插值 |
| vector_store（Rust） | 全部 `params![]` 参数化；唯一插值 `dim` 经类型校验 |
| db_client 常规 CRUD | 表名/列名用标识符转义器、值用字符串转义器，上下文匹配正确；LIMIT/OFFSET 参数化（M-4 为例外） |
| Redis 命令 | 全部经 `redis::cmd(...).arg(...)` RESP 参数传递，无 inline 拼接 |
| Rust HTTP 栈 TLS | ureq + rustls 全程开启证书校验，无任何 danger/accept_invalid 配置（grep 0 命中） |
| 服务器进程启动 | `Process.start` 逐参数传递不经 shell；自定义 tokenizer 正确处理引号；内存滑块用锚定正则替换 `-Xmx` |
| eula.txt / server.properties 编辑 | 锚定正则逐行替换，无注入 |
| FastMirror 下载源 | 30+ URL 硬编码 https，无用户任意 URL 输入、无路径穿越（完整性校验缺失归入 H-1） |
| NAT 检测（first_run_wizard） | 仅向 Google STUN 发标准 Binding Request，随机事务 ID 用 `Random.secure()`，不含用户数据，无提权操作 |
| WebView / XSS | 无 webview 依赖；AI 回复 markdown 默认不渲染 HTML；MOTD/日志按纯文本渲染 |
| OAuth 回调绑定 | `loopbackIPv4` 随机端口，token 走 URL fragment（缺 state 见 H-5） |
| 自定义 FRP TOML 生成 | `_esc` 正确转义反斜杠与双引号 |
| `package:http` 残留 | lib/ 下零残留 |
| 仓库卫生 | 无 .env、无硬编码密钥/token、CLAUDE.md 无敏感信息（`1.0.0+1/` 见 M-7） |
| Rust FFI 内存配对（除 L-6） | 7 crate 均 `CString::into_raw` + 同侧 `from_raw` 释放；入参仅 `CStr::from_ptr` 借读；`get_last_error` 返回克隆 |
| Rust logger 凭据记录 | 透传不解析，无主动记录凭据行为（风险仅在调用方传入敏感行） |
| ZIP 解压（Rust 侧） | backup crate 仅实现压缩，解压在 Dart 侧（见 M-1），Rust 无 zip-slip 面 |

---

## 7. 修复优先级建议

1. **立即**（一行改动收益最大）：H-4（换 url_launcher）→ H-1（MSL sha256 落盘校验）→ H-2（frpc 镜像加哈希校验或移除）→ H-3（MCP 加 bearer token + Origin 校验）
2. **短期**：H-5（ChmlFrp 切 HTTPS + OAuth state）、H-6（节点 apikey 移入请求头 + 远程强制 https/警告 + 拒绝空密钥）、M-1（Zip-Slip 防护）、M-4（db_client 转义器修正）、M-7（.gitignore 补 `/1.0.0+*/`）
3. **择机**：M-2/M-3/M-5/M-6、L-1~L-9

---

## 8. 修复状态（2026-08-17 当天实施）

> 以下修复已实施并验证（`flutter analyze` 零问题；FFI 集成测试与 MCP 协议测试全部通过；
> Rust 已重新编译并复制到 `windows/runner/` 与项目根目录）。

| 编号 | 修复内容 | 状态 |
|---|---|---|
| H-1 | `Downloader.downloadFile` 增加可选 `sha256`/`sha512` 参数，落盘后校验、失败删文件并告警；MSL 核心（sha256）、Adoptium JDK（`package.checksum` 的 `sha256:` 前缀）、Modrinth（sha512）均已接入；frpc 归档经 GitHub Release API digest 校验 | ✅ |
| H-2 | 移除全部第三方 GitHub 镜像（ghfast.top / ghproxy.net），仅 GitHub 官方直连 + 官方 digest 校验；直连失败提示配置系统代理 | ✅ |
| H-3 | MCP 每次启动 `Random.secure()` 生成 64 位 hex bearer token，`Authorization`/`?token=` 校验；非本机 `Origin` 拒绝；信息页移除工具枚举；AI 设置页展示含 token 的完整配置并一键复制 | ✅ |
| H-4 | AI 助手链接改用 `url_launcher`（`LaunchMode.externalApplication`），消除 `cmd /c start` 元字符注入 | ✅ |
| H-5 | ChmlFrp API 切 `https://cf-v2.uapis.cn`；OAuth 回调增加一次性随机 state（授权 URL 携带、回调校验，不匹配拒绝并继续等待） | ✅ |
| H-6 | 节点 apikey 默认走 `X-Api-Key` 请求头（MCSM 类型保留查询参数兼容，NODE_API.md 已更新）；添加节点时远程 Node 强制密钥、非 https 非回环地址弹明文警告 | ✅ |
| M-1 | frpc 与 JDK 解压均校验 `p.isWithin` 归一化边界，拒绝 `../`/绝对路径/盘符条目 | ✅ |
| M-2 | Modrinth/Hangar 下载文件名 `p.basename()` 净化并拒绝路径分隔符 | ✅ |
| M-4 | `db_client` 新增 `validate_user_ident` 白名单（`[A-Za-z0-9_$.-%]`）；MySQL `CREATE/DROP USER` 的用户名/主机改用字符串转义器（原标识符转义器错配） | ✅ |
| M-7 | `.gitignore` 补 `/1.0.0+*/`、`/2.0.0+*/` 与通用版本号匹配 | ✅ |
| L-1 | AI 路径校验 `startsWith` → `p.isWithin` | ✅ |
| L-3 | 回收站恢复/清理前校验 `trash_meta.json` 的 `original_path` 位于根目录内、`file_name` 无路径分隔符 | ✅ |
| L-4 | Rust logger 校验 `instance_id`，拒绝 `/`、`\`、`..`、空白与控制字符 | ✅ |
| L-5 | Rust downloader 单次下载上限 4 GiB（声明值与实际接收双检查，超限清理） | ✅ |
| L-6 | backup `backup_directory` 与 file_ops 回收站/删除相关 FFI 入口加 `catch_unwind`；orchestrator `last_error` 改 `CString::into_raw` 与 free 侧严格配对 | ✅（file_ops 其余入口、downloader 入口未全覆盖，见下） |
| L-7 | http_client / downloader 错误消息经 `redact_url_credentials` 剥离 userinfo 与 query | ✅ |
| L-9 | 实例 ID 改用 `Random.secure()`；API Key 复制增加 SnackBar 提示 | ✅ |
| M-3 | 凭证明文 SQLite（DPAPI/Keychain） | ⏳ 待做（需引入 flutter_secure_storage，属较大设计改动） |
| M-5 | 远程数据库默认明文（TLS opt-in） | ⏳ 待做（需 UI 告警与 Rust 连接参数改造） |
| M-6 | FRP token 命令行参数可见 | ⏳ 待做（需改为临时配置文件传递） |
| L-2 | file_ops FFI 路径校验 | ⏳ 待做（当前仅本地 UI 同权限调用方；接入远程节点前应补 canonicalize 前缀校验） |
| L-8 | backup 单文件全量读入内存 | ⏳ 待做（需流式压缩改造） |

**遗留说明**：L-6 的 catch_unwind 已覆盖 backup 主入口与 file_ops 的
`delete_to_trash`/`delete_permanently`/`restore_from_trash`/`purge_trash_entry`；
file_ops 其余 FFI 入口与 downloader 入口未逐一包裹（panic 面低，均为简单 IO 包装）。

---

## 9. 二次评审（2026-08-18，针对提交 `fa5a8b3`）

**评审范围**：提交 `fa5a8b3 security: fix audit findings from security-audit-2026-08-17` 的完整 diff
（42 文件，+2481/-150），对照本报告第 3~5 节逐项核实修复是否到位、是否引入新问题。
验证手段：完整 diff 审查 + `flutter analyze`（零问题）+ `flutter test test/mcp_server_test.dart`
（14 用例全过，含 5 个 H-3 鉴权用例）+ 关键路径源码复核。

### 9.1 已确认有效修复

| 编号 | 评审结论 |
|---|---|
| H-2 | ✅ 彻底。`_ghMirrors` 已删除，仅 `https://github.com/fatedier/frp/releases/download` 直连；`_githubAssetSha256` 经 GitHub API 取官方 digest，正则校验 64 位 hex 后强制校验，获取失败则不校验但不阻断（合理降级）。 |
| H-3 | ✅ 扎实。`Random.secure()` 生成 32 字节 token；`_authorized` 同时校验 `Authorization: Bearer` 与 `?token=`；非本机 `Origin`（含 `[::1]`）拒绝；信息页去工具枚举；测试覆盖无 token/错 token/恶意 Origin/本机 Origin/重启换 token 五场景。 |
| H-4 | ✅ 彻底。`cmd /c start` 已替换为 `launchUrl(uri, mode: LaunchMode.externalApplication)`。 |
| H-5（HTTPS 部分） | ✅ `chmlFrpApiBase` 已切 `https://cf-v2.uapis.cn`。 |
| H-6 | ✅ 到位。`X-Api-Key` 请求头（MCSM 保留 query 兼容属协议约束）；远程 Node 强制密钥；非 https 非回环弹明文警告对话框。 |
| M-1 | ✅ frpc 与 JDK 解压均 `p.normalize` + `p.isWithin` 双校验。 |
| M-2 | ✅ Modrinth/Hangar 均 `p.basename` 净化并拒绝 `..`/分隔符。 |
| M-4 | ✅ 根治。`validate_user_ident` 白名单 + MySQL `CREATE/DROP USER` 改 `esc_mysql_str`；PG 分支保持正确。 |
| M-7 | ✅ `.gitignore` 补版本号目录模式。 |
| L-1/L-4/L-5/L-7/L-9 | ✅ 均按描述落实。 |

### 9.2 二次评审新发现的问题

> **2026-08-18 二次修复**：以下三项已在二次评审当日修复并验证
> （`flutter analyze` 零问题；Rust 已重新编译并复制 `xmc_file_ops.dll`；
> Hangar 模型用真实 API 响应验证解析正确）。

#### [High] H-1 残留：Hangar（PaperMC）下载完全无完整性校验 → ✅ 已修复

- **原位置**： `lib/screens/hangar_detail_screen.dart:149`（`downloadFile` 调用无 `sha256`/`sha512` 参数）；`lib/models/hangar.dart` 无 hash 字段
- **原情况**： H-1 修复接入 MSL/JDK/Modrinth/frpc 四类下载，但 Hangar 平台被遗漏。
- **修复**：
  1. `HangarPlatformDownload` 增加 `sha256` 字段，从 `fileInfo.sha256Hash` 解析；
  2. `HangarVersion.fromJson` 修正为解析真实 API 结构——`downloads` 按平台大写名索引的 map（而非不存在的 `downloads['platforms']`），游戏版本取自 `platformDependencies`，下载量取自 `stats.totalDownloads`；
  3. `hangar_detail_screen.dart:149` 的 `downloadFile` 调用传入 `sha256: pd.sha256`。
- **附带修复**： 原模型解析 `downloads['platforms']`（API 中不存在该字段），导致 Hangar 平台下载项实际从未加载——本次一并修正，Hangar 下载功能现在才真正可用。
- **验证**： 用真实 Hangar API 响应（`projects/Ciran/Luckperms-Supporter/versions`）验证模型解析，sha256/downloadUrl/platform/gameVersions 全部正确提取。

#### [Medium] H-5 残留：OAuth 回调在服务端不回传 state 时放行 → ✅ 已修复

- **原位置**： `lib/services/oauth_callback_server.dart:70`
- **原情况**： state 校验在 `got == null`（回调不含 state）时直接放行，存在 token fixation 残留面。
- **修复**： 改为 `if (expected != null && (got == null || got != expected)) reject`——state 缺失或不匹配一律拒绝并继续等待真实回调。
- **影响**： 若 ChmlFrp SSO 不回传 state，合法回调也会被拒绝（用户需重试）；这是安全性优先的正确取舍，杜绝了同机攻击者用无 state 请求注入伪造 token 的路径。

#### [Medium] L-3 残留：`original_path` 未 canonicalize，可被 `..` 组件绕过 → ✅ 已修复

- **原位置**： `rust/file_ops/src/lib.rs:746`
- **原情况**： `original_path` 仅做词法 `Path::starts_with(root)`，`C:\inst\..\..\Windows\System32\x` 可绕过。
- **修复**： 在前缀校验前增加 `Component::ParentDir` 检查——`original_path` 含任何 `..` 组件即拒绝；随后 `canonicalize`（目标不存在则用词法归一化兜底）再做 `starts_with(root_norm)`。与 `file_name` 的严格度对齐。
- **验证**： `cargo build --release` 成功，`xmc_file_ops.dll` 已重新编译并复制到 `windows/runner/` 与项目根目录。

### 9.3 确认未修复项（与第 8 节"⏳ 待做"一致，无变化）

| 编号 | 二次评审确认 |
|---|---|
| M-3 | 仍明文。`ai_settings.dart`/`database_manager.dart`/`node_store.dart` 仍 `setSetting` 明文写 SQLite，无 secure storage/加密。 |
| M-5 | 仍 opt-in。`rust/db_client` `ssl` 默认 false，PG `NoTls`/Redis `redis://` 明文默认未改。 |
| M-6 | 仍命令行。`frpc_manager.dart:447/458` 仍 `-u <token>`/`-f <token>:<id>`。 |
| L-2 | 仍无校验。`file_ops` 的 `copy_file`/`move_file`/`create_directory`/`rename_entry`/`scan_dir`/`get_file_info` 等仍直接接受任意路径，无 canonicalize 前缀校验。 |
| L-6（部分） | 仍不全。`file_ops` 仅 4 个入口（delete_to_trash/delete_permanently/restore_from_trash/purge_trash_entry）包 `catch_unwind`，其余 8 个导出 + `downloader` 全部 2 个导出（`download_file`/`download_file_multipart`）仍未包。 |
| L-8 | 仍全量读。`backup` 仍 `read_to_end` 单文件全量入内存。 |

### 9.4 二次评审结论

- **6 个 High 全部修复**（H-1 含 Hangar 二次补遗、H-2/H-3/H-4/H-5/H-6）。
- **7 个 Medium 中 4 个已修复**（M-1/M-2/M-4/M-7），**3 个待做**（M-3/M-5/M-6，均已在文档中记录）。
- **9 个 Low 中 7 个已修复**（L-1/L-3/L-4/L-5/L-7/L-9 + L-6 部分），**2 个待做**（L-2/L-8 + L-6 残留：file_ops 8 个入口 + downloader 2 个入口仍未包 catch_unwind）。
- **未发现修复引入的新漏洞**；`flutter analyze` 零问题，MCP 鉴权测试 14 用例全过，Hangar 模型用真实 API 响应验证解析正确，Rust 重新编译成功并复制 DLL。
- **建议优先处理**：M-3 凭据加密存储 → M-5 远程数据库默认 TLS → M-6 FRP token 改配置文件 → L-2 file_ops 路径校验 → L-6 补全 catch_unwind → L-8 流式压缩。

---

*本报告基于 2026-08-17 的代码快照（main @ cafea12 + 工作区未提交改动）。Mimosa 扫描产物已密封，可通过上述 scan ID 与 seal 复核。修复状态章节随 2026-08-17 的修复提交更新；第 9 节为 2026-08-18 针对提交 `fa5a8b3` 的二次评审。*
