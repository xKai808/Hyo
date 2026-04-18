// /api/aurora-checkout
//
// Creates a Stripe Checkout session for Aurora subscriptions.
// Plan: 14-day free trial → $19/mo recurring.
// (Changed from 2-day: research shows AI apps lose 79% of annual subscribers;
//  2 days is insufficient for habit formation. 14 days = 14 briefs = real value assessment.)
//
// Flow:
//   1. aurora.html collects preferences + email
//   2. POST /api/aurora-checkout with {email, topics, voice, depth, length, keywords}
//   3. We save preferences + create Stripe Checkout session
//   4. Return {ok: true, url: 'https://checkout.stripe.com/...'}
//   5. aurora.html redirects to Stripe hosted checkout
//   6. After trial start → Stripe fires webhook to /api/aurora-webhook
//
// Env vars required (Vercel project settings):
//   STRIPE_SECRET_KEY   — Stripe secret key (sk_live_... or sk_test_...)
//   STRIPE_PRICE_ID     — Stripe Price ID for $19/mo recurring (price_...)
//   AURORA_TOKEN_SALT   — must match aurora-subscribe.js + aurora-data.js
//
// Test vs live: use sk_test_ keys during testing, sk_live_ when ready to charge.

import { createHash } from 'crypto';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const TOKEN_SALT = process.env.AURORA_TOKEN_SALT || 'hyo-aurora-dev-salt-change-in-prod';
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
const STRIPE_PRICE_ID   = process.env.STRIPE_PRICE_ID;   // price_xxxxx

const ALLOWED_TOPICS = new Set([
  'politics', 'finance', 'macro', 'stocks', 'crypto', 'startups', 'tech', 'ai',
  'social-media', 'fashion', 'gossip', 'celebrity', 'film-and-tv', 'music',
  'books', 'gaming', 'sports', 'health', 'fitness', 'food', 'travel',
  'science', 'climate', 'space', 'design', 'architecture', 'real-estate',
  'labor', 'culture-wars', 'education',
]);
const VOICE  = new Set(['gentle', 'balanced', 'sharp']);
const DEPTH  = new Set(['headlines', 'balanced', 'deep-dives']);
const LENGTH = new Set(['3min', '6min', '12min']);

function newId() {
  return 'sub_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
}

function deriveToken(subId) {
  return createHash('sha256')
    .update(subId + TOKEN_SALT)
    .digest('hex')
    .slice(0, 24);
}

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

  // Verify Stripe is configured
  if (!STRIPE_SECRET_KEY || !STRIPE_PRICE_ID) {
    console.error('[aurora-checkout] Missing STRIPE_SECRET_KEY or STRIPE_PRICE_ID');
    res.status(503).json({ ok: false, error: 'Billing not yet configured. Contact us at hyo.world.' });
    return;
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  body = body || {};

  // Validate email
  const email = String(body.email || '').trim().toLowerCase();
  if (!EMAIL_RE.test(email)) {
    res.status(400).json({ ok: false, error: 'Valid email required.' });
    return;
  }

  // Validate preferences
  const rawTopics = Array.isArray(body.topics) ? body.topics : [];
  const topics = Array.from(new Set(
    rawTopics.map(t => String(t || '').trim().toLowerCase()).filter(t => ALLOWED_TOPICS.has(t))
  ));
  if (topics.length === 0) {
    res.status(400).json({ ok: false, error: 'Pick at least one topic.' });
    return;
  }

  const voice    = VOICE.has(body.voice)   ? body.voice   : 'balanced';
  const depth    = DEPTH.has(body.depth)   ? body.depth   : 'balanced';
  const length   = LENGTH.has(body.length) ? body.length  : '6min';
  const freetext = sanitizeFreetext(body.freetext);

  // Create subscriber record (pending billing confirmation)
  const id    = newId();
  const token = deriveToken(id);
  const now   = new Date().toISOString();

  const record = {
    id,
    email,
    created: now,
    status: 'pending_billing',   // → 'trialing' after Stripe webhook
    source: 'aurora.html',
    interests: { topics, voice, depth, length, freetext },
    delivery: {
      channel: 'page',
      cadence: 'daily',
      sendAt: '06:30',
      timezone: 'America/Denver',
    },
    lastBriefDate: null,
    briefs: [],
  };

  // Log for Mini sync
  console.log('[aurora-checkout] PENDING ' + JSON.stringify(record));

  // Build return URLs
  const host       = req.headers['x-forwarded-host'] || req.headers.host || 'hyo.world';
  const protocol   = host.includes('localhost') ? 'http' : 'https';
  const baseUrl    = `${protocol}://${host}`;
  const successUrl = `${baseUrl}/aurora-success?id=${id}&token=${token}`;
  const cancelUrl  = `${baseUrl}/aurora`;

  try {
    // Lazy-import Stripe (only available at runtime in Vercel, not during build)
    const { default: Stripe } = await import('stripe');
    const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2024-06-20' });

    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      payment_method_types: ['card'],
      customer_email: email,
      line_items: [{
        price: STRIPE_PRICE_ID,
        quantity: 1,
      }],
      subscription_data: {
        trial_period_days: 14,
        metadata: {
          aurora_sub_id: id,
          aurora_token:  token,
        },
      },
      metadata: {
        aurora_sub_id: id,
        aurora_token:  token,
      },
      success_url: successUrl,
      cancel_url:  cancelUrl,
    });

    console.log('[aurora-checkout] STRIPE_SESSION ' + JSON.stringify({
      subId:     id,
      sessionId: session.id,
      email,
      created:   now,
    }));

    res.status(200).json({
      ok:  true,
      id,
      url: session.url,  // Redirect to Stripe hosted checkout
    });

  } catch (err) {
    console.error('[aurora-checkout] STRIPE_ERROR', err.message);
    res.status(500).json({ ok: false, error: 'Could not start checkout. Please try again.' });
  }
}
