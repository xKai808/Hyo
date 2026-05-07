// /api/aurora-retention
//
// Day 7 retention email for Aurora trial subscribers.
// Identifies subscribers whose trial started 6-8 days ago and sends a single
// retention email via Resend API. Marks subscribers to prevent re-sends.
//
// Call daily via Mini launchd cron:
//   kai exec "curl -sf -X POST https://www.hyo.world/api/aurora-retention \
//     -H 'Content-Type: application/json' \
//     -d '{\"auth\":\"<FOUNDER_TOKEN>\"}'"
//
// Env vars required (Vercel project settings):
//   HYO_FOUNDER_TOKEN  — auth gate (required)
//   GITHUB_TOKEN       — GitHub PAT with repo write access (required)
//   RESEND_API_KEY     — Resend.com API key for email delivery (required for send)
//   AURORA_FROM_EMAIL  — sender address (default: Aurora <aurora@hyo.world>)
//   AURORA_BASE_URL    — base URL for links (default: https://www.hyo.world)
//
// Subscriber JSON fields used:
//   trialStarted       — ISO timestamp when trial began (set by webhook)
//   retentionEmailSent — boolean, set to true after send
//   retentionEmailSentAt — ISO timestamp of send
//   status             — must be 'trialing' or 'active'
//   email              — recipient address
//   id                 — subscriber ID for page link
//   interests          — used to personalize subject line

const FOUNDER_TOKEN    = process.env.HYO_FOUNDER_TOKEN;
const GITHUB_TOKEN     = process.env.GITHUB_TOKEN;
const RESEND_API_KEY   = process.env.RESEND_API_KEY;
const FROM_EMAIL       = process.env.AURORA_FROM_EMAIL || 'Aurora <aurora@hyo.world>';
const BASE_URL         = process.env.AURORA_BASE_URL   || 'https://www.hyo.world';

const GH_OWNER = 'xKai808';
const GH_REPO  = 'Hyo';
const GH_API   = 'https://api.github.com';
const SUB_PATH = 'agents/sam/website/data/aurora-subscribers';

// Day 7 window: 6.0 – 8.0 days after trialStarted
const MIN_DAYS = 6.0;
const MAX_DAYS = 8.0;

const GH_HEADERS = () => ({
  Authorization: `Bearer ${GITHUB_TOKEN}`,
  Accept: 'application/vnd.github.v3+json',
  'User-Agent': 'aurora-retention/1.0',
  'Content-Type': 'application/json',
});

// ── GitHub helpers ──────────────────────────────────────────────────────────

async function listSubscriberFiles() {
  const url = `${GH_API}/repos/${GH_OWNER}/${GH_REPO}/contents/${SUB_PATH}`;
  const resp = await fetch(url, { headers: GH_HEADERS() });
  if (!resp.ok) throw new Error(`GitHub list failed: ${resp.status}`);
  const files = await resp.json();
  return Array.isArray(files) ? files.filter(f => f.name.endsWith('.json') && f.name !== 'sub_example.json') : [];
}

async function readSubscriber(file) {
  const resp = await fetch(file.url, { headers: GH_HEADERS() });
  if (!resp.ok) return null;
  const data = await resp.json();
  const content = Buffer.from(data.content, 'base64').toString('utf8');
  return { record: JSON.parse(content), sha: data.sha, path: file.path };
}

async function markRetentionSent(path, sha, record, timestamp) {
  const updated = {
    ...record,
    retentionEmailSent: true,
    retentionEmailSentAt: timestamp,
  };
  const content = Buffer.from(JSON.stringify(updated, null, 2)).toString('base64');
  const url = `${GH_API}/repos/${GH_OWNER}/${GH_REPO}/contents/${path}`;
  const putResp = await fetch(url, {
    method: 'PUT',
    headers: GH_HEADERS(),
    body: JSON.stringify({
      message: `aurora: retention email sent to ${record.id}`,
      content,
      sha,
      branch: 'main',
    }),
  });
  if (!putResp.ok) {
    const err = await putResp.text();
    throw new Error(`GitHub write failed: ${putResp.status} ${err.slice(0, 100)}`);
  }
  return updated;
}

// ── Email helpers ───────────────────────────────────────────────────────────

function daysSince(isoTimestamp) {
  if (!isoTimestamp) return Infinity;
  const then = new Date(isoTimestamp).getTime();
  const now  = Date.now();
  return (now - then) / (1000 * 60 * 60 * 24);
}

function isEligible(record) {
  if (record.retentionEmailSent) return false;
  if (!['trialing', 'active'].includes(record.status)) return false;
  if (!record.email) return false;
  const days = daysSince(record.trialStarted);
  return days >= MIN_DAYS && days <= MAX_DAYS;
}

function buildEmailHtml(record) {
  const topics = (record.interests?.topics || []).slice(0, 3).join(', ') || 'the topics you care about';
  const pageUrl = `${BASE_URL}/aurora-page?id=${record.id}`;
  const trialDays = Math.round(daysSince(record.trialStarted));

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Aurora — Day ${trialDays} of Your Trial</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0a0a0a; color: #e8e8e8; margin: 0; padding: 0; }
  .container { max-width: 580px; margin: 40px auto; padding: 0 20px; }
  .header { border-bottom: 1px solid #222; padding-bottom: 24px; margin-bottom: 32px; }
  .logo { font-size: 20px; font-weight: 700; color: #fff; letter-spacing: -0.5px; }
  .logo span { color: #d4a373; }
  h1 { font-size: 26px; font-weight: 700; color: #fff; line-height: 1.3; margin: 0 0 16px; }
  p { font-size: 16px; line-height: 1.7; color: #b0b0b0; margin: 0 0 20px; }
  .highlight { color: #e8e8e8; }
  .cta-block { background: #141414; border: 1px solid #2a2a2a; border-radius: 12px; padding: 28px; margin: 32px 0; text-align: center; }
  .cta-btn { display: inline-block; background: #d4a373; color: #0a0a0a; font-weight: 700; font-size: 15px; padding: 14px 32px; border-radius: 8px; text-decoration: none; letter-spacing: 0.3px; }
  .footer { border-top: 1px solid #1a1a1a; padding-top: 20px; margin-top: 40px; }
  .footer p { font-size: 13px; color: #555; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <div class="logo">Aurora<span>.</span></div>
  </div>

  <h1>Day ${trialDays}. Still with us?</h1>

  <p>Your Aurora trial is at the halfway mark. By now you've seen what a brief built around <span class="highlight">${topics}</span> actually looks like — not a firehose of links, but a curated read you can finish before coffee gets cold.</p>

  <p>Most news apps are built for volume. Aurora is built for you. The same curation, the same voice, every day — until it becomes the one thing you actually open.</p>

  <p>Your trial runs 5 days. No charge until then, and you can cancel anytime. If it's not working for you, just let it expire — no action needed.</p>

  <div class="cta-block">
    <p style="margin-bottom:16px; color:#e8e8e8; font-weight:600;">Read today's brief →</p>
    <a href="${pageUrl}" class="cta-btn">Open My Aurora</a>
  </div>

  <p style="font-size:14px; color:#555;">Questions? Just reply to this email.</p>

  <div class="footer">
    <p>Aurora by hyo.world · You're on a 5-day free trial · <a href="${BASE_URL}/aurora" style="color:#555;">Manage subscription</a></p>
  </div>
</div>
</body>
</html>`;
}

function buildEmailText(record) {
  const topics = (record.interests?.topics || []).slice(0, 3).join(', ') || 'the topics you care about';
  const pageUrl = `${BASE_URL}/aurora-page?id=${record.id}`;
  const trialDays = Math.round(daysSince(record.trialStarted));

  return `Aurora — Day ${trialDays} of Your Trial

Day ${trialDays}. Still with us?

Your Aurora trial is at the halfway mark. By now you've seen what a brief built around ${topics} actually looks like — not a firehose of links, but a curated read you can finish before coffee gets cold.

Most news apps are built for volume. Aurora is built for you. The same curation, the same voice, every day — until it becomes the one thing you actually open.

Your trial runs 5 days. No charge until then, and you can cancel anytime. If it's not working for you, just let it expire — no action needed.

Read today's brief: ${pageUrl}

---
Aurora by hyo.world · 5-day free trial`;
}

async function sendViaResend(to, subject, html, text) {
  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: FROM_EMAIL, to, subject, html, text }),
  });
  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`Resend API error ${resp.status}: ${err.slice(0, 200)}`);
  }
  return await resp.json();
}

// ── Handler ─────────────────────────────────────────────────────────────────

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'POST only' });
    return;
  }

  // Auth gate
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch { body = {}; } }
  if (!FOUNDER_TOKEN || body?.auth !== FOUNDER_TOKEN) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  if (!GITHUB_TOKEN) {
    res.status(503).json({ error: 'GITHUB_TOKEN not configured' });
    return;
  }

  const dryRun  = body?.dry_run === true;
  const results = { sent: [], skipped: [], errors: [], dryRun };
  const now     = new Date().toISOString();

  let files;
  try {
    files = await listSubscriberFiles();
  } catch (err) {
    console.error('[aurora-retention] Failed to list subscribers:', err.message);
    res.status(500).json({ error: 'Failed to list subscribers', detail: err.message });
    return;
  }

  console.log(`[aurora-retention] ${files.length} subscriber files found`);

  for (const file of files) {
    let sub;
    try {
      sub = await readSubscriber(file);
    } catch (err) {
      results.errors.push({ file: file.name, error: `read failed: ${err.message}` });
      continue;
    }
    if (!sub) { results.skipped.push({ id: file.name, reason: 'unreadable' }); continue; }

    const { record, sha, path } = sub;

    if (!isEligible(record)) {
      results.skipped.push({ id: record.id, reason: `not eligible (status:${record.status}, sent:${record.retentionEmailSent}, days:${daysSince(record.trialStarted).toFixed(1)})` });
      continue;
    }

    const topics = (record.interests?.topics || []).slice(0, 2).join(' & ') || 'your interests';
    const subject = `Day 7 of your Aurora trial — still working for you?`;
    const html = buildEmailHtml(record);
    const text = buildEmailText(record);

    if (dryRun) {
      results.sent.push({ id: record.id, email: record.email, subject, dryRun: true });
      console.log(`[aurora-retention] DRY_RUN would send to ${record.email}`);
      continue;
    }

    if (!RESEND_API_KEY) {
      console.warn(`[aurora-retention] RESEND_API_KEY not set — cannot send to ${record.email}`);
      results.errors.push({ id: record.id, error: 'RESEND_API_KEY not configured' });
      continue;
    }

    try {
      const sendResult = await sendViaResend(record.email, subject, html, text);
      console.log(`[aurora-retention] SENT to ${record.email} — resend id: ${sendResult.id}`);

      // Mark subscriber as sent (write to GitHub)
      await markRetentionSent(path, sha, record, now);

      results.sent.push({ id: record.id, email: record.email, resendId: sendResult.id });
    } catch (err) {
      console.error(`[aurora-retention] SEND_ERROR ${record.email}:`, err.message);
      results.errors.push({ id: record.id, email: record.email, error: err.message });
    }
  }

  console.log(`[aurora-retention] COMPLETE — sent:${results.sent.length} skipped:${results.skipped.length} errors:${results.errors.length}`);

  res.status(200).json({
    ok: true,
    summary: { sent: results.sent.length, skipped: results.skipped.length, errors: results.errors.length },
    results,
  });
}
