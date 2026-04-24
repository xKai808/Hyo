#!/usr/bin/env python3
"""Update HQ state with ops sync cycle results at 16:11 MT 2026-04-23.

3rd cycle of day (morning 08:09 MT, noon 12:10 MT, now 16:11 MT).
Sentinel #141: 7p/2f stable vs #140. Cipher clean. Nel score 85 STABLE.
Untested scripts UP 36→40 (+4), self-review DOWN 14→11 (-3).
"""
import json
import os
from pathlib import Path

HQ = Path(os.environ["HOME"]) / "Documents/Projects/Hyo/website/data/hq-state.json"
HQ_DUAL = Path(os.environ["HOME"]) / "Documents/Projects/Hyo/agents/sam/website/data/hq-state.json"

TS_UTC = "2026-04-23T22:11:30Z"
TS_MT = "2026-04-23T16:11:30-0600"

SUMMARY = (
    "Ops sync 16:11 MT on 2026-04-23 (hq-ops-sync scheduled task, 3rd cycle of day vs morning 08:09 MT + noon 12:10 MT). "
    "Sentinel #141 7p/2f STABLE vs #140 — 0 new, 2 recurring (P1 scheduled-tasks-fired day 30, P2 task-queue-size day 24, 29 P0 tasks), 0 resolved. "
    "Cipher clean: 0 findings, 7 permission autofixes, 0 leaks, HQ push 200 OK, founder.token 600, .secrets/ 700. "
    "Nel score 85 STABLE, cross-project sentinel 4p/0f (hyo, aurora-ra, aether, kai-ceo all passing). "
    "Self-review 11 findings (DOWN from 14 at 12:10 — 3 Gate 1 untriggered files resolved/re-wired). "
    "Flags: P2 broken-links 20 (flat), P3 code-optimizations 8 (flat), P2 audit 7 (flat), P2 untriggered-files 1 (DOWN from 4). "
    "Untested scripts 40 (UP from 36 at 12:10 — +4 regression, new scripts without tests). "
    "Growth idle (ARIC complete today, no open IMP tickets). "
    "Stderr: nel grep -P on BSD carried (day 7, P3). Dual-path sync enforced (website/ + agents/sam/website/)."
)

EVENTS_TO_ADD = [
    {
        "ts": "2026-04-23T22:10:00Z",
        "agent": "sentinel",
        "msg": (
            "QA sweep run #141 — 7 passed, 2 failed (stable vs #140 7p/2f). 0 new, 2 recurring, 0 resolved. "
            "Recurring ESCALATED: P1 scheduled-tasks-fired day 30 (aurora logs absent from sandbox — structural, aurora runs on Mini); "
            "P2 task-queue-size 29 P0 tasks day 24."
        ),
        "severity": "warning",
    },
    {
        "ts": "2026-04-23T22:10:30Z",
        "agent": "cipher",
        "msg": (
            "Security scan — clean. 0 findings, 7 permission autofixes applied (.secrets/ 0755→700; "
            "aethel-bot.key, anthropic.key, deploy-hook, env, founder.token, openai.key restored to 600), "
            "0 leaks, exit 0. Founder token mode 600 OK. HQ push 200 OK."
        ),
        "severity": "info",
    },
    {
        "ts": "2026-04-23T22:11:11Z",
        "agent": "nel",
        "msg": (
            "Health sweep — score 85/100 STABLE. Cross-project sentinel 4p/0f (hyo, aurora-ra, aether, kai-ceo all passing). "
            "Findings: 20 broken doc links (flat), 40 untested scripts (UP from 36 at 12:10 — +4 new), "
            "8 inefficient patterns (flat), 7 audit issues (flat), 0 verified leaks, 0 stale files. "
            "Self-review: 11 findings incl. 1 untriggered file (DOWN from 14/4 at 12:10 — Gate 1 re-wiring credited). "
            "Self-delegated: nel-001 P2 broken-symlink fix (carried), nel-001 P3 cycle summary. "
            "ARIC already ran today — growth phase idle (no open IMP tickets). "
            "Report published to agents/sam/website/docs/nel/report-2026-04-23.md."
        ),
        "severity": "info",
    },
    {
        "ts": TS_UTC,
        "agent": "kai",
        "msg": (
            "Ops sync cycle @ 16:11 MT on 2026-04-23 (hq-ops-sync scheduled task, 3rd cycle of day). "
            "Sentinel #141: 7p/2f stable vs #140 — 0 new, 2 recurring (P1 day 30, P2 day 24), 0 resolved. "
            "Cipher: clean, 0 findings, 7 autofixes, 0 leaks, HQ push 200 OK. "
            "Nel: score 85 STABLE, 4p/0f cross-project, self-review 11 (DOWN from 14 — Gate 1 re-wiring landed). "
            "Regression tracking: untested scripts 36→40 (+4 new scripts without coverage); self-review untriggered-files 4→1 (improvement). "
            "Flags flat: P2 broken-links 20, P3 code-optimizations 8, P2 audit 7. "
            "Stderr: nel grep -P BSD carried (day 7, P3). Dual-path hq-state.json sync enforced."
        ),
        "severity": "info",
    },
]


def load(path):
    return json.loads(path.read_text())


def save(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def update(d):
    d["updatedAt"] = TS_UTC

    mr = d.setdefault("morningReport", {})
    mr["summary"] = SUMMARY
    mr["systemStatus"] = "warnings"

    mr["topIssues"] = [
        "Nel score 85/100 STABLE this cycle (above 70 target) — holding vs 12:10 MT",
        "Sentinel #141 7p/2f stable vs #140 — 0 new, 2 recurring, 0 resolved this cycle",
        "P2 task-queue-size ESCALATED — 29 P0 tasks vs threshold 5 (day 24)",
        "P1 scheduled-tasks-fired ESCALATED — aurora logs absent from sandbox (benign, day 30)",
        "Regression: Untested scripts 36→40 (+4 new scripts without coverage — Sam fix-it candidate)",
        "Improvement: Self-review findings 14→11 (Gate 1 untriggered-files 4→1 — re-wiring landed)",
        "Broken doc links 20 (flat) — P2 nel-001 self-delegated (carried)",
        "Code optimizations 8 (flat) — P3 nel rolling improvement",
        "Audit issues 7 (flat) — P2 nel-001 self-delegated (carried)",
        "Cipher: clean, 0 findings, 7 autofixes, leaks 0, dep-audit GREEN (3p/0w/0f)",
        "ARIC research cycle already ran for 2026-04-23 — skipped (growth phase idle, no open IMP tickets)",
        "Stderr: nel runner grep -P unsupported on BSD — P3 fix-it carried forward (day 7)",
    ]

    mr["lastOpsSync"] = {
        "ts": TS_UTC,
        "tsMT": TS_MT,
        "note": (
            "Ops sync cycle @ 16:11 MT on 2026-04-23 (hq-ops-sync scheduled task, cowork, 3rd of day). "
            "Sentinel #141 7p/2f stable (0 new, 2 recurring: P1 scheduled-tasks-fired day 30, P2 task-queue-size day 24). "
            "Cipher clean: 0 findings, 7 autofixes, 0 leaks, HQ push 200. "
            "Nel score 85 STABLE, cross-project 4p/0f, self-review 11 (DOWN from 14 — Gate 1 re-wiring). "
            "Regression: untested scripts 36→40 (+4). Improvement: untriggered-files 4→1. "
            "ARIC already ran today (growth idle, no open IMP tickets). "
            "Self-delegated: nel-001 P2 (broken-symlink fix), nel-001 P3 (cycle summary). "
            "Dual-path hq-state.json sync enforced across website/ and agents/sam/website/."
        ),
        "agentsRun": ["sentinel", "cipher", "nel"],
        "results": {
            "sentinel": {
                "runId": 141,
                "passed": 7,
                "failed": 2,
                "new": 0,
                "recurring": 2,
                "resolved": 0,
                "status": "stable",
                "recurringDetail": [
                    {"id": "scheduled-tasks-fired", "priority": "P1", "day": 30, "state": "escalated"},
                    {"id": "task-queue-size", "priority": "P2", "day": 24, "p0Count": 29, "state": "escalated"},
                ],
            },
            "cipher": {
                "findings": 0,
                "autofixes": 7,
                "leaks": 0,
                "hqPush": 200,
                "depAudit": {"pass": 3, "warn": 0, "fail": 0},
                "status": "clean",
            },
            "nel": {
                "score": 85,
                "projects": "4p/0f",
                "brokenLinks": 20,
                "untestedScripts": 40,
                "untestedScriptsDelta": "+4",
                "inefficientPatterns": 8,
                "auditIssues": 7,
                "selfReviewFindings": 11,
                "selfReviewDelta": "-3",
                "untriggeredFiles": 1,
                "untriggeredFilesDelta": "-3",
                "leaks": 0,
                "staleFiles": 0,
                "growthPhase": "idle (ARIC complete, no open IMP tickets)",
                "status": "health-acceptable",
            },
        },
        "kaiActions": [
            {
                "action": "update-hq-state dual-path",
                "trigger": "hq-ops-sync scheduled task 16:11 MT",
                "result": "website/data/hq-state.json + agents/sam/website/data/hq-state.json synced with 3rd cycle",
                "verification": "updatedAt=" + TS_UTC + ", events prepended, both paths in parity",
            }
        ],
        "shipped": [],
    }

    events = d.get("events", [])
    existing_msgs = {(e.get("ts"), e.get("agent"), e.get("msg")) for e in events}
    fresh = [e for e in EVENTS_TO_ADD if (e["ts"], e["agent"], e["msg"]) not in existing_msgs]
    d["events"] = fresh + events
    d["events"] = d["events"][:50]

    d.setdefault("sentinel", {})
    d["sentinel"].update({
        "runId": 141,
        "ts": "2026-04-23T22:10:00Z",
        "passed": 7,
        "failed": 2,
        "newIssues": 0,
        "recurring": 2,
        "resolved": 0,
        "status": "stable",
    })

    d.setdefault("cipher", {})
    d["cipher"].update({
        "ts": "2026-04-23T22:10:30Z",
        "findings": 0,
        "autofixes": 7,
        "depAudit": {"pass": 3, "warn": 0, "fail": 0},
        "status": "clean",
        "log": "agents/nel/logs/cipher-2026-04-23T16.log",
    })

    d.setdefault("nel", {})
    d["nel"].update({
        "ts": "2026-04-23T22:11:11Z",
        "score": 85,
        "projects": "4p/0f",
        "findings": {
            "brokenLinks": 20,
            "untestedScripts": 40,
            "inefficientPatterns": 8,
            "auditIssues": 7,
            "selfReviewFindings": 11,
            "untriggeredFiles": 1,
            "leaks": 0,
            "staleFiles": 0,
        },
        "status": "health-acceptable",
        "report": "agents/nel/logs/nel-2026-04-23.md",
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
