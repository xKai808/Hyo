// /api/hq-push — Mini pushes task results here after each run
// POST with founder token auth
// Body: { agent: "ra"|"sentinel"|..., data: {...}, event: "short message" }

import { getStore, pushEvent, updateSection } from './_hq-store.js';

export default function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      return res.status(405).json({ ok: false, error: 'POST only' });
    }

    // founder-token auth
    const token = req.headers['x-founder-token'] || req.headers['authorization']?.replace('Bearer ', '');
    const expected = process.env.HYO_FOUNDER_TOKEN;
    if (!expected || token !== expected) {
      return res.status(401).json({ ok: false, error: 'unauthorized' });
    }

    const { agent, data, event } = req.body || {};
    if (!agent) {
      return res.status(400).json({ ok: false, error: 'missing agent' });
    }

    // update section data — always inject lastRun timestamp
    const merged = { lastRun: new Date().toISOString(), ...(data && typeof data === 'object' ? data : {}) };
    updateSection(agent, merged);

    // log event
    if (event) {
      pushEvent(agent, event);
    }

    res.status(200).json({ ok: true, ts: new Date().toISOString() });
  } catch (err) {
    console.error('[hq-push] Error:', err.message, err.stack);
    res.status(500).json({ ok: false, error: 'internal error', detail: err.message });
  }
}
