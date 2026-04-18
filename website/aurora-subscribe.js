// /api/aurora-subscribe
//
// Accepts interest-intake submissions from website/aurora.html and creates
// a subscriber record.
//
// Returns:
//   { ok: true, id, pageUrl: "/aurora-page.html?id=sub_...&token=xxxx", token: "xxxx" }
//
// Token is derived deterministically:
//   sha256(sub_id + AURORA_TOKEN_SALT)[0:24]
//   AURORA_TOKEN_SALT must be set as a Vercel env var (matches aurora-data.js).
//
// Persistence: logs a structured NEW record line to Vercel function logs.
// The Mini syncs subscribers from those logs into data/aurora-subscribers/{id}.json
// via bin/sync-aurora-subscribers.sh (P1 task).

import { createHash } from 'crypto';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Token salt — must match aurora-data.js
const TOKEN_SALT = process.env.AURORA_TOKEN_SALT || 'hyo-aurora-dev-salt-change-in-prod';

function deriveToken(subId) {
  return createHash('sha256')
    .update(subId + TOKEN_SALT)
    .digest('hex')
    .slice(0, 24);
}

const ALLOWED_TOPICS = new Set([
  'politics', 'finance', 'macro', 'stocks', 'crypto', 'startups', 'tech', 'ai',
  'social-media', 'fashion', 'gossip', 'celebrity', 'film-and-tv', 'music',
  'books', 'gaming', 'sports', 'health', 'fitness', 'food', 'travel',
  'science', 'climate', 'space', 'design', 'architecture', 'real-estate',
  'labor', 'culture-wars', 'education',
]);
const VOICE    = new Set(['gentle', 'balanced', 'sharp']);
const DEPTH    = new Set(['headlines', 'balanced', 'deep-dives']);
const LENGTH   = new Set(['3min', '6min', '12min']);

function newId() {
  return 'sub_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
}

// Minimal profanity / slop filter for the freetext field — just length + a
// handful of patterns. Full moderation is out of scope for MVP.
function sanitizeFreetext(s) {
  if (typeof s !== 'string') return '';
  return s.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 240).trim();
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Method not allowed.' });
    return;
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  body = body || {};

  const email = String(body.email || '').trim().toLowerCase();
  if (!EMAIL_RE.test(email)) {
    res.status(400).json({ ok: false, error: 'Valid email required.' });
    return;
  }

  const rawTopics = Array.isArray(body.topics) ? body.topics : [];
  const topics = Array.from(new Set(
    rawTopics
      .map(t => String(t || '').trim().toLowerCase())
      .filter(t => ALLOWED_TOPICS.has(t))
  ));
  if (topics.length === 0) {
    res.status(400).json({ ok: false, error: 'Pick at least one topic.' });
    return;
  }

  const voice  = VOICE.has(body.voice)   ? body.voice  : 'balanced';
  const depth  = DEPTH.has(body.depth)   ? body.depth  : 'balanced';
  const length = LENGTH.has(body.length) ? body.length : '6min';
  const freetext = sanitizeFreetext(body.freetext);
  const source   = String(body.source || 'unknown').slice(0, 64);

  const id  = newId();
  const now = new Date().toISOString();

  const record = {
    id,
    email,
    created: now,
    status: 'active',
    source,
    interests: { topics, voice, depth, length, freetext },
    delivery: {
      channel: 'email',
      cadence: 'daily',
      sendAt:   '06:30',
      timezone: 'America/Denver',
    },
    lastSent:    null,
    lastBriefId: null,
    history:     [],
  };

  // Derive the subscriber's personal page token
  const token = deriveToken(id);
  const pageUrl = `/aurora-page.html?id=${encodeURIComponent(id)}&token=${encodeURIComponent(token)}`;

  // Structured log line — the Mini syncs from these into data/aurora-subscribers/{id}.json
  console.log('[aurora-subscribe] NEW ' + JSON.stringify(record));

  res.status(200).json({
    ok:      true,
    id,
    token,
    pageUrl,
    message: 'Subscribed. Your Aurora page is ready.',
  });
}
