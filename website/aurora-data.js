// /api/aurora-data
//
// Returns a subscriber's profile and brief list for their personal Aurora page.
//
// GET /api/aurora-data?id=sub_abc123&token=xxxx
//
// Token validation:
//   token = sha256(sub_id + AURORA_TOKEN_SALT)[0:24]
//   AURORA_TOKEN_SALT is set as a Vercel environment variable.
//   If not set, falls back to a hardcoded dev salt (never deploy without the env var).
//
// Response: { ok: true, subscriber: { id, name, interests, delivery, created, lastBriefDate }, briefs: [...] }
//
// Brief files are stored at: data/aurora-briefs/{sub_id}/{YYYY-MM-DD}.md
// Subscriber records at:     data/aurora-subscribers/{sub_id}.json

import { createHash } from 'crypto';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

// Token salt — must match what aurora-subscribe.js uses when generating pageUrl
const TOKEN_SALT = process.env.AURORA_TOKEN_SALT || 'hyo-aurora-dev-salt-change-in-prod';

// Derive token deterministically (same algo as aurora-subscribe.js)
function deriveToken(subId) {
  return createHash('sha256')
    .update(subId + TOKEN_SALT)
    .digest('hex')
    .slice(0, 24);
}

// Locate the data directory relative to the API file.
// In Vercel, __dirname is the api/ folder. Data lives at ../data/
function dataDir() {
  return join(__dirname, '..', 'data');
}

function loadSubscriber(subId) {
  const p = join(dataDir(), 'aurora-subscribers', subId + '.json');
  if (!existsSync(p)) return null;
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

function loadBriefBody(subId, date) {
  const p = join(dataDir(), 'aurora-briefs', subId, date + '.md');
  if (!existsSync(p)) return null;
  try {
    return readFileSync(p, 'utf8');
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (req.method !== 'GET') {
    res.status(405).json({ ok: false, error: 'Method not allowed.' });
    return;
  }

  const { id, token, brief } = req.query;

  // Basic input validation
  if (!id || typeof id !== 'string' || !/^sub_[a-z0-9_]+$/.test(id)) {
    res.status(400).json({ ok: false, error: 'Invalid subscriber id.' });
    return;
  }
  if (!token || typeof token !== 'string' || token.length !== 24) {
    res.status(401).json({ ok: false, error: 'Token required.' });
    return;
  }

  // Token validation — constant-time compare to prevent timing attacks
  const expected = deriveToken(id);
  const tokenBuf   = Buffer.from(token.padEnd(32, '\0').slice(0, 32));
  const expectedBuf = Buffer.from(expected.padEnd(32, '\0').slice(0, 32));
  let match = 0;
  for (let i = 0; i < 32; i++) match |= tokenBuf[i] ^ expectedBuf[i];
  if (match !== 0) {
    res.status(401).json({ ok: false, error: 'Invalid token.' });
    return;
  }

  // Load subscriber record
  const sub = loadSubscriber(id);
  if (!sub) {
    res.status(404).json({ ok: false, error: 'Subscriber not found.' });
    return;
  }
  if (sub.status !== 'active') {
    res.status(403).json({ ok: false, error: 'Subscriber is not active.' });
    return;
  }

  // If ?brief=YYYY-MM-DD, return full markdown for that specific brief
  if (brief) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(brief)) {
      res.status(400).json({ ok: false, error: 'Invalid brief date format.' });
      return;
    }
    const body = loadBriefBody(id, brief);
    if (!body) {
      res.status(404).json({ ok: false, error: 'Brief not found.' });
      return;
    }
    res.status(200).json({ ok: true, date: brief, body });
    return;
  }

  // Return subscriber profile + brief index (no full markdown bodies in index)
  const subscriberOut = {
    id:           sub.id,
    name:         sub.name || '',
    created:      sub.created,
    lastBriefDate: sub.lastBriefDate || null,
    interests:    sub.interests || {},
    delivery:     sub.delivery || {},
  };

  res.status(200).json({
    ok: true,
    subscriber: subscriberOut,
    briefs: (sub.briefs || []).slice().reverse(), // most recent first
  });
}
