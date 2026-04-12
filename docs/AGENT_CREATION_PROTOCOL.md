# Agent Creation Protocol

**Version:** 1.0 | **Author:** Kai (CEO, hyo.world) | **Date:** 2026-04-13
**Status:** Battle-tested across 8 agents (Kai, Sam, Nel, Ra, Aurora, Aether, Dex, + Cipher/Sentinel sub-agents)

This document is the complete, repeatable protocol for creating, integrating, testing, and operating an autonomous agent within a multi-agent system. It was developed through iterative production use — every step exists because skipping it caused a failure at some point.

This protocol is designed to be portable. The Hyo-specific implementation details are included as examples, but the patterns apply to any dispatch-based agent architecture.

---

## Table of Contents

1. Pre-Creation (Define the Agent)
2. File Structure (Build the Skeleton)
3. Manifest (Identity Card)
4. Runner Script (Execution Engine)
5. Dispatch Integration (Closed-Loop Communication)
6. Algorithm Documentation (Runbook)
7. CEO/Dispatcher Integration (Routing)
8. Dashboard/UI Integration (Visibility)
9. Schedule (Automation)
10. Testing Protocol (8-Point Validation)
11. Migration Protocol (Renaming/Restructuring)
12. Post-Creation (Maintenance)
13. Appendix: Failure Catalog

---

## 1. Pre-Creation: Define the Agent

Before writing a single file, answer these questions. If you can't answer all of them, the agent isn't ready to be built.

**Identity:**
- What is the agent's name? (Short, memorable, no spaces. Will become directory names, CLI commands, manifest keys.)
- What is the agent's one-sentence role? (If it takes more than one sentence, you're building two agents.)
- What does this agent own that no other agent owns? (Ownership must be exclusive. Overlapping ownership creates race conditions and confusion.)

**Boundaries:**
- What does this agent do that a human currently does manually? (This is the automation justification.)
- What does this agent NOT do? (Negative space is as important as positive. Document it.)
- Which other agents does it interact with? (Upstream: who gives it work. Downstream: who consumes its output.)

**Data:**
- What data does this agent read? (Input files, APIs, ledgers.)
- What data does this agent write? (Output files, metrics, reports.)
- What data does this agent own exclusively? (Its ledger, its logs, its state.)

**Schedule:**
- Does it run on a schedule? (Every N minutes, daily at time X, on-demand only.)
- Does it run in response to events? (Trade recorded, file changed, flag raised.)
- What happens if it misses a scheduled run? (Idempotent recovery? Silent skip? Escalation?)

**Example — Aether (Trading Intelligence):**
- Name: aether
- Role: Trading metrics collector, portfolio monitor, GPT-powered fact-checker
- Owns: Trade recording, weekly metrics, exchange API integration, all GPT/OpenAI calls
- Does NOT do: Execute trades (human only), manage infrastructure (Sam), audit security (Nel)
- Interacts with: Kai (receives delegations, reports results), Nel (gets audited), HQ dashboard (pushes metrics)
- Schedule: Every 15 minutes via launchd

**Example — Dex (System Memory Manager):**
- Name: dex
- Role: Ledger integrity, compaction, stale task detection, pattern recognition
- Owns: JSONL validation, archive compaction, cross-agent pattern detection
- Does NOT do: Create tasks (Kai), write code (Sam), gather intelligence (Ra)
- Interacts with: Every agent (reads their ledgers), Kai (reports findings), Nel (complementary auditing)
- Schedule: Daily at 23:00 MT (before nightly simulation)

---

## 2. File Structure: Build the Skeleton

Every agent follows the same directory structure. No exceptions. Consistency is what makes the system debuggable at 2 AM.

```
agents/<name>/
├── <name>.sh              ← Runner script (the agent's brain)
├── PRIORITIES.md           ← Current operational priorities
├── ledger/
│   ├── ACTIVE.md          ← Open tasks assigned to this agent
│   └── log.jsonl          ← Append-only event log
├── logs/
│   └── <name>-YYYY-MM-DD.log  ← Daily execution logs
└── [optional domain-specific files]
    ├── com.hyo.<name>.plist    ← macOS launchd schedule
    ├── data/                   ← Agent-specific data files
    └── ...
```

**Create the skeleton first, populate second:**
```bash
NAME="myagent"
mkdir -p agents/$NAME/ledger agents/$NAME/logs
touch agents/$NAME/$NAME.sh
chmod +x agents/$NAME/$NAME.sh
touch agents/$NAME/ledger/log.jsonl
```

**ACTIVE.md template:**
```markdown
# <Name> Agent — Active Tasks

_Last updated: YYYY-MM-DD_

## Open

(none)

## Recently Closed

(none)
```

**PRIORITIES.md template:**
```markdown
# <Name> Agent — Operational Priorities

## P0 (Critical)
- [describe the thing that must never break]

## P1 (Important)
- [describe the thing that should run reliably]

## P2 (Improvement)
- [describe what would make this agent better]

## Success Criteria
- [how do you know this agent is working?]
```

---

## 3. Manifest: Identity Card

The manifest is a JSON file that describes the agent to the rest of the system. Think of it as the agent's passport — it contains everything another agent or human needs to know to interact with it.

**Location:** `agents/manifests/<name>.hyo.json`

**Required fields:**
```json
{
  "name": "<name>.hyo",
  "version": "1.0.0",
  "identity": {
    "handle": "@<name>",
    "role": "One-sentence description of what this agent does",
    "oneLiner": "Even shorter — used in dashboards and logs",
    "operator": "hyo.world"
  },
  "capabilities": [
    "capability-one",
    "capability-two"
  ],
  "inputs": [
    "list/of/files/this/agent/reads"
  ],
  "outputs": [
    {
      "name": "output-name",
      "path": "where/it/writes",
      "format": "markdown|jsonl|json|html"
    }
  ],
  "pipeline": {
    "entrypoint": "agents/<name>/<name>.sh",
    "schedule": "cron expression or 'on-demand'",
    "scheduleTimezone": "America/Denver",
    "runtime": "bash",
    "invocation": "kai <name> [subcommands]"
  },
  "monitors": [
    {
      "id": "monitor-name",
      "description": "What this monitors",
      "frequency": "how often",
      "priority": "P0|P1|P2|P3"
    }
  ],
  "credit": {
    "tier": "founding",
    "fees": "waived"
  }
}
```

**Validation check:** After writing the manifest, parse it:
```bash
python3 -c "import json; json.load(open('agents/manifests/<name>.hyo.json')); print('valid')"
```

---

## 4. Runner Script: Execution Engine

The runner is a bash script that IS the agent. It reads state, does work, writes results, and reports back to the CEO.

**Template structure:**
```bash
#!/usr/bin/env bash
# agents/<name>/<name>.sh — <Name> agent runner
#
# Usage:
#   bash <name>.sh              # normal run
#   bash <name>.sh [subcommand] # specific operation

set -uo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
AGENT_HOME="$ROOT/agents/<name>"
LOGS="$AGENT_HOME/logs"
LEDGER="$AGENT_HOME/ledger"
SECRETS="$ROOT/agents/nel/security"

mkdir -p "$LOGS"

LOG="$LOGS/<name>-$(date +%Y-%m-%d).log"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S-06:00")

log() { echo "[$TS] $*" | tee -a "$LOG"; }

# ─── Phase 1: [Name of phase] ────────────────────────────────────────────────
phase_one() {
  log "Phase 1: [description]"
  # ... do work ...
  log "Phase 1 complete"
}

# ─── Phase N: Report ──────────────────────────────────────────────────────────
phase_report() {
  log "Writing report"
  # Write human-readable report to logs/
  # Dispatch results to CEO
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    bash "$dispatch_bin" report <name> "summary of what happened" 2>> "$LOG" || true
  fi
}

# ─── Error trap ───────────────────────────────────────────────────────────────
trap_error() {
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    bash "$dispatch_bin" flag <name> P2 "<name>.sh exited with error" 2>/dev/null || true
  fi
}
trap trap_error ERR

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "=== <Name> agent run ==="
  phase_one
  # ... more phases ...
  phase_report
  log "Run complete"
}

main "$@"
```

**Critical requirements:**
1. `set -uo pipefail` — fail fast on errors and undefined variables
2. `trap trap_error ERR` — report failures to dispatch
3. `dispatch report` at the end — close the loop
4. Mountain Time timestamps — consistency across all agents
5. Logs to `agents/<name>/logs/` — one file per day
6. Secrets only from `agents/nel/security/` — never hardcoded

---

## 5. Dispatch Integration: Closed-Loop Communication

Every agent MUST integrate with the dispatch system. This is non-negotiable. Without dispatch, the CEO can't verify the agent ran, can't detect failures, and can't track task lifecycles.

**Minimum dispatch calls every runner must make:**
```bash
# On success:
dispatch report <name> "what happened"

# On failure:
dispatch flag <name> P<level> "what went wrong"

# On finding something noteworthy:
dispatch flag <name> P<level> "what was found"
```

**Priority levels:**
- P0: System-breaking. Immediate attention required.
- P1: Important. Should be addressed within 24 hours.
- P2: Notable. Address when convenient.
- P3: Informational. Log for pattern detection.

**Task lifecycle through dispatch:**
```
1. Kai delegates:     dispatch delegate <name> "task description"
2. Agent acknowledges: dispatch ack <task_id>
3. Agent works:       (does the work)
4. Agent reports:     dispatch report <name> "results"
5. Kai verifies:      (checks the output)
6. Kai closes:        dispatch close <task_id>
```

---

## 6. Algorithm Documentation: Runbook

Every agent gets a section in the central algorithms file (`kai/AGENT_ALGORITHMS.md`). This is the source of truth for how the agent behaves.

**Template:**
```
## <Name> — <Role Description> Algorithm

STARTUP:
  1. Read agents/<name>/PRIORITIES.md
  2. Read agents/<name>/ledger/ACTIVE.md
  3. [Agent-specific initialization]

[PHASE/CYCLE/OPERATION descriptions]:
  1. [Step with specific action]
  2. [Step with conditional: IF condition → action]
  3. [Step with dispatch call]

FAILURE MODES:
  - [Failure scenario] → [recovery action]
  - [Failure scenario] → [escalation action]
```

---

## 7. CEO/Dispatcher Integration: Routing

The CEO dispatcher (`bin/kai.sh`) must know how to invoke the agent.

**Add to the case statement:**
```bash
<name>)  bash "$ROOT/agents/<name>/<name>.sh" "$@" ;;
```

**Add to the help text:**
```
kai <name>                Run the <Name> agent
```

**Add to the agent list in push help:**
```
agent: ra|aurora|sentinel|cipher|sim|consolidation|aether|dex|<name>
```

---

## 8. Dashboard/UI Integration: Visibility

If the agent produces data that should be visible in a dashboard:

1. Create a Vercel API endpoint: `website/api/<name>.js`
2. Add a view section in `website/hq.html`
3. Add navigation entry in the sidebar
4. Wire the data loading function
5. Mirror changes to `agents/sam/website/` if that copy exists

**API endpoint template (Vercel serverless):**
```javascript
export default function handler(req, res) {
  const { action } = req.query;
  
  if (req.method === 'GET' && action === 'metrics') {
    return res.json(globalThis.__<name> || { status: 'no data' });
  }
  
  if (req.method === 'POST' && action === 'metrics') {
    // Validate token
    const token = req.headers['x-founder-token'];
    // Store data
    globalThis.__<name> = req.body;
    return res.json({ ok: true });
  }
  
  return res.json({ agent: '<name>', status: 'operational' });
}
```

---

## 9. Schedule: Automation

For agents that run on a schedule, create a macOS launchd plist.

**Location:** `agents/<name>/com.hyo.<name>.plist`

**Template (interval-based — every N seconds):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hyo.<name></string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/node</string>
        <string>/Users/kai/Documents/Projects/Hyo/agents/<name>/<name>.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/hyo-<name>.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/hyo-<name>.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HYO_ROOT</key>
        <string>/Users/kai/Documents/Projects/Hyo</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Template (calendar-based — specific time daily):**
```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

**Installation:**
```bash
cp agents/<name>/com.hyo.<name>.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hyo.<name>.plist
```

**Verification:**
```bash
launchctl list | grep hyo
```

---

## 10. Testing Protocol: 8-Point Validation

Run ALL 8 tests before declaring an agent production-ready. No exceptions.

### Test 1: Manifest Validation
```bash
python3 -c "import json; d=json.load(open('agents/manifests/<name>.hyo.json')); print('PASS' if 'name' in d and 'capabilities' in d else 'FAIL')"
```
- Valid JSON
- Required fields present
- No stale references to old names
- Paths point to correct directories

### Test 2: Runner Script Syntax
```bash
bash -n agents/<name>/<name>.sh && echo "PASS" || echo "FAIL"
```

### Test 3: File Structure Completeness
```bash
for f in agents/<name>/<name>.sh agents/<name>/PRIORITIES.md agents/<name>/ledger/ACTIVE.md agents/<name>/ledger/log.jsonl; do
  [[ -f "$f" ]] && echo "PASS: $f" || echo "FAIL: $f missing"
done
[[ -d agents/<name>/logs ]] && echo "PASS: logs/" || echo "FAIL: logs/ missing"
[[ -x agents/<name>/<name>.sh ]] && echo "PASS: executable" || echo "FAIL: not executable"
```

### Test 4: Dispatcher Integration
```bash
grep -q "<name>" bin/kai.sh && echo "PASS" || echo "FAIL: not in kai.sh"
```

### Test 5: API Endpoint (if applicable)
```bash
[[ -f website/api/<name>.js ]] && node -c website/api/<name>.js && echo "PASS" || echo "FAIL or N/A"
```

### Test 6: Dashboard Integration (if applicable)
```bash
grep -c "<name>" website/hq.html  # Should be > 0 if dashboard view exists
grep -c "oldname" website/hq.html  # Should be 0 — no stale references
```

### Test 7: Dispatch Integration
```bash
grep -c "dispatch" agents/<name>/<name>.sh  # Should be >= 2 (report + flag)
```

### Test 8: Algorithm Documented
```bash
grep -q "## <Name>" kai/AGENT_ALGORITHMS.md && echo "PASS" || echo "FAIL"
```

**Scoring:** All 8 must PASS. Any FAIL blocks production deployment.

---

## 11. Migration Protocol: Renaming/Restructuring

When an agent needs to be renamed (e.g., "aetherbot" → "aether"):

**Phase 1: Create new files**
1. Create new directory structure under the new name
2. Copy each file, renaming content (agent name, paths, variables, function names)
3. Create new manifest with updated name
4. If API endpoint exists: create new endpoint file with renamed content
5. If dashboard references exist: update HTML, CSS classes, data attributes, function names

**Phase 2: Update cross-cutting files**
These files reference agents by name and must be updated:
- `bin/kai.sh` (dispatcher routing + help text)
- `kai/AGENT_ALGORITHMS.md` (algorithm section header + content)
- `KAI_BRIEF.md` (shipped items, scheduled tasks, operational model)
- `KAI_TASKS.md` (any tasks referencing the agent)
- `CLAUDE.md` (project layout, hydration protocol)
- `agents/nel/nel.sh` (consolidation targets)
- `agents/nel/consolidation/consolidate.sh` (project list)
- All files in `agents/nel/logs/` and `website/docs/` that mention the agent
- `NFT/HyoRegistry_Notes.md` (if agent is registered)

**Phase 3: Delete old files**
Only after verifying zero orphaned references:
```bash
grep -r "oldname" . --include="*.sh" --include="*.js" --include="*.json" --include="*.md" --include="*.html"
```
If this returns zero results, delete the old directory and manifest.

**Phase 4: Full test protocol**
Run all 8 tests from Section 10 on the renamed agent.

---

## 12. Post-Creation: Maintenance

**Daily:**
- Agent runs on schedule (verify via logs or dispatch status)
- No P0/P1 flags raised

**Weekly:**
- Review PRIORITIES.md — are priorities still correct?
- Check ledger/ACTIVE.md — any stale tasks?
- Review logs for patterns — same warnings repeating?

**Monthly:**
- Run full 8-point test protocol again
- Review manifest — capabilities still accurate?
- Dex (or equivalent memory manager) runs compaction on the agent's ledger

**On every code change:**
- Run `bash -n` syntax check
- Run dispatch integration check (grep for dispatch calls)
- Verify no broken references (grep for the agent name in changed files)

---

## 13. Appendix: Failure Catalog

Failures we've hit in production, documented so they never happen again.

**F1: SDK schema mismatch**
- Symptom: "Tool X expected a Zod schema or ToolAnnotations, but received an unrecognized object"
- Cause: MCP SDK v1.29.0 requires Zod schemas, not plain JS objects
- Fix: Import `{ z } from "zod"` and use `z.string()`, `z.number().optional()`, etc.
- Prevention: Always check SDK version requirements before building tool definitions

**F2: Orphaned references after rename**
- Symptom: Dashboard shows old agent name, dispatch routes to nonexistent path
- Cause: Incomplete search during rename — missed files in docs/, logs/, website/
- Fix: `grep -r "oldname" . --include="*.{sh,js,json,md,html}"` before deleting old files
- Prevention: Section 11 of this protocol. Run the orphan scan. Every time.

**F3: Silent task drops**
- Symptom: Task delegated but never completed, no error, no flag
- Cause: Agent runner didn't integrate with dispatch — no ACK, no report
- Fix: Add dispatch report/flag calls (Section 5)
- Prevention: Test 7 in the testing protocol catches this

**F4: Dispatch flag with wrong agent name**
- Symptom: Flag appears in wrong agent's ledger, can't trace back to source
- Cause: Copy-paste from another agent's runner without updating the agent name
- Fix: Grep the runner for `dispatch.*<oldname>` and fix
- Prevention: Test 7 specifically checks that dispatch calls use the correct agent name

**F5: Missing error trap**
- Symptom: Agent crashes silently, no dispatch flag, no one knows
- Cause: No `trap trap_error ERR` in the runner
- Fix: Add the error trap (see runner template in Section 4)
- Prevention: Test 7 checks for dispatch flag calls, which implies trap exists

**F6: Hardcoded secrets**
- Symptom: API key committed to git
- Cause: Secret written directly in script instead of reading from secrets directory
- Fix: Move to agents/nel/security/, gitignore, mode 600
- Prevention: Nel's cipher.sh scans for this. Also: never accept a key as a variable — always read from file at runtime.

**F7: Timezone drift**
- Symptom: Monday reset fires on Sunday, logs show wrong dates
- Cause: Using system timezone instead of explicit `TZ="America/Denver"`
- Fix: Prefix all date commands with `TZ="America/Denver"`
- Prevention: Runner template includes this. Nel checks for UTC timestamps.

**F8: Dashboard loads stale data**
- Symptom: HQ shows old metrics even after agent runs
- Cause: Dashboard reads from static JSON file but agent pushes to API — API uses in-memory store that resets on cold start
- Fix: Agent writes to static JSON (file-based persistence) AND pushes to API (live updates)
- Prevention: Dual-write pattern in Aether's runner. Both paths must be present.

---

## License

This protocol is proprietary to hyo.world. It may be licensed for use in other agent systems. Contact hyo.world for licensing inquiries.

---

*Built through production failures, not theory. Every line exists because something broke without it.*
