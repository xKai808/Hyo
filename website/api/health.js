// /api/health — deploy smoke test
// Visit https://www.hyo.world/api/health after deploy to verify
// that Vercel is actually executing serverless functions on this project.

export default function handler(req, res) {
  try {
    res.status(200).json({
      ok: true,
      service: 'hyo-world-api',
      ts: new Date().toISOString(),
      runtime: 'vercel-node',
      founderTokenConfigured: Boolean(process.env.HYO_FOUNDER_TOKEN),
    });
  } catch (err) {
    console.error('[health] Error:', err.message, err.stack);
    res.status(500).json({ ok: false, error: 'internal error', detail: err.message });
  }
}
