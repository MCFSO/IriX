# IriX 更新分发 Worker（Cloudflare Workers）

给 IriX 客户端提供**稳定可缓存的更新源**并**代理安装包下载**：国内直连
`api.github.com` 勉强可用、`github.com/releases/download` 经常超时，走
Cloudflare 边缘后检查与下载都稳定得多。

客户端侧的更新逻辑不变（`docs/ota-update.md`），只是把「更新源」换成这个
Worker：列表接口返回 GitHub 兼容字段，`assets[].browser_download_url` 已改写
为 Worker 的 `/dl/…`，`assets[].digest` 保留 GitHub 计算的 SHA-256 供客户端校验。

## 本项目的实际部署（2026-11-14）

| 项 | 值 |
|---|---|
| 生产地址 | **https://update.mcfso.org** |
| Worker 名 | `irix-update-feed`（账号 `1400619125` 的 workers.dev 子域） |
| workers.dev 地址 | `https://irix-update-feed.1400619125.workers.dev`（**国内基本不可用**，见下） |
| 自定义域名 | `update.mcfso.org` → zone `mcfso.org`，证书自动签发 |
| 当前版本 ID | 每次 `deploy` 更新，见 `wrangler deploy` 输出 |

> ⚠️ 为什么必须绑自有域名：`*.workers.dev` 在国内的 DNS 会被污染
> （实测解析到 Facebook 的 `69.63.176.59` / `2a03:2880:f112:83:face:b00c:0:25de`），
> 客户端直接连它只会超时。绑到自有 zone 后走 Cloudflare 正常边缘 IP，实测可用。
>
> 客户端已把 `https://update.mcfso.org` 作为**默认内置源**（`UpdateService.defaultFeedUrl`），
> 仍然保留 GitHub 官方 API 作为兜底。

部署与改绑命令（已执行过的记录）：

```bash
# 部署（token 从环境变量读，别写进仓库）
CLOUDFLARE_ACCOUNT_ID=182f0d4946ec11ab8f29b1a2cbd28bad npx wrangler deploy

# 首次部署后若 workers.dev 未自动启用（wrangler 报 10007）：
#   POST /client/v4/accounts/{account_id}/workers/scripts/irix-update-feed/subdomain
#   {"enabled": true}

# 绑定/改绑自定义域名（Workers Custom Domain，自动建 DNS + 证书）：
#   PUT /client/v4/accounts/{account_id}/workers/domains
#   {"environment":"production","hostname":"update.mcfso.org",
#    "service":"irix-update-feed","zone_id":"<mcfso.org 的 zone id>"}
```

上线验证（2026-11-14 实测）：

| 检查 | 结果 |
|---|---|
| `GET /health` | `200 {"ok":true,...}` |
| `GET /api/latest` | `200`，返回 `Stable-v1.3.0` + 9 个资产，`digest` 原样保留 |
| `GET /api/releases` | `200`，6 条（过滤 draft） |
| `GET /dl/...exe`（`Range: bytes=0-99`） | `206`，100 字节 |
| `HEAD /dl/...exe` | `200`，`Content-Length: 26032108` |
| 完整下载 26 MB + SHA-256 | **PASS**，`f190066c…` 与 GitHub digest 完全一致 |
| 不存在的资产 / 路径穿越 | `404` / `400` |

## 路由

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | 路由说明 |
| GET | `/health` | 健康检查 `{"ok":true}` |
| GET | `/api/releases` | GitHub 兼容发布列表（过滤 draft，保留 prerelease 标记） |
| GET | `/api/latest` | 同上，只留最新一条 |
| GET/HEAD | `/dl/<tag>/<asset>` | 安装包下载：优先 R2，其次代理 GitHub；支持 Range 断点续传 |

`/api/*` 与 `/dl/*` 带边缘缓存（`CACHE_TTL`、安装包 24h immutable），并对
`os`/`arch` 之类的客户端差异不敏感 —— 平台区分由客户端 `selectAsset()` 完成。

## 部署

```bash
cd workers/update-feed
npm install          # 只装 wrangler
npx wrangler login
npx wrangler deploy  # 输出 https://irix-update-feed.<子域>.workers.dev
```

可选：

```bash
# 提高 GitHub API 限额（60/h → 5000/h），只读公共仓库的 fine-grained token 即可
npx wrangler secret put GITHUB_TOKEN

# 绑定自有域名：Cloudflare 控制台 → Workers → 该 Worker → Settings → Domains & Routes
```

## 让客户端用上

两种方式，任选其一（设置里的值优先）：

1. 构建时内置（推荐给正式发行版）：

   ```bash
   flutter build windows --release \
     --dart-define=IRIX_UPDATE_FEED=https://irix-update-feed.<子域>.workers.dev
   ```

2. 运行时配置：IriX →「设置 → 软件更新 → 更新源」填 Worker 根地址，
   保存后自动补 `/api/releases`。留空即回到内置源 / GitHub 官方。

客户端的源顺序固定为：**设置里的源 → 构建内置源 → GitHub 官方 API 兜底**，
任何一环失败都会自动降级，不会阻塞启动。

## 自己托管安装包（可选 R2）

默认代理 GitHub 上的 Release 资产，不需要上传。想把包放到自己的 R2：

1. `wrangler.toml` 里取消注释 `[[r2_buckets]]`，创建 `irix-releases` 桶；
2. 按 `<tag>/<文件名>` 上传：

   ```bash
   npx wrangler r2 object put \
     irix-releases/Stable-v1.3.0/irix-1.3.0-windows-x64.exe \
     --file ./irix-1.3.0-windows-x64.exe
   ```

有同名对象时优先走 R2，缺失则回落到 GitHub 代理（两种方式可并存、可逐版本迁移）。
注意 `/dl/` 长缓存按 tag 不可变设计：**同一 tag 重传同名资产请清缓存或换 tag**。

## 验证

```bash
# 单元测试（不需要网络/wrangler）
node --test test/smoke.test.mjs

# 部署后
curl -s https://<worker>/health
curl -s https://<worker>/api/latest | head -c 400
curl -sI https://<worker>/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe
curl -s -r 0-99 https://<worker>/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe -o /dev/null -w '%{http_code}\n'
```

在 IriX 里「设置 → 软件更新 → 检查更新」应能看到与 GitHub 相同的版本号，
且「当前生效」显示你的 Worker 地址；断网或 Worker 不可用时会自动回退 GitHub。
