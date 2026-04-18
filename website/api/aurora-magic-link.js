// /api/aurora-magic-link
//
// Magic link sign-in for Aurora subscribers.
//
// POST { email: "user@example.com" }
//
// Flow:
//   1. Validate email
//   2. Find subscriber record by email in data/aurora-subscribers/
//   3. Generate their pageUrl: /aurora-page?id=SUB_ID&token=TOKEN
//   4a. If RESEND_API_KEY configured → send email with magic link
//   4b. If not configured (dev mode) → return pageUrl directly in response
//
// Response (email sent):  { ok: true }
// Response (dev mode):    { ok: true, pageUrl: "..." }
// Response (not found):   { ok: false, error: "..." }

import { createHash } from 'crypto';
import { readdirSync, readFileSync, existsSync } from 'fs';
import { join } from 'path';

const TOKEN_SALT = process.env.AURORA_TOKEN_SALT || 'hyo-aurora-dev-salt-change-in-prod';
const RESEND_API_KEY = process.env.RESEND_API_KEY || '';
const BASE_URL = process.env.NEXT_PUBLIC_BASE_URL || 'https://www.hyo.world';

function dataDir() {
  return join(__dirname, '..', 'data');
}

function deriveToken(subId) {
  return createHash('sha256')
    .update(subId + TOKEN_SALT)
    .digest('hex')
    .slice(0, 24);
}

function findSubscriberByEmail(email) {
  const dir = join(dataDir(), 'aurora-subscribers');
  if (!existsSync(dir)) return null;
  try {
    const files = readdirSync(dir).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const sub = JSON.parse(readFileSync(join(dir, file), 'utf8'));
        if (sub.email && sub.email.toLowerCase() === email.toLowerCase()) {
          return sub;
        }
      } catch { /* skip */ }
    }
  } catch { /* dir not readable */ }
  return null;
}

async function sendMagicLinkEmail(email, name, pageUrl) {
  if (!RESEND_API_KEY) return false;

  const firstName = (name || '').split(' ')[0] || 'there';

  const body = {
    from: 'Aurora <aurora@hyo.world>',
    to: [email],
    subject: 'Your Aurora sign-in link',
    html: `
      <div style="background:#0a0a12;color:#f2e2c4;font-family:'Inter',sans-serif;padding:48px 32px;max-width:520px;margin:0 auto;border-radius:16px;">
        <div style="font-family:'Syne',sans-serif;font-size:26px;font-weight:800;color:#e8b877;margin-bottom:8px;">Aurora</div>
        <p style="margin:0 0 24px;color:rgba(242,226,196,0.7);font-size:13px;letter-spacing:0.08em;text-transform:uppercase;font-family:'DM Mono',monospace;">your morning brief</p>
        <p style="margin:0 0 20px;font-size:16px;line-height:1.7;">Hi ${firstName},</p>
        <p style="margin:0 0 28px;font-size:15px;line-height:1.8;color:rgba(242,226,196,0.85);">
          Here's your Aurora sign-in link. Click it to access your briefs:
        </p>
        <a href="${pageUrl}" style="display:inline-block;background:#e8b877;color:#0a0a12;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:700;font-size:15px;font-family:'Syne',sans-serif;letter-spacing:0.03em;">
          Open Aurora →
        </a>
        <p style="margin:28px 0 0;font-size:13px;color:rgba(242,226,196,0.45);line-height:1.7;">
          If you didn't request this, you can safely ignore it.<br>
          This link is permanent — bookmark it for quick access.
        </p>
        <hr style="border:none;border-top:1px solid rgba(242,226,196,0.1);margin:32px 0 20px;" />
        <p style="font-size:12px;color:rgba(242,226,196,0.35);font-family:'DM Mono',monospace;">
          <a href="${BASE_URL}" style="color:rgba(242,226,196,0.35);text-decoration:none;">hyo.world</a>
        </p>
      </div>
    `,
    text: `Hi ${firstName},\n\nHere's your Aurora sign-in link:\n${pageUrl}\n\nBookmark it for quick access.\n\nhyo.world`
  };

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify(body),
  });

  return response.ok;
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

  const { email } = req.body || {};

  // Validate
  if (!email || typeof email !== 'string') {
    res.status(400).json({ ok: false, error: 'Email required.' });
    return;
  }
  const emailClean = email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailClean)) {
    res.status(400).json({ ok: false, error: 'Invalid email address.' });
    return;
  }

  // Look up subscriber
  const sub = findSubscriberByEmail(emailClean);
  if (!sub) {
    // Don't reveal if email exists or not — return generic message
    // But in dev mode without email sending, we can be explicit
    if (!RESEND_API_KEY) {
      res.status(404).json({ ok: false, error: 'No Aurora subscription found for this email. Subscribe at /aurora.' });
    } else {
      // In prod: always return ok to prevent email enumeration
      res.status(200).json({ ok: true });
    }
    return;
  }

  if (sub.status !== 'active') {
    res.status(403).json({ ok: false, error: 'Your subscription is not active. Contact support at hello@hyo.world.' });
    return;
  }

  // Generate magic link
  const token  = deriveToken(sub.id);
  const pageUrl = `${BASE_URL}/aurora-page?id=${encodeURIComponent(sub.id)}&token=${encodeURIComponent(token)}`;

  // Try to send email
  if (RESEND_API_KEY) {
    const sent = await sendMagicLinkEmail(emailClean, sub.name || '', pageUrl);
    if (sent) {
      res.status(200).json({ ok: true });
    } else {
      // Email failed — fall back to returning URL (better than nothing)
      res.status(200).json({ ok: true, pageUrl });
    }
  } else {
    // Dev mode: return the URL directly so it can be displayed in the browser
    res.status(200).json({ ok: true, pageUrl, devMode: true });
  }
}
