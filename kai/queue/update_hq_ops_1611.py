#!/usr/bin/env python3
"""Update HQ state with ops sync cycle results at 16:11 MT 2026-04-21.

Run #3 of day. Sentinel run #119: 6p/3f — REGRESSION from #118 (7p/2f).
1 NEW failure (kai-dispatcher-present — bin/kai.sh missing exec bit) FIXED via chmod +x.
"""
import json
import os
from pathlib import Path

HQ = Path(os.environ["HOME"]) / "Documents/Projects/Hyo/website/data/hq-state.json"
HQ_DUAL = Path(os.environ["HOME"]) / "Documents/Projects/Hyo/agents/sam/website/data/hq-state.json"

TS_UTC = "2026-04-21T22:12:00Z"
TS_MT = "2026-04-21T16:12:00-0600"

SUMMARY = (
    "Ops sync cycle @ 16:11 MT (2026-04-21, hq-ops-sync scheduled task, 4th of day). "
    "Sentinel run #119: 6p/3f REGRESSION from #118 (7p/2f) — 1 NEW failure detected and AUTO-REMEDIATED: "
    "kai-dispatcher-present P2 (bin/kai.sh mode 0600, missing exec bit — Kai ran chmod +x on Mini, "
    "now mode 0711, fixed in same cycle). Recurring: scheduled-tasks-fired P1 day 20 (benign, aurora runs "
    "on Mini not sandbox), task-queue-size P2 29 P0 (day 2, same as 12:11 cycle). "
    "Cipher: clean, 0 findings, 7 permission autofixes, gitleaks ran on working tree, dep-audit 3 pass / "
    "0 warn / 0 fail (Nel W2 CVE scanner stable). Note: cipher autofixes did NOT catch kai.sh exec bit "
    "regression — cipher's permission check may not include bin/ scripts (Nel fix-it candidate). "
    "Nel: score 85/100 stable, 4 projects passing sentinel, findings — 20 broken doc links (flat), "
    "30 untested scripts (UP from 29, +1 new script), 8 inefficient patterns (UP from 4, +4 regression), "
    "7 audit issues (flat), 5 sensitive files (flat), 1 untriggered file (flat), 0 leaks, 0 stale files. "
    "Cross-project sentinel: hyo=2p/2f, aurora-ra=4p/0f, aether=1p/1f, kai-ceo=4p/0f. "
    "ARIC research metrics-only (already published today). Growth phase idle (no open IMP tickets — "
    "IMP-20260414-nel-002 dep-audit shipped earlier today). Self-delegated: nel-001 P2 broken-symlinks "
    "(carried), nel-001 P2 [SELF-REVIEW] 1 untriggered file, nel-001 P3 cycle summary. "
    "Stderr: nel runner grep -P unsupported on BSD (P3 fix-it carried, day 5)."
)

EVENTS_TO_ADD = [
    {
        "ts": "2026-04-21T22:10:45Z",
        "agent": "sentinel",
        "msg": ("Sentinel run #119: 6p/3f — REGRESSION vs #118 (7p/2f). 1 new P2 failure: "
                "kai-dispatcher-present (bin/kai.sh missing exec bit). 2 recurring: "
                "scheduled-tasks-fired P1 day 20 (benign), task-queue-size P2 29 P0 (day 2)."),
        "severity": "warning",
    },
    {
        "ts": "2026-04-21T22:11:00Z",
        "agent": "cipher",
        "msg": ("Security scan #3 today — clean, 0 findings, 7 permission autofixes, gitleaks ran on "
                "tree, dep-audit 3 pass/0 warn/0 fail (W2 CVE scanner GREEN). Note: did NOT autofix "
                "bin/kai.sh exec bit regression (cipher scope gap — fix-it candidate)."),
        "severity": "info",
    },
    {
        "ts": "2026-04-21T22:11:21Z",
        "agent": "nel",
        "msg": ("Nel score 85/100 — 4p/0f cross-project. Regressions: inefficient patterns 4→8 (+4), "
                "untested scripts 29→30 (+1). Flat: broken links 20, audit issues 7, sensitive 5. "
                "HQ push 200 OK. Growth phase idle (no open IMP tickets)."),
        "severity": "warning",
    },
    {
        "ts": TS_UTC,
        "agent": "kai",
        "msg": ("Kai autonomous remediation: detected kai-dispatcher-present P2 failure in sentinel #119, "
                "ran chmod +x on bin/kai.sh via queue — restored to mode 0711. Verified present and "
                "executable. Next sentinel run expected to resolve this finding. Logged regression "
                "cause for Nel review (kai.sh was chmod'd to 0600 at 14:39 today — likely git op side "
                "effect)."),
        "severity": "info",
    },
]


def load(path):
    return json.loads(path.read_text())


def save(path, data):
    path.write_text(json.dumps(data, indent=2))


def update(d):
    # Top-level updatedAt
    d["updatedAt"] = TS_UTC

    # Morning report envelope: overwrite summary/lastOpsSync with this cycle
    mr = d.setdefault("morningReport", {})
    mr["summary"] = SUMMARY
    mr["systemStatus"] = "warnings"

    # topIssues: rewrite with current state
    mr["topIssues"] = [
        "Sentinel run #119 REGRESSION — 6p/3f (1 new P2 kai-dispatcher, 2 recurring) — new issue AUTO-FIXED this cycle",
        "Kai auto-remediated: chmod +x bin/kai.sh (was mode 0600 after 14:39 git op) — restored to 0711",
        "Inefficient patterns UP — 8 vs 4 prior cycle (+4 regression; 4 new `instead of < redirection` patterns)",
        "Untested scripts UP — 30 vs 29 prior (+1 new pipeline script lacking smoke test)",
        "Task queue P0 saturation continues — 29 P0 tasks vs threshold 5 (day 2)",
        "Scheduled-tasks-fired P1 day 20 ELEVATED (benign — aurora runs on Mini, not sandbox)",
        "Nel: 20 broken doc links (flat), 7 audit issues (flat), 5 sensitive files, 1 untriggered file",
        "Cipher dep-audit GREEN — IMP-20260414-nel-002 CVE scanner stable (3 pass / 0 warn / 0 fail)",
        "Cipher scope gap — did NOT autofix kai.sh exec bit regression (Nel fix-it candidate: extend cipher perm-check to bin/)",
        "Founder-token integrity P0 day 12 (cosmetic: mode 0600 valid but regex expects 6xx — fix regex)",
        "Nel runner stderr noise — grep -P unsupported on macOS BSD grep (P3 fix-it day 5)",
    ]

    mr["lastOpsSync"] = {
        "ts": TS_UTC,
        "tsMT": TS_MT,
        "note": SUMMARY,
        "agentsRun": ["sentinel", "cipher", "nel"],
        "results": {
            "sentinel": {
                "runId": 119,
                "passed": 6,
                "failed": 3,
                "new": 1,
                "recurring": 2,
                "resolved": 0,
                "regression": True,
                "newFailure": "kai-dispatcher-present",
                "autoRemediated": True,
            },
            "cipher": {
                "findings": 0,
                "autofixes": 7,
                "depAudit": {"pass": 3, "warn": 0, "fail": 0},
                "scopeGap": "did not catch bin/kai.sh exec bit regression",
            },
            "nel": {
                "score": 85,
                "projects": "4p/0f",
                "brokenLinks": 20,
                "untestedScripts": 30,
                "untestedScriptsDelta": "+1",
                "inefficientPatterns": 8,
                "inefficientPatternsDelta": "+4",
                "auditIssues": 7,
                "sensitiveFiles": 5,
                "untriggeredFiles": 1,
                "leaks": 0,
                "staleFiles": 0,
                "growthPhase": "idle (no open IMP tickets)",
            },
        },
        "kaiActions": [
            {
                "action": "chmod +x ~/Documents/Projects/Hyo/bin/kai.sh",
                "trigger": "sentinel #119 P2 kai-dispatcher-present",
                "result": "mode 0600 → 0711, file executable",
                "verification": "ls -la confirmed -rwx--x--x after chmod",
            }
        ],
        "shipped": [],
    }

    # Append new events (prepend — events list has newest first)
    events = d.get("events", [])
    # Filter out any identical events we're about to re-insert (idempotency)
    existing_msgs = {(e.get("ts"), e.get("agent"), e.get("msg")) for e in events}
    fresh = [e for e in EVENTS_TO_ADD if (e["ts"], e["agent"], e["msg"]) not in existing_msgs]
    d["events"] = fresh + events
    # Cap at 50 events (existing policy — see first 50 in file)
    d["events"] = d["events"][:50]

    # Per-agent summaries
    d.setdefault("sentinel", {})
    d["sentinel"].update({
        "runId": 119,
        "ts": "2026-04-21T22:10:45Z",
        "passed": 6,
        "failed": 3,
        "newIssues": 1,
        "recurring": 2,
        "resolved": 0,
        "status": "regression-auto-remediated",
        "note": "kai-dispatcher-present fixed via chmod +x in same cycle",
    })

    d.setdefault("cipher", {})
    d["cipher"].update({
        "ts": "2026-04-21T22:11:00Z",
        "findings": 0,
        "autofixes": 7,
        "depAudit": {"pass": 3, "warn": 0, "fail": 0},
        "status": "clean",
        "log": "agents/nel/logs/cipher-2026-04-21T16.log",
    })

    d.setdefault("nel", {})
    d["nel"].update({
        "ts": "2026-04-21T22:11:21Z",
        "score": 85,
        "projects": "4p/0f",
        "findings": {
            "brokenLinks": 20,
            "untestedScripts": 30,
            "inefficientPatterns": 8,
            "auditIssues": 7,
            "sensitiveFiles": 5,
            "untriggeredFiles": 1,
            "leaks": 0,
            "staleFiles": 0,
        },
        "status": "health-acceptable",
        "report": "agents/nel/logs/nel-2026-04-21.md",
    })

    return d


for path in (HQ, HQ_DUAL):
    if not path.exists():
        print(f"SKIP (missing): {path}")
        continue
    d = load(path)
    d = update(d)
    save(path, d)
    print(f"UPDATED: {path}")
    print(f"  updatedAt: {d['updatedAt']}")
    print(f"  events: {len(d['events'])}")
    print(f"  lastOpsSync.ts: {d['morningReport']['lastOpsSync']['ts']}")
