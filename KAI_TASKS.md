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

- [ ] **[K]** [sentinel] Aurora did not produce 2026-04-10 newsletter — fix by migrating synthesize.py to Claude Code subprocess. See `newsletter/synthesize_claude.py` (pre-staged tonight). _(sentinel 2026-04-10)_
- [ ] **[K]** [sentinel] No aurora logs in `kai/logs` — schedule may not be wired correctly OR `newsletter.sh` isn't writing a log. Add explicit `tee` to log file in the dispatcher. _(sentinel 2026-04-10)_
- [ ] **[K]** Verify aurora 03:00 MT run on 2026-04-11 actually produces `newsletters/2026-04-11.md`. If not, read log and iterate. _(added overnight)_

## P1 — This week

- [ ] **[B]** Deploy `HyoRegistry.sol` to Base Sepolia testnet for on-chain mint dry-run.
- [ ] **[K]** Implement `mintReserved` admin function on the contract (spec in `NFT/HyoRegistry_Marketplace.md`).
- [ ] **[K]** Swap `/api/register-founder` MVP console logging for persistent storage — Vercel KV or GitHub commit via `@octokit`. Right now the manifest only lives in Vercel function logs (ephemeral).
- [ ] **[K]** Add Merkle root of reserved 48,988 handles to the contract constructor (spec in `NFT/HyoRegistry_Marketplace.md`).
- [ ] **[K]** Newsletter: verify Yahoo Finance endpoint (the 20.6s/0 records result Hyo flagged earlier). Swap for `yfinance` or a different free source if still broken.
- [ ] **[H]** Get FRED_API_KEY from https://fred.stlouisfed.org/docs/api/api_key.html (free) so the gather stage has macro signal.
- [ ] **[H]** Confirm Claude Code CLI (`claude -p`) is on the PATH used by the scheduler on the Mini. Without this, the aurora migration cannot work.

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
