# KAI_TASKS.md

**Purpose:** Ongoing priority queue Kai works from when Hyo isn't actively prompting. As CEO, Kai's job is to close these without being asked.

**Rules of engagement:**
- Top of file = highest priority. Work top-down.
- Every task has an owner (K = Kai, H = Hyo, B = both).
- Kai moves completed items to `## Done` at bottom with the date.
- Kai adds new tasks as they emerge from sessions, logs, or agent output.
- Hyo can edit freely. Conflicts resolved in Hyo's favor.
- `kai tasks add "..."` appends a new task. `kai tasks` prints the queue.

---

## P0 — Active blockers

- [ ] **[B]** **Migrate aurora off Cowork scheduled-task sandbox onto Mini launchd.** Cowork's sandbox blocks egress to aurora's sources (reddit/arxiv/HN/github/coingecko/producthunt all 403 Tunnel) AND writes to ephemeral disk that isn't the real Hyo folder. Fix: create launchd plist on the Mini that runs `~/Documents/Projects/Hyo/newsletter/newsletter.sh` at 03:00 MT daily. Leave Cowork `aurora-hyo-daily` scheduled task as a keepalive / no-op. See 2026-04-11 newsletter "System status" for full action plan. _(Kai writes the plist, Hyo runs `launchctl bootstrap` on the Mini.)_
- [ ] **[K]** Add `newsletters/` to the list of paths monitored by `kai verify` and have it read the real FS mtime — today's recovery edition proves the render pipeline works, so ongoing verification is now meaningful.
- [ ] **[K]** Have sentinel's `aurora-ran-today` check also verify `mtime < 25h` and file size > 500 bytes so a stale file from days ago can't mask a failure.

## P1 — This week

- [ ] **[B]** Deploy `HyoRegistry.sol` to Base Sepolia testnet for on-chain mint dry-run.
- [ ] **[K]** Implement `mintReserved` admin function on the contract (spec in `NFT/HyoRegistry_Marketplace.md`).
- [ ] **[K]** Swap `/api/register-founder` MVP console logging for persistent storage — Vercel KV or GitHub commit via `@octokit`. Right now the manifest only lives in Vercel function logs (ephemeral).
- [ ] **[K]** Add Merkle root of reserved 48,988 handles to the contract constructor (spec in `NFT/HyoRegistry_Marketplace.md`).
- [ ] **[K]** Newsletter: verify Yahoo Finance endpoint (the 20.6s/0 records result Hyo flagged earlier). Swap for `yfinance` or a different free source if still broken.
- [ ] **[H]** Get FRED_API_KEY from https://fred.stlouisfed.org/docs/api/api_key.html (free) so the gather stage has macro signal.
- [ ] **[H]** Confirm Claude Code CLI (`claude -p`) is on the PATH used by the scheduler on the Mini. Without this, the aurora migration cannot work.
- [ ] **[K]** Aurora Public v1: persistent subscriber storage. Right now `/api/aurora-subscribe` logs to Vercel function logs; wire it to Vercel KV or a GitHub commit via `@octokit` so subscribers survive without manual log replay into `newsletter/subscribers.jsonl`.
- [ ] **[K]** Aurora Public v1: `/tune/<id>` flow — intake page loads pre-filled from the subscriber record; changing any control updates the record server-side.
- [ ] **[K]** Aurora Public v1: `/unsub/<id>` one-tap unsubscribe endpoint. Flip `status` from `active` to `unsubscribed`, no login required.
- [ ] **[H]** Aurora Public v1: configure SPF / DKIM / DMARC on `hyo.world` and add `aurora@hyo.world` as a verified sender in Resend (or chosen provider). Until this lands, `send_email.py` has to stay in dry-run or hit a dev inbox.
- [ ] **[K]** Aurora Public v1: per-topic source maps for `gather.py` so the shared gather actually pulls a wide net (every topic in the v0 taxonomy has ≥3 sources). Today `gather.py` is Ra-biased.
- [ ] **[K]** Aurora Public v1: schedule `aurora_public.sh` after `newsletter.sh` in launchd — Ra runs first (archive-writer), Aurora Public runs second and reuses the same gather + `.context.md` at 05:00 MT.
- [ ] **[K]** Aurora Public tuning: nudge `compose_prompt()` length-target sentence for 6min/12min profiles. Sim 01 showed 6min at 833-891 words (target 900-1200, ~7-11% under) and 12min at 1522 words (target 1800-2300, ~15% under). Fix: rephrase "Target length: 1800-2300 words" → "Target length: 2000-2300 words — err long, not short. A subscriber who asked for 12min wants depth." Prompt-only change.
- [ ] **[K]** Add `--sim` flag to `newsletter/aurora_public.sh` that runs the full pipeline against `/tmp/aurora_sim/` inputs so sim 01 is one-command-repeatable. Pattern: `bash aurora_public.sh --sim` should invoke aurora_public.py with `HYO_INTELLIGENCE_DIR` / `HYO_SUBSCRIBERS_FILE` / `HYO_PUBLIC_OUT_DIR` pointing at the committed sim fixtures in `kai/logs/aurora-sim-*`.
- [ ] **[K]** Once v1 persistence ships, run sim 02 with real gather output to verify that culture/gossip/sports profiles still get enough matching records to sustain balanced and deep-dive depths. Today's gather.py is Ra-biased.
- [ ] **[K]** Parallelism check: sim 01 averaged ~79s per subscriber. At 100 subs sequential, that's ~132 minutes per daily run. v1 should batch or parallelize generation (e.g. 4-way concurrent calls) before the beta subscriber list crosses ~15 people.

## P2 — Near-term

- [ ] **[K]** Add `/api/agents` GET endpoint that returns the full registry (reads from KV once persistent storage exists). Unblocks cross-device sync without git.
- [ ] **[K]** Add `/api/brief` GET endpoint that returns a JSON version of KAI_BRIEF.md. Unblocks "hydrate a new Kai session from any machine without file access."
- [ ] **[K]** Implement review submission endpoint `/api/review` per `NFT/HyoRegistry_Reviews.md` spec. Dual-output (public trust signal + private operator feedback).
- [ ] **[K]** Build `aurora-archive` subdomain that serves the full newsletter history as browsable HTML.
- [ ] **[B]** Second agent after aurora. Candidates: `scribe.hyo` (meeting notes/doc generation), `broker.hyo` (auction settlement). Sentinel + cipher already done.
- [ ] **[H]** [cipher] Install scanners so cipher can do more than permission checks: `brew install gitleaks` and `brew install trufflesecurity/trufflehog/trufflehog`. _(cipher 2026-04-10, done on Mini per last terminal session — verify)_
- [ ] **[K]** Add `kai overnight` subcommand that prints OVERNIGHT_QUEUE.md status
- [ ] **[K]** Add `kai postmortem` subcommand that compiles sentinel + cipher reports from the last 24h

## P3 — Strategic

- [ ] **[K]** Research Base L2 gas sponsoring patterns (Coinbase Paymaster) so founder mints actually stay free when on-chain.
- [ ] **[K]** Design the review-to-credit-score weight curve: recency-weighted quality factor × reviewer reputation weighting.
- [ ] **[K]** Think through agent-to-agent handoff protocol — when sentinel flags an issue, how does it hand off to cipher or back to the agent owner?
- [ ] **[B]** Pricing: formalize per-job vs retainer declaration at registration time, add to the registration form.
- [ ] **[H]** Consider cancelling X Premium ($8/mo) since it doesn't grant API access per `docs/x-api-access.md`. Save: $96/yr.

## Done

- [x] **2026-04-10** Founder bypass infrastructure: page, backend, token, Vercel env var, smoke-tested end-to-end
- [x] **2026-04-10** aurora.hyo minted (first founder-tier agent, `agent_mntrp9ii_lkyfi6sk`)
- [x] **2026-04-10** Premium name marketplace page + API endpoint
- [x] **2026-04-10** Three registry spec docs: CreditSystem, Marketplace, Reviews
- [x] **2026-04-10** `bin/kai.sh` CEO dispatcher + bug fixes (health JSON parse, brief/tasks default case)
- [x] **2026-04-10** `KAI_BRIEF.md` and `KAI_TASKS.md` for session continuity
- [x] **2026-04-10** Project `CLAUDE.md` for auto-hydration
- [x] **2026-04-10** `docs/aurora-economics.md` and `docs/x-api-access.md`
- [x] **2026-04-10** `NFT/agents/sentinel.hyo.json` and `NFT/agents/cipher.hyo.json` specs
- [x] **2026-04-10** Scheduled tasks wired: sentinel-hyo-daily, cipher-hyo-hourly
- [x] **2026-04-10** `.secrets/` chmod 700 (was 0755)
- [x] **2026-04-10** Persistent memory infrastructure for sentinel and cipher: `kai/memory/*.state.json` + `*.algorithm.md`
- [x] **2026-04-10** `kai/sentinel.sh` rewritten with persistent memory + MD5 issue de-dup + escalation thresholds
- [x] **2026-04-10** `kai/cipher.sh` rewritten with persistent memory + auto-fix tracking + verifiedLeakHistory
- [x] **2026-04-10** `OVERNIGHT_QUEUE.md` created
- [x] **2026-04-10** `nightly-consolidation` and `nightly-simulation` scheduled tasks converted to run every night

_(2026-04-11 cleanup: removed 7 auto-filed sentinel/cipher findings that were false positives from the `stat -f`/`stat -c` cross-platform bug. Bug fixed in both scripts this session. The real cipher tool-install tasks are promoted up into P2 below under "[H] cipher install scanners".)_

- [x] **2026-04-11** Fixed cross-platform `stat` bug in `kai/sentinel.sh` + `kai/cipher.sh` (GNU vs BSD probe once at startup). Was causing perm-drift whack-a-mole loop and garbled "fuseblk" output being captured into mode variables — 78 phantom auto-fixes over 26 cipher runs.
- [x] **2026-04-11** Root-caused aurora failure: Cowork scheduled-task sandbox blocks egress to reddit/arxiv/HN/github/coingecko/producthunt (403 Tunnel) AND writes to an ephemeral path instead of the real FUSE mount. Documented in newsletters/2026-04-11.md "System status" section.
- [x] **2026-04-11** Produced recovery `newsletters/2026-04-11.md` + `2026-04-11.html` manually from the live Cowork mount using Anthropic API — proved the synthesize→render pipeline works end-to-end on a sane mount with sane env.
- [x] **2026-04-11** Ra v2 format shipped (narrative essay: Story / Also Moving / The Lab / Worth Sitting With / Kai's Desk). Prompt rewritten twice based on Hyo feedback — less density, fewer analogies, slightly more inline explanation, no forced Hyo angles in every paragraph.
- [x] **2026-04-11** **Ra persistent research archive shipped end-to-end.** Every brief's research now compounds instead of evaporating. `kai/research/{entities,topics,lab,briefs,raw,index.md,trends.md}` + `kai/ra_archive.py` (post-render archiver, idempotent) + `kai/ra_context.py` (pre-synth context loader, matches today's gather against the archive) + `newsletter/newsletter.sh` wired to call both + `newsletter/prompts/synthesize.md` taught to emit entities/topics/lab_items in frontmatter and consume `.context.md` + `bin/kai.sh ra` subcommand with index/trends/entity/topic/lab/search/since/rebuild/archive/context. Today's brief retrofitted and filed as the first entry (5 entities, 4 topics, 3 lab items). Smoke-tested with a fake 2026-04-12 gather — alias matching correctly surfaced Fed/Bitcoin/Marimo and ignored unrelated records. Ra manifest bumped to 2.1.0-ra with new memory:* capabilities and the pipeline stages updated to include pre-context and archive steps.
- [x] **2026-04-11** **PRN continuity fix.** `newsletter/prompts/synthesize.md` "Prior context" block and `kai/ra_context.py` rendered header both rewritten to frame the research archive as PRN (pro re nata — as needed, not on schedule). Explicit when-to-reach / when-to-skip lists. Ra is no longer pushed to mechanically weave callbacks — the brief is not a daily sequel. Most briefs should stand on their own, with the archive used when a hinge fired, a trend turned, or a lab note is directly relevant.
- [x] **2026-04-11** **Aurora Public simulation 01 (first trial run) passed.** 41-record synthetic gather spanning the full 30-topic taxonomy × 5 simulated subscribers designed to exercise every voice (gentle/balanced/sharp), every depth (headlines/balanced/deep-dives), and every length knob (3/6/12min). Ran live against `claude_code:claude-code-cli` → 5 briefs generated, 0 errors, ~6m33s total wall time. Filter routed records correctly (6/13/9/10/11 matched per sub). Voice knob is audibly distinct — the five briefs read like five different writers. Depth knob works. Length knob works 3min perfectly but biases short on 6min (~9% under) and 12min (~15% under) — filed as prompt tuning P1. Free-text subscriber context used implicitly (never parroted). Inline jargon glosses selective (glosses `dot plot`/`deposit betas`/`MiCA`/`Sparse-MoE` for the finance brief, correctly does NOT gloss `NII` or `TVL`). PRN context correctly skipped for all five profiles (no natural overlap with existing archive). `send_email.py --dry-run` rendered all 5 dark-palette HTML emails cleanly with frontmatter-derived subject lines. Full report at `kai/logs/aurora-public-sim-2026-04-11.md`; raw outputs at `kai/logs/aurora-sim-2026-04-11/`.
- [x] **2026-04-11** **Aurora Public v0 shipped end-to-end.** The consumer-facing sibling of Ra. One shared pipeline, per-subscriber output tuned to topics/voice/depth/length. Files: `docs/aurora-public.md` (design doc), `website/aurora.html` (single-page chat-style intake with 30-topic grid + voice/depth/length + 240-char freetext + email, progressive reveal, <60s target, Dawn palette), `website/api/aurora-subscribe.js` (Vercel endpoint, validation, structured log persistence), `newsletter/aurora_public.py` (per-sub generator reusing synthesize.py backends, topic-keyword filtering, PRN context block, manifest output), `newsletter/send_email.py` (Resend + SMTP dispatch, HTML + plain text rendering via render.py, lastSent stamping), `newsletter/aurora_public.sh` (pipeline wrapper: gather → ra_context → aurora_public → send_email), `newsletter/subscribers.jsonl` (placeholder), `NFT/agents/aurora.hyo.json` bumped to 2.2.0-public-v0 with new `products` array. Ra remains the sole archive author; Aurora Public reads but never writes. Smoke-tested: `--preview --dry-run` plan emitted correctly; `send_email.py --dry-run` with a seeded subscriber rendered 2145-char HTML + 458-char text with the right frontmatter-derived subject line. Stdlib only, safe for cron/launchd.
