# Nel Growth Plan

**Domain:** System quality assurance, security scanning, vulnerability detection
**Last updated:** 2026-04-14
**Assessment cycle:** Daily (q6h sentinel run, nightly consolidation)
**Status:** Active

## System Weaknesses (in my domain)

### W1: Static Checks Never Adapt — Sentinel Runs Same 9 Checks Until Failure Is Deafening

**Severity:** P0

**Evidence:** 
- `api-health-green` has failed **25 consecutive runs** (session-errors.jsonl line 39-55). The check reports: "health endpoint unreachable or token unconfigured." Nel detects it, logs it, flags it, then runs again tomorrow and detects the SAME issue.
- `aurora-ran-today` failing for 3 consecutive days (no newsletter for 04-12, 04-13, 04-14). Nel flags it, but never escalates to a deeper diagnostic like: "Is the aurora daemon alive? Did it receive its scheduled trigger? What was the error in its execution?"
- Sentinel runs 9 checks every q6h cycle (~40 runs in recent days). **Zero checks adapt** based on prior failures. When a check fails repeatedly, Nel should auto-generate a targeted investigation, not just re-run the same surface-level test.

**Root cause:** 
Sentinel is a static template (sentinel.sh:150-220). Each check is a one-liner bash test. There's no feedback loop that says "this check has failed 5 times, time to dig deeper" or "a new failure pattern emerged, add a targeted check for it."

**Impact:** 
- P0 issues take 3+ days to remediate because Nel can only report, not diagnose.
- Hyo sees "api-health-green FAIL" 25 times in the audit but gets no new intelligence — just repetition.
- System has no way to learn and prevent repeated failures. Every cycle rediscovers the same problems.

### W2: Zero Dependency Vulnerability Scanning — Cipher Ignores Supply Chain Risk

**Severity:** P1

**Evidence:**
- cipher.sh (agents/nel/cipher.sh:1-200) scans: filesystem permissions (mode 777/666 checks), hardcoded patterns (api_key=, password=), git secrets (via gitleaks if installed).
- cipher does **zero checks** on: `package.json` versions, `requirements.txt` Python packages, CVE cross-reference against actual dependencies.
- Nel reads security research from multiple sources and accumulates CVE intelligence but never cross-references it against what the system actually uses. Missing: "OpenSSL 1.0.2 (2035 days overdue) — do we use it?"
- The session-errors.jsonl line 33 logs: placeholder OpenAI API key `sk-your-***-here` discovered by cipher. Cipher found the secret KEY EXISTS but didn't validate it's REAL (non-placeholder).

**Root cause:**
Cipher was written to solve immediate security gaps (leaked private keys, hardcoded secrets). It never expanded to supply-chain intelligence. The architecture expects "secrets live in agents/nel/security/" but has zero awareness of the dependency tree.

**Impact:**
- Unpatched dependencies can ship to production with zero detection.
- When a new CVE drops (e.g., XZ backdoor class), Nel has no way to know if we're affected.
- Time to detect a compromised package = manual audit, not automated scanning.

### W3: Research Sources Are Broken — 5 of 6 External Security Feeds Fail From Sandbox

**Severity:** P1

**Evidence:**
- KAI_BRIEF.md line 8: "Nel operates on 16% intelligence. Can't learn about new vulnerabilities, attack patterns, or security best practices if it can't reach the data."
- Session-errors.jsonl line 33 notes: OpenAI API key placeholder discovered, but gpt_factcheck.py + Nel's own GPT-driven analysis fail with HTTP 401 because the key isn't real.
- Nel has access to GitHub Advisory Database (verified reachable in KAI_BRIEF line 70) but other 5 sources timeout from Cowork sandbox (403/timeout).
- Known-issues.jsonl lines 49, 54, 56 show pattern: "agents/nel/security is NOT gitignored", "/api/hq?action=data returned HTTP 401" — Nel detects these but can't fix infrastructure issues.

**Root cause:**
Nel's research phase assumes network egress. Cowork sandbox blocks outbound HTTPS except to trusted domains. When Nel can't reach sources, there's no fallback. Research = network request = failure = no intelligence.

**Impact:**
- Nel blind on emerging threats, new attack patterns, best practice changes.
- Can't validate whether discovered CVEs are actually in our dependency tree (requires CVE database lookups).
- Nel's own reports based on 3-day-old cached data or nothing at all.

## Improvement Plan

### I1: Adaptive Sentinel — When a Check Fails N Times, Generate a Targeted Investigation

Addresses W1

**Approach:** 
Sentinel tracks failure state in a persistent ledger (`agents/nel/ledger/sentinel-state.jsonl`). Each check logs: timestamp, check_id, status (PASS/FAIL), consecutive_fails. When a check reaches N=3 consecutive failures, sentinel auto-generates a deeper diagnostic tailored to that check:
- `api-health-green` fails 3x → run `curl -v https://...`, trace SSL, test auth header separately, check header syntax
- `aurora-ran-today` fails 3x → check if daemon is running, check launchd logs, verify schedule was triggered, check for permission errors
- Each diagnostic produces a `.investigation.txt` report that nel can review and act on.

**Research needed:**
- What threshold triggers escalation? (3, 5, 10 failures?)
- How deep should investigations go? (test both parts of a two-part check, or full stack trace?)
- Should new checks auto-generate when a pattern emerges? (e.g., "every 12h at 03:00 this check fails" → add a timer-specific check)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/nel/sentinel-adaptive.sh` — reads sentinel-state.jsonl, checks failure counts
2. For each check hitting threshold, append 5-10 lines of deeper diagnostics (separate test steps, verbose output)
3. Append investigation results to sentinel report
4. Update `agents/nel/ledger/sentinel-state.jsonl` with latest counts
5. Integrate into sentinel.sh Phase 3 (reporting) — add investigation section if any threshold crossed
6. Test: manually fail a check 3 times, verify investigation auto-generates

**Success metric:** 
- Any check that fails 3+ consecutive times triggers an investigation report with 2-3 actionable diagnostics
- Investigation results visible in HQ / nel logs within 1 cycle
- Hyo can read investigation and understand root cause (not just "failed again")

**Status:** planned

**Ticket:** IMP-nel-001

### I2: Dependency Audit Pipeline — Parse Dependencies, Cross-Reference CVEs, Output Vulnerability List

Addresses W2

**Approach:**
Build a new phase in cipher.sh (Phase 7: Supply Chain Audit) that:
1. Parses `package.json` → extract all npm dependencies with versions
2. Parses `requirements.txt` + any Python setup.py → extract Python package versions
3. Local vulnerability scanner: compare each dependency against GitHub Advisory Database (which is reachable — nel already pulls from it)
4. Output: `agents/nel/ledger/dependency-audit.jsonl` with format: { package, version, vulnerability_count, severity, notes }
5. Score each dependency 0-100 (no vulns = 100, critical vulns = 0)
6. Flag any package scoring <50 as P1 during nightly audit

**Research needed:**
- Which free APIs/tools can query CVE data locally? (GitHub Advisory DB has a free GraphQL endpoint, Snyk has a free tier)
- How to handle transitive dependencies? (npm/pip lock files list them)
- Should we auto-patch minor versions or only flag for review?

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Build `agents/nel/dependency-audit.sh` — reads package.json, requirements.txt, Python setup files
2. Query GitHub Advisory Database for each dependency version
3. Write output to `agents/nel/ledger/dependency-audit.jsonl` with structured format
4. Add Phase 7 to cipher.sh: call dependency-audit.sh, parse results, flag high-risk packages
5. Add a `/api/audit` endpoint if needed (or just publish to HQ feed via kai push)
6. Test with real package.json from agents/sam/website/

**Success metric:**
- Every npm and Python dependency has a vulnerability score in the audit report
- Any package with known CVEs is flagged P1 during nightly audit
- Hyo can read the audit and know exactly which packages need updating

**Status:** planned

**Ticket:** IMP-nel-002

### I3: Local Intelligence Cache + Fallback Mode — Cache Research Data When Reachable, Use Cache When Blocked

Addresses W3

**Approach:**
Nel research phase builds a local cache:
1. When research sources ARE reachable (from Mini), fetch and cache results in `agents/nel/ledger/intelligence-cache.jsonl`
2. Cache structure: { source_id, fetch_time, data_hash, summary_points, full_content }
3. When running from sandbox (blocked), use cached data from the last 48h
4. Cache auto-invalidates after 48h (research >= 2 days old is stale)
5. Show cache-flag in reports: "Based on live data [timestamp]" vs "Based on cached data [timestamp, age]"

**Research needed:**
- Which research sources should be cached? (GitHub Advisory, Shodan, SecurityAdvisories, etc.)
- What's the right cache size/format? (JSONLines to avoid large files)
- Should cache be gitignored or committed? (gitignore for secrets, commit for research)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/nel/research-cache.sh` — fetch source, hash result, compare to cache, update if changed
2. Update all research phases in nel.sh to call research-cache.sh with fallback: "try live, use cache if fails"
3. Store cache at `agents/nel/ledger/intelligence-cache.jsonl` (gitignored if contains secrets, committed if public research)
4. Add cache-age flag to nel reports: "⚠️ Using 36h-old cached data" or "✓ Live data from 5min ago"
5. Test: verify cache-enabled report reads from cache when network is blocked

**Success metric:**
- Nel continues to report on CVEs/threats even when Cowork sandbox blocks network
- Cache automatically updates when on Mini (reachable)
- Hyo can see cache age and knows whether data is fresh or stale

**Status:** planned

**Ticket:** IMP-nel-003

## Goals (self-set)

1. **By 2026-04-21:** Implement Adaptive Sentinel escalation (threshold 3 failures) so repeated issues auto-generate investigation reports instead of being flagged redundantly.

2. **By 2026-04-28:** Build and test Dependency Audit Pipeline against real package.json + requirements.txt. Have first vulnerability report shipped to HQ showing all packages and their CVE status.

3. **By 2026-05-05:** Complete Local Intelligence Cache so research sources that fail in sandbox don't leave Nel blind. Cache visible in reports with freshness metadata.

## Growth Log

| Date | What changed | Evidence of improvement |
|------|-------------|----------------------|
| 2026-04-14 | Initial assessment created. Identified 3 core weaknesses: static checks, no supply-chain scanning, broken research sources. | Baseline established. All 3 weaknesses documented with real evidence from session-errors.jsonl, known-issues.jsonl, KAI_BRIEF. |
| 2026-04-21 | (Planned) Adaptive Sentinel Phase 1 complete. | Deeper diagnostics auto-generate when checks fail 3x. Example: `api-health-green` failure at run 26 triggers SSL test, auth header validation, endpoint latency check. |
| 2026-04-28 | (Planned) Dependency Audit Pipeline shipped. | First audit report shows 47 npm packages, 12 Python packages, 3 packages with known CVEs flagged P1. |
| 2026-05-05 | (Planned) Local Intelligence Cache operational. | Nel reports show "based on live GitHub Advisory data (5min ago)" when on Mini, "based on cached data (18h ago)" when in sandbox. Cache never stale >48h. |
| 2026-04-14 | IMP-20260414-nel-001 (W1): No chronic failures detected (all <5 consecutive) | Automated assessment |
