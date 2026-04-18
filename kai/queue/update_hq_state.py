#!/usr/bin/env python3
"""Update hq-state.json with results from the 2026-04-17T23:54Z ops sync cycle.

Writes to both website/data/hq-state.json and agents/sam/website/data/hq-state.json
per the dual-path file awareness rule in CLAUDE.md.
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", "/sessions/epic-exciting-tesla/mnt/Hyo"))
PATHS = [
    ROOT / "website" / "data" / "hq-state.json",
    ROOT / "agents" / "sam" / "website" / "data" / "hq-state.json",
]

# Source of truth: the more-complete file (primary website/data path)
primary = json.loads(PATHS[0].read_text())

TS_UTC = "2026-04-17T23:54:07Z"
TS_MT = "2026-04-17T17:54:07-0600"

# ----- sentinel -----
primary["sentinel"] = {
    "lastRun": TS_MT,
    "passed": 5,
    "failed": 4,
    "totalRuns": 63,
    "findings": [
        "P0: founder-token-integrity — mode 0600 but policy wants 6xx (new this run)",
        "P1: secrets-dir-permissions — .secrets/ is 0755 (want 700)",
        "P1: scheduled-tasks-fired — no aurora logs (recurring)",
        "P2: task-queue-size — 25 P0 tasks / threshold 5",
    ],
    "resolvedThisRun": [
        "api-health-green (was day 62, ESCALATED)",
        "aurora-ran-today (was day 4)",
        "scheduled-tasks-fired (recurred same run)",
        "task-queue-size (recurred same run)",
    ],
    "escalations": [
        "P0 new: founder-token-integrity — investigate sentinel rule vs cipher autofix (both agree mode=0600 but sentinel flags it)",
    ],
    "latestDoc": "/viewer?agent=sentinel&file=2026-04-17",
}

# ----- cipher -----
primary["cipher"] = {
    "lastRun": TS_UTC,
    "secretsDir": "0755",
    "founderToken": "0600",
    "leaks": 0,
    "autofixes": 6,
    "notes": (
        "Authoritative scan on Mini. 0 findings, 6 auto-fixes applied. "
        "Disagreement with sentinel: cipher reports .secrets/ at 0755 after autofix; "
        "sentinel P1 flags 0755 (want 700). Investigate whether autofix is idempotent "
        "or whether another process is resetting perms. brew install gitleaks + trufflehog still pending on Mini."
    ),
    "latestDoc": None,
    "totalRuns": 214,
}

# ----- nel -----
primary["nel"] = {
    "lastRun": TS_UTC,
    "improvementScore": 85,
    "healthScore": 85,
    "findingsCount": 5,
    "staleFiles": 0,
    "brokenLinks": 16,
    "untested": 14,
    "inefficient": 1,
    "sensitiveFilesOutsideSecrets": 5,
    "repoFiles": 1540,
    "repoSizeMb": 80,
    "sentinel": {"pass": 4, "fail": 4},  # per-project aggregate: hyo 2p/2f, aurora-ra 4p/0f, aether 1p/1f, kai-ceo 4p/0f → but nel summary said "4 projects passing"; we'll use their aggregate pass count
    "cipher": {"leaks": 0},
    "delta": "Score recovered 65 → 85 vs morning run (+20). api-health-green resolved after 62 days.",
    "latestDoc": "/viewer?agent=nel&file=2026-04-17",
}

# ----- updatedAt -----
primary["updatedAt"] = TS_UTC

# ----- events: prepend this cycle's events -----
new_events = [
    {
        "ts": TS_UTC,
        "agent": "kai",
        "msg": (
            "Ops sync cycle 17:54 MT — sentinel run #63 (5p/4f; resolved api-health-green "
            "after 62-day escalation and aurora-ran-today after 4 days; new P0 "
            "founder-token-integrity), cipher run #214 (0 findings, 6 autofixes), nel "
            "score 85 (up from 65, +20). Two agents disagree on .secrets/ mode — investigating."
        ),
    },
    {
        "ts": TS_MT,
        "agent": "sentinel",
        "msg": (
            "QA sweep run #63 — 5 passed, 4 failed. RESOLVED: api-health-green (day 62 "
            "escalation cleared), aurora-ran-today (day 4 cleared). NEW: P0 "
            "founder-token-integrity, P1 secrets-dir-permissions (0755 vs 700), "
            "P1 scheduled-tasks-fired (recurring), P2 task-queue-size (25/5)."
        ),
        "doc": "/viewer?agent=sentinel&file=2026-04-17",
    },
    {
        "ts": TS_UTC,
        "agent": "cipher",
        "msg": (
            "Security scan run #214 (authoritative, on Mini) — 0 leaks, 6 auto-fixes. "
            "Founder token 0600, .secrets 0755 (conflicts with sentinel P1 expectation of 700)."
        ),
    },
    {
        "ts": TS_UTC,
        "agent": "nel",
        "msg": (
            "System sweep — score 85/100 (recovered from 65). 16 broken links (unchanged), "
            "14 untested scripts, 1 inefficient pattern, 5 sensitive files outside .secrets/ "
            "(.env.local ×2, .env.example, claude_api_tokens CSV ×2). Stale files: 0."
        ),
        "doc": "/viewer?agent=nel&file=2026-04-17",
    },
]

existing = primary.get("events", [])
# Dedupe: drop any prior events with identical (ts, agent, msg)
seen = {(e.get("ts"), e.get("agent"), e.get("msg")) for e in new_events}
kept = [e for e in existing if (e.get("ts"), e.get("agent"), e.get("msg")) not in seen]
primary["events"] = new_events + kept
# Keep at most 30 events
primary["events"] = primary["events"][:30]

# ----- morningReport: leave the morning snapshot intact, but append a note -----
mr = primary.get("morningReport", {})
if mr:
    mr["lastOpsSync"] = {
        "ts": TS_UTC,
        "note": "17:54 MT ops sync — api-health-green resolved after 62 days; score 65→85.",
    }
    primary["morningReport"] = mr

# ----- write to both paths -----
for p in PATHS:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(primary, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {p} ({p.stat().st_size} bytes)")
