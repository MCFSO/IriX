/**
 * IriX 更新分发 Worker
 *
 * 作用：给 IriX 客户端提供一个「稳定、可缓存、可自定义域名」的更新源，
 * 并代理安装包下载（国内直连 github.com 常常超时，而 Cloudflare 边缘可达）。
 *
 * 路由：
 *   GET  /                     说明与路由列表
 *   GET  /health               健康检查
 *   GET  /api/releases         GitHub 兼容的发布列表（assets 下载地址改写为本站 /dl/…）
 *   GET  /api/latest           同上，只保留最新一条
 *   GET  /dl/<tag>/<asset>     安装包下载（优先 R2，其次代理 GitHub，支持 Range 断点续传）
 *   HEAD  /dl/<tag>/<asset>    只取头部（大小/范围）
 *
 * 环境变量（wrangler.toml 的 [vars] 或 `wrangler secret put`）：
 *   GITHUB_OWNER       默认 MCFSO
 *   GITHUB_REPO        默认 IriX
 *   GITHUB_TOKEN       可选；填了可把 GitHub API 限额从 60/小时 提到 5000/小时
 *   PER_PAGE           默认 30
 *   CACHE_TTL          列表缓存秒数，默认 300
 *   CACHE_DOWNLOADS    "0" 关闭安装包的边缘缓存（默认开启）
 *
 * 可选 R2 绑定（自己托管安装包时）：
 *   [[r2_buckets]] binding = "BUCKET"  bucket_name = "irix-releases"
 *   对象键名格式：<tag>/<asset 文件名>，例如 Stable-v1.3.0/irix-1.3.0-windows-x64.exe
 *   有 R2 对象时优先用 R2，没有则回落到 GitHub 代理。
 *
 * 说明：
 * - 客户端把本 Worker 根地址填进「设置 → 软件更新 → 更新源」，
 *   或构建时用 --dart-define=IRIX_UPDATE_FEED=https://<worker> 内置。
 * - 返回体是 { releases: [...] }，字段与 GitHub Releases API 对齐，
 *   assets[].browser_download_url 指向本站 /dl/…，assets[].digest 保留
 *   GitHub 计算的 sha256，客户端据此校验安装包完整性。
 * - 安装包按 tag 不可变，所以 /dl/ 响应可以长缓存；改用同名重传时请换 tag。
 */

const DEFAULT_OWNER = 'MCFSO';
const DEFAULT_REPO = 'IriX';
const ALLOWED_SEGMENT = /^[A-Za-z0-9._+-]+$/;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    try {
      if (path === '/') {
        return json(
          {
            name: 'irix-update-feed',
            version: 1,
            routes: [
              'GET /health',
              'GET /api/releases',
              'GET /api/latest',
              'GET /dl/<tag>/<asset>',
            ],
          },
          request,
          200,
          60,
        );
      }

      if (path === '/health') {
        return json({ ok: true, time: new Date().toISOString() }, request, 200, 0);
      }

      if (path === '/api/releases' || path === '/api/latest') {
        return await handleReleases(request, env, ctx, {
          latest: path === '/api/latest',
        });
      }

      const download = /^\/dl\/([^/]+)\/([^/]+)$/.exec(path);
      if (download) {
        return await handleDownload(
          request,
          env,
          ctx,
          decodeURIComponent(download[1]),
          decodeURIComponent(download[2]),
        );
      }

      return json({ error: 'not_found', path }, request, 404, 0);
    } catch (error) {
      return json(
        { error: 'worker_error', message: String((error && error.message) || error) },
        request,
        500,
        0,
      );
    }
  },
};

// ======================== 发布列表 ========================

async function handleReleases(request, env, ctx, { latest }) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return json({ error: 'method_not_allowed' }, request, 405, 0);
  }

  const cache = caches.default;
  const cacheKey = new Request(
    `${new URL(request.url).origin}${latest ? '/api/latest' : '/api/releases'}`,
    { method: 'GET' },
  );
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const owner = env.GITHUB_OWNER || DEFAULT_OWNER;
  const repo = env.GITHUB_REPO || DEFAULT_REPO;
  const perPage = clampInt(env.PER_PAGE, 30, 1, 100);
  const ttl = clampInt(env.CACHE_TTL, 300, 0, 86400);

  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'IriX-UpdateFeed/1 (Cloudflare Worker)',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  if (env.GITHUB_TOKEN) headers.Authorization = `Bearer ${env.GITHUB_TOKEN}`;

  const upstream = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/releases?per_page=${perPage}`,
    { headers, cf: { cacheTtl: ttl, cacheEverything: true } },
  );

  if (!upstream.ok) {
    return json(
      {
        error: 'upstream_error',
        status: upstream.status,
        message: '获取 GitHub Releases 失败',
      },
      request,
      502,
      0,
    );
  }

  const raw = await upstream.json();
  if (!Array.isArray(raw)) {
    return json({ error: 'upstream_format' }, request, 502, 0);
  }

  const origin = new URL(request.url).origin;
  const releases = raw
    .filter((item) => item && item.draft !== true)
    .map((item) => normalizeRelease(item, origin, owner, repo))
    .filter(Boolean);

  const body = {
    source: { owner, repo, kind: 'cloudflare-worker' },
    generated_at: new Date().toISOString(),
    releases: latest ? releases.slice(0, 1) : releases,
  };

  const response = json(body, request, 200, ttl);
  if (ttl > 0) ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

function normalizeRelease(item, origin, owner, repo) {
  const tag = String(item.tag_name || '').trim();
  if (!tag) return null;

  const assets = Array.isArray(item.assets)
    ? item.assets.map((asset) => normalizeAsset(asset, tag, origin)).filter(Boolean)
    : [];

  return {
    tag_name: tag,
    name: item.name || tag,
    body: item.body || '',
    prerelease: item.prerelease === true,
    draft: false,
    published_at: item.published_at || item.created_at || null,
    html_url:
      item.html_url || `https://github.com/${owner}/${repo}/releases/tag/${tag}`,
    assets,
  };
}

function normalizeAsset(asset, tag, origin) {
  const name = String(asset.name || '').trim();
  if (!name) return null;
  return {
    name,
    size: Number(asset.size) || 0,
    digest: typeof asset.digest === 'string' ? asset.digest : undefined,
    updated_at: asset.updated_at || undefined,
    browser_download_url: `${origin}/dl/${encodeURIComponent(tag)}/${encodeURIComponent(name)}`,
    github_url: asset.browser_download_url || undefined,
  };
}

// ======================== 安装包下载 ========================

async function handleDownload(request, env, ctx, tag, assetName) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return json({ error: 'method_not_allowed' }, request, 405, 0);
  }
  if (!ALLOWED_SEGMENT.test(tag) || !ALLOWED_SEGMENT.test(assetName)) {
    return json({ error: 'invalid_path' }, request, 400, 0);
  }

  // 1) 自己托管：优先 R2（存在同名对象时）
  if (env.BUCKET) {
    const fromR2 = await serveFromR2(request, env, tag, assetName);
    if (fromR2) return fromR2;
  }

  // 2) 回落到 GitHub Releases 代理
  return await proxyFromGithub(request, env, ctx, tag, assetName);
}

async function serveFromR2(request, env, tag, assetName) {
  const key = `${tag}/${assetName}`;

  if (request.method === 'HEAD') {
    const head = await env.BUCKET.head(key);
    if (!head) return null;
    const headers = new Headers(corsHeaders());
    headers.set('content-length', String(head.size));
    headers.set('etag', head.httpEtag);
    headers.set('accept-ranges', 'bytes');
    headers.set('cache-control', 'public, max-age=86400, immutable');
    return new Response(null, { status: 200, headers });
  }

  const rangeHeader = request.headers.get('Range');
  const object = await env.BUCKET.get(key, {
    range: rangeHeader ? request.headers : undefined,
  });
  if (!object) return null;

  const headers = new Headers(corsHeaders());
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('accept-ranges', 'bytes');
  headers.set('cache-control', 'public, max-age=86400, immutable');
  if (!headers.has('content-type')) {
    headers.set('content-type', 'application/octet-stream');
  }

  if (object.range && typeof object.range.offset === 'number') {
    const start = object.range.offset;
    const length = object.range.length ?? object.size - start;
    headers.set('content-range', `bytes ${start}-${start + length - 1}/${object.size}`);
    headers.set('content-length', String(length));
    return new Response(object.body, { status: 206, headers });
  }

  headers.set('content-length', String(object.size));
  return new Response(object.body, { status: 200, headers });
}

async function proxyFromGithub(request, env, ctx, tag, assetName) {
  const owner = env.GITHUB_OWNER || DEFAULT_OWNER;
  const repo = env.GITHUB_REPO || DEFAULT_REPO;
  const upstreamUrl =
    `https://github.com/${owner}/${repo}/releases/download/` +
    `${encodeURIComponent(tag)}/${encodeURIComponent(assetName)}`;

  const isHead = request.method === 'HEAD';
  const wantsRange = Boolean(request.headers.get('Range'));
  const cacheable = !isHead && !wantsRange && env.CACHE_DOWNLOADS !== '0';
  const cache = caches.default;
  const cacheKey = new Request(request.url, { method: 'GET' });

  if (cacheable) {
    const cached = await cache.match(cacheKey);
    if (cached) return cached;
  }

  const upstreamHeaders = {
    'User-Agent': 'IriX-UpdateFeed/1 (Cloudflare Worker)',
    Accept: 'application/octet-stream',
  };
  const range = request.headers.get('Range');
  if (range) upstreamHeaders.Range = range;

  const upstream = await fetch(upstreamUrl, {
    method: isHead ? 'HEAD' : 'GET',
    headers: upstreamHeaders,
    redirect: 'follow',
  });

  if (!upstream.ok && upstream.status !== 206) {
    return json(
      {
        error: 'download_failed',
        status: upstream.status,
        tag,
        asset: assetName,
        message: '从 GitHub 获取安装包失败（是否已上传该资产？）',
      },
      request,
      upstream.status === 404 ? 404 : 502,
      0,
    );
  }

  const headers = new Headers();
  for (const name of [
    'content-type',
    'content-length',
    'content-range',
    'accept-ranges',
    'etag',
    'last-modified',
  ]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  if (!headers.has('content-type')) {
    headers.set('content-type', 'application/octet-stream');
  }
  if (!headers.has('accept-ranges')) headers.set('accept-ranges', 'bytes');
  headers.set('access-control-allow-origin', '*');
  headers.set(
    'cache-control',
    cacheable ? 'public, max-age=86400, immutable' : 'public, max-age=300',
  );

  const response = new Response(isHead ? null : upstream.body, {
    status: upstream.status,
    headers,
  });
  if (cacheable && upstream.status === 200) {
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
  }
  return response;
}

// ======================== 工具 ========================

function json(payload, request, status = 200, maxAge = 0) {
  const headers = new Headers(corsHeaders());
  headers.set('content-type', 'application/json; charset=utf-8');
  headers.set(
    'cache-control',
    maxAge > 0 ? `public, max-age=${maxAge}` : 'no-store',
  );
  const body = JSON.stringify(payload, null, 0);
  return new Response(request && request.method === 'HEAD' ? null : body, {
    status,
    headers,
  });
}

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,HEAD,OPTIONS',
    'access-control-allow-headers': 'Range,If-None-Match,Content-Type',
    'access-control-expose-headers': 'Content-Length,Content-Range,ETag',
  };
}

function clampInt(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}
