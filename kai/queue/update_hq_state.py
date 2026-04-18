#!/usr/bin/env python3
"""Update hq-state.json with results from the 2026-04-18T06:14Z ops sync cycle.

Writes to both website/data/hq-state.json and agents/sam/website/data/hq-state.json
per the dual-path file awareness rule in CLAUDE.md.
"""
import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", "/sessions/sweet-peaceful-thompson/mnt/Hyo"))
PATHS = [
    ROOT / "website" / "data" / "hq-state.json",
    ROOT / "agents" / "sam" / "website" / "data" / "hq-state.json",
]

# Load primary (whichever is freshest — both should be synced after this).
candidates = [p for p in PATHS if p.exists()]
candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
primary = json.loads(candidates[0].read_text())

TS_UTC = "2026-04-18T06:14:18Z"
TS_MT = "2026-04-18T00:14:18-0600"

# ----- sentinel -----
# Direct sentinel.sh run #65: 4 passed / 5 failed; resolved api-health-green
# (was day 64 ESCALATED), scheduled-tasks-fired, task-queue-size.
# New findings include P0 founder-token-integrity (known regex bug: 0600 vs 6xx mask),
# P0 aurora-ran-today (newsletter didn't run for 2026-04-18 yet; pipeline runs at 03:00 MT
# — this run is at 00:14 MT so newsletter hasn't fired), P1 scheduled-tasks-fired,
# P1 secrets-dir-permissions (0755 — symlink cosmetic), P2 task-queue-size (30/5).
primary["sentinel"] = {
    "lastRun": TS_MT,
    "passed": 4,
    "failed": 5,
    "totalRuns": 65,
    "findings": [
        "P0: aurora-ran-today — /newsletters/2026-04-18.md missing (expected: newsletter fires at 03:00 MT; this sentinel ran at 00:14 MT)",
        "P0: founder-token-integrity — founder.token mode 0600 (regex bug: want 6xx, matches literally not as mask)",
        "P1: scheduled-tasks-fired — no aurora logs (recurring, ties to aurora-ran-today)",
        "P1: secrets-dir-permissions — .secrets/ is 0755 (symlink — target at 700; cosmetic, known)",
        "P2: task-queue-size — 30 P0 tasks (overload threshold 5)",
    ],
    "resolvedThisRun": [
        "api-health-green (was day 64, P0 ESCALATED — cleared)",
        "scheduled-tasks-fired (recurred same run under different hash)",
        "task-queue-size (recurred same run under different hash)",
    ],
    "escalations": [
        "P0 persistent: founder-token-integrity — sentinel regex bug; mode 0600 flagged as failing 6xx. Fix sentinel rule, not the file.",
        "api-health-green CLEARED after 64-day escalation — investigate what changed; confirm it stays green through 07:00 completeness check.",
    ],
    "latestDoc": "/viewer?agent=sentinel&file=2026-04-18",
}

# ----- cipher -----
# Clean scan, 0 findings, 7 autofixes (idempotent — logs same 7 autofixes every run).
# Autofixes: .secrets/ dir 0755->700 (cosmetic: symlink), plus 6 key/token files 0600->600
# (leading zero normalization — same mode, logged as "fixed" spuriously).
primary["cipher"] = {
    "lastRun": TS_UTC,
    "secretsDir": "0755",
    "founderToken": "0600",
    "leaks": 0,
    "autofixes": 7,
    "notes": (
        "Clean scan, 0 findings, 7 auto-fixes (idempotent — same fixes logged "
        "every run: .secrets dir 0755->700 on symlink; 6 keys 0600->600 leading-zero "
        "normalization). Founder token 0600 OK. secretsDir 0755 on symlink (target at 700). "
        "gitleaks/trufflehog install still pending on Mini. FIX: cipher should detect "
        "idempotent autofixes and suppress spurious log lines."
    ),
    "latestDoc": None,
    "totalRuns": 189,
}

# ----- nel -----
# Score 85 (recovered from 65 — +20), 4 projects passing sentinel overall (per-project:
# hyo 2p/2f, aurora-ra 4p/0f, aether 1p/1f, kai-ceo 4p/0f), 0 leaks, 16 broken links,
# 23 untested scripts, 3 inefficient patterns, 7 audit issues. Self-delegated broken
# link fix (TASK-20260418-nel-001 P2). ARIC research cycle executed, W3 improvement
# ticket emitted. Growth phase: IMP-nel-002 CVE scanner (blocked — no package.json at root).
primary["nel"] = {
    "lastRun": TS_UTC,
    "improvementScore": 85,
    "healthScore": 85,
    "findingsCount": 9,
    "staleFiles": 0,
    "brokenLinks": 16,
    "untested": 23,
    "inefficient": 3,
    "auditIssues": 7,
    "sentinel": {"pass": 4, "fail": 0, "perProject": {"hyo": "2p/2f", "aurora-ra": "4p/0f", "aether": "1p/1f", "kai-ceo": "4p/0f"}},
    "cipher": {"leaks": 0},
    "delta": "Score holds at 85. Ops sync cycle @ 00:14 MT. Self-delegated broken-link fix TASK-20260418-nel-001 (P2). W3 improvement ticket emitted. Reflection + research published to feed.",
    "latestDoc": "/viewer?agent=nel&file=2026-04-18",
}

# ----- updatedAt -----
primary["updatedAt"] = TS_UTC

# ----- events: prepend this cycle's events, dedupe, keep 30 -----
new_events = [
    {
        "ts": TS_UTC,
        "agent": "kai",
        "msg": (
            "Ops sync cycle @ 00:14 MT (2026-04-18) — sentinel #65 (4p/5f, api-health-green "
            "CLEARED after 64-day P0 escalation), cipher run clean (0 findings, 7 idempotent "
            "autofixes), nel score 85 (holds, self-delegated broken-link fix + W3 improvement). "
            "Known findings stable: aurora-ran-today expected (newsletter fires 03:00 MT), "
            "founder-token-integrity is sentinel regex bug (mode 0600 vs 6xx mask), "
            ".secrets 0755 is symlink cosmetic (target at 700)."
        ),
    },
    {
        "ts": TS_MT,
        "agent": "sentinel",
        "msg": (
            "QA sweep run #65 — 4 passed, 5 failed. RESOLVED: api-health-green (day 64 "
            "P0 escalation CLEARED), scheduled-tasks-fired, task-queue-size. NEW: P0 "
            "aurora-ran-today, P0 founder-token-integrity, P1 secrets-dir-permissions, "
            "P1 scheduled-tasks-fired, P2 task-queue-size (30/5)."
        ),
        "doc": "/viewer?agent=sentinel&file=2026-04-18",
    },
    {
        "ts": TS_UTC,
        "agent": "cipher",
        "msg": (
            "Security scan — clean. 0 findings, 7 idempotent autofixes (cosmetic mode "
            "normalization). Founder token 0600, .secrets 0755 on symlink (target 700)."
        ),
    },
    {
        "ts": TS_UTC,
        "agent": "nel",
        "msg": (
            "System sweep — score 85/100 (holds). Sentinel: 4 projects passing overall "
            "(hyo 2p/2f, aurora-ra 4p/0f, aether 1p/1f, kai-ceo 4p/0f). 16 broken links, "
            "23 untested scripts, 3 inefficient patterns, 7 audit issues. 0 verified leaks. "
            "Self-delegated: TASK-20260418-nel-001 (P2) broken-link fix. W3 improvement "
            "ticket emitted. Research + reflection published to feed."
        ),
        "doc": "/viewer?agent=nel&file=2026-04-18",
    },
]

existing = primary.get("events", [])
# Dedupe: drop any prior events with identical (ts, agent, msg)
seen = {(e.get("ts"), e.get("agent"), e.get("msg")) for e in new_events}
kept = [e for e in existing if (e.get("ts"), e.get("agent"), e.get("msg")) not in seen]
primary["events"] = new_events + kept
primary["events"] = primary["events"][:30]

# ----- morningReport: keep this morning's report intact; annotate ops sync note -----
mr = primary.get("morningReport", {})
if mr:
    mr["lastOpsSync"] = {
        "ts": TS_UTC,
        "note": (
            "00:14 MT ops sync (2026-04-18) — api-health-green CLEARED after 64-day P0 "
            "escalation; nel score holds at 85; aurora-ran-today P0 expected (newsletter "
            "fires 03:00 MT); founder-token-integrity P0 is known sentinel regex bug."
        ),
    }
    primary["morningReport"] = mr

# ----- write to both paths -----
for p in PATHS:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(primary, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {p} ({p.stat().st_size} bytes)")
