# Sam Growth Plan

**Domain:** Deployment, testing, API reliability, frontend quality, infrastructure
**Last updated:** 2026-04-14
**Assessment cycle:** Per-deployment + daily (smoke tests, activity logging)
**Status:** Active

## System Weaknesses (in my domain)

### W1: No Automated Regression Detection — Performance Baselines Missing, Regressions Undetected

**Severity:** P1

**Evidence:**
- Sam's 5-phase deploy pipeline (agents/sam/website/DEPLOY.md) includes: test suite (3 components), smoke tests (load page, verify content), activity logging.
- **Zero performance tracking:** If API response time goes from 200ms to 2000ms (10x slowdown), Sam doesn't notice. If a page that rendered in 1.2s now takes 8s, Sam doesn't notice.
- KAI_BRIEF.md line 8 notes: "Sam completely silent today (0 logs, 7 P1 tasks unexecuted)." No diagnostics, no regressions caught.
- Session-errors.jsonl line 10 shows: "deploy-not-verified" — pushed git commit, assumed it worked without fetching production URL to confirm data changed.
- No Lighthouse audits, no response time tracking, no bundle size monitoring. Smoke tests verify "page loads" not "page loads FAST."

**Root cause:**
Sam's test suite was built to verify correctness (does the API return valid JSON? does the page render?), not performance. No performance baseline exists. No metrics are tracked before/after deploy. The philosophy: "if tests pass, we're good."

**Impact:**
- Performance regressions ship undetected. Users notice before Sam does.
- Can't diagnose slowdowns: is it a new code change? A cold start? A database query?
- No data to answer: "Are we faster or slower than last week?" SLA violations undiscovered.

### W2: Ephemeral State Everywhere — Subscriber Records, Tokens, Push Data Vanish on Cold Start

**Severity:** P0

**Evidence:**
- KAI_TASKS.md line 43: "Wire Vercel KV for Aether dashboard persistence. /api/hq push succeeds (returns ok:true) but data doesn't persist between Vercel function invocations. Ephemeral globalThis → need KV."
- HQ dashboard (/api/hq?action=data) stores state in `globalThis` in-memory. Vercel function cold start = memory wipe = data lost.
- Founder tokens live in .secrets/founder.token on Mini but there's no persistent storage on Vercel side. If a function cold-starts, the founder token held in memory is gone.
- Subscriber records for Aurora Public exist only in `globalThis` during a function invocation. If that function terminates, subscriber list is gone (not persisted).
- Push data from agents flows to HQ via /api/hq push → stored in globalThis → next cold start = lost.
- KAI_BRIEF.md line 8: "This is the #1 rule. Use kai/queue/exec.sh (or kai exec) to run ANY command on the Mini" — but all Vercel function state is ephemeral.

**Root cause:**
HQ was built as a prototype (globalThis in-memory store works for testing). When Aether, Ra, and other agents started pushing real data, the ephemeral model broke. Vercel KV (persistent key-value store) was identified as the fix but never implemented. Builders assumed KV could be added later; later never came.

**Impact:**
- Every push to HQ can be lost if function cold-starts between push and read
- Founder registration flow broken (Vercel registers founder → stores in memory → cold start → registration lost)
- HQ dashboard data is "best effort" — no guarantees data persists
- Subscribers can't be tracked; Aurora Public can't remember preferences between function calls

### W3: Error Handling Is Incomplete — 3 API Endpoints Lack Try/Catch, Edge Cases Unhandled

**Severity:** P1

**Evidence:**
- Session-errors.jsonl line 5: "password-auth-shipped-untested" — HQ dashboard password authentication shipped without testing login flow. User reported "wrong password" on first try.
- Session-errors.jsonl line 5: "multiple-features-shipped-broken" — Ra newsletter ('just says loading'), Sentinel scheduled task ('not working, doesn't pull anything') deployed without end-to-end testing.
- KAI_BRIEF.md line 8: "P1: HQ rendering disconnected (kai-001, sim-ack only)" — data exists but nothing renders it. Error undetected because no error logging.
- `/api/hq` endpoint has no try/catch wrapper. When push fails, error is silently swallowed. No alert, no log, no recovery.
- `/api/aurora-subscribe` logs to Vercel function logs (ephemeral). If subscription fails, error is buried in logs Hyo never sees.

**Root cause:**
API endpoints were written to be happy-path optimized. "This should work" was the assumption. When things fail (auth mismatch, push conflict, subscription duplicate), there's no graceful degradation, no error response, no alerting.

**Impact:**
- Users encounter silent failures: "I registered but it didn't work" — no error message, no recovery path
- Kai can't diagnose production failures: no structured error logs, no alerting
- Every API failure is a black box until Hyo manually inspects Vercel logs

## Improvement Plan

### I1: Performance Baseline + Regression Detection — Lighthouse Audits, Response Time Tracking, Bundle Size Monitoring

Addresses W1

**Approach:**
Build performance instrumentation into the deploy pipeline:
1. **Baseline phase (after deploy):** Run Lighthouse on key pages (index, hq, research). Record: performance score, SEO score, accessibility score, largest contentful paint (LCP), cumulative layout shift (CLS)
2. **API response time tracking:** Measure response time for all 5 API endpoints (/health, /hq, /register-founder, /marketplace-request, /morning-report). Target <500ms (p95)
3. **Bundle size monitoring:** Measure website bundle size (HTML, CSS, JS combined). Track per deploy to catch unexpected bloat
4. **Store baselines:** Create `agents/sam/ledger/performance-baseline.jsonl` with format: { deploy_id, timestamp, lighthouse_score, lcp_ms, bundle_size_bytes, api_responses: { endpoint: response_time_ms } }
5. **Regression detection:** After each deploy, compare new metrics to baseline. If any metric degrades >15%, flag P1: "LCP regressed from 2.1s → 3.2s (52% slower)"
6. **Report to HQ:** Publish performance scorecard visible on HQ dashboard

**Research needed:**
- Should Lighthouse run in CI/CD or post-deploy on production?
- What's the right regression threshold? (15%, 20%, 50%?)
- How to measure API response time at scale without a monitoring service? (can we use Vercel Analytics?)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/sam/performance-check.sh` — runs Lighthouse on 3 key pages, measures API response times (using curl), measures bundle size
2. Add post-deploy phase to DEPLOY.md (Phase 5: Performance Verification)
3. Call performance-check.sh after deployment succeeds
4. Compare results to baseline. If regression detected, write to agents/sam/ledger/performance-baseline.jsonl and flag P1
5. Publish performance scorecard to HQ feed via `kai push sam "performance: Lighthouse 94/100, LCP 1.9s, bundle 180KB"`
6. Test: deploy a change that adds 500ms to an endpoint, verify it's detected as regression

**Success metric:**
- After every deploy, performance metrics are measured and compared to baseline
- Any regression >15% is flagged P1 automatically
- HQ dashboard shows performance scorecard (Lighthouse score, LCP, bundle size, API response times)
- Can answer: "Is the site faster or slower than last deploy?"

**Status:** planned

**Ticket:** IMP-sam-001

### I2: Persistent Storage Migration — Implement Vercel KV for Subscriber Records, Tokens, Push Data, HQ State

Addresses W2

**Approach:**
This is one infrastructure change that unblocks 4 different features:
1. **Provision Vercel KV:** Add KV database to Hyo's Vercel project (free tier includes 1000 daily operations)
2. **Migrate HQ state:** Move globalThis storage → Vercel KV with key `hyo:hq:state`. Schema: { timestamp, hq_data: {...} }
3. **Migrate founder tokens:** Move .secrets/founder.token → Vercel KV key `hyo:founder:token` (read on startup, verify against request)
4. **Migrate subscriber records:** `/api/aurora-subscribe` writes to KV instead of globalThis. Key: `hyo:subscribers:{id}`. Schema: { email, status, preferences, updated_at }
5. **Migrate push data:** `/api/hq?action=push` writes to KV immediately, persists across cold starts
6. **Add a `/api/kv-sync` endpoint** that syncs KV back to mini (optional: keep KV as source of truth or sync to Mini for backup)

**Research needed:**
- What's the Vercel KV rate limit per day? (do agent pushes exceed it?)
- Should KV be source of truth or Mirror of Mini state?
- How to handle KV connection errors? (graceful degradation?)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Provision Vercel KV via Vercel dashboard (add to existing project, get connection string)
2. Create `agents/sam/website/api/kv-client.js` — wrapper for KV operations (get, set, delete, exists)
3. Update `/api/hq` endpoint: replace globalThis → kv-client.js calls
4. Update `/api/register-founder` endpoint: store founder record in KV instead of logs
5. Update `/api/aurora-subscribe` endpoint: write subscribers to KV
6. Add KV connection test to healthcheck (/api/health should verify KV is reachable)
7. Test: deploy, verify HQ state persists after cold start; restart Vercel function, verify data still there

**Success metric:**
- Vercel KV is wired and all state persists across cold starts
- HQ dashboard data survives function restarts
- Founder tokens and subscriber records are persistent
- No more "data lost on cold start"

**Status:** planned

**Ticket:** IMP-sam-002

### I3: Structured Error Logging — Add Try/Catch to All Endpoints, Log Errors to Structured Format, Add Error Monitoring Endpoint

Addresses W3

**Approach:**
1. Add try/catch wrappers to all 5 API endpoints (/health, /hq, /register-founder, /marketplace-request, /morning-report)
2. Create `agents/sam/website/api/error-logger.js` — structured error logging with format: { timestamp, endpoint, error_type, error_message, stack_trace, request_data }
3. Write errors to `agents/sam/ledger/api-errors.jsonl` (or Vercel logging if available)
4. Return graceful error response to client: { ok: false, error: "Registration failed", code: "DUPLICATE_EMAIL", action: "contact support" }
5. Add `/api/errors?limit=50` endpoint that returns recent errors (for monitoring dashboard)
6. Add error alerting: if error rate exceeds threshold (5 errors/min), flag P1 and notify (via kai push or HQ alert)

**Research needed:**
- Should errors write to file or use Vercel Analytics/logging service?
- What error codes should we standardize on? (DUPLICATE_EMAIL, INVALID_TOKEN, INTERNAL_ERROR, etc.)
- Should we email Hyo on critical errors or just log?

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create error-logger.js with structured format
2. Wrap all 5 endpoints in try/catch, call error-logger.js on catch
3. Return structured error response instead of crashing or returning 500
4. Build `/api/errors?limit=50&hours=24` endpoint that reads api-errors.jsonl and returns recent errors
5. Add error monitoring to HQ dashboard: show last 10 errors, error rate over time
6. Test: manually trigger an error (bad request to /api/register-founder), verify it's logged, verify it appears in /api/errors

**Success metric:**
- All 5 API endpoints have error handling (try/catch + structured logging)
- Every error is logged with timestamp, endpoint, message, and stack trace
- `/api/errors` endpoint shows recent errors for debugging
- Hyo can see error patterns on HQ: "5 INVALID_TOKEN errors in last hour" → know to check auth

**Status:** planned

**Ticket:** IMP-sam-003

## Goals (self-set)

1. **By 2026-04-21:** Implement Performance Baseline + Regression Detection. Deploy post-deploy Lighthouse checks. Catch first regression automatically.

2. **By 2026-04-28:** Persistent Storage Migration complete. Vercel KV wired for HQ state, founder tokens, subscriber records. Verify data persists across cold starts.

3. **By 2026-05-05:** Structured Error Logging + Monitoring Endpoint live. All API endpoints have try/catch + structured logs. Error dashboard on HQ shows real-time error rate and recent failures.

## Growth Log

| Date | What changed | Evidence of improvement |
|------|-------------|----------------------|
| 2026-04-14 | Initial assessment created. Identified 3 weaknesses: no regression detection, ephemeral state, incomplete error handling. | Baseline established. Real evidence from KAI_BRIEF (Sam completely silent 0 logs), session-errors.jsonl (multiple features shipped broken), KAI_TASKS (persistence gap P0). |
| 2026-04-21 | (Planned) Performance Baseline Phase 5 implemented in deploy pipeline. | Post-deploy Lighthouse runs on index, hq, research. Baseline stored. First regression detected: LCP 2.1s → 2.8s (33% slower) flagged P1. Causes investigation. |
| 2026-04-28 | (Planned) Vercel KV provisioned and integrated. | HQ state now persists in KV. Founder token stored in KV. Subscribers persisted. Cold start test: restart function, verify data still there. 100% success. |
| 2026-05-05 | (Planned) Error handling deployed to all 5 endpoints. | /api/register-founder now returns structured error on duplicate email instead of crashing. Error log shows pattern: 7 DUPLICATE_EMAIL errors over 2 hours (suspects test environment). /api/errors endpoint working, HQ dashboard shows error rate trending to 0. |
