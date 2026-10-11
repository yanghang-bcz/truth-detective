'use strict';
/*
 * Truth Detective — 同域后端（静态托管 + AI 分析员代理）
 * =====================================================
 *
 * 为什么需要它：网页版是纯前端 + WASM，**任何写进前端的密钥都等于公开**。
 * 所以 Web 版不再直连 DeepSeek，而是把请求交给这个同域代理，
 * 由它持有密钥、加上约束、再转发给上游。
 *
 *   浏览器/游戏 (wasm)
 *        │  POST /api/analyst   （同域，无需密钥，无 CORS）
 *        ▼
 *   本服务  ── 校验 → 限流 → 配额 → 注入密钥 → 转发
 *        │  HTTPS + Bearer <DEEPSEEK_API_KEY>
 *        ▼
 *   api.deepseek.com
 *        │
 *        ▼  输出再校验（编造编号 / 直接给答案 / 空答复）后原样返回给游戏
 *   游戏里的 AiResponseValidator 还会再验一次（泄题检查依赖"已解锁"状态）
 *
 * 设计取舍：
 *   · 零依赖。只用 node: 内置模块 —— 部署沙箱里不需要 npm install，
 *     少一个环节就少一种"线上跑不起来"的可能。
 *   · 系统提示词**钉死**。请求里的 system 必须是我们自己那一段，
 *     否则 400。这让本接口无法被当成"免费通用大模型"使用。
 *   · 密钥只来自服务端（环境变量或同目录密钥文件），从不回传给前端，
 *     也从不出现在日志里。
 *
 * 环境变量：
 *   PORT                  监听端口（部署平台注入）
 *   DEEPSEEK_API_KEY      上游密钥（优先）
 *   TD_DAILY_LIMIT        每日全局调用上限，默认 400
 *   TD_IP_WINDOW_SEC     单 IP 限流窗口秒数，默认 300
 *   TD_IP_MAX            单 IP 窗口内最大请求数，默认 12
 */

const http = require('node:http');
const https = require('node:https');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = __dirname;
const PORT = Number(process.env.PORT || 3000);
const BIND = '0.0.0.0';

const UPSTREAM_HOST = 'api.deepseek.com';
const UPSTREAM_PATH = '/chat/completions';
const MODEL = 'deepseek-chat';
const MAX_TOKENS = 400;         // 与客户端 AiConfig.MAX_TOKENS 对齐
const TEMPERATURE = 0.3;        // 分析不是创作
const UPSTREAM_TIMEOUT_MS = 8500; // 客户端 10s 超时，这里先一步放弃并回明确错误

const BODY_LIMIT_BYTES = 16 * 1024;
const SYSTEM_MAX = 4000;
const USER_MAX = 8000;

const DAILY_LIMIT = Number(process.env.TD_DAILY_LIMIT || 400);
const IP_WINDOW_MS = Number(process.env.TD_IP_WINDOW_SEC || 300) * 1000;
const IP_MAX = Number(process.env.TD_IP_MAX || 12);

/* 系统提示词指纹：只要 system 不以它开头，就不是我们自己的分析员请求。
 * 这是把本接口限制成「分析员专用」、而不是「免费通用 LLM」的关键一条。 */
const SYSTEM_MARKER = 'You are the Reasoning Analyst in Truth Detective.';
const USER_MARKER = 'Current state:';

/* 直接给答案的说法 —— 与 scripts/ai/ai_response_validator.gd 的 ANSWER_PHRASES 保持一致。
 * 这是服务端的兜底：即使客户端被改，脏话术也不会流回玩家。 */
const ANSWER_PHRASES = [
  'correct answer', 'final answer', 'the answer is', 'you should choose',
  'should select', '正确答案', '标准答案', '答案是', '应该选', '应当选',
];

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
};

/* 永不外发：密钥、服务端源码、依赖清单、案件原始数据。 */
const DENY_FILES = new Set(['server.js', 'package.json', 'package-lock.json', 'deepseek.key']);

/* ── 密钥 ───────────────────────────────────────────────────────── */

function loadKey() {
  const fromEnv = (process.env.DEEPSEEK_API_KEY || '').trim();
  if (fromEnv) return fromEnv;
  try {
    const raw = fs.readFileSync(path.join(ROOT, 'deepseek.key'), 'utf8');
    for (const line of raw.split('\n')) {
      const t = line.trim();
      if (!t || t.startsWith('#')) continue;
      const eq = t.indexOf('=');
      const value = (eq === -1 ? t : t.slice(eq + 1)).trim().replace(/^["']|["']$/g, '');
      if (value) return value;
    }
  } catch (_) { /* 没有密钥文件就是没有 */ }
  return '';
}

const API_KEY = loadKey();

/* ── 案件数据：只取证据编号，用于服务端识别「编造证据」 ─────────── */

function loadEvidenceIds() {
  const ids = new Set();
  for (const f of ['case_001.json', 'case_001.zh.json']) {
    const p = path.join(ROOT, 'case', f);
    try {
      const data = JSON.parse(fs.readFileSync(p, 'utf8'));
      for (const card of (data.evidence || [])) {
        if (card && card.id) ids.add(String(card.id).toUpperCase());
      }
    } catch (_) { /* 数据缺失时退化为只做其它检查 */ }
  }
  return ids;
}

const EVIDENCE_IDS = loadEvidenceIds();

/* ── 限流与配额（进程内，重启即清零 —— 够用且不引入依赖） ───────── */

const ipBuckets = new Map();
let dayStamp = new Date().toISOString().slice(0, 10);
let dayCount = 0;

function clientKey(req) {
  const fwd = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  const ip = fwd || req.socket.remoteAddress || 'unknown';
  // 只留哈希前 12 位：既能按来源限流，日志里又不落真实 IP。
  return crypto.createHash('sha256').update(ip).digest('hex').slice(0, 12);
}

function checkRate(key) {
  const now = Date.now();
  const bucket = (ipBuckets.get(key) || []).filter((t) => now - t < IP_WINDOW_MS);
  if (bucket.length >= IP_MAX) return { ok: false, retryAfter: Math.ceil((IP_WINDOW_MS - (now - bucket[0])) / 1000) };
  bucket.push(now);
  ipBuckets.set(key, bucket);
  if (ipBuckets.size > 5000) ipBuckets.clear(); // 防止 Map 无限增长
  return { ok: true, retryAfter: 0 };
}

function checkQuota() {
  const today = new Date().toISOString().slice(0, 10);
  if (today !== dayStamp) { dayStamp = today; dayCount = 0; }
  if (dayCount >= DAILY_LIMIT) return false;
  dayCount += 1;
  return true;
}

/* ── 服务端输出校验 ─────────────────────────────────────────────── */

function validateOutput(text) {
  const body = String(text || '').trim();
  if (!body) return 'empty';
  const lower = body.toLowerCase();
  for (const phrase of ANSWER_PHRASES) {
    if (lower.includes(phrase)) return 'final_answer';
  }
  if (EVIDENCE_IDS.size) {
    const re = /\bE(\d{1,2})\b/g;
    let m;
    while ((m = re.exec(body)) !== null) {
      const id = 'E' + String(m[1]).padStart(2, '0');
      if (!EVIDENCE_IDS.has(id)) return 'unknown_evidence';
    }
  }
  return '';
}

/* ── 日志（脱敏：不落密钥、不落提示词正文、不落真实 IP） ────────── */

function log(fields) {
  const parts = Object.entries(fields).map(([k, v]) => `${k}=${v}`);
  console.log('[api] ' + parts.join(' '));
}

/* ── 上游调用 ───────────────────────────────────────────────────── */

function callUpstream(system, user) {
  return new Promise((resolve) => {
    const payload = JSON.stringify({
      model: MODEL,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      temperature: TEMPERATURE,
      max_tokens: MAX_TOKENS,
      stream: false,
    });

    const req = https.request({
      hostname: UPSTREAM_HOST,
      path: UPSTREAM_PATH,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        Authorization: 'Bearer ' + API_KEY,
      },
      timeout: UPSTREAM_TIMEOUT_MS,
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        if (res.statusCode === 401 || res.statusCode === 403) return resolve({ status: 502, code: 'upstream_auth' });
        if (res.statusCode === 429) return resolve({ status: 429, code: 'upstream_rate' });
        if (res.statusCode !== 200) return resolve({ status: 502, code: 'upstream_' + res.statusCode });
        let parsed;
        try { parsed = JSON.parse(text); } catch (_) { return resolve({ status: 502, code: 'upstream_json' }); }
        const choices = parsed && parsed.choices;
        if (!Array.isArray(choices) || !choices.length) return resolve({ status: 502, code: 'upstream_empty' });
        const content = String((choices[0].message || {}).content || '').trim();
        if (!content) return resolve({ status: 502, code: 'upstream_empty' });
        resolve({ status: 200, content });
      });
    });

    req.on('timeout', () => { req.destroy(); resolve({ status: 504, code: 'upstream_timeout' }); });
    req.on('error', () => resolve({ status: 502, code: 'upstream_network' }));
    req.write(payload);
    req.end();
  });
}

/* ── /api/analyst ───────────────────────────────────────────────── */

function readBody(req) {
  return new Promise((resolve) => {
    const declared = Number(req.headers['content-length'] || 0);
    if (declared > BODY_LIMIT_BYTES) return resolve({ tooLarge: true });
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > BODY_LIMIT_BYTES) { resolve({ tooLarge: true }); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve({ body: Buffer.concat(chunks).toString('utf8') }));
    req.on('error', () => resolve({ tooLarge: true }));
  });
}

function sendJSON(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

async function handleAnalyst(req, res, key) {
  const started = Date.now();
  const rate = checkRate(key);
  if (!rate.ok) {
    log({ event: 'analyst', status: 429, reason: 'ip_rate', src: key, ms: Date.now() - started });
    res.setHeader('Retry-After', String(rate.retryAfter));
    return sendJSON(res, 429, { error: { code: 'rate_limited' } });
  }

  const { tooLarge, body } = await readBody(req);
  if (tooLarge) {
    log({ event: 'analyst', status: 413, reason: 'body_too_large', src: key, ms: Date.now() - started });
    return sendJSON(res, 413, { error: { code: 'body_too_large' } });
  }

  let parsed;
  try { parsed = JSON.parse(body); } catch (_) { parsed = null; }
  if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.messages) || parsed.messages.length !== 2) {
    log({ event: 'analyst', status: 400, reason: 'bad_shape', src: key, ms: Date.now() - started });
    return sendJSON(res, 400, { error: { code: 'bad_request' } });
  }

  const [first, second] = parsed.messages;
  const system = String((first || {}).content || '');
  const user = String((second || {}).content || '');

  if ((first || {}).role !== 'system' || (second || {}).role !== 'user'
      || !system.startsWith(SYSTEM_MARKER) || !user.includes(USER_MARKER)) {
    // 不是本游戏的分析员请求 —— 本接口不是通用大模型入口。
    log({ event: 'analyst', status: 400, reason: 'prompt_mismatch', src: key, ms: Date.now() - started });
    return sendJSON(res, 400, { error: { code: 'not_analyst_request' } });
  }
  if (system.length > SYSTEM_MAX || user.length > USER_MAX) {
    return sendJSON(res, 413, { error: { code: 'prompt_too_long' } });
  }

  if (!API_KEY) {
    log({ event: 'analyst', status: 503, reason: 'no_server_key', src: key, ms: Date.now() - started });
    return sendJSON(res, 503, { error: { code: 'no_server_key' } });
  }
  if (!checkQuota()) {
    log({ event: 'analyst', status: 429, reason: 'daily_quota', src: key, day: dayStamp, count: dayCount, ms: Date.now() - started });
    return sendJSON(res, 429, { error: { code: 'daily_quota_exhausted' } });
  }

  const out = await callUpstream(system, user);
  if (out.status !== 200) {
    log({ event: 'analyst', status: out.status, reason: out.code, src: key, ms: Date.now() - started });
    return sendJSON(res, out.status, { error: { code: out.code } });
  }

  const problem = validateOutput(out.content);
  if (problem) {
    // 模型不守规矩：不回脏内容，让游戏走离线兜底（且不扣玩家次数）。
    log({ event: 'analyst', status: 502, reason: 'blocked_' + problem, src: key, ms: Date.now() - started });
    return sendJSON(res, 502, { error: { code: 'blocked_' + problem } });
  }

  log({ event: 'analyst', status: 200, src: key, chars: out.content.length, ms: Date.now() - started });
  return sendJSON(res, 200, { choices: [{ message: { role: 'assistant', content: out.content } }] });
}

/* ── 静态文件 ───────────────────────────────────────────────────── */

function serveStatic(req, res, urlPath) {
  let rel = decodeURIComponent(urlPath.split('?')[0]);
  if (rel === '/' || rel === '') rel = '/index.html';

  // 案件原始数据只给服务端读（用来识别编造的证据编号），不作为一个可下载的文件暴露。
  // 注：案件内容本来就在 .pck 里（单机推理游戏的固有属性），这里不做过度承诺，
  // 只是不给它开一个额外的明文入口。
  if (rel === '/case' || rel.startsWith('/case/')) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
    return;
  }

  // 目录穿越防护：解析后必须仍在 ROOT 内。
  const target = path.resolve(ROOT, '.' + rel);
  if (!target.startsWith(ROOT + path.sep) && target !== ROOT) {
    res.writeHead(403).end('Forbidden');
    return;
  }

  const base = path.basename(target);
  const ext = path.extname(base).toLowerCase();
  if (base.startsWith('.') || DENY_FILES.has(base) || !MIME[ext]) {
    // 只放白名单后缀，其余（含密钥、服务端源码、案件原始数据）一律看不见。
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
    return;
  }

  fs.stat(target, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
      return;
    }
    const etag = `W/"${st.size}-${Math.floor(st.mtimeMs)}"`;
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304).end();
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[ext],
      'Content-Length': st.size,
      'ETag': etag,
      // 每次都回源校验：发布新版本后用户不必清缓存。
      'Cache-Control': 'no-cache',
      'X-Content-Type-Options': 'nosniff',
    });
    fs.createReadStream(target).pipe(res);
  });
}

/* ── 服务器 ─────────────────────────────────────────────────────── */

const server = http.createServer((req, res) => {
  const urlPath = (req.url || '/').split('?')[0];

  if (urlPath === '/api/analyst') {
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST');
      return sendJSON(res, 405, { error: { code: 'method_not_allowed' } });
    }
    return handleAnalyst(req, res, clientKey(req));
  }

  if (urlPath === '/api/health') {
    return sendJSON(res, 200, {
      ok: true,
      key_configured: Boolean(API_KEY),
      evidence_ids: EVIDENCE_IDS.size,
      daily_limit: DAILY_LIMIT,
      day_count: dayCount,
    });
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return sendJSON(res, 405, { error: { code: 'method_not_allowed' } });
  }
  return serveStatic(req, res, urlPath);
});

server.listen(PORT, BIND, () => {
  console.log(`[server] listening on ${BIND}:${PORT}`);
  console.log(`[server] key_configured=${Boolean(API_KEY)} evidence_ids=${EVIDENCE_IDS.size} daily_limit=${DAILY_LIMIT}`);
  if (!API_KEY) console.warn('[server] 未配置 DEEPSEEK_API_KEY：/api/analyst 会返回 503，游戏将自动走离线规则引擎。');
});
