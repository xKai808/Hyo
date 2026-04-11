// /api/marketplace-request
// Receives premium-handle requests from marketplace.html.
// MVP: validates input, logs to Vercel function logs, returns a ticket id.
// Follow-up: route to email, Slack, or a queue for auction scheduling.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function classifyTier(handle) {
  if (!handle) return 0;
  const v = handle.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (v.length === 1) return 1;
  if (v.length === 2) return 2;
  if (v.length === 3) return 3;
  return 0;
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

  const handle = (body.handle || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const email = (body.email || '').trim();
  const bid = Number(body.bid || 0);
  const why = (body.why || '').slice(0, 2000);

  if (!handle)        { res.status(400).json({ ok: false, error: 'Handle required.' }); return; }
  if (!EMAIL_RE.test(email)) { res.status(400).json({ ok: false, error: 'Valid email required.' }); return; }

  const tier = classifyTier(handle);
  if (tier === 0) {
    res.status(400).json({
      ok: false,
      error: 'Not a premium handle. Use the regular registration flow for 4+ character handles.',
    });
    return;
  }

  const ticketId = 'mkt_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
  const ticket = {
    ticketId,
    handle: handle + '.hyo',
    tier,
    bidUsd: bid,
    email,
    why,
    receivedAt: new Date().toISOString(),
    status: 'queued',
  };

  console.log('[marketplace-request] NEW', JSON.stringify(ticket));

  res.status(200).json({
    ok: true,
    ticketId,
    handle: ticket.handle,
    tier,
    message: tier === 3
      ? 'Three-letter fixed-price request received. Payment instructions sent within 24h.'
      : `Tier-${tier} auction bid queued for next window.`,
  });
}
