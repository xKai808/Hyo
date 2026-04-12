// /api/hq-data — dashboard pulls all HQ state
// GET with session token from hq-auth
// Returns the full store snapshot

import { getStore } from './_hq-store.js';
import { verifyToken } from './hq-auth.js';

export default function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ ok: false, error: 'GET only' });
  }

  // verify session token
  const token = req.headers['authorization']?.replace('Bearer ', '');
  if (!verifyToken(token)) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }

  const store = getStore();
  res.status(200).json({
    ok: true,
    ts: new Date().toISOString(),
    ...store,
  });
}
