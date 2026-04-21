// /api/v1/track/click — Ra engagement tracking: link click events
//
// Fires when a reader clicks a tracked link in the newsletter.
// Logs a 'clicked' event and 302-redirects to the original URL.
//
// Query params:
//   nid  — newsletter ID (e.g. "newsletter-2026-04-21")
//   li   — link index within newsletter (0-based, for identifying which link)
//   url  — original destination URL (URL-encoded)
//
// Response: 302 redirect to original URL
// Side effect: logs click event to Vercel runtime logs (searchable in dashboard)
//
// Ra I1 Phase 1 — shipped 2026-04-21
// See: agents/ra/PROTOCOL_RA_SELF_IMPROVEMENT.md Part 7 (I1)

import fs from 'fs';

export default function handler(req, res) {
  try {
    const { nid, li, url } = req.query;

    // Validate URL to prevent open redirects
    let destination = null;
    if (url) {
      try {
        const parsed = new URL(decodeURIComponent(url));
        // Only allow http and https redirects
        if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
          destination = parsed.href;
        }
      } catch (e) {
        console.warn('[track/click] invalid url param:', url);
      }
    }

    // Log the click event
    const event = {
      event: 'clicked',
      nid: nid || 'unknown',
      li: li !== undefined ? parseInt(li, 10) : null,
      url: destination,
      ts: new Date().toISOString(),
      ip: req.headers['x-forwarded-for'] || req.socket?.remoteAddress || null,
      ua: req.headers['user-agent'] || null,
    };

    // Write to /tmp engagement events (non-fatal)
    try {
      fs.appendFileSync('/tmp/ra-engagement-events.jsonl', JSON.stringify(event) + '\n');
    } catch (e) {
      console.warn('[track/click] ledger write failed:', e.message);
    }

    // Log to Vercel runtime logs
    console.log('[ra-track] click', JSON.stringify({ nid, li, url: destination?.substring(0, 80) }));

    if (!destination) {
      return res.status(400).json({ ok: false, error: 'missing or invalid url param' });
    }

    // 302 redirect to original URL — reader continues to destination
    res.setHeader('Location', destination);
    res.setHeader('Cache-Control', 'no-store');
    res.status(302).end();
  } catch (err) {
    console.error('[track/click] Error:', err.message);
    // Fail gracefully — redirect to home rather than dead end
    res.setHeader('Location', 'https://hyo.world');
    res.status(302).end();
  }
}
