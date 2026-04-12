# Sam Task List

Master coder agent task queue. Owned by Sam, executed via `kai sam <subcommand>` or `claude -p` on the Mini.

**Priority:** top of file = highest. Work top-down.

---

## Active — In Progress

- [ ] **HQ dashboard facelift**
  - Desktop version (1024px+) with redesigned layout, improved typography, better spacing
  - Mobile version (responsive <768px) with stacked layout, touch-friendly interactions
  - Light mode (default): clean, high-contrast, modern font stack
  - Dark mode (Hyo's brand palette): deep background #080810, off-white text #e8d5b7, accent #c9a96e
  - Font overhaul: user reported current design as "unappealing" — migrate to modern font stack (Syne for display, DM Mono for code, system font fallback for body text)
  - Component library: buttons, cards, tables, forms with consistent visual language
  - Status: high-priority, user-facing, impacts product perception

- [ ] **Ra newsletter aesthetics overhaul**
  - Update visual identity to match HQ dashboard redesign
  - Responsive email template (dark + light modes)
  - Improve typography, spacing, hierarchy in markdown → HTML render
  - Footer redesign (branding, unsubscribe, archive link)
  - Test across email clients (Apple Mail, Gmail, Outlook, Mobile)
  - Status: secondary to HQ facelift but blocks Aurora Public subscriber satisfaction

- [ ] **Set up proper testing pipeline**
  - Automated test framework (Jest for JavaScript, or Vitest for Vercel compatibility)
  - Unit tests: API endpoint handlers, JSON validation, token verification
  - Integration tests: API → database (once KV is live), email dispatch dry-run
  - Smoke tests: health endpoint, 401 rejection, marketplace validation
  - CI/CD hooks: pre-commit linting, pre-push test suite, Vercel preview checks
  - Coverage threshold: 70% minimum, reported in deployment logs
  - Status: foundational, unblocks feature velocity

- [ ] **Wire Vercel deploy verification into `kai sam deploy`**
  - Enhance `kai sam deploy` to poll `https://www.hyo.world/api/health` after push
  - Timeout: 30s with exponential backoff (3s → 5s → 10s → 15s)
  - Report: "Deployment live and verified" or "Deployment verification timeout — check Vercel"
  - Integrate with HQ state tracking so dashboard shows last-deployed timestamp + status
  - Status: improves deploy confidence, partially done (basic polling exists)

---

## P1 — This week

- [ ] **Implement `/api/agents` GET endpoint**
  - Returns full registry of agents from `NFT/agents/*.hyo.json`
  - JSON response: `{ "agents": [ { "name": "aurora.hyo", "version": "2.2.0-public-v0", ... }, ... ] }`
  - Unblocks cross-device sync without git (HQ can hydrate Kai session from any machine)
  - Reads from live filesystem (once KV persistence lands, read from KV instead)

- [ ] **Implement `/api/brief` GET endpoint**
  - Returns JSON version of KAI_BRIEF.md (sections: identity, operational-model, current-state, blockers)
  - Unblocks new Kai sessions hydrating from any machine without file access
  - Rendered as pretty JSON with optional `?format=markdown` param

- [ ] **Build Aurora subscriber persistence**
  - Migrate `/api/aurora-subscribe` from function-log dump to Vercel KV or GitHub commit via @octokit
  - Schema: `sub_{timestamp}` key with `{ email, topics[], voice, depth, length, freetext, subscribedAt, status }`
  - Enable `/tune/<id>` and `/unsub/<id>` endpoints (next phase)
  - Seed subscriber list from manually collected Vercel logs into `newsletter/subscribers.jsonl` as bootstrap

- [ ] **Implement `/api/review` endpoint per HyoRegistry_Reviews.md spec**
  - POST `/api/review` accepts `{ agentId, reviewer, rating, feedback }`
  - Dual output: public trust signal (average rating display) + private operator feedback (email to hyo)
  - Requires: rate limiting, spam detection, optional reviewer identity verification

- [ ] **Audit and document API error handling**
  - Ensure all endpoints return consistent error JSON: `{ error: "message", code: "ERROR_CODE", status: 400 }`
  - Document expected status codes for each endpoint
  - Add logging: all errors logged to Vercel function logs with request ID + timestamp

---

## P2 — Near-term

- [ ] **Aurora Public email template improvements**
  - Better inline CSS (avoid external stylesheets, use `<style>` in `<head>`)
  - Test rendering in 5+ email clients (Gmail, Apple Mail, Outlook, mobile)
  - Fallback plain-text version is readable (no over-reliance on HTML)
  - Add "View in Browser" link to rendered HTML version hosted on hyo.world

- [ ] **Implement `/tune/<id>` subscriber intake update endpoint**
  - Load existing subscriber record from KV
  - Render intake form pre-filled with current choices
  - POST updates back to KV: `{ voice, depth, length, topics[], freetext }`
  - Requires session/auth (optional: token-in-URL or magic link)

- [ ] **Implement `/unsub/<id>` one-tap unsubscribe endpoint**
  - Simple GET or POST that flips subscriber status from `active` to `unsubscribed`
  - No login required (subscriber ID is the proof of access)
  - Optional: return a "goodbye" page with re-subscribe option

- [ ] **Set up Vercel KV for persistent storage**
  - Provision Vercel KV project
  - Wire KV client into `/api/register-founder`, `/api/aurora-subscribe`, HQ state
  - Schema docs: agent manifests, subscriber records, HQ event log, push history
  - Fallback: GitHub commit via @octokit if KV costs are prohibitive

- [ ] **Document code architecture for future Sam sessions**
  - Add `docs/architecture.md` covering API design, file structure, data flow
  - Add `docs/deployment.md` covering Vercel setup, env vars, secrets management
  - Add `docs/testing.md` with examples of how to run and write tests
  - Keep in sync with actual code; include diagrams if helpful

- [ ] **Build `/aurora-archive` subdomain**
  - Serve full newsletter history as browsable HTML (index + searchable archives)
  - Link from hyo.world/aurora intake to archive
  - Requires: metadata extraction from `newsletters/YYYY-MM-DD.md`, HTML generation, search index

- [ ] **Implement HQ state persistence and recovery**
  - Currently HQ state lives in Vercel function `globalThis` (lost on cold start)
  - Move to Vercel KV with schema: `{ lastRun, events[], deployment[], agents{} }`
  - Add HQ endpoint to dump/restore state (backup/restore pattern)
  - Integrate with consolidation so nightly consolidation appends to persistent state

---

## P3 — Strategic / Backlog

- [ ] **Full test coverage**
  - Target: 80%+ code coverage on all API endpoints
  - Add visual regression tests for website redesign (once facelift ships)
  - Add email rendering tests (MJML or similar) for Aurora emails

- [ ] **Monitoring and observability**
  - Structured logging to external service (Datadog, LogRocket, or Vercel Analytics)
  - Error tracking: Sentry or Vercel error alerts
  - Performance metrics: API latency, deployment duration, test run time

- [ ] **Second language support** (if expanding globally)
  - i18n framework for website (locale negotiation, translation files)
  - Affects: founder-register.html, marketplace.html, aurora.html + API responses

- [ ] **Advanced email features for Aurora**
  - A/B testing on voice/depth/length (optional: measure engagement by variant)
  - Clickthrough tracking (optional: private, no tracking pixels, subscriber-aware)
  - Preference center (manage topics, frequency, format without unsubscribing)

- [ ] **Expand Hyo.world to multi-project platform**
  - Once one agent is proven (Ra), design landing page for agent marketplace
  - Implement agent search/filter UI
  - Enable external agent submission and listing

---

## Done

- [x] **2026-04-10** Core website pages (index, founder-register, marketplace)
- [x] **2026-04-10** API endpoints: health, register-founder, marketplace-request
- [x] **2026-04-10** Founder token configuration in Vercel env
- [x] **2026-04-11** Aurora Public subscriber intake page (website/aurora.html)
- [x] **2026-04-11** Aurora Public email dispatcher (newsletter/send_email.py stdlib-ready)
- [x] **2026-04-11** HQ dashboard v2-v6 (data-driven views, auth, push endpoint)
- [x] **2026-04-11** Document viewer for briefs/reports/logs
- [x] **2026-04-12** Sam agent manifest (NFT/agents/sam.hyo.json)
- [x] **2026-04-12** Sam dispatcher script (kai/sam.sh with subcommands deploy/test/build/fix/review)

---

## Notes for future Sam sessions

When resuming from KAI_TASKS, pick the top item and work through it end-to-end:
1. Read the task description
2. Understand the acceptance criteria
3. Implement the code
4. Test locally
5. Deploy to Vercel
6. Update this file (move to Done with date)
7. Log activity to `kai/logs/sam-YYYY-MM-DD.md`

For multi-step features (e.g., full HQ facelift), break into smaller commits and deploy frequently to get feedback early.

Always run `kai sam test` before `kai sam deploy`.

If stuck, use `kai sam fix "<issue description>"` to get a fresh Mini session focused on that specific problem.
