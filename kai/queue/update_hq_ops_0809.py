#!/usr/bin/env python3
"""HQ state updater — ops sync cycle 08:09 MT on 2026-04-23 (scheduled task).

Source data:
  - Sentinel run #138: 7 passed, 2 failed (stable vs #137 7p/2f)
  - Cipher: clean, 0 findings, 7 autofixes, 0 leaks, HQ push 200 OK, founder 600, secrets 700
  - Nel: score 85/100 STABLE, cross-project sentinel 4p/0f, findings 1, 20 broken links (flat),
         36 untested scripts (up 2 from 34), 8 inefficient patterns (flat), 7 audit issues (flat),
         self-review 14 findings (up 1 from 13)
  - Flags: P2 broken-links 20 (flat), P3 code-optimizations 8 (flat), P2 audit 7 (flat),
           P2 self-review untriggered-files 1 (flat)

Writes to BOTH website/data/hq-state.json AND agents/sam/website/data/hq-state.json
per dual-path rule in CLAUDE.md.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", str(Path.home() / "Documents/Projects/Hyo")))
PATH_A = ROOT / "website/data/hq-state.json"
PATH_B = ROOT / "agents/sam/website/data/hq-state.json"

# Load primary (nel updated this one most recently)
with open(PATH_A) as f:
    state = json.load(f)

# ---- Timestamps ------------------------------------------------------------
UTC = "2026-04-23T14:11:00Z"      # 08:11 MT ops sync cycle window
MT_LABEL = "08:09 MT on 2026-04-23"

# ---- morningReport summary + lastOpsSync -----------------------------------
summary = (
    "Ops sync 08:09 MT on 2026-04-23 (hq-ops-sync scheduled task, 1st cycle since overnight 00:14). "
    "Sentinel #138 7p/2f stable vs #137 — 0 new, 2 recurring (P1 scheduled-tasks-fired, "
    "P2 task-queue-size), 0 resolved. Cipher clean: 0 findings, 7 permission autofixes, 0 leaks, "
    "HQ push 200, founder.token 600, .secrets/ 700. Nel score 85 STABLE, cross-project 4p/0f, "
    "self-review 14 findings (up 1). Flags flat: P2 broken-links 20, P3 code-optimizations 8, "
    "P2 audit 7, P2 self-review untriggered-files 1. Growth idle (ARIC complete for today, "
    "no open IMP tickets). Stderr: nel grep -P on BSD carried (day 6 P3). Dual-path sync enforced."
)

last_ops_sync = {
    "ts": UTC,
    "note": (
        f"Ops sync cycle @ {MT_LABEL} (hq-ops-sync scheduled task, cowork). "
        "Sentinel #138 7p/2f stable (pass: 4 cross-project, fail: 0). Cipher clean: 0 findings, "
        "7 autofixes, 0 leaks, HQ push 200. Nel score 85 STABLE, cross-project 4p/0f, "
        "ARIC already ran today (growth idle, no open IMP tickets). Flags flat "
        "(P2 broken-links 20, P3 code-optimizations 8, P2 audit 7, P2 untriggered-files 1). "
        "Self-delegated: nel-001 P2 (broken-symlink fix), nel-001 P3 (cycle summary). "
        "Dual-path hq-state.json sync enforced across website/ and agents/sam/website/."
    ),
}

# ---- topIssues (refresh for this cycle) ------------------------------------
top_issues = [
    "Nel score 85/100 STABLE this cycle (above 70 target) — holding vs overnight 00:14 MT",
    "Sentinel #138 7p/2f stable vs #137 — 0 new, 2 recurring, 0 resolved this cycle",
    "P2 task-queue-size ESCALATED — 29 P0 tasks vs threshold 5 (counter persists, day 17)",
    "P1 scheduled-tasks-fired ESCALATED — aurora logs absent from sandbox /agents/nel/logs (benign, sandbox-specific, day 25)",
    "Untested scripts: 36 (up 2 from prior 34)",
    "Broken documentation links held at 20 (flag-nel P2 re-filed)",
    "Code-optimization opportunities held at 8 (flag-nel P3 re-filed)",
    "Audit issues held at 7 (flag-nel P2 re-filed)",
    "Sensitive files detected: 20 (env-examples inside worktrees + website/.env.local — cosmetic)",
    "Cipher: clean, 0 findings, 7 autofixes, leaks 0 — perms stable (founder.token 600, secrets 700)",
    "Self-review: 14 findings (up 1 from 13) — 1 untriggered file flagged P2",
    "ARIC research cycle already ran for 2026-04-23 — skipped (growth phase idle, no open IMP tickets)",
    "Stderr: nel runner grep -P unsupported on BSD — P3 fix-it carried forward (day 6)",
    "81 stale tickets across all agents per verified-state.json — backlog compaction needed",
]

state.setdefault("morningReport", {})
state["morningReport"]["summary"] = summary
state["morningReport"]["systemStatus"] = "warnings"
state["morningReport"]["topIssues"] = top_issues
state["morningReport"]["lastOpsSync"] = last_ops_sync

# ---- Per-agent blocks ------------------------------------------------------
state["sentinel"] = {
    "lastRunId": 138,
    "lastRunAt": UTC,
    "passed": 7,
    "failed": 2,
    "new": 0,
    "recurring": 2,
    "resolved": 0,
    "regression": False,
    "note": "sentinel.sh run #138 — 7p/2f stable vs #137. Recurring: P1 scheduled-tasks-fired (aurora logs absent from sandbox, benign), P2 task-queue-size 29 P0 tasks (above 5 threshold).",
}

state["cipher"] = {
    "lastRunAt": UTC,
    "findings": 0,
    "autofixes": 7,
    "leaks": 0,
    "founderToken": "600",
    "secretsDir": "700",
    "hqPush": "200 OK",
    "note": "Clean. 0 findings, 7 permission autofixes (.secrets/ + all tokens restored to canonical modes), 0 leaks, founder.token 600 OK, HQ push 200.",
}

# Nel block was already updated by nel.sh; preserve but ensure counts match log
nel_block = state.get("nel", {})
nel_block.update({
    "lastRun": UTC,
    "improvementScore": 85,
    "findingsCount": 1,
    "staleFiles": 0,
    "brokenLinks": 20,
    "untested": 36,
    "inefficient": 8,
    "auditIssues": 7,
    "selfReviewFindings": 14,
    "sentinel": {"pass": 4, "fail": 0},
    "cipher": {"leaks": 0},
    "flags": {"broken_links_p2": 20, "code_optimizations_p3": 8, "audit_p2": 7, "untriggered_files_p2": 1},
})
state["nel"] = nel_block

# ---- Events ----------------------------------------------------------------
new_events = [
    {
        "ts": UTC,
        "agent": "kai",
        "msg": (
            f"Ops sync cycle @ {MT_LABEL} (hq-ops-sync scheduled task, cowork run). "
            "Sentinel run #138: 7p/2f stable vs #137 — 0 new, 2 recurring (P1 scheduled-tasks-fired day 25, "
            "P2 task-queue-size day 17, 29 P0 tasks), 0 resolved. Cipher clean: 0 findings, 7 permission "
            "autofixes (.secrets/→700, tokens→600), 0 leaks, HQ push 200 OK. Nel: score 85/100 STABLE, "
            "cross-project sentinel 4p/0f, 1 finding in block + 14 in self-review (up 1). Flags: "
            "P2 broken-links 20 (flat), P3 code-optimizations 8 (flat), P2 audit 7 (flat), "
            "P2 untriggered-files 1 (flat). Self-delegated: nel-001 P2 (broken-symlink), nel-001 P3 "
            "(cycle summary). ARIC complete for 2026-04-23 — growth phase idle (no open IMP tickets). "
            "Dual-path hq-state.json sync enforced (website/ + agents/sam/website/). "
            "Stderr: nel grep -P BSD carried (day 6, P3)."
        ),
        "severity": "warning",
    },
    {
        "ts": UTC,
        "agent": "sentinel",
        "msg": (
            "QA sweep run #138 — 7 passed, 2 failed (stable vs #137 7p/2f). 0 new, 2 recurring, "
            "0 resolved. Recurring: P1 scheduled-tasks-fired (aurora logs absent from sandbox — "
            "structural, aurora runs on Mini), P2 task-queue-size 29 P0 tasks."
        ),
        "doc": "/viewer?agent=sentinel&file=2026-04-23",
        "severity": "warning",
    },
    {
        "ts": UTC,
        "agent": "cipher",
        "msg": (
            "Security scan — clean. 0 findings, 7 permission autofixes applied "
            "(.secrets/ 755→700; aethel-bot.key, anthropic.key, deploy-hook, env, founder.token, "
            "openai.key restored to 600), 0 leaks, exit 0. Founder token mode 600 OK. "
            "HQ push 200 OK."
        ),
        "severity": "info",
    },
    {
        "ts": UTC,
        "agent": "nel",
        "msg": (
            "Health sweep — score 85/100 STABLE. Cross-project sentinel 4p/0f (hyo, aurora-ra, "
            "aether, kai-ceo all passing). Findings: 20 broken doc links (flat), 36 untested scripts "
            "(up 2), 8 inefficient patterns (flat), 7 audit issues (flat), 20 potentially-sensitive "
            "files flagged (repo size 859M, 12606 total files), 0 verified leaks. Self-review: "
            "14 findings (up 1) incl. 1 untriggered file. Flags: P2 broken-links, P3 code-optimizations, "
            "P2 audit, P2 untriggered-files. Self-delegated: nel-001 (P2) broken-symlink fix, "
            "nel-001 (P3) cycle summary. ARIC already ran today — growth phase idle. "
            "Report published to agents/sam/website/docs/nel/report-2026-04-23.md."
        ),
        "doc": "/viewer?agent=nel&file=2026-04-23",
        "severity": "warning",
    },
]

events = state.get("events", [])
# Prepend new events, keep last 100
state["events"] = new_events + events
state["events"] = state["events"][:100]

# ---- Top-level updatedAt ---------------------------------------------------
state["updatedAt"] = UTC

# ---- Write to BOTH paths (dual-path rule) ----------------------------------
for p in (PATH_A, PATH_B):
    with open(p, "w") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"✓ wrote {p}")

print("✓ hq-state.json updated (dual-path)")
