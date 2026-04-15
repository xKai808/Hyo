# Pattern Library
# When a pattern appears 3+ times, it becomes a standing rule.
# Standing rules go into tacit.md immediately.

---
## Pattern: Flag-without-fix loop
- First seen: 2026-04-11
- Occurrences: 3 (Ra newsletter blocked 3 consecutive days)
- Trigger: Agent reports the same blocker in consecutive cycle reports
- Response: Create a BLOCKED ticket with SLA. Escalate to Kai if not resolved within SLA.
- Added to: AGENT_ALGORITHMS.md (Ticket System), kai/WORKFLOW_SYSTEMS.md
- Rule: Flagging is not fixing. Every flag must become a ticket within 1 cycle.
## Pattern: Sandbox-Mini gap
- First seen: 2026-04-12
- Occurrences: 4 (morning report, newsletter, git push, API endpoint tests)
- Trigger: Script generates output in Cowork sandbox but cannot push/deploy to production
- Response: Route all production-affecting commands through `kai/queue/exec.sh` on Mini
- Added to: CLAUDE.md (EXECUTION MODE), healthcheck.sh (auto-remediate)
- Rule: Never assume sandbox output reached production. Verify via live URL or queue worker.
## Pattern: Dual-copy desync (feed.json)
- First seen: 2026-04-13
- Occurrences: 3 (feed.json, morning-report.json, hq-state.json)
- Trigger: File exists at `website/data/` AND `agents/sam/website/data/` — only one gets updated
- Response: Every write to website/data/ must also write to agents/sam/website/data/ (publish-to-feed.sh does this)
- Added to: bin/publish-to-feed.sh (dual-write), agents/sam/verify.sh (sync check)
- Rule: If a data file exists in both paths, BOTH get written. Sam verify.sh checks sync.
## Pattern: Security header side effects
- First seen: 2026-04-14
- Occurrences: 1 (X-Frame-Options DENY breaking research iframe)
- Trigger: Changing a global security header without testing all pages that load in iframes
- Response: Sam verify.sh checks X-Frame-Options is SAMEORIGIN. System 3 Sprint requires secondary/tertiary effect analysis.
- Status: Not yet a rule (1 occurrence). Watching.
