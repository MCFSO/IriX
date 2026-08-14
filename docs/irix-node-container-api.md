# irix-node 容器 API 对接文档（Docker + Bastille）

> 目标读者：`irix-node`（Go 守护进程）后端实现者。
> 对接对象：IriX 桌面客户端（Flutter），分支 `4-dockerbastille容器化支持`，
> 客户端容器层代码在 `lib/services/container/` 与 `lib/services/node_api_client.dart`。
>
> 本文档是**客户端与服务端的字段级契约**：客户端只按本文档解析响应，
> 任何字段缺失/命名不符都会直接表现为前端异常（如「发行版大小显示 0」、
> 「无法创建 Jail」）。实现时请以本文档为准逐条核对。

---

## 0. 当前已知问题（请后端优先排查）

| # | 现象 | 客户端侧表现 | 排查点 |
|---|------|-------------|--------|
| 1 | bootstrap 后发行版列表**不显示大小** | 显示 `0 B` | `GET /api/bastille/releases` 响应是否包含 `sizeBytes` 字段（见 §4.1）。客户端只认 `sizeBytes`（数字，字节）。 |
| 2 | **无法创建 Jail** | 面板报错 | ① `POST /api/bastille/jails/create` 的 body 契约（见 §4.2），注意 `vnet` 是字符串 `none|vnet|bridge` 而不是 bool；② 客户端创建成功后**会自动调用 rdr 应用端口**（body 中的 `ports` 是客户端自行调 rdr，不在 create body 里）——若 `/api/bastille/rdr` 端点未实现或 PF 未初始化，客户端会把「Jail 已创建」误报为「创建失败」。 |

---

## 1. 通用约定（与现有 irix-node API 一致）

| 项 | 约定 |
|----|------|
| 基础地址 | `http://<host>:<port>` |
| 认证 | `apikey` 查询参数（本地节点可省略） |
| 请求头 | `X-Requested-With: XMLHttpRequest`（MCSM 必需，irix-node 建议兼容） |
| 请求体 | `application/json; charset=utf-8` |
| 响应体 | 统一 `{ "status": 200, "data": <payload>, "time": <unix_ms> }` |
| 错误 | `status != 200` 时 `data` 为错误消息字符串；HTTP 层错误（4xx/5xx）客户端会转成 `HTTP <code>: <body>` 展示 |
| 字符集 | UTF-8 |

客户端所有请求都带 `apikey` 查询参数（配置了密钥时），响应 `status != 200` 即抛异常并把 `data` 字符串显示给用户。**错误信息请写清楚可读的中文/英文原因**，不要只返回 exit code。

---

## 2. 能力探测

```
GET /api/container/info
```

响应 `data`（Bastille 节点示例）：

```json
{
  "runtime": "bastille",
  "platform": "freebsd",
  "version": "0.13.20250126",
  "available": true
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `runtime` | string | `docker` \| `bastille` |
| `platform` | string | `linux` \| `freebsd` 等（用于节点列表显示能力标签） |
| `version` | string? | 运行时版本（面板右上角显示 `vX.Y.Z`） |
| `available` | bool | false 时客户端整体展示不可用状态 |
| `error` | string? | 不可用原因（可选，展示给用户） |

---

## 3. Docker 端点（Linux 节点）

> 客户端 Docker 侧为「创建时全参数 + 列表/操作」，无热更新端口能力。

### 3.1 列表

```
GET /api/container/ps?all=1
GET /api/image/list
GET /api/volume/list
GET /api/network/list
```

容器条目字段（客户端解析键名，**必须逐字一致**）：

```json
{
  "id": "a1b2c3d4e5f6",
  "name": "mc-server",
  "image": "itzg/minecraft-server:latest",
  "status": "Up 2 hours",
  "state": "running",
  "ports": ["0.0.0.0:25565->25565/tcp"],
  "createdAt": "2026-01-01T00:00:00Z",
  "restartPolicy": "unless-stopped"
}
```

镜像条目：`{ "id", "tags": ["name:tag", ...], "sizeBytes": <int>, "createdAt": "..." }`。
卷条目：`{ "name", "driver", "mountpoint" }`。网络条目：`{ "name", "driver", "subnet" }`。

### 3.2 创建与操作

```
POST   /api/container/create      body: 见下
POST   /api/container/{id}/start | stop | restart | kill
DELETE /api/container/{id}?force=1
POST   /api/container/{id}/clone      body: { "name": "<新名称>" }
POST   /api/container/{id}/limits     body: { "memoryMb"?: int, "cpus"?: int }   // docker update
GET    /api/container/{id}/logs?tail=N          → data 为纯文本日志
POST   /api/container/{id}/exec      body: { "command": "..." }
GET    /api/container/{id}/stats      → { "cpuPercent": double, "memoryBytes": int,
                                           "memoryLimitBytes": int, "netRxBytes": int,
                                           "netTxBytes": int }
```

create body（客户端 `DockerCliBackend.createContainer` / `NodeDockerBackend` 组装，全部可选除 name/image）：

```json
{
  "name": "mc-server",
  "image": "itzg/minecraft-server:latest",
  "command": "java -jar server.jar nogui",
  "ports": ["25565:25565"],
  "volumes": ["/data/mc:/data"],
  "env": { "EULA": "TRUE", "MEMORY": "2G" },
  "restartPolicy": "unless-stopped",
  "memoryLimitMb": 4096,
  "cpus": 4,
  "diskLimitMb": 20480,
  "workdir": "/data"
}
```

命令映射：`docker create --name <name> [-p 每个端口] [-v 每个卷] [-e K=V ...]
[--restart <策略>] [-m <N>m] [--cpus <N>] [--storage-opt size=<N>m] [-w <workdir>] <image> [command...]`。

### 3.3 镜像构建（长任务）

```
POST /api/image/pull        body: { "name": "itzg/minecraft-server:latest" }
POST /api/image/build       body: { "dockerfile": "...", "name": "...", "tag": "..." }
                            → data: { "jobId": "<任务id>" }
GET  /api/image/build-progress?jobId=<id>
                            → data: { "status": "building|done|failed",
                                      "log": ["行1", "行2", ...],
                                      "image": "name:tag" }
DELETE /api/image/{name}
DELETE /api/volume/{name}
```

---

## 4. Bastille 端点（FreeBSD 节点）

> 命令语法以官方文档 latest 为准（bastille.readthedocs.io / docs.bastillebsd.org）。
> 服务端通过 `Process.run('bastille', ...)` 包装；**所有会交互确认的命令必须附加 `-y`**。

### 4.1 发行版列表（问题 #1 所在）

```
GET /api/bastille/releases
```

响应 `data` 为数组，**条目必须包含 `sizeBytes`**（客户端仅认这个键；缺省时面板显示 `0 B`）：

```json
[
  {
    "name": "14.2-RELEASE",
    "version": "14.2-RELEASE",
    "sizeBytes": 524288000,
    "createdAt": "2026-01-01T00:00:00Z"
  }
]
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 发行版名（客户端 `ImageInfo.id`） |
| `version` | string? | 客户端拼标签 `name:version`，缺省显示 `name:RELEASE` |
| `sizeBytes` | **int（必填）** | 发行版目录占用字节数，可 `du -sm` 换算；**这是当前面板唯一显示的大小来源** |
| `createdAt` | string? | ISO-8601 时间，可选 |

### 4.2 创建 Jail（问题 #2 所在）

```
POST /api/bastille/jails/create
```

body（客户端 `NodeBastilleBackend.createContainer` 组装的**完整实际字段**，字段类型务必核对）：

```json
{
  "name": "mc-jail",
  "release": "14.2-RELEASE",
  "ip": "192.168.1.50/24",
  "type": "thin",
  "vnet": "none",
  "interface": null,
  "volumes": [],
  "workdir": null,
  "memoryLimitMb": null,
  "cpus": null,
  "diskLimitMb": null
}
```

| 字段 | 类型 | 取值 | 服务端命令映射 |
|------|------|------|---------------|
| `name` | string | Jail 名（客户端已校验 `^(?=.*[a-zA-Z])[a-zA-Z0-9_-]+$`，**不能为纯数字**——纯数字会被 jail(8) 当作 jid 解析） | 位置参数 NAME |
| `release` | string | 已 bootstrap 的发行版；**`type=empty` 时可为空串** | 位置参数 RELEASE |
| `ip` | string | 显式必填（empty 除外）；VNET 时必须含 `/掩码` | 位置参数 IP |
| `type` | string | `thin`(默认) \| `thick` \| `clone` \| `empty` \| `linux` | thin 无标志；`-T`/`-C`/`-E`/`-L` |
| `vnet` | **string** | `none` \| `vnet` \| `bridge`（**不是 bool！**） | `none` 无标志；`vnet`→`-V`；`bridge`→`-B` |
| `interface` | string? | VNET 时必填：`vnet` 模式为物理网卡、`bridge` 模式为桥接网卡 | 位置参数 INTERFACE |
| `volumes` | string[] | 数据目录挂载 `"宿主机路径:jail内路径"` | 创建后逐条 `bastille mount <name> <host> <jailpath> nullfs` |
| `workdir` | string? | 容器内工作目录（如 `/data`） | 设置 jail `exec.start` 的 cwd（cd 到该目录执行启动命令） |
| `memoryLimitMb` | int? | 内存上限（MB） | `bastille limits <name> add memoryuse <N>M` |
| `cpus` | int? | CPU 核数（服务端换算为 cpuset 列表 `0..N-1`） | `bastille limits <name> cpu 0..N-1` |
| `diskLimitMb` | int? | 磁盘上限（MB） | ZFS：`zfs set quota=<N>M`（jail 数据集）；UFS 可忽略并返回提示 |

约束（官方文档依据）：

- `thin/thick/clone/empty/linux` 互斥；`linux` 与任何 VNET 模式互斥（客户端已挡，服务端可再校验）。
- VNET 时 IP 必须含子网掩码（官方：非 VNET 可省略，VNET 强制）。
- `bastille create -E NAME` 仅需名称（客户端在 empty 时 release/ip 可能为空，服务端不要因此 400）。

**⚠️ 客户端创建后会自动应用端口转发**：面板「端口映射」字段（如 `25565:25565`）不在 create body 里，而是 create 成功后客户端逐条调用 `POST /api/bastille/rdr`。如果 rdr 端点缺失或 PF 未初始化，客户端会报「创建失败」——**但 Jail 其实已经建好**。请服务端保证 rdr 端点存在；PF 未配置时返回带说明的错误消息。

### 4.3 生命周期

```
POST /api/bastille/jails/{name}/start | stop | restart
POST /api/bastille/jails/{name}/destroy?force=1
    → bastille destroy -y [-a] <name>
      force=1（客户端删除时恒传）→ 附加 -a（可摧毁运行中的 jail）；-y 恒附加
POST /api/bastille/jails/{name}/clone     body: { "newName": "...", "ip": "192.168.1.51/24" }
    → bastille clone <name> <newName> [ip]
GET  /api/bastille/jails/{name}/console?tail=N   → data 为纯文本日志尾部
POST /api/bastille/jails/{name}/cmd       body: { "command": "..." }  → bastille cmd / jexec
GET  /api/bastille/jails/{name}/config    → jail.conf 属性（客户端预留）
GET  /api/bastille/jails/{name}/mounts    → 挂载列表（客户端预留）
```

jail 列表 `GET /api/bastille/jails` 条目字段（客户端解析键名）：

```json
{
  "name": "mc-jail",
  "release": "14.2-RELEASE",
  "status": "Up",
  "state": "running",
  "ports": ["tcp 25565 -> 25565"],
  "createdAt": "2026-01-01T00:00:00Z"
}
```

> 客户端用 `status` 判断运行态（含 `up` 即视为运行）；`release` 用于展示「镜像/发行版」列。

### 4.4 Bootstrap / 模板（长任务）

```
POST /api/bastille/bootstrap      body: { "release": "14.2-RELEASE" }
    → 可同步执行（bastille bootstrap 本身耗时）；若异步，返回 data: { "jobId": "..." }
GET  /api/bastille/templates      → [{ "namespace", "name", ... }]
POST /api/bastille/templates/apply body: { "jail", "template", "args": {"KEY": "VALUE"} }
```

### 4.5 端口转发（rdr）

```
POST   /api/bastille/rdr     body: { "jail": "mc-jail", "proto": "tcp",
                                     "hostPort": 25565, "jailPort": 25565 }
    → bastille rdr <jail> tcp|udp <hostPort> <jailPort>
DELETE /api/bastille/rdr     body: 同上
    → 官方 CLI 无单条删除：读 `bastille rdr <jail> list` → `bastille rdr <jail> clear` → 重放其余规则
GET    /api/bastille/rdr?jail=<name>?
    → data 数组，条目：{ "jail": "mc-jail", "proto": "tcp", "hostPort": 25565, "jailPort": 25565 }
```

### 4.6 导入 / 导出

```
POST /api/bastille/jails/{name}/export
    → bastille export --txz <name> /usr/local/bastille/backups/<name>_<ts>.txz
    → data: { "path": "/usr/local/bastille/backups/mc-jail_20260101_120000.txz" }
POST /api/bastille/jails/import     body: { "file": "/path/archive.txz",
                                             "release": "14.2-RELEASE",   // 可选
                                             "force": false }              // 可选，-f 跳过校验和
    → bastille import [-f] <file> [release]
    → data: { "name": "<导入后的 jail 名>" }
```

### 4.7 环境初始化（bastille setup）

```
POST /api/bastille/setup     body: { "mode": "firewall", "extIf": "em0", "tunIf": null, "addr": null }
    → data: { "ok": true, "detail": "<命令输出摘要>" }
```

| mode | 服务端命令 | 参数 |
|------|-----------|------|
| `default` | `bastille setup -y`（自动 loopback+firewall+storage） | 无 |
| `firewall` | `bastille setup firewall` | `extIf` 外网网卡（可选） |
| `vnet` | `bastille setup vnet` | `extIf`/`tunIf`/`addr`（部分版本交互式，可 `-y` + stdin 注入或提示用户手动执行） |
| `bridge` | `bastille setup bridge` | 无 |
| `shared` | `bastille setup shared` | `extIf` 网卡 |
| `linux` | `bastille setup linux`（加载内核模块 + 安装 debootstrap） | 无 |

### 4.8 节点级归档（编排系统跨物理机迁移存档用）

> 客户端编排引擎（xmc_orchestrator）的迁移状态机执行「压缩 → 传输 → 恢复」时
> 调用以下节点级端点。**与实例无关**（不需要 uuid）：操作任意宿主机路径。
> 存档传输以桌面客户端为中继（源节点下载 → 目标节点上传）。

```
POST /api/container/archive          body: { "path": "/data/mc/world", "archive"?: "world_s1_0.zip" }
                                     → data: { "path": "/usr/local/bastille/backups/world_s1_0.zip" }
                                     （服务端在节点上压缩 path 为 zip；archive 缺省自动命名）
GET  /api/container/archive?file=<归档名>
                                     → 原始二进制（非 JSON 信封，直接返回文件字节）
POST /api/container/archive/upload   multipart 字段 "file"（原始字节）→ data: { "path": "<保存路径>" }
POST /api/container/archive/restore  body: { "file": "<归档名>", "destPath": "/data/mc/world" }
                                     （服务端解压归档到 destPath，覆盖式恢复）
```

实现提示：压缩/解压可用系统 `zip`/`tar`（FreeBSD 自带），或复用 zip 库；
`GET archive` 与 `POST upload` 为原始字节传输，不走统一 JSON 信封。

---

## 5. 自测清单（curl 示例，假设 apikey=KEY）

```bash
# 1. 能力探测
curl "http://<node>:<port>/api/container/info?apikey=KEY"

# 2. 发行版列表 —— 必须含 sizeBytes（问题 #1）
curl "http://<node>:<port>/api/bastille/releases?apikey=KEY"

# 3. 创建 Jail —— 用客户端真实 body 验证（问题 #2）
curl -X POST "http://<node>:<port>/api/bastille/jails/create?apikey=KEY" \
  -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  -d '{"name":"mc-test","release":"14.2-RELEASE","ip":"192.168.1.50/24","type":"thin","vnet":"none","interface":null,"volumes":[],"workdir":null,"memoryLimitMb":null,"cpus":null,"diskLimitMb":null}'

# 4. rdr（创建后客户端会自动调用）
curl -X POST "http://<node>:<port>/api/bastille/rdr?apikey=KEY" \
  -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  -d '{"jail":"mc-test","proto":"tcp","hostPort":25565,"jailPort":25565}'
```

预期：全部返回 `status: 200`；任何一步非 200，前端对应功能即报错。

---

## 6. 客户端侧已确认的容错行为（后端无需处理，仅知悉）

- 发行版 `sizeBytes` 缺失时面板显示 `0 B`（**计划改为显示 `—`**，等后端确认字段后落地）。
- 创建 Jail 时 rdr 失败会中断整个创建流程（**计划改为「创建成功后 rdr 失败仅提示、不中断」**，等后端确认 rdr 可用性后落地）。
- 客户端不会调用本文档以外的 Bastille 命令；`kill` 对 Bastille 回退为 `stop`；Docker 不支持热端口管理（create 时指定）。

## 7. 变更记录

| 日期 | 变更 |
|------|------|
| 2026-01 | 初版：Docker + Bastille 全端点契约（分支 `4-dockerbastille容器化支持`，commit `a2cef12` 起） |
