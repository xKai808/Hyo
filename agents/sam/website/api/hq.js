// /api/hq — unified HQ endpoint (auth + push + data in ONE lambda)
// Sam W2: Vercel KV persistence layer added 2026-04-21
//   - globalThis used as fast in-memory cache (same as before)
//   - On cold start: hydrates from KV if KV_REST_API_URL is configured
//   - On every write: fire-and-forget KV sync (best-effort, never blocks response)
//   - Fallback: if KV not configured or unavailable, behaves exactly as before
//
// To activate persistence: provision Vercel KV in dashboard, then add env vars:
//   KV_REST_API_URL   — from Vercel KV dashboard "REST API" tab
//   KV_REST_API_TOKEN — from same tab (read-write token)
//   See: agents/sam/website/docs/VERCEL_KV_SETUP.md
//
// Routes (via ?action= query param):
//   POST ?action=auth    { password }           → { ok, token }
//   POST ?action=push    { agent, event, data } → { ok } (founder-token gated)
//   GET  ?action=data                           → { ok, ...store } (session-token gated)
//   GET  (no action)                            → { ok, service: "hq", kv_connected }

import { createHash, createHmac, timingSafeEqual } from 'crypto';

// ─── KV persistence layer (activates when KV_REST_API_URL is set) ─────────────
let kv = null;
let kvConnected = false;
const KV_KEY = 'hq:store';

async function initKV() {
  if (!process.env.KV_REST_API_URL) return; // KV not provisioned — silent no-op
  try {
    const mod = await import('@vercel/kv');
    kv = mod.kv;
    kvConnected = true;
    console.log('[hq] Vercel KV connected — state persists across cold starts');
  } catch (e) {
    console.warn('[hq] @vercel/kv not installed or import failed:', e.message);
    console.warn('[hq] Falling back to in-memory store. Run: npm install @vercel/kv in website/');
  }
}

function makeEmptyStore() {
  return {
    events: [],
    ra: {}, aurora: {}, sentinel: {}, cipher: {},
    sim: {}, consolidation: {}, aether: {}, health: {},
    credits: {},
    hyoMessages: [],
  };
}

// Hydrate globalThis from KV on cold start
async function hydrateFromKV() {
  if (!kv || globalThis.__hq) return; // Already warm or KV unavailable
  try {
    const persisted = await kv.get(KV_KEY);
    globalThis.__hq = persisted || makeEmptyStore();
    console.log('[hq] State hydrated from KV (' +
      (globalThis.__hq.events?.length || 0) + ' events loaded)');
  } catch (e) {
    console.warn('[hq] KV hydration failed:', e.message, '— using empty store');
    globalThis.__hq = makeEmptyStore();
  }
}

// Fire-and-forget KV write — never blocks the response
function syncToKV() {
  if (!kv) return;
  kv.set(KV_KEY, globalThis.__hq).catch(e =>
    console.warn('[hq] KV write failed (non-fatal):', e.message)
  );
}

// Initialize KV and hydrate — runs once per cold start (top-level await)
await initKV();
await hydrateFromKV();

// ─── In-memory store (shared across requests in the same lambda) ───────────────
if (!globalThis.__hq) {
  globalThis.__hq = makeEmptyStore();
}
// Ensure hyoMessages exists on older warm lambdas
if (!globalThis.__hq.hyoMessages) globalThis.__hq.hyoMessages = [];

function getStore() { return globalThis.__hq; }
function pushEvent(agent, msg) {
  const store = getStore();
  store.events.unshift({ ts: new Date().toISOString(), agent, msg });
  if (store.events.length > 100) store.events.length = 100;
  syncToKV();
}
function updateSection(section, data) {
  const store = getStore();
  if (store[section] !== undefined) {
    Object.assign(store[section], data);
  }
  syncToKV();
}

// ─── Auth helpers ──────────────────────────────────────────────────────────────
const HQ_PASS_HASH = '0ff6c5c11e95ef67d8ee819553c366dcfa1895cd29592cbd9e4d97b074f0a333';
const SECRET = process.env.HYO_FOUNDER_TOKEN;
if (!SECRET) {
  console.error('[hq] FATAL: HYO_FOUNDER_TOKEN env var not set — endpoint refusing all requests');
}

// ─── Rate limiting (in-memory, per-lambda) ────────────────────────────────────
if (!globalThis.__hqRateLimit) globalThis.__hqRateLimit = new Map();
function checkRateLimit(ip, max = 10, windowMs = 60000) {
  const now = Date.now();
  const key = `auth:${ip}`;
  const entry = globalThis.__hqRateLimit.get(key) || { count: 0, reset: now + windowMs };
  if (now > entry.reset) { entry.count = 0; entry.reset = now + windowMs; }
  entry.count++;
  globalThis.__hqRateLimit.set(key, entry);
  if (globalThis.__hqRateLimit.size > 500) {
    for (const [k, v] of globalThis.__hqRateLimit) {
      if (now > v.reset) globalThis.__hqRateLimit.delete(k);
    }
  }
  return entry.count <= max;
}

function sha256(str) {
  return createHash('sha256').update(str).digest('hex');
}
function makeToken(ts) {
  return createHmac('sha256', SECRET).update(`hq:${ts}`).digest('hex');
}
function verifyToken(token) {
  if (!token) return false;
  try {
    const [ts, sig] = token.split('.');
    if (!ts || !sig) return false;
    const age = Date.now() - parseInt(ts, 36);
    if (age > 86400000 || age < 0) return false;
    const expected = makeToken(ts);
    const a = Buffer.from(sig, 'hex');
    const b = Buffer.from(expected, 'hex');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  } catch { return false; }
}

// ─── Handler ───────────────────────────────────────────────────────────────────
export default function handler(req, res) {
  if (!SECRET) {
    return res.status(503).json({ ok: false, error: 'service misconfigured' });
  }

  const action = req.query.action || '';

  // ── AUTH ──
  if (action === 'auth' && req.method === 'POST') {
    const { password } = req.body || {};
    if (!password) return res.status(400).json({ ok: false, error: 'missing password' });

    const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket?.remoteAddress || 'unknown';
    if (!checkRateLimit(ip, 10, 60000)) {
      return res.status(429).json({ ok: false, error: 'too many requests' });
    }

    const hash = sha256(password);
    const a = Buffer.from(hash, 'hex');
    const b = Buffer.from(HQ_PASS_HASH, 'hex');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      return res.status(401).json({ ok: false, error: 'wrong password' });
    }

    const ts = Date.now().toString(36);
    const sig = makeToken(ts);
    return res.status(200).json({ ok: true, token: `${ts}.${sig}` });
  }

  // ── PUSH (founder-token gated) ──
  if (action === 'push' && req.method === 'POST') {
    const token = req.headers['x-founder-token'] || req.headers['authorization']?.replace('Bearer ', '');
    const expected = process.env.HYO_FOUNDER_TOKEN;
    if (!expected || token !== expected) {
      return res.status(401).json({ ok: false, error: 'unauthorized' });
    }

    const { agent, data, event } = req.body || {};
    if (!agent) return res.status(400).json({ ok: false, error: 'missing agent' });

    const merged = { lastRun: new Date().toISOString(), ...(data && typeof data === 'object' ? data : {}) };
    updateSection(agent, merged);
    if (event) pushEvent(agent, event);

    return res.status(200).json({ ok: true, ts: new Date().toISOString() });
  }

  // ── HYO EXPORT (founder-token gated — Mini pulls messages for persistence) ──
  if (action === 'hyo-export' && req.method === 'GET') {
    const token = req.headers['x-founder-token'] || req.headers['authorization']?.replace('Bearer ', '');
    const expected = process.env.HYO_FOUNDER_TOKEN;
    if (!expected || token !== expected) {
      return res.status(401).json({ ok: false, error: 'unauthorized' });
    }
    const store = getStore();
    return res.status(200).json({
      ok: true,
      ts: new Date().toISOString(),
      hyoMessages: store.hyoMessages || [],
    });
  }

  // ── HYO MESSAGE (session-token gated POST from HQ) ──
  if (action === 'hyo-message' && req.method === 'POST') {
    const token = req.headers['authorization']?.replace('Bearer ', '');
    if (!verifyToken(token)) {
      return res.status(401).json({ ok: false, error: 'unauthorized' });
    }

    const { message } = req.body || {};
    if (!message || typeof message !== 'string' || !message.trim()) {
      return res.status(400).json({ ok: false, error: 'missing message' });
    }

    const store = getStore();
    const entry = {
      ts: new Date().toISOString(),
      from: 'hyo',
      message: message.trim(),
      status: 'unread',
    };
    store.hyoMessages.unshift(entry);
    if (store.hyoMessages.length > 200) store.hyoMessages.length = 200;
    pushEvent('hyo', `[Hyo→Kai] ${message.trim().slice(0, 80)}`);
    syncToKV();

    return res.status(200).json({ ok: true, ts: entry.ts });
  }

  // ── DATA (session-token gated) ──
  if (action === 'data' && req.method === 'GET') {
    const token = req.headers['authorization']?.replace('Bearer ', '');
    if (!verifyToken(token)) {
      return res.status(401).json({ ok: false, error: 'unauthorized' });
    }

    return res.status(200).json({ ok: true, ts: new Date().toISOString(), ...getStore() });
  }

  // ── fallback ──
  if (req.method === 'GET' && !action) {
    return res.status(200).json({
      ok: true,
      service: 'hq',
      ts: new Date().toISOString(),
      kv_connected: kvConnected,
      persistence: kvConnected ? 'vercel-kv' : 'in-memory-only',
    });
  }

  return res.status(400).json({ ok: false, error: 'unknown action' });
}
