// /api/hq — unified HQ endpoint (auth + push + data in ONE lambda)
// This ensures push and data share the same globalThis memory.
//
// Routes (via ?action= query param):
//   POST ?action=auth    { password }           → { ok, token }
//   POST ?action=push    { agent, event, data } → { ok } (founder-token gated)
//   GET  ?action=data                           → { ok, ...store } (session-token gated)
//   GET  (no action)                            → { ok, service: "hq" }

import { createHash, createHmac, timingSafeEqual } from 'crypto';

// ─── In-memory store (shared across requests in the same lambda) ───
if (!globalThis.__hq) {
  globalThis.__hq = {
    events: [],
    ra: {}, aurora: {}, sentinel: {}, cipher: {},
    sim: {}, consolidation: {}, aether: {}, health: {},
    credits: {},
    hyoMessages: [],  // Hyo → Kai inbox (persists during lambda warm period)
  };
}
// Ensure hyoMessages exists on older warm lambdas
if (!globalThis.__hq.hyoMessages) globalThis.__hq.hyoMessages = [];
function getStore() { return globalThis.__hq; }
function pushEvent(agent, msg) {
  const store = getStore();
  store.events.unshift({ ts: new Date().toISOString(), agent, msg });
  if (store.events.length > 100) store.events.length = 100;
}
function updateSection(section, data) {
  const store = getStore();
  if (store[section] !== undefined) {
    Object.assign(store[section], data);
  }
}

// ─── Auth helpers ───
const HQ_PASS_HASH = '0ff6c5c11e95ef67d8ee819553c366dcfa1895cd29592cbd9e4d97b074f0a333';
const SECRET = process.env.HYO_FOUNDER_TOKEN;
if (!SECRET) {
  // Fail loud at startup — a missing env var must never silently downgrade security
  console.error('[hq] FATAL: HYO_FOUNDER_TOKEN env var not set — endpoint refusing all requests');
}

// ─── Rate limiting (in-memory, per-lambda — Vercel serverless) ───
// Limits auth attempts to 10/min per IP to prevent brute-force attacks
if (!globalThis.__hqRateLimit) globalThis.__hqRateLimit = new Map();
function checkRateLimit(ip, max = 10, windowMs = 60000) {
  const now = Date.now();
  const key = `auth:${ip}`;
  const entry = globalThis.__hqRateLimit.get(key) || { count: 0, reset: now + windowMs };
  if (now > entry.reset) { entry.count = 0; entry.reset = now + windowMs; }
  entry.count++;
  globalThis.__hqRateLimit.set(key, entry);
  // Prune old entries occasionally
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

// ─── Handler ───
export default function handler(req, res) {
  // Refuse all requests if secret is not configured
  if (!SECRET) {
    return res.status(503).json({ ok: false, error: 'service misconfigured' });
  }

  const action = req.query.action || '';

  // ── AUTH ──
  if (action === 'auth' && req.method === 'POST') {
    const { password } = req.body || {};
    if (!password) return res.status(400).json({ ok: false, error: 'missing password' });

    // Rate limit auth attempts by IP
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
    // Keep last 200 messages
    if (store.hyoMessages.length > 200) store.hyoMessages.length = 200;

    // Also push to events feed so it appears in store.events
    pushEvent('hyo', `[Hyo→Kai] ${message.trim().slice(0, 80)}`);

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
    return res.status(200).json({ ok: true, service: 'hq', ts: new Date().toISOString() });
  }

  return res.status(400).json({ ok: false, error: 'unknown action' });
}
