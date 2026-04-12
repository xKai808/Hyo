# Aurora / Ra — Tasks

**Updated:** 2026-04-12
**Owner:** Kai + Hyo

## Active

- [ ] **[B]** Migrate Ra to Mini launchd (Kai writes plist, Hyo runs `launchctl bootstrap`)
- [ ] **[K]** Sentinel: verify `mtime < 25h` + file size > 500b on newsletter check
- [ ] **[K]** Sentinel: add `newsletters/` to `kai verify` monitored paths
- [ ] **[K]** Aurora v1: persistent subscriber storage (Vercel KV or Octokit)
- [ ] **[K]** Aurora v1: `/tune/<id>` pre-filled intake page
- [ ] **[K]** Aurora v1: `/unsub/<id>` one-tap endpoint
- [ ] **[K]** Aurora v1: per-topic source maps for gather.py (every topic ≥3 sources)
- [ ] **[K]** Aurora v1: schedule `aurora_public.sh` after `newsletter.sh` in launchd at 05:00 MT
- [ ] **[K]** Tuning: nudge length targets for 6min/12min profiles (prompt-only fix)
- [ ] **[K]** Add `--sim` flag to `aurora_public.sh` for one-command sim reruns
- [ ] **[H]** Configure SPF/DKIM/DMARC on hyo.world + verified sender in Resend
- [ ] **[H]** Confirm `claude -p` is on PATH for Mini's scheduler
- [ ] **[K]** Verify Yahoo Finance endpoint (20.6s/0 records issue)
- [ ] **[H]** Get FRED_API_KEY for macro signal

## Blocked

- [ ] Live email sends — blocked on SPF/DKIM/DMARC
- [ ] Automated Ra runs — blocked on launchd migration

## Done

- [x] 2026-04-11 Ra v2 format shipped (narrative essay)
- [x] 2026-04-11 Research archive end-to-end
- [x] 2026-04-11 PRN continuity fix
- [x] 2026-04-11 Aurora Public v0 shipped
- [x] 2026-04-11 Sim 01 passed (5/5 briefs, 0 errors)
- [x] 2026-04-11 Recovery brief authored manually (2,254 words)
