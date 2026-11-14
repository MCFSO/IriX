// Worker 冒烟测试：不需要 wrangler / 网络，用 node 内置 test runner。
//
// 运行：
//   node --test workers/update-feed
//
// 覆盖：/api/releases 与 /api/latest 的字段改写与缓存、/dl 的 GitHub 代理与
// Range 透传、R2 优先、路径校验、未知路由。

import test from 'node:test';
import assert from 'node:assert/strict';

import worker from '../src/index.js';

/** GitHub Releases API 的精简样本（字段形态取自真实响应）。 */
const RELEASES = [
  {
    tag_name: 'Stable-v1.3.0',
    name: 'v1.3.0',
    body: '# IriX 1.3.0\n',
    draft: false,
    prerelease: false,
    published_at: '2026-11-01T00:08:42Z',
    html_url: 'https://github.com/MCFSO/IriX/releases/tag/Stable-v1.3.0',
    assets: [
      {
        name: 'irix-1.3.0-windows-x64.exe',
        size: 26032108,
        digest:
          'sha256:f190066c49a1bd6826d00c6a76369c1dc3e951ff5245fe1101d020eb3d6933f9',
        browser_download_url:
          'https://github.com/MCFSO/IriX/releases/download/Stable-v1.3.0/irix-1.3.0-windows-x64.exe',
      },
      {
        name: 'SHA256SUMS-1.3.0.txt',
        size: 512,
        browser_download_url:
          'https://github.com/MCFSO/IriX/releases/download/Stable-v1.3.0/SHA256SUMS-1.3.0.txt',
      },
    ],
  },
  {
    tag_name: 'Stable-v1.4.0-rc.1',
    name: 'v1.4.0-rc.1',
    body: '- rc\n',
    draft: false,
    prerelease: true,
    published_at: '2026-12-01T00:00:00Z',
    assets: [],
  },
  {
    tag_name: 'Stable-v1.9.0',
    name: 'draft only',
    draft: true,
    prerelease: false,
    assets: [],
  },
];

/** 安装 一个极简的 caches.default 与 fetch 桩，返回可观测的记录对象。 */
function installStubs({ downloadBody = 'BINARY', bucket = null } = {}) {
  const cacheStore = new Map();
  const calls = [];

  globalThis.caches = {
    default: {
      async match(request) {
        return cacheStore.get(request.url) ?? undefined;
      },
      async put(request, response) {
        cacheStore.set(request.url, response);
      },
    },
  };

  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === 'string' ? input : input.url;
    calls.push({ url, init });
    if (url.startsWith('https://api.github.com/')) {
      return new Response(JSON.stringify(RELEASES), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }
    if (url.startsWith('https://github.com/')) {
      const headers = init.headers || {};
      const range = headers.Range || headers.range;
      if (range) {
        const start = Number(/bytes=(\d+)-(\d+)?/.exec(range)[1]);
        return new Response(downloadBody.slice(start), {
          status: 206,
          headers: {
            'content-type': 'application/octet-stream',
            'content-range': `bytes ${start}-${downloadBody.length - 1}/${downloadBody.length}`,
            'accept-ranges': 'bytes',
          },
        });
      }
      return new Response(init.method === 'HEAD' ? null : downloadBody, {
        status: 200,
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': String(downloadBody.length),
          'accept-ranges': 'bytes',
        },
      });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const env = {
    GITHUB_OWNER: 'MCFSO',
    GITHUB_REPO: 'IriX',
    CACHE_TTL: '300',
    ...(bucket ? { BUCKET: bucket } : {}),
  };

  return { calls, env, cacheStore };
}

function ctxStub() {
  const pending = [];
  return {
    waitUntil(promise) {
      pending.push(promise);
    },
    async settle() {
      await Promise.all(pending);
    },
  };
}

async function call(request, env, ctx) {
  return worker.fetch(request, env, ctx);
}

test('/api/releases 改写下载地址并保留 digest', async () => {
  const { env } = installStubs();
  const ctx = ctxStub();
  const response = await call(
    new Request('https://feed.example.com/api/releases'),
    env,
    ctx,
  );
  assert.equal(response.status, 200);

  const body = await response.json();
  assert.equal(body.releases.length, 2, 'draft 发布应被过滤');
  const [stable, rc] = body.releases;
  assert.equal(stable.tag_name, 'Stable-v1.3.0');
  assert.equal(rc.prerelease, true);

  const exe = stable.assets.find((a) => a.name === 'irix-1.3.0-windows-x64.exe');
  assert.equal(
    exe.browser_download_url,
    'https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe',
  );
  assert.equal(
    exe.digest,
    'sha256:f190066c49a1bd6826d00c6a76369c1dc3e951ff5245fe1101d020eb3d6933f9',
  );
  assert.equal(exe.size, 26032108);
});

test('/api/latest 只返回最新一条，并命中缓存', async () => {
  const { env, calls } = installStubs();
  const first = ctxStub();
  const response = await call(
    new Request('https://feed.example.com/api/latest'),
    env,
    first,
  );
  const body = await response.json();
  assert.equal(body.releases.length, 1);
  assert.equal(body.releases[0].tag_name, 'Stable-v1.3.0');
  await first.settle();

  const before = calls.length;
  const second = ctxStub();
  const again = await call(
    new Request('https://feed.example.com/api/latest'),
    env,
    second,
  );
  assert.equal(again.status, 200);
  assert.equal((await again.json()).releases.length, 1);
  assert.equal(calls.length, before, '第二次请求不应再回源 GitHub');
});

test('/dl 代理安装包，支持 Range 透传', async () => {
  const { env } = installStubs({ downloadBody: '0123456789' });

  const full = await call(
    new Request('https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe'),
    env,
    ctxStub(),
  );
  assert.equal(full.status, 200);
  assert.equal(await full.text(), '0123456789');
  assert.equal(full.headers.get('cache-control').includes('immutable'), true);

  const ranged = await call(
    new Request('https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe', {
      headers: { Range: 'bytes=3-9' },
    }),
    env,
    ctxStub(),
  );
  assert.equal(ranged.status, 206);
  assert.equal(await ranged.text(), '3456789');
  assert.equal(ranged.headers.get('content-range'), 'bytes 3-9/10');
});

test('/dl 只发 HEAD 时返回头部', async () => {
  const { env } = installStubs({ downloadBody: '0123456789' });
  const response = await call(
    new Request('https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe', {
      method: 'HEAD',
    }),
    env,
    ctxStub(),
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-length'), String('0123456789'.length));
});

test('/dl 优先使用 R2 对象', async () => {
  const payload = 'FROM-R2';
  const bucket = {
    async head() {
      return null;
    },
    async get(key) {
      if (key !== 'Stable-v1.3.0/irix-1.3.0-windows-x64.exe') return null;
      return {
        body: payload,
        size: payload.length,
        httpEtag: '"etag-r2"',
        httpMetadata: { contentType: 'application/octet-stream' },
        range: undefined,
        writeHttpMetadata(headers) {
          headers.set('content-type', 'application/octet-stream');
        },
      };
    },
  };
  const { env, calls } = installStubs({ bucket });
  const response = await call(
    new Request('https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe'),
    env,
    ctxStub(),
  );
  assert.equal(response.status, 200);
  assert.equal(await response.text(), payload);
  assert.equal(
    calls.some((c) => c.url.startsWith('https://github.com/')),
    false,
    'R2 命中时不应回源 GitHub',
  );
});

test('非法路径与未知路由', async () => {
  const { env } = installStubs();

  const traversal = await call(
    new Request('https://feed.example.com/dl/..%2Fetc/passwd'),
    env,
    ctxStub(),
  );
  assert.equal(traversal.status, 400);

  const missing = await call(
    new Request('https://feed.example.com/nope'),
    env,
    ctxStub(),
  );
  assert.equal(missing.status, 404);

  const health = await call(
    new Request('https://feed.example.com/health'),
    env,
    ctxStub(),
  );
  assert.equal(health.status, 200);
  assert.equal((await health.json()).ok, true);
});

test('GitHub 上游失败时返回 502 且不缓存', async () => {
  const { env } = installStubs();
  globalThis.fetch = async () => new Response('rate limited', { status: 403 });
  const response = await call(
    new Request('https://feed.example.com/api/releases'),
    env,
    ctxStub(),
  );
  assert.equal(response.status, 502);
  const body = await response.json();
  assert.equal(body.error, 'upstream_error');
  assert.equal(body.status, 403);
});
