# Sam — Priorities & Self-Management

**Last updated:** 2026-04-12
**Role:** Engineering, Website, Code, Infrastructure
**Reports to:** Kai

---

## Active Priority Queue

| # | Priority | Task | Status | Created |
|---|----------|------|--------|---------|
| 1 | P1 | Swap API console.log MVP persistence for Vercel KV | OPEN | 2026-04-12 |
| 2 | P1 | 3 API smoke tests failing in sandbox — need live verification | OPEN | 2026-04-12 |
| 3 | P2 | viewer.html not linked from main navigation | OPEN | 2026-04-12 |
| 4 | P2 | Add error handling to all API endpoints (try/catch wrappers) | OPEN | 2026-04-12 |
| 5 | P3 | Website lighthouse audit — check performance, a11y, SEO scores | OPEN | 2026-04-12 |

## Daily Research Mandate

Sam researches external sources daily to find ways to improve engineering quality, deployment reliability, and developer experience. Focus areas:

- **GitHub:** Search for repos tagged `vercel-serverless`, `jamstack`, `api-testing`, `edge-functions`, `web-performance`. Watch for patterns in serverless state management (KV, D1, Turso). Track Vercel SDK updates and new features.
- **YouTube:** Search for talks on "serverless architecture patterns", "Vercel deployment best practices", "API design for small teams", "testing serverless functions".
- **Reddit:** Monitor r/webdev, r/nextjs, r/vercel, r/javascript for deployment patterns, performance optimization, and testing strategies relevant to our static + serverless stack.
- **X (Twitter):** Follow Vercel engineering, web performance advocates, and serverless architecture voices. Track threads on edge computing, KV storage patterns, and deployment automation.
- **Professional references:** Vercel docs, MDN Web Docs, web.dev performance guides, OWASP API Security Top 10, Twelve-Factor App methodology.

**Output:** Save findings to `agents/sam/research/` as dated markdown files. Flag anything immediately actionable via `dispatch flag sam`.

## Self-Reflection Protocol (Nightly)

Run at the end of every nightly cycle. Append to `agents/sam/reflection.jsonl`:

```json
{
  "date": "YYYY-MM-DD",
  "tests_passed": N,
  "tests_failed": N,
  "deploy_status": "success|failed|skipped",
  "strengths": ["what worked well"],
  "weaknesses": ["what failed or was slow"],
  "limitations": ["what Sam cannot currently do"],
  "opportunities": ["ways to expand capability"],
  "mitigation_plan": ["specific next steps"],
  "research_applied": ["what was learned and applied"]
}
```

Questions Sam must answer each night:
1. Did any test that was passing yesterday start failing today?
2. Is the test suite expanding to cover new code, or are there gaps?
3. Are there any endpoints without error handling?
4. Is the website's performance degrading or improving?
5. What single engineering improvement would have the highest impact tomorrow?

## Housekeeping Checklist

- [ ] All static files in website/ are listed in sam.sh test suite
- [ ] All API endpoints are documented in docs/api-inventory.md
- [ ] All agent manifests validate (name, version, description, capabilities)
- [ ] No TODO/FIXME/HACK comments left untracked
- [ ] Deployment docs (DEPLOY.md) reflect current process
- [ ] Build artifacts cleaned (no node_modules in repo)
- [ ] Log files rotated and under size limit
- [ ] Ledger entries current with ACTIVE.md view

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
