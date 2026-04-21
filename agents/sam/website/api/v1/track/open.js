// /api/v1/track/open — Ra engagement tracking: email open events
//
// Fires when an email client renders the tracking pixel injected by render.py.
// Logs an 'opened' event and returns a 1x1 transparent GIF.
//
// Query params:
//   nid  — newsletter ID (e.g. "newsletter-2026-04-21")
//
// Response: 1x1 transparent GIF (standard tracking pixel response)
// Side effect: appends to agents/ra/ledger/engagement.jsonl via HQ push
//
// Ra I1 Phase 1 — shipped 2026-04-21
// See: agents/ra/PROTOCOL_RA_SELF_IMPROVEMENT.md Part 7 (I1)

import path from 'path';
import fs from 'fs';

// 1x1 transparent GIF (base64-decoded bytes)
const PIXEL_GIF = Buffer.from(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
  'base64'
);

export default function handler(req, res) {
  try {
    const { nid } = req.query;

    // Log the open event
    const event = {
      event: 'opened',
      nid: nid || 'unknown',
      ts: new Date().toISOString(),
      ip: req.headers['x-forwarded-for'] || req.socket?.remoteAddress || null,
      ua: req.headers['user-agent'] || null,
    };

    // Write to engagement ledger (Vercel serverless: use /tmp, then sync via hq-push)
    const tmpLog = '/tmp/ra-engagement-events.jsonl';
    try {
      fs.appendFileSync(tmpLog, JSON.stringify(event) + '\n');
    } catch (e) {
      // Non-fatal: log to console, continue serving pixel
      console.warn('[track/open] ledger write failed:', e.message);
    }

    // Log to Vercel runtime logs (searchable in Vercel dashboard)
    console.log('[ra-track] open', JSON.stringify({ nid, ts: event.ts }));

    // Return 1x1 transparent GIF — no caching so pixel fires every time
    res.setHeader('Content-Type', 'image/gif');
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.status(200).end(PIXEL_GIF);
  } catch (err) {
    console.error('[track/open] Error:', err.message);
    // Still return pixel even on error — don't break email rendering
    res.setHeader('Content-Type', 'image/gif');
    res.status(200).end(PIXEL_GIF);
  }
}
