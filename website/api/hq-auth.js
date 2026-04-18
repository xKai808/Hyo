// /api/hq-auth — server-side password validation for HQ dashboard
// POST { password } → { ok, token } or { ok: false, error }
// Token is a simple HMAC — good enough for single-user, upgradeable to JWT.

import { createHash, createHmac, timingSafeEqual } from 'crypto';

const HQ_PASS_HASH = '0ff6c5c11e95ef67d8ee819553c366dcfa1895cd29592cbd9e4d97b074f0a333';
const SECRET = process.env.HYO_FOUNDER_TOKEN || 'hq-fallback-secret';

function sha256(str) {
  return createHash('sha256').update(str).digest('hex');
}

function makeToken(ts) {
  return createHmac('sha256', SECRET).update(`hq:${ts}`).digest('hex');
}

export function verifyToken(token) {
  if (!token) return false;
  try {
    const [ts, sig] = token.split('.');
    if (!ts || !sig) return false;
    // tokens expire after 24h
    const age = Date.now() - parseInt(ts, 36);
    if (age > 86400000 || age < 0) return false;
    const expected = makeToken(ts);
    const a = Buffer.from(sig, 'hex');
    const b = Buffer.from(expected, 'hex');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  } catch { return false; }
}

export default function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ ok: false, error: 'POST only' });
  }

  const { password } = req.body || {};
  if (!password) {
    return res.status(400).json({ ok: false, error: 'missing password' });
  }

  const hash = sha256(password);
  // constant-time comparison
  const a = Buffer.from(hash, 'hex');
  const b = Buffer.from(HQ_PASS_HASH, 'hex');
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return res.status(401).json({ ok: false, error: 'wrong password' });
  }

  // issue a 24h token
  const ts = Date.now().toString(36);
  const sig = makeToken(ts);
  const token = `${ts}.${sig}`;

  res.status(200).json({ ok: true, token });
}
