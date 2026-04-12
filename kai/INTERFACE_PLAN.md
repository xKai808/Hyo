# Hyo Visibility Interface Plan

**Author:** Kai | **Date:** 2026-04-12
**Purpose:** Give Hyo real-time visibility into all agent activity without needing to open Cowork.

---

## Two-Layer Approach

### Layer 1: Discord (Real-Time Notifications)

**Why Discord:** Free, webhook-based (no API key needed for posting), works on mobile, supports threads, and Nat Eliason validates the pattern with Felix.

**Channel Structure:**
```
#kai-status        — Kai's 3-line status at session start/end
#nel-activity      — Nel's findings, flags, audit results
#sam-activity      — Sam's test results, deploy status, code changes  
#ra-activity       — Ra's pipeline health, source status, newsletter output
#flags             — All P0/P1/P2 flags from any agent (high signal)
#simulation-results — Nightly simulation pass/fail summary
#daily-digest      — Consolidated daily summary (Kai authors)
```

**Implementation:**
1. Create Discord server with channels above
2. Create webhooks for each channel (one-time manual setup by Hyo)
3. Store webhook URLs in `agents/nel/security/discord-hooks.json`
4. Add `dispatch notify <channel> <message>` command to dispatch.sh
5. Wire into agent runners: after every flag, report, or simulation → post to Discord
6. Daily digest: scheduled task compiles all activity into one summary post

**What posts to Discord:**
- Every `dispatch flag` (any severity) → #flags + agent channel
- Every nightly simulation result → #simulation-results
- Every agent runner completion → agent channel
- Session start/end status → #kai-status
- Daily research findings → agent channel

### Layer 2: HQ Dashboard (Deep Dive)

**Already exists at hyo.world/hq.** Enhancements needed:

1. **Agent Ledger View:** New tab showing each agent's ACTIVE.md + recent log entries
2. **Simulation History:** Graph of pass/fail over time from simulation-outcomes.jsonl  
3. **Known Issues Panel:** Display known-issues.jsonl with status indicators
4. **Research Feed:** Show latest research findings from all agents

**Implementation:** Sam builds these as new sections in hq.html, fed by existing JSONL data via the push API.

---

## Priority

1. **Discord webhooks** — highest ROI, gives Hyo mobile visibility immediately
2. **HQ ledger view** — gives deep-dive capability for when Hyo wants details
3. **HQ simulation graph** — gives trend visibility over time

---

## Next Steps

- [ ] Hyo creates Discord server + channels (requires Hyo's account)
- [ ] Hyo creates webhooks and saves URLs to security/discord-hooks.json
- [ ] Kai adds `dispatch notify` command
- [ ] Sam wires Discord into agent runners
- [ ] Sam builds HQ ledger view
