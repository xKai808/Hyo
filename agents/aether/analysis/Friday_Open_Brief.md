# Friday 2026-04-10 — Operator Open Brief
Prepared by Kai during nightly consolidation, 2026-04-09 23:30 MDT
Read time: 2 minutes. Execution time: ~15 minutes end to end.
Framing corrected 23:37 MDT — earlier draft misdated this as "Monday 4/13". Tomorrow is Friday, a trading day. Push before the bot opens.

---

## The situation in one line
Every revenue dollar is gated on pushing one commit. Everything else is downstream.

---

## The single highest-impact action (do this first)

**Push Hyo commit `7e2831e` from the Mini.**

Paste-ready:
```bash
cd ~/Documents/Projects/Kai/github && bash push_and_verify.sh
```

The script:
- Verifies working tree is clean
- Confirms branch is `main`
- Fetches origin
- Pushes
- **Verifies the remote SHA actually matches local** (the bridge auto-deploy lied about this four times on 4/9 — do not trust it)
- Prints the Vercel preview URL

If auth fails: rotate the PAT first (see below), then re-run the script.

---

## Secondary: rotate the exposed PAT

The old token `ghp_iBLxl...` was exposed in a Cowork chat transcript on 4/9. It's no longer in `.git/config` (already sanitized), but it's still valid on GitHub's side until you rotate.

1. https://github.com/settings/tokens → revoke the old token
2. Generate a new classic token, scope `repo`
3. On the Mini:
   ```bash
   git config --global credential.helper osxkeychain
   cd ~/Documents/Projects/Kai/github && git push origin main
   # enter username: xKai808
   # enter password: <new token>
   ```
   (Credential helper caches it for future pushes. Do NOT embed in remote URL again.)

---

## After the push lands

In order, ~10 minutes:

1. **Watch Vercel build** — https://vercel.com/dashboard. Should go Ready within ~60s of push.
2. **Verify preview URL** — https://github-eight-kappa.vercel.app should show the dark dual-panel Hyo site (human on left, agent on right). If it shows a Next.js default or a blank page, the stripping didn't take — tell Kai and we debug.
3. **Point DNS** — Namecheap → hyo.world → Advanced DNS → add two CNAMEs:
   - `@` → `cname.vercel-dns.com`
   - `www` → `cname.vercel-dns.com`
4. **Deploy AetherBot v254** — separate from Hyo, but just as important:
   ```bash
   cd ~/Documents/Projects/AetherBot && bash deploy_v254.sh
   ```
5. **Reshuffle Mini cron timing (do this before 19:30 Fri)** — playbook moved analysis from 17:00 to 19:30 but the Mini crons for factcheck/api-check/dashboard are still on the old schedule. Bump them to 19:45 / 20:00 / 20:15. Without this, **tonight's (Fri 4/10)** fact-check will race the analysis and produce a stale cross-check.
6. **Verify heartbeat.md** — still missing for the second day running:
   ```bash
   /opt/homebrew/bin/python3 ~/Documents/Projects/AetherBot/Kai\ analysis/heartbeat.py
   ls ~/Documents/Projects/Kai/memory/heartbeat.md
   ```

---

## Status snapshot

| Thing | State | Blocker |
|---|---|---|
| AetherBot v253 | Running 24/7, trades Friday 4/10, off Sat+Sun | — |
| AetherBot v254 | Built, deploy script ready | Operator runs `bash deploy_v254.sh` |
| Hyo commit `7e2831e` | Staged locally, 1 ahead of origin | This push |
| Hyo DNS | `hyo.world` parked at Namecheap | DNS CNAMEs |
| Stripe env vars | Not in Vercel | Add after push lands |
| Heartbeat monitoring | `heartbeat.md` still missing (day 2) | 30-sec command |
| Mini cron drift | fact-check/api/dashboard still at old 17:xx times | Reshuffle to 19:45/20:00/20:15 |

## Balance ledger
```
3/28 $89.87 | 3/29 $101.25 | 3/30 $90.18
3/31 $110.32 | 4/1 $119.02 | 4/2 $121.02 (peak)
4/3 $111.55 | 4/4 $107.30 | 4/5 $76.18
4/6 $93.04 | 4/7 $104.02 | 4/8 $89.26
4/9 $79.23 (SETTLE RECHECK, T26 open, -$18.88 reconciliation gap)
```

Peak → current: -34.5%. Break-even: $10.06/day. v254 fixes BDI=0 catastrophe (-$17.19 today, 93% of losses) and the harvest-below-entry bug. Low-end projection is +$5.50/day, high-end +$15/day — either way, deployment is urgent.

## 3 open questions for you

1. The bridge auto-deploy script reported "pushed" four times on 4/9 while the commit never actually landed on origin. Do you want me to investigate the bridge script (I'd need it copied into a mount), or replace it entirely with `push_and_verify.sh` + a launchd job that watches for a flag file?
2. We have two paid products ready to sell ("Zero to Autonomous Blueprint" $49, "Agent Economy Report Q2 2026" $49). Do you want me to wire Stripe payment links into the landing page as a separate commit after the main fix lands, or keep them offline until the core registry flow is proven?
3. Should Kai have a "Friday EOD recap" scheduled task (16:00 MDT, after bot closes) so you don't walk into the weekend without a summary? Cron would be Fri-only, does not conflict with existing schedule.

---

*This brief is regenerated every night during consolidation. The version you're reading was written after nightly-simulation and nightly-consolidation both ran cleanly on 2026-04-09.*
