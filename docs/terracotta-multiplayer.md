# 陶瓦联机（Terracotta）集成说明

实例详情页 →「联机」Tab，为 IriX 提供**陶瓦联机（Terracotta）**房间的创建与加入能力。
实现参考 HMCL 的 `org.jackhuang.hmcl.terracotta.*` 与 `ui.terracotta.TerracottaControllerPage`
（HMCL 侧代码只作为协议与流程参考，本仓库不复用其源码）。

---

## 1. 基本立场：只调度，不改造

陶瓦联机核心是第三方开源软件 **Terracotta**（作者 burningtnt，许可
`AGPL-3.0-or-later`），本应用：

1. 从官方发布渠道（GitHub Releases / Gitee / CNB / alist 镜像）下载官方打包的
   `terracotta-<版本>-<平台>-pkg.tar.gz`；
2. 用元数据里的 **SHA-512** 校验整包与解包后的每个文件，任一不符即整目录删除；
3. 以 `terracotta-<版本>-<平台>[.exe] --hmcl <端口文件>` 起子进程；
4. **只**通过它监听的本地 HTTP 接口（`http://127.0.0.1:<port>/…`）交互。

不改二进制、不做静态/动态链接、不重打包。Terracotta 的 AGPL 例外条款明确：
「程序通过本作品提供的进程间通信接口（如 HTTP API）与未经修改的本作品应用程序
进行交互」不导致本应用被 AGPL 覆盖，前提是**在用户界面明显处标识本作品的版权
信息**——所以「联机」页底部固定展示署名卡片（项目主页 + 许可证 + 日志导出入口），
该卡片不得删除。

## 2. 代码结构

| 文件 | 职责 | HMCL 对应物 |
| --- | --- | --- |
| `lib/services/terracotta/terracotta_metadata.dart` | 版本、各平台包 SHA-512、镜像顺序、节点列表 URL、平台/架构判定 | `TerracottaMetadata` + `assets/terracotta.json` |
| `lib/services/terracotta/terracotta_state.dart` | `/state` 状态模型与解析（含 `index`/`profile_index` 语义） | `TerracottaState` |
| `lib/services/terracotta/terracotta_bundle.dart` | 下载 / 校验 / 解包 / 旧版本清理 / 本地包安装 | `TerracottaBundle` + provider |
| `lib/services/terracotta/terracotta_launcher.dart` | 起子进程、端口文件握手、stdout/stderr 日志泵 | `TerracottaManager#launch` + `GeneralProvider` |
| `lib/services/terracotta/terracotta_control_api.dart` | 本地控制 API 与公共节点列表（走 Rust `HttpFfiService`） | `HttpRequest.GET(...)` 调用点 |
| `lib/services/terracotta/terracotta_manager.dart` | 全局状态机 + `/state` 守护轮询 + 各动作编排 | `TerracottaManager` |
| `lib/screens/instance_multiplayer_tab.dart` | 实例页「联机」Tab 的界面 | `TerracottaControllerPage` |

落盘目录（`AppPaths`）：

```
<数据根>/terracotta/
├── 0.4.2/                     # 当前版本联机核心（官方包解包结果）
│   ├── terracotta-0.4.2-windows-x86_64.exe
│   └── VCRUNTIME140.DLL
├── temp/run-<毫秒时间戳>/http # 每次启动的端口握手文件（JSON: {"port": N}）
└── logs/terracotta-log-*.zip  # 导出给用户/开发者的排错归档
```

## 3. 状态机

状态与 `/state` 返回值一一对应（`state` 字段，`index` 单调递增）：

| 状态 | 触发 | 界面动作 |
| --- | --- | --- |
| `Bootstrap` | 页面首次打开 | 只显示「正在收集信息」 |
| `Uninitialized(hasLegacy)` | 未安装 / 存在旧版本目录 | 「下载联机核心」/「更新联机核心」+ 本地安装 + 第三方下载渠道 |
| `Preparing` | 下载或安装中 | 进度条（下载未知总量时不确定进度）+ 本地安装入口 |
| `Launching` | 起子进程 / 等待端口文件 | 占位进度 |
| `Unknown(port)` | 端口已就绪、尚未取到状态 | 占位进度 |
| `Waiting` | `/state` = `waiting` | 「我想当房主」/「我想当房客」 |
| `HostScanning` | 调 `/state/scanning` 后本地乐观状态 | 「退出」（`/state/ide`） |
| `HostStarting` | `/state` = `host-starting` | 「退出」 |
| `HostOk(room, profiles)` | `/state` = `host-ok` | 邀请码大号展示 + 自动复制 + 玩家列表 + 「退出」 |
| `GuestConnecting` | 调 `/state/guesting` 后本地乐观状态 | 「退出」 |
| `GuestStarting(difficulty)` | `/state` = `guest-starting` | 难度估算提示 + 「退出」 |
| `GuestOk(url, profiles)` | `/state` = `guest-ok` | 备用联机地址（可复制）+ 玩家列表 + 「退出」 |
| `ExceptionState(type)` | `/state` = `exception` | 按类型给出中文原因 + 「重试」+ 导出日志 |
| `Fatal(type)` | 平台不支持 / 下载失败 / 安装失败 / 通讯失败 / 未知 | 可恢复的给「重试」，网络类追加下载渠道 |

要点：

- **UI 假状态**：用户点按钮后先用 `index = -1` 的本地状态显示，等真实快照到达再覆盖；
  真实快照的 `index >= 0` 一定大于 -1，所以不会被挡住。
- **乱序保护**：只接受 `index` 更大的快照（`_pollOnce`），避免并发响应把界面拉回旧状态。
- **玩家列表刷新**：`HostOk/GuestOk` 的 `isForkOf(previous)`（`index - prev.index <= profile_index`）
  表示同一房间的玩家列表更新，界面直接替换列表，不重新「开房」（也不重复复制邀请码）。

## 4. 本地控制 API

联机核心只接受 GET，本应用用到的端点：

```
GET /state                                   → {state, index, room?, url?, difficulty?, type?, profile_index?, profiles?}
GET /state/ide                               → 回到空闲态（退出房间 / 停止扫描）
GET /state/scanning?player=<名>&public_nodes=<url>&public_nodes=<url>…
GET /state/guesting?room=<邀请码>&player=<名>&public_nodes=…
GET /log?fetch=true                          → 联机核心日志（纯文本）
```

- 端口来自启动时写入的端口文件，文件路径由启动器生成在 `<数据根>/terracotta/temp/run-*/http`。
- 公共节点列表来自 `https://terracotta.glavo.site/nodes`（`[{url, region}]`）。
  HMCL 会按机器归属地过滤节点；本应用没有可靠归属地判定，因此**不过滤**，交由联机核心选路。
- 播放器名：本应用不管理 Minecraft 账号，默认取**实例名**（`TerracottaManager.playerName`）。

## 5. 安装与校验

1. 按平台解析 `classifier`（`windows-x86_64` / `windows-arm64` / `macos-*` / `linux-*` / `freebsd-x86_64`）。
2. 依次尝试 4 个下载渠道（国内镜像优先），整包用 Rust `Downloader` 的 `sha512` 参数校验，
   任一渠道失败自动换下一个并删除半成品。
3. 解包在独立 isolate 中完成（`package:archive` 的 `GZipDecoder` + `TarDecoder`），
   逐文件复核 SHA-512；条目名按「末段文件名」匹配以兼容 `./` / `/` 前缀；
   tar 条目逃逸安装目录直接中止；POSIX 平台补 `chmod 755`。
4. 与 HMCL 一致保留 50MB 上限的判断（正常包远小于此值，超限视为异常）。
5. 安装成功后清理 `<数据根>/terracotta/<版本>` 之外、版本号 ≤ 当前版本的旧目录。
6. 也可「从本地安装包安装」：先校验文件名必须等于官方包名（`terracotta-<版本>-<平台>-pkg.tar.gz`），
   再走同一套解包校验；若此时正在下载，则撤销「安装完成后自动启动」的许可（install fence）。

## 6. 进程与轮询

- **应用级单例**：`TerracottaManager.instance`，整个应用只有一个联机核心进程；
  切换实例的「联机」Tab 不会重启它（房间是全局的，一个进程同时只能开/进一个房间）。
- **轮询节律**：页面可见 500ms，不可见 15s（`setActive`）。`TabBarView` 在切换 Tab
  时销毁页面，页面 `dispose` 会把节律降回 15s。
- **通讯失败判定**：连续 5 次 `/state` 失败，或子进程已退出而状态仍依赖该端口 →
  `Fatal(terracotta)`，界面给「重试」（重新起进程）。
- **退出钩子**：`main.dart` 注册 `AppLifecycleListener(onExitRequested: …)`，
  关窗时 `shutdown()` 杀掉子进程，避免孤儿进程继续占用端口。

## 7. 排错

| 现象 | 处置 |
| --- | --- |
| 「未能下载联机核心」 | 检查网络；或从第三方渠道手动下载官方包后「从本地安装包安装」 |
| 「无法与联机核心通讯」 | 点「重试」重启核心；仍失败则「导出联机核心日志」并把 ZIP 反馈给上游 |
| 「房间出现异常」 | 按提示区分房主/房客侧 EasyTier 崩溃、房间已关闭、协议错误 |
| 平台不支持 | 需要 Windows 10+ / 64 位；Linux 不支持 LoongArch64 旧世界发行版 |
| 房主开房后好友仍进不来 | 需在 Minecraft 客户端里「对局域网开放」世界；防火墙需允许联机核心出站 |

导出的日志 ZIP 含两份文件：`terracotta.log`（联机核心自身日志）与
`irix-terracotta.log`（本应用捕获的进程 stdout/stderr，最多保留最近 400 行）。

## 8. 测试

```bash
flutter test test/terracotta_state_test.dart        # /state 协议解析、fork 语义
flutter test test/terracotta_bundle_test.dart       # 安装器：摘要校验 / 缺文件 / 篡改 / 旧版本清理
flutter test test/terracotta_manager_test.dart      # 状态机：初始化、开房、加入、乱序、恢复、退出
flutter test test/instance_multiplayer_tab_test.dart # 界面：状态映射、邀请码输入、玩家列表
```

所有测试都用 `test/support/terracotta_fakes.dart` 里的假 API / 假启动器 /
合成核心包，不联网、不下载、不起真实子进程。
