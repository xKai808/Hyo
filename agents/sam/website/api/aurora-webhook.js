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
//
// Webhook setup (Stripe dashboard → Developers → Webhooks):
//   URL: https://hyo.world/api/aurora-webhook
//   Events: checkout.session.completed, customer.subscription.updated,
//           customer.subscription.deleted, invoice.payment_failed

const STRIPE_SECRET_KEY     = process.env.STRIPE_SECRET_KEY;
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET;

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
      // Trial has started — subscriber is confirmed
      const subId   = obj.metadata?.aurora_sub_id;
      const token   = obj.metadata?.aurora_token;
      const email   = obj.customer_email;
      const stripeCustomerId     = obj.customer;
      const stripeSubscriptionId = obj.subscription;
      console.log('[aurora-webhook] TRIALING ' + JSON.stringify({
        subId, email, stripeCustomerId, stripeSubscriptionId, token,
        event: 'checkout.session.completed',
        timestamp: new Date().toISOString(),
      }));
      break;
    }

    case 'customer.subscription.updated': {
      const subId  = obj.metadata?.aurora_sub_id;
      const status = obj.status; // trialing, active, past_due, canceled, unpaid
      console.log('[aurora-webhook] SUBSCRIPTION_UPDATED ' + JSON.stringify({
        subId, stripeSubId: obj.id, status,
        trialEnd: obj.trial_end ? new Date(obj.trial_end * 1000).toISOString() : null,
        currentPeriodEnd: new Date(obj.current_period_end * 1000).toISOString(),
        event: 'customer.subscription.updated',
        timestamp: new Date().toISOString(),
      }));
      break;
    }

    case 'customer.subscription.deleted': {
      const subId = obj.metadata?.aurora_sub_id;
      console.log('[aurora-webhook] CANCELED ' + JSON.stringify({
        subId, stripeSubId: obj.id,
        canceledAt: new Date(obj.canceled_at * 1000).toISOString(),
        event: 'customer.subscription.deleted',
        timestamp: new Date().toISOString(),
      }));
      break;
    }

    case 'invoice.payment_failed': {
      const stripeSubId = obj.subscription;
      const email       = obj.customer_email;
      const attempt     = obj.attempt_count;
      console.log('[aurora-webhook] PAYMENT_FAILED ' + JSON.stringify({
        stripeSubId, email, attempt,
        event: 'invoice.payment_failed',
        timestamp: new Date().toISOString(),
      }));
      break;
    }

    default:
      // Ignore unhandled events
      break;
  }

  res.status(200).json({ received: true });
}
