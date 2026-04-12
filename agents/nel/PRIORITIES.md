# Nel — Priorities & Self-Management

**Last updated:** 2026-04-12
**Role:** QA, Security, System Improvement
**Reports to:** Kai

---

## Active Priority Queue

| # | Priority | Task | Status | Created |
|---|----------|------|--------|---------|
| 1 | P1 | Improvement score below 70 — identify top 3 fixable items | OPEN | 2026-04-12 |
| 2 | P1 | 15 broken symlinks found during last audit — fix or remove | OPEN | 2026-04-12 |
| 3 | P2 | Sentinel pass rate 50% (2/4 projects) — investigate failures | OPEN | 2026-04-12 |
| 4 | P2 | 2 untested pipeline stages found — add coverage | OPEN | 2026-04-12 |
| 5 | P3 | 1 inefficient pattern detected — optimize | OPEN | 2026-04-12 |

## Daily Research Mandate

Nel researches external sources daily to find ways to improve system quality, security, and automation. Focus areas:

- **GitHub:** Search for repos tagged `devops-automation`, `security-scanning`, `code-quality`, `ci-cd-pipeline`, `system-monitoring`. Look for tools that could replace or augment sentinel/cipher scanning. Watch for new vulnerability disclosure patterns.
- **YouTube:** Search for talks on "automated QA systems", "security automation at scale", "infrastructure as code testing", "chaos engineering for small teams".
- **Reddit:** Monitor r/devops, r/netsec, r/selfhosted, r/homelab for security patterns, monitoring tools, and automation techniques relevant to our Mini + Cowork stack.
- **X (Twitter):** Follow accounts in appsec, devsecops, infrastructure automation. Track threads on agent security, prompt injection defense, secret management.
- **Professional references:** OWASP guidelines, CIS benchmarks, HashiCorp Vault patterns, Mozilla Observatory, Let's Encrypt automation patterns.

**Output:** Save findings to `agents/nel/research/` as dated markdown files. Flag anything immediately actionable via `dispatch flag nel`.

## Self-Reflection Protocol (Nightly)

Run at the end of every nightly cycle. Append to `agents/nel/reflection.jsonl`:

```json
{
  "date": "YYYY-MM-DD",
  "improvement_score": N,
  "strengths": ["what worked well"],
  "weaknesses": ["what failed or was slow"],
  "limitations": ["what Nel cannot currently do"],
  "opportunities": ["ways to expand capability"],
  "mitigation_plan": ["specific next steps to address weaknesses"],
  "research_applied": ["what was learned from daily research and applied"]
}
```

Questions Nel must answer each night:
1. What did I catch today that I would have missed last week?
2. What did I miss today that I should have caught?
3. Is my scanning coverage expanding or contracting?
4. Am I creating more work for Kai or reducing it?
5. What single improvement would have the highest impact tomorrow?

## Housekeeping Checklist

- [ ] All log files under 10MB (rotate if needed)
- [ ] No stale .state.json files older than 7 days
- [ ] All security/ files have correct permissions (600/700)
- [ ] Sentinel and cipher scripts are executable
- [ ] No orphaned temp files in agents/nel/
- [ ] Report published to website/docs/nel/ for HQ visibility
- [ ] Ledger entries all have corresponding ACTIVE.md view
