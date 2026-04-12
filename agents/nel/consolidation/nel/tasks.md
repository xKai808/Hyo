# Nel — Task Queue

**Purpose:** Nel's ongoing work. Task ownership: K = Kai, H = Hyo, B = both.

---

## Active — Current focus

- [ ] **[K]** Improve sentinel escalation logic to reduce false positives (3-day recurring threshold, known-false-positive list)
- [ ] **[K]** Add mtime < 25h guard to sentinel's aurora-ran-today check (prevent stale file from masking silent failure)
- [ ] **[K]** Analyze stale file candidates and batch-file archival tasks (consolidate into 1-2 P2 tasks in KAI_TASKS.md)
- [ ] **[K]** Create smoke-test suite for gather.py, synthesize.py, render.py (validate pipeline correctness)
- [ ] **[K]** Refactor $(cat) pattern in cipher.sh and other scripts (use <redirection instead)

## Pending — Next iteration

- [ ] **[K]** Add cross-project metrics dashboard to HQ (sentinel health per project, cipher scan frequency, improvement trend)
- [ ] **[K]** Implement nel-specific view in HQ that shows: findings by project, stale candidates, broken links, untested stages
- [ ] **[K]** Auto-file nel findings into KAI_TASKS.md using structured prefix: `- [ ] **[K]** [nel] [P{0-3}] ...`
- [ ] **[K]** Integrate nel with HQ data-push (every nel run syncs findings to hq-state.json → dashboard updates)
- [ ] **[K]** Add nel metrics to weekly consolidation report (improvement score trend, findings cadence)

## Strategic — System improvement roadmap

- [ ] **[K]** Design anti-fatigue rules for nel findings (don't repeat same stale-file task 3 weeks in a row, auto-suppress false positives after verification)
- [ ] **[K]** Build nel suggestion engine: for every finding, suggest the fix (broken link → suggest replacement, stale file → suggest archive, inefficient pattern → suggest refactor snippet)
- [ ] **[K]** Research code quality metrics generation (LOC per project, cyclomatic complexity via shellcheck, function coverage)
- [ ] **[K]** Create nel review workflow: nel files finding → Kai reviews → nel archives and learns from Kai's decision
- [ ] **[K]** Build nel-to-agent feedback loop (nel recommendations → agent owners get notified → agent owners provide feedback → nel learns what's actionable)

## Infrastructure — Platform improvements

- [ ] **[B]** Wire nel as an MCP tool (nel can be called from other agents, returns structured improvement recommendations)
- [ ] **[B]** Add nel to nightly consolidation schedule (currently weekly Sunday 05:00 MT — consider daily light scan + weekly deep dive)
- [ ] **[B]** Build nel webhook so external agents can report findings (e.g., "hey Nel, we noticed broken link here")
- [ ] **[K]** Create /api/nel GET endpoint that returns latest findings + improvement score (unblock nel status view on HQ)
- [ ] **[K]** Implement nel findings export (JSON, CSV, markdown) for external team consumption

---

## Done

_(No completed tasks yet — Nel is newly minted as of 2026-04-12.)_
