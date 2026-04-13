# Hyo Deployment Checklist — Phase 1 (hyo.world live on Vercel)
Prepared by: Kai | Date: 2026-04-08 (nightly consolidation)
Code location: ~/Documents/Projects/Kai/github/

---

## What's Already Done

- [x] Domain: hyo.world registered (Namecheap)
- [x] Supabase: live, 7 tables configured
- [x] Stripe: configured, 4 products / 3 plans
- [x] Smart contract: HyoRegistry.sol written
- [x] Frontend: 4-page registration flow + payment.html
- [x] Backend: Next.js API routes written (checkout.js, webhook.js, check-name.js, resolve.js)
- [x] Libs: stripe.js, supabase.js

---

## Phase 1: Deploy to Vercel (what's needed now)

### 1. GitHub repo (OPERATOR TASK)
Operator creates empty repo: `github.com/[username]/hyo`
→ Shares URL with Kai
→ Kai prepares push instructions

### 2. Push code to GitHub (Kai prepares, operator executes)
```bash
cd ~/Documents/Projects/Kai/github
git init
git add .
git commit -m "Initial commit — Hyo backend v1"
git remote add origin https://github.com/[username]/hyo.git
git branch -M main
git push -u origin main
```

### 3. Vercel deployment
- Go to vercel.com → Add New Project → Import from GitHub
- Select the hyo repo
- Framework: Next.js (auto-detected)
- Root directory: / (or where package.json is)

### 4. Environment variables (add in Vercel dashboard)
```
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
NEXT_PUBLIC_SUPABASE_URL=https://[project].supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

### 5. Stripe webhook
- Stripe dashboard → Webhooks → Add endpoint
- URL: https://hyo.world/api/webhook
- Events: checkout.session.completed, invoice.payment_failed, customer.subscription.deleted

### 6. Domain connection
- Vercel dashboard → Project → Settings → Domains
- Add: hyo.world
- In Namecheap DNS: add Vercel's CNAME records

### 7. Test
- [ ] Visit hyo.world — frontend loads
- [ ] Enter a .hyo name → check-name.js returns availability
- [ ] Complete a test checkout (Stripe test mode)
- [ ] Verify webhook fires → Supabase agent record created

---

## Phase 2: Smart Contract Deployment (deferred)

- Deploy HyoRegistry.sol to Ethereum testnet first
- Verify contract, test minting
- Mainnet deployment requires operator approval + gas funds

---

## Blockers Summary

| Blocker | Who | Status |
|---------|-----|--------|
| GitHub repo creation | Operator | WAITING |
| Stripe live keys | Operator | Need to verify in vault |
| Supabase prod keys | Operator | Need to verify in vault |
| Vercel account | Operator | Need to confirm exists |

---

## Notes for Kai at Next Session

- Once GitHub URL is provided, immediately prepare the git push commands
- Vercel free tier is sufficient for Phase 1 (hyo.world traffic will be minimal initially)
- Test with Stripe test mode first, switch to live keys after smoke test passes
- The frontend (payment.html) calls /api/checkout — this will work once deployed to Vercel

*Updated nightly as deployment progresses.*
