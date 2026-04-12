// /api/register-founder
// Founder-only registration endpoint. Bypasses the Stripe-gated public
// flow and mints a Hyo-operated agent directly into the registry.
//
// Auth: constant-time compare against HYO_FOUNDER_TOKEN env var.
// Storage MVP: logs the full manifest to Vercel function logs and returns
// the generated agentId. Canonical manifest is committed to the Mini at
// ~/Documents/Projects/Hyo/NFT/agents/{handle}.hyo.json by the operator
// or by a follow-up process (Kai on the Mini).
//
// Follow-up: swap this for a writeable store (Vercel KV, Supabase, or a
// GitHub commit via @octokit) once the registry goes live.

import { timingSafeEqual } from 'node:crypto';

const RESERVED_ARCHETYPES = new Set([
  'herald', 'scribe', 'scout', 'sentinel',
  'oracle', 'broker', 'artisan', 'steward',
]);

const VALID_TIERS = new Set(['founding', 'trusted', 'earning', 'probation']);
const VALID_PRICING = new Set(['per-job', 'retainer', 'hybrid', 'internal']);
const VALID_RUNS_ON = new Set(['mini', 'cowork', 'external']);
const VALID_SIDES = new Set(['HUMAN', 'AGENT']);

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const ab = Buffer.from(a, 'utf8');
  const bb = Buffer.from(b, 'utf8');
  if (ab.length !== bb.length) return false;
  try { return timingSafeEqual(ab, bb); } catch { return false; }
}

function validateHandle(h) {
  if (typeof h !== 'string') return 'Handle must be a string.';
  if (h.length < 1 || h.length > 64) return 'Handle must be 1–64 characters.';
  if (!/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/.test(h)) {
    return 'Handle must be lowercase alphanumeric with optional hyphens (not leading/trailing).';
  }
  return null;
}

export default async function handler(req, res) {
  // CORS (permissive for now; lock down once we know the deploy origin)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Method not allowed.' });
    return;
  }

  const expected = process.env.HYO_FOUNDER_TOKEN;
  if (!expected) {
    res.status(500).json({
      ok: false,
      error: 'Server misconfigured: HYO_FOUNDER_TOKEN not set in environment.',
    });
    return;
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  body = body || {};

  if (!safeEqual(body.token || '', expected)) {
    res.status(401).json({ ok: false, error: 'Invalid founder token.' });
    return;
  }

  // Validate required fields
  const handleErr = validateHandle(body.agent_name);
  if (handleErr) { res.status(400).json({ ok: false, error: handleErr }); return; }

  if (!body.description || body.description.length < 10) {
    res.status(400).json({ ok: false, error: 'Description required (min 10 chars).' });
    return;
  }
  if (!body.endpoint_url) {
    res.status(400).json({ ok: false, error: 'Endpoint URL required.' });
    return;
  }

  const tier = VALID_TIERS.has(body.initial_tier) ? body.initial_tier : 'founding';
  const pricing = VALID_PRICING.has(body.pricing_model) ? body.pricing_model : 'internal';
  const runsOn = VALID_RUNS_ON.has(body.runs_on) ? body.runs_on : 'mini';
  const side = VALID_SIDES.has(body.side) ? body.side : 'HUMAN';
  const archetype = RESERVED_ARCHETYPES.has(body.archetype) ? body.archetype : 'herald';

  const handle = body.agent_name;
  const fullHandle = handle + '.hyo';
  const agentId = 'agent_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
  const createdAt = new Date().toISOString();

  const manifest = {
    $schema: 'https://hyo.world/schemas/agent/v1.json',
    agentId,
    name: fullHandle,
    version: '1.0.0',
    created: createdAt.slice(0, 10),
    registry: {
      chain: 'base',
      chainId: 8453,
      testnet: { chain: 'base-sepolia', chainId: 84532 },
      contract: 'HyoRegistry',
      tokenStandard: 'ERC-721',
      status: 'pending-mint',
      founding: true,
      feesWaived: true,
      gasSubsidized: true,
      mintPath: 'founder-register',
    },
    identity: {
      displayName: body.display_name || handle,
      handle: fullHandle,
      tagline: body.tagline || '',
      description: body.description,
      archetype,
      operator: 'hyo',
      runsOn,
    },
    credit: {
      tier,
      probationExempt: tier === 'founding',
      escrowHold: !(tier === 'founding' || tier === 'trusted'),
      score: null,
    },
    pricing: {
      model: pricing,
      rate: Number(body.rate || 0),
      currency: 'USD',
      billedTo: pricing === 'internal' ? 'hyo' : 'customer',
    },
    endpoint: body.endpoint_url,
    visual: { side },
    metadata: {
      external_url: 'https://hyo.world/agents/' + handle,
      attributes: [
        { trait_type: 'Archetype', value: archetype },
        { trait_type: 'Tier', value: tier },
        { trait_type: 'Side', value: side },
        { trait_type: 'Origin', value: 'Founder Registry' },
        { trait_type: 'Fees', value: 'Waived' },
        { trait_type: 'Chain', value: 'Base' },
      ],
    },
  };

  // MVP storage: log to Vercel function logs. Retrievable via `vercel logs`.
  // A follow-up will commit manifest to the Mini at
  // ~/Documents/Projects/Hyo/NFT/agents/{handle}.hyo.json
  console.log('[founder-register] MINT', JSON.stringify({ agentId, handle: fullHandle, tier }));
  console.log('[founder-register] MANIFEST', JSON.stringify(manifest));

  res.status(200).json({
    ok: true,
    agentId,
    handle: fullHandle,
    tier,
    manifest,
    next: {
      saveToMini: `~/Documents/Projects/Hyo/NFT/agents/${handle}.hyo.json`,
      status: 'logged to Vercel function logs; pending mint on Base',
    },
  });
}
