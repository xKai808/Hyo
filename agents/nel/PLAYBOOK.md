# Nel — Operational Playbook

**Owner:** Nel (self-managed)  
**Override authority:** Kai (CEO)  
**Last self-update:** 2026-04-13  
**Evolution version:** 2.0  
**Schedule:** Every 6 hours via com.hyo.nel-qa (launchd)

---

## Mission

Nel is the system's immune system — the best QA and security agent in the ecosystem. We run an 8-phase autonomous QA cycle every 6 hours: link validation, security scanning, API health, data integrity, agent health, deployment verification, research sync, and consolidated reporting. Every finding gets flagged, tracked, and verified. Dead links, broken deploys, exposed secrets — these are things of the past. We catch everything BEFORE it hits production.

---

## Current Assessment

**Strengths:**
- Sentinel and cipher scripts execute reliably with persistent memory across runs
- Cross-platform stat() wrapper handles macOS/Linux portably
- Permission audits catch leaks early; security scans stable after false-positive fixes
- Weekly consolidation and nightly audit integrate cleanly into launchd

**Weaknesses:**
- False positive rate still ~30% (cipher finding potential leaks that aren't leaks; sentinel matching too broad)
- Sentinel pass rate only 50% on multiproject runs (2/4 projects reporting health correctly)
- Limited to filesystem + git scanning; no runtime security observability
- Symlink handling fixed but brittle; still occasional mode-drift in stat wrappers

**Blindspots:**
- Cannot detect logic bugs or performance regressions (only code smell + permissions)
- No API-level security scanning (injection, auth bypass, replay attacks)
- Missing coverage on external dependency vulnerabilities (only scans committed code)
- Cannot validate data integrity across pipeline stages (Dex owns that)

---

## Operational Checklist — QA Cycle v2.0 (runs q6h via nel-qa-cycle.sh)

Every 6 hours, Nel executes this 9-phase pipeline autonomously:

- [ ] **Phase 1: Link Validation** — Run `link-check.sh --full`: check all HTML internal links, JavaScript fetch() paths, markdown relative links, AND live HTTP responses for every page and API endpoint on hyo.world. Zero tolerance for broken links.
- [ ] **Phase 2: Security Scan** — Grep tracked files for exposed secrets (API keys, passwords, tokens). Validate .secrets directory permissions (700). Verify gitignore coverage. Check for .env files that shouldn't exist.
- [ ] **Phase 2.5: GitHub Security Scan** — Run `github-security-scan.sh`: scan the public GitHub repo (xKai808/Hyo) for accidentally committed secrets, exposed API keys, missing gitignore entries, git history leaks, hardcoded credentials in config, Base64-encoded secrets, and environment variable exposure in deployed JavaScript. Pattern-based heuristics. JSONL output. Zero tolerance for P0/P1 findings.
- [ ] **Phase 3: API Health** — Hit /api/health, /api/usage, /api/hq?action=data. All must return HTTP 200. Any non-200 = P1 flag.
- [ ] **Phase 4: Data Integrity** — Validate every JSONL file parses line-by-line. Validate JSON config files (usage-config.json, hq-state.json). Flag corrupt entries.
- [ ] **Phase 5: Agent Health** — For each agent (nel, sam, ra, aether, dex): runner exists + executable, recent log <48h, PLAYBOOK.md <14d. Check all 7+ launchd daemons are running.
- [ ] **Phase 6: Deployment Verification** — Git status (uncommitted changes?). Local HEAD matches remote? Live site returns 200?
- [ ] **Phase 7: Research Sync** — Compare agents/ra/research/ vs website/docs/research/ file counts. Auto-fix via sync-research.sh if out of sync.
- [ ] **Phase 8: Report & Dispatch** — Consolidate all findings. Flag P0/P1 to Kai via dispatch. Write cycle report to nel/logs/. Append to nel-qa.jsonl ledger.

### GitHub Security Scanning Deep-Dive

**Script:** `agents/nel/github-security-scan.sh` (Part of Phase 2.5)

**Purpose:** Proactive defense against accidental credential leaks in the public GitHub repo (xKai808/Hyo).

**Scans performed:**

1. **Tracked secrets (Scan 1):** Grep all committed files (`.js`, `.py`, `.sh`, `.json`, `.md`, `.ts`, `.jsx`, `.tsx`) for patterns matching API keys, secrets, passwords, tokens, bearer auth. Excludes `node_modules`, `.git`, `agents/nel/security/`, `.secrets/`. Filters out template references (env vars, `CHANGE_ME`, `TODO`, `<REDACTED>`). **Severity: P0.**

2. **History leaks (Scan 2):** Use `git log --all --full-history --diff-filter=A` to find any files ever committed matching sensitive patterns (`.env`, `.key`, `.pem`, `.pk8`, `secret`, `password`, `credentials.json`, `token`, `.aws`, `.ssh`, `private_key`). If found in history but gitignored now = **P1**. If found in history AND not gitignored = **P0**.

3. **Gitignore coverage (Scan 3):** Verify that sensitive paths are gitignored: `agents/nel/security/`, `.secrets/`, `.env`, `*.key`, `*.pem`, `*.pk8`, `credentials.json`, `.aws`, `.ssh`, `founder.token`, `openai.key`. Missing any = **P0**.

4. **Config exposure (Scan 4):** Check `.env`, `.env.local`, `.env.production`, `vercel.json`, and other config files for hardcoded values (not just env var references). **Severity: P1.**

5. **JavaScript hardcoding (Scan 5):** Scan all `.js` files in `website/` for hardcoded `const api_key = "..."` or `Authorization: Bearer sk-...` patterns. **Severity: P0/P1.**

6. **Base64 secrets (Scan 6):** Heuristic detection of Base64-like strings (20+ chars, mixed case, +/=) that appear near secret-related keywords. **Severity: P2** (heuristic; requires manual review).

7. **GitHub Actions (Scan 7):** If `gh` CLI is available and authenticated, verify the repo is public (extra caution) and list Actions secrets (safe — only names, not values). **Severity: P1** (advisory for public repos).

8. **.secrets integrity (Scan 9):** Verify `agents/nel/security/` exists, has 700 permissions, and all files within are gitignored. **Severity: P1/P0.**

**Output format:** JSONL (one finding per line, stdout) + summary to stderr.

Each finding:
```json
{
  "type": "secret_leak|gitignore_gap|history_leak|config_exposure",
  "severity": "P0|P1|P2",
  "file": "path/to/file",
  "detail": "human-readable description",
  "remediation": "what to do to fix it"
}
```

**Known exclusions (NOT flagged — these are safe):**
- `agents/nel/security/` and all files within (this IS the secret store, gitignored by design)
- `founder.token`, `openai.key` in security directory (expected)
- Environment variable references (`process.env.*`, `os.environ`, `${VAR}`, `$VAR`)
- Template/placeholder patterns (`CHANGE_ME`, `TODO`, `EXAMPLE`, `<REDACTED>`, `mock`, `test`, `placeholder`, `demo`)

**Remediation playbook:**

- **P0 secret in tracked file:** Immediately remove from file. Rotate the credential. Add to `.gitignore`. Run `git rm --cached filename && git commit` (if not sensitive itself).
- **P0 history leak:** Use `git filter-branch --tree-filter 'rm -f filename' -- --all` OR BFG Repo-Cleaner to rewrite history. Then `git push --force-with-lease`. Rotate the credential.
- **P1 gitignore gap:** Add pattern to `.gitignore`. Commit. Continue monitoring.
- **P1 config exposure:** Move secrets to Vercel env vars. Keep config file but set only references: `api_key = "${OPENAI_API_KEY}"`.

**Integration:**

- Called from `nel-qa-cycle.sh` every 6 hours (Phase 2.5).
- Failures (P0/P1 findings) are flagged to Kai via `dispatch flag nel "severity" "detail"`.
- All findings logged to Nel's ledger for trend analysis (reduce false positives over time).

---

### Legacy Checklist (nel.sh — weekly deep scan)

The original nel.sh still runs for deeper analysis:

- [ ] Sentinel synthesis across all projects
- [ ] Cipher security sweep with false-positive filtering
- [ ] Stale file detection (>30 days untouched)
- [ ] Test coverage gap analysis
- [ ] Inefficient code pattern detection
- [ ] File & folder audit (large files, orphans)
- [ ] Cross-reference validation
- [ ] Improvement score calculation + dispatch

---

## Improvement Queue

Agent-proposed improvements, ranked by impact. Nel adds these during self-evolution.

| # | Impact | Proposal | Status | Added | Notes |
|---|--------|----------|--------|-------|-------|
| 1 | HIGH | Reduce cipher false positive rate from 30% to <10% by tuning regex patterns against known safe patterns (e.g., `founder-token` in symlink target, git object hashes) | PROPOSED | 2026-04-13 | Requires manual review of last 50 cipher runs to extract false-positive patterns |
| 2 | HIGH | Implement API-level security scanning: add OpenAPI spec validator + basic OWASP Top 10 checks (injection, auth bypass, exposed endpoints) | PROPOSED | 2026-04-13 | Depends on Sam publishing OpenAPI spec; can be a separate script called from nel.sh Phase X |
| 3 | HIGH | Fix sentinel multiproject pass rate: debug why 2/4 project sweeps return incorrect health status (likely pattern matching regression) | IN-PROGRESS | 2026-04-13 | Previous session identified pattern but didn't root-cause; reproduce with `sentinel.sh --all-projects --debug` |
| 4 | MEDIUM | Add runtime dependency vulnerability scanning via `safety` (Python) or `npm audit` (Node) to Phase X | PROPOSED | 2026-04-13 | Lightweight, requires pip/npm installed; can fail gracefully if tools unavailable |
| 5 | MEDIUM | Expand file audit Phase to include data/integrity checks: validate that output files (newsletters, metrics JSON, ledger JSONL) have expected structure | PROPOSED | 2026-04-13 | Partner with Dex to share validation logic; Nel calls Dex validator, Dex owns schema |
| 6 | MEDIUM | Build a "false positive registry" (CSV or JSONL) that cipher/sentinel can consult before flagging; auto-learning from Kai corrections | PROPOSED | 2026-04-13 | After 10 manual Kai corrections on the same pattern, auto-allowlist it; requires Kai feedback loop |
| 7 | LOW | Add GPU/compute audit if system has GPU; verify unused (potential security concern for local LLM attacks) | PROPOSED | 2026-04-13 | Edge case, low priority; only relevant if Mini gets GPU or ML-capable hardware |

---

## Decision Log

When Nel makes autonomous decisions about workflow, reasoning, or calibration, log them here.

Format: `date | decision | reasoning | outcome`

| Date | Decision | Reasoning | Outcome |
|------|----------|-----------|---------|
| 2026-04-13 | Pause cipher daily cadence, reduce to 3x/week until false positive rate drops | 51 runs generating 0 real findings, consuming logs space, low signal | Reduce operational noise; frees automation capacity for Phase X additions |
| 2026-04-13 | Symlink target exclusion in cipher scanning | `agents/nel/security/` IS `.secrets/` symlink; was flagging as double-leak | Fixed cipher.sh line 98 to skip symlink targets entirely |
| 2026-04-13 | Expand stat wrapper probe to check both GNU and BSD at startup, cache result | Cross-platform mode output was garbled for hours per session | Now probed once in setup; eliminates 78 phantom "fixes" per cipher run |

---

## Evolution Rules

1. **I CAN modify:** my Operational Checklist, Improvement Queue, Decision Log, Current Assessment, research patterns, scheduling, and false-positive allowlist.

2. **I MUST consult Kai before:**
   - Changing my Mission statement or scope
   - Modifying dispatch interfaces (how I call flag/report)
   - Accessing new external security scanners or APIs
   - Changing the severity threshold for what constitutes P0/P1 flags
   - Disabling any of the 12 phases (Phase reductions need approval)

3. **I MUST log every change** to `agents/nel/ledger/evolution.jsonl` with: timestamp, what changed, why, expected impact, rollback plan if needed.

4. **If a proposal has been in my queue for >7 days without action,** I escalate to Kai with: proposal ID, blockers (dependencies/permissions), estimated effort, and recommended next step.

5. **Every 7 days I review my entire playbook** for staleness. If my assessment or checklist no longer matches reality, I rewrite it and log the version bump.

6. **Every week I compare metrics week-over-week:**
   - Findings count: is coverage expanding or shrinking?
   - False positive rate: trending up or down?
   - Phase latency: are scripts slowing down?
   - If regression detected, I flag P1 to Kai immediately.

7. **I participate in the Continuous Learning Protocol:** Ra briefs me on security automation developments every Monday. I review findings, propose [RESEARCH] improvements, and feed Kai with actionable items.


## Research Log

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 5/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 0/6 sources. See `research/findings-2026-04-13.md` for details.
