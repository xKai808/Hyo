// /api/aurora-webhook
//
// Handles Stripe webhooks for Aurora subscription lifecycle.
//
// Events handled:
//   checkout.session.completed    → subscriber moves from pending_billing → trialing
//   customer.subscription.updated → tracks status changes (trialing → active → canceled)
//   customer.subscription.deleted → subscriber canceled/churned
//   invoice.payment_failed        → payment failed after trial
//
// Env vars required:
//   STRIPE_SECRET_KEY      — Stripe secret key
//   STRIPE_WEBHOOK_SECRET  — Stripe webhook signing secret (whsec_...)
//   GITHUB_TOKEN           — GitHub PAT with repo write access (for subscriber persistence)
//
// Webhook setup (Stripe dashboard → Developers → Webhooks):
//   URL: https://hyo.world/api/aurora-webhook
//   Events: checkout.session.completed, customer.subscription.updated,
//           customer.subscription.deleted, invoice.payment_failed
//
// Subscriber persistence: reads/writes JSON files in GitHub repo via Contents API.
// Path: agents/sam/website/data/aurora-subscribers/{aurora_sub_id}.json

const STRIPE_SECRET_KEY     = process.env.STRIPE_SECRET_KEY;
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET;
const GITHUB_TOKEN          = process.env.GITHUB_TOKEN;

const GH_OWNER = 'xKai808';
const GH_REPO  = 'Hyo';

// Read a subscriber JSON file from GitHub. Returns {record, sha} or null.
async function readSubscriberFromGitHub(subId) {
  if (!GITHUB_TOKEN || !subId) return null;
  const path = `agents/sam/website/data/aurora-subscribers/${subId}.json`;
  const apiUrl = `https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/contents/${path}`;
  try {
    const resp = await fetch(apiUrl, {
      headers: {
        Authorization: `Bearer ${GITHUB_TOKEN}`,
        Accept: 'application/vnd.github.v3+json',
        'User-Agent': 'aurora-webhook/1.0',
      },
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    const content = Buffer.from(data.content, 'base64').toString('utf8');
    return { record: JSON.parse(content), sha: data.sha };
  } catch (err) {
    console.error('[aurora-webhook] GITHUB_READ_ERROR', subId, err.message);
    return null;
  }
}

// Write (create or update) a subscriber JSON file to GitHub via Contents API.
async function writeSubscriberToGitHub(subId, record, sha, commitMsg) {
  if (!GITHUB_TOKEN) {
    console.warn('[aurora-webhook] GITHUB_TOKEN not set — subscriber not persisted');
    return false;
  }
  const path = `agents/sam/website/data/aurora-subscribers/${subId}.json`;
  const apiUrl = `https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/contents/${path}`;
  try {
    const content = Buffer.from(JSON.stringify(record, null, 2)).toString('base64');
    const putBody = {
      message: commitMsg || `aurora: subscriber ${subId} updated (${record.status})`,
      content,
      branch: 'main',
    };
    if (sha) putBody.sha = sha;

    const putResp = await fetch(apiUrl, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${GITHUB_TOKEN}`,
        Accept: 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        'User-Agent': 'aurora-webhook/1.0',
      },
      body: JSON.stringify(putBody),
    });

    if (putResp.ok) {
      console.log('[aurora-webhook] GITHUB_WRITE_OK ' + JSON.stringify({ subId, path, status: record.status }));
      return true;
    } else {
      const errText = await putResp.text();
      console.error('[aurora-webhook] GITHUB_WRITE_FAIL ' + JSON.stringify({
        subId, httpStatus: putResp.status, error: errText.slice(0, 200),
      }));
      return false;
    }
  } catch (err) {
    console.error('[aurora-webhook] GITHUB_WRITE_ERROR', subId, err.message);
    return false;
  }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed.' });
    return;
  }

  if (!STRIPE_SECRET_KEY || !STRIPE_WEBHOOK_SECRET) {
    console.error('[aurora-webhook] Missing Stripe env vars');
    res.status(503).end();
    return;
  }

  // Read raw body for signature verification
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const rawBody = Buffer.concat(chunks).toString('utf8');
  const sig     = req.headers['stripe-signature'];

  let event;
  try {
    const { default: Stripe } = await import('stripe');
    const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2024-06-20' });
    event = stripe.webhooks.constructEvent(rawBody, sig, STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('[aurora-webhook] Signature verification failed:', err.message);
    res.status(400).json({ error: 'Webhook signature invalid.' });
    return;
  }

  const obj = event.data.object;

  switch (event.type) {
    case 'checkout.session.completed': {
      // Trial has started — subscriber is confirmed, move pending_billing → trialing
      const subId                = obj.metadata?.aurora_sub_id;
      const token                = obj.metadata?.aurora_token;
      const email                = obj.customer_email;
      const stripeCustomerId     = obj.customer;
      const stripeSubscriptionId = obj.subscription;
      const now                  = new Date().toISOString();

      console.log('[aurora-webhook] TRIALING ' + JSON.stringify({
        subId, email, stripeCustomerId, stripeSubscriptionId, token,
        event: 'checkout.session.completed',
        timestamp: now,
      }));

      if (subId) {
        const existing = await readSubscriberFromGitHub(subId);
        if (existing) {
          // Update existing pending_billing record
          const updated = {
            ...existing.record,
            status: 'trialing',
            stripeCustomerId,
            stripeSubscriptionId,
            trialStarted: now,
          };
          await writeSubscriberToGitHub(
            subId, updated, existing.sha,
            `aurora: ${subId} → trialing (checkout.session.completed)`
          );
        } else {
          // Subscriber record missing (checkout write may have failed) — create it now
          const fallback = {
            id: subId,
            email,
            created: now,
            status: 'trialing',
            source: 'aurora.html',
            stripeCustomerId,
            stripeSubscriptionId,
            trialStarted: now,
            interests: {},
            delivery: { channel: 'page', cadence: 'daily', sendAt: '06:30', timezone: 'America/Denver' },
            lastBriefDate: null,
            briefs: [],
          };
          await writeSubscriberToGitHub(
            subId, fallback, null,
            `aurora: ${subId} → trialing (fallback create on webhook)`
          );
        }
      }
      break;
    }

    case 'customer.subscription.updated': {
      const subId  = obj.metadata?.aurora_sub_id;
      const status = obj.status; // trialing, active, past_due, canceled, unpaid
      const now    = new Date().toISOString();

      console.log('[aurora-webhook] SUBSCRIPTION_UPDATED ' + JSON.stringify({
        subId, stripeSubId: obj.id, status,
        trialEnd: obj.trial_end ? new Date(obj.trial_end * 1000).toISOString() : null,
        currentPeriodEnd: new Date(obj.current_period_end * 1000).toISOString(),
        event: 'customer.subscription.updated',
        timestamp: now,
      }));

      if (subId) {
        const existing = await readSubscriberFromGitHub(subId);
        if (existing) {
          const updated = {
            ...existing.record,
            status,
            stripeSubscriptionId: obj.id,
            subscriptionUpdatedAt: now,
            trialEnd: obj.trial_end ? new Date(obj.trial_end * 1000).toISOString() : existing.record.trialEnd,
            currentPeriodEnd: new Date(obj.current_period_end * 1000).toISOString(),
          };
          await writeSubscriberToGitHub(
            subId, updated, existing.sha,
            `aurora: ${subId} → ${status} (subscription.updated)`
          );
        } else {
          console.warn('[aurora-webhook] SUBSCRIBER_NOT_FOUND for update:', subId);
        }
      }
      break;
    }

    case 'customer.subscription.deleted': {
      const subId = obj.metadata?.aurora_sub_id;
      const now   = new Date().toISOString();

      console.log('[aurora-webhook] CANCELED ' + JSON.stringify({
        subId, stripeSubId: obj.id,
        canceledAt: obj.canceled_at ? new Date(obj.canceled_at * 1000).toISOString() : now,
        event: 'customer.subscription.deleted',
        timestamp: now,
      }));

      if (subId) {
        const existing = await readSubscriberFromGitHub(subId);
        if (existing) {
          const updated = {
            ...existing.record,
            status: 'canceled',
            canceledAt: obj.canceled_at ? new Date(obj.canceled_at * 1000).toISOString() : now,
            stripeSubscriptionId: obj.id,
          };
          await writeSubscriberToGitHub(
            subId, updated, existing.sha,
            `aurora: ${subId} → canceled (subscription.deleted)`
          );
        } else {
          console.warn('[aurora-webhook] SUBSCRIBER_NOT_FOUND for cancel:', subId);
        }
      }
      break;
    }

    case 'invoice.payment_failed': {
      const stripeSubId = obj.subscription;
      const subId       = obj.lines?.data?.[0]?.metadata?.aurora_sub_id;  // best-effort
      const email       = obj.customer_email;
      const attempt     = obj.attempt_count;
      const now         = new Date().toISOString();

      console.log('[aurora-webhook] PAYMENT_FAILED ' + JSON.stringify({
        stripeSubId, subId, email, attempt,
        event: 'invoice.payment_failed',
        timestamp: now,
      }));

      // Update subscriber record if we can identify them
      if (subId) {
        const existing = await readSubscriberFromGitHub(subId);
        if (existing) {
          const updated = {
            ...existing.record,
            status: 'payment_failed',
            paymentFailedAt: now,
            paymentAttemptCount: attempt,
          };
          await writeSubscriberToGitHub(
            subId, updated, existing.sha,
            `aurora: ${subId} → payment_failed (attempt ${attempt})`
          );
        }
      }
      break;
    }

    default:
      // Ignore unhandled events
      break;
  }

  res.status(200).json({ received: true });
}
