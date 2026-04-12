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
  };
}
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
const SECRET = process.env.HYO_FOUNDER_TOKEN || 'hq-fallback-secret';

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
  const action = req.query.action || '';

  // ── AUTH ──
  if (action === 'auth' && req.method === 'POST') {
    const { password } = req.body || {};
    if (!password) return res.status(400).json({ ok: false, error: 'missing password' });

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
