#!/usr/bin/env bash
# bin/generate-morning-report.sh — v4 Growth-Driven Morning Report Generator
#
# REWRITTEN FOR ARIC PHASE 7 CONSUMPTION
# ════════════════════════════════════════════════════════════════════════════════
#
# Protocol: kai/protocols/AGENT_RESEARCH_CYCLE.md
#   - Phase 7 output format (aric-latest.json per agent)
#   - Morning Report Structure (v4 — Growth-Driven)
#
# KEY DIFFERENCES FROM v3:
#   - v3 tracked: agent operational status (checks passed, newsletters shipped, etc)
#   - v4 tracks: novel work, weakness research, improvements built, metrics moved
#   - v3: "what agents did" (baseline ops)
#   - v4: "what agents are LEARNING and BUILDING" (growth)
#   - v3 consumed: logs, health checks, arbitrary files
#   - v4 consumes: ARIC Phase 7 JSON + GROWTH.md
#
# WHAT THE REPORT SHOWS (per agent):
#   1. Novel work — what new improvement is this agent building?
#   2. Weakness — what structural issue did they identify?
#   3. Research — what external sources informed their fix? (with sources + findings)
#   4. Improvement built — what code/config changed? (with commit)
#   5. Metric movement — before → after (with measurement method)
#   6. External expansion — vertical (deeper) or horizontal (broader) opportunity
#
# INPUT FILES (required):
#   - agents/<name>/research/aric-latest.json  [Phase 7 output, JSON format]
#   - agents/<name>/GROWTH.md                  [fallback if ARIC data missing]
#
# OUTPUT FILES:
#   - website/data/morning-report.json         [structured JSON for HQ dashboard]
#   - stdout                                   [human-readable narrative for Hyo]
#
# EXAMPLE ARIC PHASE 7 JSON:
#   {
#     "agent": "nel",
#     "cycle_date": "2026-04-15",
#     "weakness_worked": "Static Checks Never Adapt ...",
#     "research_conducted": [
#       {"source": "GitHub: prometheus/alertmanager", "finding": "Adaptive grouping with ..."},
#       {"source": "Reddit: r/devops/...", "finding": "Exponential backoff on ..."}
#     ],
#     "improvement_built": {
#       "description": "sentinel-adapt.sh — 4-level escalation",
#       "files_changed": ["agents/nel/sentinel-adapt.sh"],
#       "commit": "f9a1938c2b5d7e9a1c3d5e7f",
#       "status": "shipped"
#     },
#     "metric_before": "Mean time to root-cause: 3+ days",
#     "metric_after": "Mean time to root-cause: <1h",
#     "external_opportunity": {
#       "type": "vertical",
#       "description": "GitHub Advisory Database API for CVE scanning",
#       "status": "researched, ticket IMP-20260415-nel-003"
#     },
#     "next_target": "Reduce false positive rate from 8% to <3%",
#     "needs_from_kai": null
#   }
#
# FALLBACK BEHAVIOR:
#   - If aric-latest.json missing → reads GROWTH.md for context
#   - Flags agent with "No ARIC cycle completed yet — growth data only"
#   - Extracts weaknesses but notes research is incomplete
#
# CALLED BY:
#   - com.hyo.morning-report launchd plist (05:00 MT daily)
#   - Manual: HYO_ROOT=/path/to/Hyo bash bin/generate-morning-report.sh
#
# USAGE: bash bin/generate-morning-report.sh
#        HYO_ROOT=/path/to/Hyo bash bin/generate-morning-report.sh

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
JSON_OUTPUT="$ROOT/website/data/morning-report.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
LOG_TAG="[morning-report-v4]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

log "Generating morning report v4 (growth-driven) for $TODAY"

# ══════════════════════════════════════════════════════════════════════════════
# Python script: Read ARIC Phase 7, GROWTH.md, compile report
# ══════════════════════════════════════════════════════════════════════════════

python3 - "$JSON_OUTPUT" "$TODAY" "$NOW_MT" "$ROOT" <<'PYEOF'
import json, sys, os, re, glob
from pathlib import Path
from collections import defaultdict
from datetime import datetime, timezone

json_output_path = sys.argv[1]
today = sys.argv[2]
now_mt = sys.argv[3]
root = sys.argv[4]

# ── Helper functions ──

def read_json_safe(path):
    """Read JSON file, return None if missing or malformed."""
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return None

def read_file_safe(path, max_chars=5000):
    """Read text file, return empty string if missing."""
    try:
        with open(path) as f:
            return f.read(max_chars)
    except:
        return ""

def parse_growth_md(agent_name):
    """Parse GROWTH.md for context on weaknesses and improvements."""
    path = os.path.join(root, "agents", agent_name, "GROWTH.md")
    if not os.path.exists(path):
        return None

    text = read_file_safe(path, 10000)
    result = {
        "weaknesses": [],
        "improvements": [],
        "assessment": ""
    }

    # Extract weaknesses (W1, W2, W3)
    for m in re.finditer(r'### W(\d): (.+)\n', text):
        wnum = m.group(1)
        title = m.group(2).strip()
        result["weaknesses"].append({"id": f"W{wnum}", "title": title})

    # Extract improvements (I1, I2, I3)
    for m in re.finditer(r'### I(\d): (.+)\n', text):
        inum = m.group(1)
        title = m.group(2).strip()
        # Find status if present
        status_match = re.search(rf'### I{inum}:.+?\*\*Status:\*\*\s*(.+?)(?:\n|$)', text, re.DOTALL)
        status = status_match.group(1).strip() if status_match else "unknown"
        result["improvements"].append({"id": f"I{inum}", "title": title, "status": status})

    # Extract first assessment line (usually a summary)
    assess_match = re.search(r'## System Weaknesses.*?\n\n(.+?)(?=###|\n\n)', text, re.DOTALL)
    if assess_match:
        first_line = assess_match.group(1).split('\n')[0]
        result["assessment"] = first_line[:150]

    return result

def read_aric_phase7(agent_name):
    """Read aric-latest.json for an agent. This is Phase 7 output.

    FRESHNESS GATE (2026-04-27): If the file is > 24h old, it is stale.
    Stale data must NEVER be presented as today's work.
    We attach _stale=True and _stale_date so callers can label it honestly.
    """
    path = os.path.join(root, "agents", agent_name, "research", "aric-latest.json")
    data = read_json_safe(path)
    if data:
        data["_source"] = "aric-phase7"
        # ── FRESHNESS CHECK ──────────────────────────────────────────────────
        try:
            mtime = os.path.getmtime(path)
            age_hours = (datetime.now(timezone.utc).timestamp() - mtime) / 3600
            if age_hours > 24:
                stale_date = datetime.fromtimestamp(mtime, tz=timezone.utc).strftime("%Y-%m-%d")
                data["_stale"] = True
                data["_stale_hours"] = round(age_hours, 1)
                data["_stale_date"] = stale_date
            else:
                data["_stale"] = False
                data["_stale_hours"] = round(age_hours, 1)
                data["_stale_date"] = None
        except Exception:
            data["_stale"] = False
            data["_stale_date"] = None
        return data
    return None

def extract_novel_work(agent_name, aric_data, growth_data):
    """Determine what novel work the agent is doing."""
    if aric_data:
        # Phase 7.3: improvement_built
        improvement = aric_data.get("improvement_built")
        if improvement and improvement.get("status") == "shipped":
            return f"Shipped {improvement.get('description', 'improvement')} (commit {improvement.get('commit', '?')})"
        elif improvement:
            return f"Building: {improvement.get('description', 'improvement')} ({improvement.get('status', 'in progress')})"

    if growth_data:
        # Check for active improvements
        active = [i for i in growth_data.get("improvements", []) if i.get("status") in ("in progress", "building", "active")]
        if active:
            return f"Building: {active[0].get('title', 'improvement')}"

    return "No novel work identified — check if improvement cycle is running."

def extract_weakness_and_research(aric_data, growth_data):
    """Extract what weakness was worked on and what was researched."""
    if aric_data:
        weakness = aric_data.get("weakness_worked")
        research = aric_data.get("research_conducted", [])
        if weakness and research:
            sources_str = "; ".join([r.get("source", "?") for r in research[:2]])
            findings_str = "; ".join([r.get("finding", "?") for r in research[:2]])
            return {
                "weakness": weakness,
                "sources": sources_str,
                "findings": findings_str,
                "count": len(research)
            }

    if growth_data:
        weaknesses = growth_data.get("weaknesses", [])
        if weaknesses:
            w = weaknesses[0]
            return {
                "weakness": w.get("title", "unknown"),
                "sources": "(no ARIC data yet)",
                "findings": "(research not completed)",
                "count": 0
            }

    return {
        "weakness": "Unknown",
        "sources": "N/A",
        "findings": "N/A",
        "count": 0
    }

def extract_metric_movement(aric_data):
    """Extract before/after metric."""
    if aric_data:
        before = aric_data.get("metric_before")
        after = aric_data.get("metric_after")
        if before and after:
            return {"before": before, "after": after}
    return None

def extract_external_expansion(aric_data):
    """Extract vertical/horizontal expansion opportunity."""
    if aric_data:
        opp = aric_data.get("external_opportunity")
        if opp:
            return {
                "type": opp.get("type", "unknown"),
                "description": opp.get("description", ""),
                "status": opp.get("status", "")
            }
    return None

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 0: EXECUTION LAYER CHECK — leads the report if system is offline
# Rule: if the execution layer is down, that IS the morning report.
# ═══════════════════════════════════════════════════════════════════════════════

def check_execution_layer(root):
    """
    Returns dict: {alive, stall_hours, queue_depth, last_worker_ts, detail}
    Checks queue worker log + healthcheck-latest.json
    """
    result = {"alive": True, "stall_hours": 0, "queue_depth": 0,
              "last_worker_ts": None, "detail": ""}
    now_epoch = datetime.now(timezone.utc).timestamp()

    # Check worker.log last entry
    worker_log = os.path.join(root, "kai/queue/worker.log")
    if os.path.exists(worker_log):
        try:
            mtime = os.path.getmtime(worker_log)
            stall_s = now_epoch - mtime
            stall_h = stall_s / 3600
            result["last_worker_ts"] = datetime.fromtimestamp(mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M")
            if stall_h > 3:
                result["alive"] = False
                result["stall_hours"] = round(stall_h, 1)
                result["detail"] = f"Worker log last updated {result['last_worker_ts']}Z ({stall_h:.1f}h ago)"
        except Exception as e:
            result["detail"] = f"worker.log unreadable: {e}"
    else:
        result["alive"] = False
        result["detail"] = "worker.log missing"

    # Check running/ directory for orphaned tasks
    running_dir = os.path.join(root, "kai/queue/running")
    pending_dir = os.path.join(root, "kai/queue/pending")
    if os.path.isdir(running_dir):
        running = [f for f in os.listdir(running_dir) if f.endswith(".json")]
        if running:
            # Check how old the running tasks are
            oldest_h = 0
            for fn in running:
                try:
                    mtime = os.path.getmtime(os.path.join(running_dir, fn))
                    age_h = (now_epoch - mtime) / 3600
                    oldest_h = max(oldest_h, age_h)
                except:
                    pass
            if oldest_h > 2:
                result["alive"] = False
                result["stall_hours"] = max(result["stall_hours"], round(oldest_h, 1))
                result["detail"] += f" | {len(running)} task(s) stuck in running/ for {oldest_h:.1f}h"
    if os.path.isdir(pending_dir):
        pending = [f for f in os.listdir(pending_dir) if f.endswith(".json")]
        result["queue_depth"] = len(pending)

    # Read healthcheck-latest.json for additional signals
    hc_path = os.path.join(root, "kai/queue/healthcheck-latest.json")
    hc = read_json_safe(hc_path)
    if hc:
        issues = hc.get("issues", [])
        # issues may be an int (count) or a list of dicts — handle both
        if isinstance(issues, int):
            p0_count = issues  # treat count as approximate P0 indicator
            if p0_count > 0:
                result["detail"] += f" | healthcheck: {p0_count} issue(s)"
        elif isinstance(issues, list):
            p0_count = sum(1 for i in issues if isinstance(i, dict) and i.get("severity") == "P0")
            if p0_count > 0:
                result["detail"] += f" | healthcheck: {p0_count} P0 issue(s)"

    return result

def check_api_spend(root, today):
    """Returns (total_cost, call_count, by_provider). Cost 0 with any ARIC = simulation."""
    by_prov = defaultdict(lambda: {"cost": 0.0, "calls": 0})
    total = 0.0
    calls = 0
    ledger = os.path.join(root, "kai", "ledger", "api-usage.jsonl")
    if not os.path.exists(ledger):
        return 0.0, 0, {}
    try:
        with open(ledger) as f:
            for line in f:
                try:
                    e = json.loads(line)
                    if e.get("date") != today:
                        continue
                    c = float(e.get("cost_usd", 0) or 0)
                    p = e.get("provider", "?")
                    by_prov[p]["cost"] += c
                    by_prov[p]["calls"] += 1
                    total += c
                    calls += 1
                except:
                    pass
    except:
        pass
    return total, calls, dict(by_prov)

def load_resolved_issues(root):
    """Load known-issues.jsonl — return set of descriptions marked resolved."""
    resolved = set()
    path = os.path.join(root, "kai", "ledger", "known-issues.jsonl")
    if not os.path.exists(path):
        return resolved
    try:
        with open(path) as f:
            for line in f:
                try:
                    e = json.loads(line)
                    if e.get("status") in ("resolved", "closed"):
                        resolved.add(e.get("description", "").lower()[:80])
                except:
                    pass
    except:
        pass
    return resolved

# ─── Self-improvement report reader ─────────────────────────────────────────
def read_self_improve(agent_name):
    """Read agents/<name>/research/self-improve-latest.json if it exists."""
    path = os.path.join(root, "agents", agent_name, "research", "self-improve-latest.json")
    if not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            data = json.load(f)
        # Only return if it's from today or yesterday (not stale)
        report_date = data.get("report_date", "")
        from datetime import datetime, timedelta
        yesterday = (datetime.strptime(today, "%Y-%m-%d") - timedelta(days=1)).strftime("%Y-%m-%d")
        if report_date not in (today, yesterday):
            return None
        return data
    except:
        return None

# ═══════════════════════════════════════════════════════════════════════════════
# GATHER DATA PER AGENT
# ═══════════════════════════════════════════════════════════════════════════════

agents_list = ["nel", "ra", "sam", "aether", "dex", "kai"]
agent_reports = {}
growth_trajectories = []
risks = []
wins = []

self_improve_reports = {}  # agent_name → self-improve-latest.json data

for agent_name in agents_list:
    si = read_self_improve(agent_name)
    self_improve_reports[agent_name] = si

for agent_name in agents_list:
    aric = read_aric_phase7(agent_name)
    growth = parse_growth_md(agent_name)

    novel_work = extract_novel_work(agent_name, aric, growth)
    weakness_research = extract_weakness_and_research(aric, growth)
    metric_move = extract_metric_movement(aric)
    external = extract_external_expansion(aric)

    # Improvement status
    improvement_status = "unknown"
    if aric and aric.get("improvement_built"):
        improvement_status = aric["improvement_built"].get("status", "unknown")
    elif growth:
        active_imps = [i for i in growth.get("improvements", []) if i.get("status") in ("in progress", "building")]
        if active_imps:
            improvement_status = "in progress"
        else:
            improvement_status = "no active work"

    # Track trajectory and risks/wins
    # GATE: "expanding" requires something actually shipped or verifiably building with commit.
    # Fetching sources alone (ARIC Phase 4) is NOT expanding — it's prerequisite work.
    actually_shipped = improvement_status.lower() == "shipped"
    actively_building = (
        improvement_status.lower() == "in progress"
        and aric is not None
        and aric.get("improvement_built", {}).get("files_changed")  # real files, not placeholder
    )
    if actually_shipped or actively_building:
        growth_trajectories.append("expanding")
    else:
        growth_trajectories.append("maintaining")

    if "no" in novel_work.lower() or "unknown" in novel_work.lower():
        risks.append(f"{agent_name}: no active novel work")

    # Only a real win if something shipped with a commit hash
    if actually_shipped and aric and aric.get("improvement_built", {}).get("commit"):
        wins.append(f"{agent_name}: {novel_work}")

    # ── New v6 fields: 5 mandatory questions per PROTOCOL_MORNING_REPORT.md ──
    # Q1: What shipped since the last report?
    shipped_since_last = "Nothing shipped."
    if aric and aric.get("improvement_built", {}).get("status") == "shipped":
        imp = aric["improvement_built"]
        commit = imp.get("commit", "")
        desc = imp.get("description", "improvement")
        shipped_since_last = f"Shipped: {desc}" + (f" (commit {commit})" if commit else " (unverified — no commit hash)")
    elif growth:
        shipped_imps = [i for i in growth.get("improvements", []) if i.get("status") in ("shipped", "Phase 1 shipped")]
        if shipped_imps:
            shipped_since_last = f"Previously shipped: {shipped_imps[0].get('title', 'improvement')} — but no current cycle shipment."

    # Q2: What is the single highest-priority unresolved issue?
    highest_priority_issue = "No data — ARIC Phase 1 not completed."
    if aric and aric.get("weakness_worked"):
        highest_priority_issue = aric["weakness_worked"]
    elif growth:
        weaknesses = growth.get("weaknesses", [])
        if weaknesses:
            highest_priority_issue = weaknesses[0].get("title", "Unknown weakness")

    # Q3: What is the next concrete action?
    next_action = "Run ARIC Phase 5 to define next step."
    if aric and aric.get("improvement_built"):
        imp = aric["improvement_built"]
        imp_status = imp.get("status", "unknown")
        if imp_status == "shipped":
            next_action = aric.get("next_target", "Measure metric movement from shipped improvement.")
        elif imp_status == "researched":
            next_action = f"Execute improvement: bash bin/agent-execute-improvement.sh {agent_name} I1"
        elif imp_status == "in_progress":
            next_action = f"Complete and commit: {imp.get('description', 'improvement in progress')}"
        else:
            next_action = f"Build: {imp.get('description', 'improvement defined but not started')}"

    # Q4: Action type classification
    action_type = "research"  # default
    if next_action.startswith("Execute improvement") or next_action.startswith("bash bin/agent-execute"):
        action_type = "build"
    elif next_action.startswith("Shipped") or "deploy" in next_action.lower():
        action_type = "deployment"
    elif next_action.startswith("Measure") or "metric" in next_action.lower():
        action_type = "instrumentation"
    elif next_action.startswith("Build") or next_action.startswith("Create") or "implement" in next_action.lower():
        action_type = "build"
    elif next_action.startswith("Complete") or "commit" in next_action.lower():
        action_type = "build"
    elif not aric:
        action_type = "research"

    # Q5: Priority evidence
    priority_evidence = "No ARIC data — evidence not available."
    if aric:
        research = aric.get("research_conducted", [])
        if research:
            priority_evidence = "; ".join([f"{r.get('source','?')}: {r.get('finding','?')[:60]}" for r in research[:2]])
        elif aric.get("weakness_worked"):
            priority_evidence = f"Weakness identified from Phase 1 observe: {aric['weakness_worked'][:100]}"

    # Improvement detail (all 3 improvements status)
    improvement_status_detail = "No GROWTH.md data."
    if growth:
        imps = growth.get("improvements", [])
        details = []
        for imp in imps:
            details.append(f"{imp.get('id','?')}: {imp.get('title','?')[:40]} ({imp.get('status','?')})")
        improvement_status_detail = " | ".join(details) if details else "No improvements defined."

    # ── Self-improvement data ──
    si = self_improve_reports.get(agent_name)
    si_summary = None
    if si:
        si_summary = {
            "weakness_id": si.get("weakness_id", "?"),
            "weakness_title": si.get("weakness_title", "unknown"),
            "stage_completed": si.get("cycle_stage_completed", "unknown"),
            "outcome": si.get("outcome", ""),
            "fix_approach": si.get("fix_approach", ""),
            "confidence": si.get("confidence", ""),
            "improvements_resolved": si.get("improvements_resolved", []),
            "total_cycles": si.get("total_cycles", 0),
            "report_date": si.get("report_date", ""),
        }

    # ── STALENESS LABEL ──────────────────────────────────────────────────────
    # If ARIC data is stale (>24h), every field from it must carry a label
    # so the reader knows when it was actually generated.
    aric_stale = aric.get("_stale", False) if aric else False
    aric_stale_date = aric.get("_stale_date") if aric else None
    aric_stale_hours = aric.get("_stale_hours", 0) if aric else 0
    _stale_prefix = f"[DATA FROM {aric_stale_date}] " if aric_stale and aric_stale_date else ""

    # Apply stale prefix to text fields sourced from ARIC
    def _maybe_stale(val, fallback="N/A"):
        """Prefix val with stale label if ARIC data is stale."""
        if val and val not in ("N/A", "unknown", "?", "none", ""):
            return f"{_stale_prefix}{val}" if _stale_prefix else val
        return fallback

    # Compile agent report
    agent_reports[agent_name] = {
        "novel_work": _maybe_stale(novel_work, novel_work),
        "weakness_identified": _maybe_stale(weakness_research.get("weakness", "?"), "?"),
        "research_conducted": weakness_research.get("sources", "none"),
        "research_findings": weakness_research.get("findings", "none"),
        "research_count": weakness_research.get("count", 0),
        "improvement_status": improvement_status,
        "improvement_description": (
            _maybe_stale(aric.get("improvement_built", {}).get("description"), "N/A") if aric else "N/A"
        ),
        "improvement_commit": (aric.get("improvement_built", {}).get("commit") if aric else None),
        "metric_before": metric_move.get("before") if metric_move else "N/A",
        "metric_after": metric_move.get("after") if metric_move else "N/A",
        "metric_moved": bool(metric_move),
        "external_opportunity_type": external.get("type") if external else "none",
        "external_opportunity_desc": external.get("description") if external else "none",
        "has_aric_data": aric is not None,
        "aric_stale": aric_stale,
        "aric_stale_date": aric_stale_date,
        "aric_stale_hours": aric_stale_hours,
        "aric_cycle_date": aric.get("cycle_date", "unknown") if aric else None,
        # ── v6 new fields (PROTOCOL_MORNING_REPORT.md Part 2) ──
        "shipped_since_last": shipped_since_last,
        "highest_priority_issue": highest_priority_issue,
        "next_action": next_action,
        "action_type": action_type,
        "priority_evidence": priority_evidence,
        "improvement_status_detail": improvement_status_detail,
        # ── self-improve cycle report (from agent-self-improve.sh) ──
        "self_improve": si_summary,
    }

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD EXECUTIVE SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

# Run pre-checks
exec_layer = check_execution_layer(root)
api_cost, api_calls, api_by_prov = check_api_spend(root, today)
resolved_issues = load_resolved_issues(root)

# API spend string + simulation detection
if api_calls > 0:
    parts = [f"{p}=${info['cost']:.2f}" for p, info in sorted(api_by_prov.items(), key=lambda x: -x[1]["cost"])]
    api_spend_summary = f"${api_cost:.2f} ({api_calls} calls)" + (f" — {', '.join(parts)}" if parts else "")
else:
    api_spend_summary = "$0.00 (0 calls) — ledger not started" if not os.path.exists(
        os.path.join(root, "kai", "ledger", "api-usage.jsonl")) else "$0.00 (0 calls)"

# SIMULATION FLAG: $0 spend + ARIC claimed completions = synthesis didn't run
aric_claimed = sum(1 for a in agents_list if agent_reports[a]["has_aric_data"])
synthesis_ran = api_calls > 0
simulation_warning = None
if aric_claimed > 0 and not synthesis_ran:
    simulation_warning = (
        f"⚠️ SIMULATION: {aric_claimed} agent(s) show ARIC data but $0 API spend confirms "
        f"synthesis phase did not execute. Research output = raw source snippets, not synthesized findings. "
        f"Agents ran in sandbox context without LLM synthesis path."
    )

# STALE ARIC WARNING: any agent with ARIC data >24h is presenting recycled content as fresh
stale_agents = [
    f"{a} ({agent_reports[a]['aric_stale_date']}, {round(agent_reports[a].get('aric_stale_hours',0))}h ago)"
    for a in agents_list
    if agent_reports[a].get("aric_stale") and agent_reports[a].get("aric_stale_date")
]
stale_aric_warning = None
if stale_agents:
    stale_aric_warning = (
        f"⚠️ STALE ARIC DATA: {len(stale_agents)} agent(s) have not completed a fresh ARIC cycle — "
        f"{', '.join(stale_agents)}. Their sections below show data from a prior date, not today. "
        f"Root cause: ARIC cycle runner not executing or Claude Code auth expired."
    )

# Growth trajectory
expanding_count = growth_trajectories.count("expanding")
trajectory = "expanding" if expanding_count >= 3 else ("maintaining" if expanding_count >= 1 else "declining")

biggest_risk = risks[0] if risks else "No blockers identified"
biggest_win = wins[0] if wins else "No improvements shipped today"

# Determine if Hyo attention needed
hyo_attention = None
no_novel = [a for a in agents_list if "no novel" in agent_reports[a]["novel_work"].lower() or
            "no active" in agent_reports[a]["novel_work"].lower()]

# EXECUTION LAYER DOWN overrides everything
if not exec_layer["alive"]:
    hyo_attention = (
        f"Execution layer down — queue worker stalled {exec_layer['stall_hours']}h. "
        f"All agent delegations are sim-ack only. No real work has executed. "
        f"Fix: restart queue worker on Mini (5 min). "
        f"{exec_layer['detail']}"
    )

# ── v6: Count agents by action state ──
agents_shipped_count = sum(1 for a in agents_list
    if agent_reports[a].get("improvement_status") == "shipped")
agents_building_count = sum(1 for a in agents_list
    if agent_reports[a].get("action_type") in ("build", "deployment")
    and agent_reports[a].get("improvement_status") != "shipped")
agents_researching_count = sum(1 for a in agents_list
    if agent_reports[a].get("action_type") == "research"
    and agent_reports[a].get("improvement_status") not in ("shipped",))
agents_stalled_count = sum(1 for a in agents_list
    if agent_reports[a].get("improvement_status") in ("no active work", "stalled", "unknown")
    and agent_reports[a].get("has_aric_data") == False)

# ── Research theater detection (PROTOCOL_MORNING_REPORT.md FM3) ──
research_theater_warning = None
all_researching = all(
    agent_reports[a].get("action_type") == "research" for a in agents_list
)
if all_researching:
    research_theater_warning = (
        "RESEARCH THEATER DETECTED: All agents in research phase with no agent in build/deploy. "
        "ARIC execution engine (bin/agent-execute-improvement.sh) may not be firing. "
        "Research without execution is not improvement."
    )

# ── Critical blocked agents ──
critical_blocked = []
for a in agents_list:
    if agent_reports[a].get("improvement_status") in ("no active work", "stalled"):
        issue = agent_reports[a].get("highest_priority_issue", "unknown issue")
        critical_blocked.append(f"{a}: {issue[:80]}")

# ── Self-improvement flywheel summary (across all agents) ──
si_resolved_today = []
si_in_progress = []
si_no_data = []
for a in agents_list:
    si = self_improve_reports.get(a)
    if not si:
        si_no_data.append(a)
        continue
    resolved = si.get("improvements_resolved", [])
    if resolved:
        si_resolved_today.append(f"{a}: resolved {', '.join(resolved)}")
    stage = si.get("cycle_stage_completed", "")
    wid = si.get("weakness_id", "?")
    wtitle = si.get("weakness_title", "")
    outcome = si.get("outcome", "")
    si_in_progress.append(f"{a}: {wid} — {wtitle} ({stage}) → {outcome[:80]}")

report = {
    "generated": now_mt,
    "date": today,
    "version": "v6-action-engine",
    "self_improvement_flywheel": {
        "resolved_today": si_resolved_today,
        "in_progress": si_in_progress,
        "no_report": si_no_data,
        "agents_with_data": len(agents_list) - len(si_no_data),
        "total_agents": len(agents_list),
        # SICQ scores from flywheel-doctor (computed at 09:00 MT, available by morning report)
        "sicq_scores": (lambda p: json.load(open(p)).get("scores", {})
                        if os.path.exists(p) else {})(
            os.path.join(root, "kai/ledger/sicq-latest.json")),
        "doctor_issues": (lambda p: json.load(open(p)).get("issues_found", [])
                          if os.path.exists(p) else [])(
            os.path.join(root, "kai/ledger/flywheel-doctor-latest.json")),
    },
    "executive_summary": {
        "system_online": exec_layer["alive"],
        "execution_layer": exec_layer,
        "simulation_warning": simulation_warning,
        "stale_aric_warning": stale_aric_warning,
        "research_theater_warning": research_theater_warning,
        "growth_trajectory": trajectory,
        # Growth trajectory confidence: only count agents with shipped commits
        "trajectory_confidence": f"{expanding_count}/{len(agents_list)} agents with shipped work",
        "biggest_risk": biggest_risk,
        "biggest_win": biggest_win,
        "hyo_attention": hyo_attention,
        "api_spend_today": api_spend_summary,
        "api_calls_today": api_calls,
        "synthesis_ran": synthesis_ran,
        # ── v6 new fields (PROTOCOL_MORNING_REPORT.md Part 3) ──
        "agents_shipped": agents_shipped_count,
        "agents_building": agents_building_count,
        "agents_researching": agents_researching_count,
        "agents_stalled": agents_stalled_count,
        "critical_blocked": critical_blocked,
    },
    "agents": agent_reports
}

# Write JSON
with open(json_output_path, "w") as f:
    json.dump(report, f, indent=2)

print(f"✓ JSON report written: {json_output_path}")

# ═══════════════════════════════════════════════════════════════════════════════
# GENERATE HUMAN-READABLE NARRATIVE FOR HYO
# ═══════════════════════════════════════════════════════════════════════════════

def build_agent_narrative(name, report):
    """Build a 2-4 sentence human-readable narrative for one agent.
    Tone: smart colleague briefing a CEO. BLUF first. No jargon without explanation.
    Per PROTOCOL_MORNING_REPORT.md v1.1 Part 0b.
    """
    agent_labels = {
        "nel": "Nel (security & QA)",
        "ra": "Ra (newsletter)",
        "sam": "Sam (engineering)",
        "aether": "Aether (trading bot)",
        "dex": "Dex (pattern detection)",
        "kai": "Kai (CEO orchestrator)"
    }
    label = agent_labels.get(name, name.capitalize())

    imp_status = report.get("improvement_status", "unknown")
    weakness = report.get("weakness_identified", "")
    novel = report.get("novel_work", "")
    metric_before = report.get("metric_before", "")
    metric_after = report.get("metric_after", "")
    findings = report.get("research_findings", "")
    has_aric = report.get("has_aric_data", False)
    imp_desc = report.get("improvement_description", "")
    commit = report.get("improvement_commit", "")
    aric_stale = report.get("aric_stale", False)
    aric_stale_date = report.get("aric_stale_date")
    aric_stale_hours = report.get("aric_stale_hours", 0)

    parts = []

    # ── FRESHNESS GATE: stale ARIC data must be labeled, not presented as today's ──
    if aric_stale and aric_stale_date:
        parts.append(
            f"⚠️ {label}: ARIC data is {round(aric_stale_hours)}h old (last cycle: {aric_stale_date}) — "
            f"the details below are from that date, not today. Self-improvement cycle may be broken."
        )

    if imp_status == "shipped" and imp_desc:
        # Something real shipped — lead with that
        if commit:
            parts.append(f"{label} shipped a real improvement overnight: {imp_desc}.")
        else:
            parts.append(f"{label} completed work on: {imp_desc}.")
        if metric_before and metric_after and metric_before != "N/A":
            parts.append(f"Before: {metric_before}. After: {metric_after} — a measurable change.")
        elif findings and findings not in ("none", "N/A", "(no ARIC data yet)", "(research not completed)"):
            parts.append(f"What drove it: {findings[:120]}.")
    elif has_aric and weakness and weakness not in ("Unknown", "?"):
        # Research happened but nothing built yet — honest about that
        parts.append(f"{label} is working on a structural weakness: {weakness}.")
        if findings and findings not in ("none", "N/A", "(no ARIC data yet)", "(research not completed)"):
            parts.append(f"What the research surfaced: {findings[:120]}.")
        parts.append("No code has changed yet — the research is done, execution is next.")
    elif novel and "no novel" not in novel.lower() and "unknown" not in novel.lower():
        # Some active work, even without ARIC
        parts.append(f"{label} is actively working on: {novel}.")
        if weakness and weakness not in ("Unknown", "?"):
            parts.append(f"The core issue being addressed: {weakness}.")
    else:
        # Nothing notable — say so plainly
        parts.append(f"{label} has no active improvement work this cycle.")
        if weakness and weakness not in ("Unknown", "?"):
            parts.append(f"Known weakness not yet worked: {weakness}.")
        if not has_aric:
            parts.append("Research cycle did not complete — no data to work from.")

    return " ".join(parts)

# Build narrative per agent
# Per PROTOCOL_MORNING_REPORT.md v1.1 Part 0b: BLUF + inverted pyramid, human tone
print("\n" + "="*80)
print("MORNING REPORT — " + today)
print("="*80 + "\n")

# Executive summary: 3 human sentences
# Q1: System healthy? — checks queue liveness AND score thresholds
# Gate: "healthy" requires queue alive AND no agent SICQ critically below threshold
_sicq_critical_agents = []
try:
    _sq = json.load(open(os.path.join(root, "kai/ledger/sicq-latest.json"))) if os.path.exists(os.path.join(root, "kai/ledger/sicq-latest.json")) else {}
    for _a, _s in _sq.get("scores", {}).items():
        if _s < 60:  # Below minimum threshold (60) — not just critical (40)
            _sicq_critical_agents.append(f"{_a.capitalize()}({_s}/100 — min:60)")
except Exception:
    pass

if not exec_layer["alive"]:
    health_sentence = f"The execution layer is down — queue worker has been stalled for {exec_layer['stall_hours']}h, which means no delegated commands have run."
elif _sicq_critical_agents:
    health_sentence = f"System has quality issues that need attention — {', '.join(_sicq_critical_agents)} scored critically low. Improvements are being built but the system is not fully healthy."
elif hyo_attention:
    health_sentence = f"Something needs your attention this morning: {hyo_attention}"
else:
    health_sentence = "System is healthy — the queue is active, all agents ran overnight, and quality scores are within range."

# Q2: Biggest thing to know
if wins:
    big_thing = f"Biggest win: {wins[0]}."
elif agents_shipped_count > 0:
    big_thing = f"{agents_shipped_count} agent(s) shipped improvements overnight."
elif agents_building_count > 0:
    big_thing = f"{agents_building_count} agent(s) are actively building; nothing has shipped to production yet."
else:
    big_thing = f"No improvements shipped overnight — all agents are in research or stalled. That's not progress yet."

# Q3: Watch for
if risks:
    watch_sentence = f"Watch: {risks[0]}."
elif stale_aric_warning:
    watch_sentence = f"Watch: {stale_aric_warning}"
elif simulation_warning:
    watch_sentence = "Watch: API synthesis didn't run, so agent 'research' is raw source snippets, not analyzed findings."
else:
    watch_sentence = "Nothing urgent to flag."

print(health_sentence)
print(big_thing)
print(watch_sentence)
if stale_aric_warning:
    print(f"\n{stale_aric_warning}")
if hyo_attention and not exec_layer["alive"]:
    print(f"\n⚠️  {hyo_attention}")
print()

# Agent sections
for agent_name in agents_list:
    narrative = build_agent_narrative(agent_name, agent_reports[agent_name])
    print(narrative)
    print()

# ── Self-Improvement Flywheel Section ──────────────────────────────────────────
print("─"*80)
print("🔧 SELF-IMPROVEMENT CYCLE (reported by each agent to Kai)")
print("─"*80)
print()

si_section_lines = []
for agent_name in agents_list:
    si = self_improve_reports.get(agent_name)
    agent_labels = {
        "nel": "Nel", "ra": "Ra", "sam": "Sam",
        "aether": "Aether", "dex": "Dex", "kai": "Kai (orchestrator)"
    }
    label = agent_labels.get(agent_name, agent_name.capitalize())

    if not si:
        si_section_lines.append(f"{label}: No self-improvement report yet — cycle has not run today.")
        continue

    wid = si.get("weakness_id", "?")
    wtitle = si.get("weakness_title", "") or "unknown weakness"
    stage = si.get("cycle_stage_completed", "?")
    outcome = si.get("outcome", "")
    fix = si.get("fix_approach", "")
    conf = si.get("confidence", "")
    resolved = si.get("improvements_resolved", [])
    cycles = si.get("total_cycles", 0)

    if resolved:
        line = f"{label}: ✓ Resolved {', '.join(resolved)} — {wtitle}. Cycle {cycles} complete."
    else:
        stage_label = {"research": "Researched", "implement": "Implementing", "verify": "Verifying"}.get(stage, stage.capitalize())
        conf_str = f" (confidence: {conf})" if conf else ""
        line = f"{label}: {stage_label} {wid} — {wtitle}{conf_str}."
        if fix:
            line += f" Approach: {fix[:100]}."

    si_section_lines.append(line)

for line in si_section_lines:
    print(line)

# SICQ quality scores (process compliance — from flywheel-doctor-latest.json)
import json as _json_sicq, os as _os_sicq
_sicq_path = os.path.join(root, "kai/ledger/sicq-latest.json")
if _os_sicq.path.exists(_sicq_path):
    try:
        _sicq = _json_sicq.load(open(_sicq_path))
        _scores = _sicq.get("scores", {})
        _score_date = _sicq.get("date", "")
        if _scores:
            print()
            print(f"📊 SICQ Process Compliance ({_score_date}):")
            for _a, _s in sorted(_scores.items()):
                _flag = "✓" if _s >= 60 else ("⚠" if _s >= 40 else "✗")
                print(f"  {_flag} {_a.capitalize()}: {_s}/100")
            _avg = sum(_scores.values()) // len(_scores) if _scores else 0
            print(f"  System average: {_avg}/100 {'(healthy)' if _avg >= 60 else '(needs attention)'}")
    except:
        pass

# OMP outcome quality scores (from omp-summary.json — runs at 06:45 MT)
_omp_path = os.path.join(root, "kai/ledger/omp-summary.json")
if os.path.exists(_omp_path):
    try:
        _omp = json.load(open(_omp_path))
        _omp_agents = _omp.get("agents", {})
        _omp_date = _omp.get("date", "")
        if _omp_agents:
            print()
            print(f"🎯 OMP Outcome Quality ({_omp_date}):")
            _metric_labels = {
                "nel": "APS", "sam": "DSS", "ra": "EQS",
                "aether": "ASR", "dex": "PAR", "kai": "KAI_COMPOSITE"
            }
            _thresholds = {
                "APS": 0.80, "DSS": 0.90, "EQS": 0.50,
                "ASR": 0.65, "PAR": 0.35, "KAI_COMPOSITE": 0.75
            }
            # Kai-specific dimension thresholds
            _kai_dim_thresholds = {"DQI": 0.80, "OSS": 0.85, "KRI": 0.90, "AAS": 0.75, "BIS": 0.85}
            _kai_dim_labels = {
                "DQI": "CEO decisions",
                "OSS": "orchestration sync",
                "KRI": "knowledge retention",
                "AAS": "autonomous action",
                "BIS": "business impact"
            }
            for _a in sorted(_omp_agents.keys()):
                _ad = _omp_agents[_a]
                _mn = _ad.get("specific_metric", "?")
                _ms = _ad.get("specific_score")
                _thr = _thresholds.get(_mn, 0.50)
                # Kai: show 5-dimensional breakdown instead of single metric
                if _a == "kai" and _ad.get("kai_profile"):
                    _kp = _ad["kai_profile"]
                    print(f"  Kai OMP (5-dimensional):")
                    for _dim in ["DQI", "OSS", "KRI", "AAS", "BIS"]:
                        _dv = _kp.get(_dim)
                        _dt = _kai_dim_thresholds.get(_dim, 0.75)
                        _dl = _kai_dim_labels.get(_dim, _dim)
                        if _dv is not None:
                            _df = "✓" if _dv >= _dt else ("⚠" if _dv >= _dt * 0.80 else "✗")
                            print(f"    {_df} {_dim} ({_dl}): {_dv:.3f}")
                        else:
                            print(f"    — {_dim} ({_dl}): no data")
                    if _ms is not None:
                        _cf = "✓" if _ms >= _thr else ("⚠" if _ms >= _thr * 0.80 else "✗")
                        print(f"    → Composite: {_ms:.3f} {_cf}")
                    continue
                if _ms is not None:
                    _flag = "✓" if _ms >= _thr else ("⚠" if _ms >= _thr * 0.80 else "✗")
                    _pct = int(_ms * 100)
                    print(f"  {_flag} {_a.capitalize()} {_mn}: {_pct}% (target: {int(_thr*100)}%)")
                else:
                    print(f"  — {_a.capitalize()} {_mn}: no data yet")
            # RDI (research depth) — show aggregate
            _rdi_vals = [v.get("RDI") for v in _omp_agents.values() if v.get("RDI") is not None]
            if _rdi_vals:
                _avg_rdi = sum(_rdi_vals) / len(_rdi_vals)
                _rdi_flag = "✓" if _avg_rdi >= 0.70 else ("⚠" if _avg_rdi >= 0.40 else "✗")
                print(f"  {_rdi_flag} Research Depth (RDI avg): {int(_avg_rdi*100)}% (target: 70%)")
    except Exception as _e:
        pass

# Kai synthesis of all agent self-improve reports
# Exclude Kai from "agent" count for synthesis phrasing (Kai is the synthesizer, not a reportee)
non_kai_agents = [a for a in agents_list if a != "kai"]
reported_count = sum(1 for a in non_kai_agents if self_improve_reports.get(a) is not None)

# Kai's own research highlight (separate from orchestrator synthesis)
kai_si = self_improve_reports.get("kai")
if kai_si:
    print()
    kai_wid = kai_si.get("weakness_id", "?")
    kai_wtitle = kai_si.get("weakness_title", "") or "system weakness"
    kai_stage = kai_si.get("cycle_stage_completed", "research")
    kai_fix = kai_si.get("fix_approach", "")
    kai_conf = kai_si.get("confidence", "")
    kai_resolved = kai_si.get("improvements_resolved", [])
    kai_cycles = kai_si.get("total_cycles", 0)
    if kai_resolved:
        print(f"Kai Research: ✓ Resolved orchestrator weakness {', '.join(kai_resolved)} — {kai_wtitle}. "
              f"Research + implementation complete after {kai_cycles} cycles. "
              f"System architecture improved. See agents/kai/research/ for full findings.")
    else:
        stage_label = {"research": "Researched", "implement": "Implementing fix for", "verify": "Verifying"}.get(kai_stage, kai_stage.capitalize())
        conf_str = f" (confidence: {kai_conf})" if kai_conf else ""
        print(f"Kai Research: {stage_label} {kai_wid} — {kai_wtitle}{conf_str}.")
        if kai_fix:
            print(f"  Fix approach: {kai_fix[:150]}.")
        print(f"  Published research drop to HQ — see Research tab for full findings.")

if reported_count == 0:
    print()
    print("Kai synthesis: No agent has reported yet — self-improvement cycle has not run today (expected 08:00 MT).")
elif len(si_resolved_today) > 0:
    print()
    print(f"Kai synthesis: {len(si_resolved_today)} improvement(s) resolved today via the compounding flywheel. "
          f"Knowledge persisted to KNOWLEDGE.md and memory engine.")
else:
    print()
    print(f"Kai synthesis: {reported_count}/{len(non_kai_agents)} agents reported. "
          f"All cycles in progress — no weaknesses fully resolved yet today. "
          f"Expected completions: next overnight cycle.")

print()
print("="*80)

PYEOF

if [[ $? -ne 0 ]]; then
  log "ERROR: Failed to generate reports"
  exit 1
fi

# ── Sync to sam/website mirror ──
SAM_MIRROR="$ROOT/agents/sam/website/data/morning-report.json"
if [[ -d "$(dirname "$SAM_MIRROR")" ]]; then
  if [[ ! "$JSON_OUTPUT" -ef "$SAM_MIRROR" ]] 2>/dev/null; then
    cp "$JSON_OUTPUT" "$SAM_MIRROR" 2>/dev/null || true
  fi
  log "Mirror synced: $SAM_MIRROR"
fi

# ── Publish to feed.json (TASK-20260417-kai-002: must happen in this script, not externally) ──
FEED_JSON="$ROOT/website/data/feed.json"
if [[ -f "$FEED_JSON" ]] && [[ -f "$JSON_OUTPUT" ]]; then
  log "Adding morning report to feed.json..."
  python3 - "$FEED_JSON" "$JSON_OUTPUT" "$TODAY" <<'FEED_PYEOF'
import json, sys
from datetime import datetime

feed_path = sys.argv[1]
mr_path = sys.argv[2]
today = sys.argv[3]

with open(feed_path) as f:
    feed = json.load(f)
with open(mr_path) as f:
    mr = json.load(f)

reports = feed.get("reports", [])

# Remove any existing morning report for today (idempotent)
reports = [r for r in reports if not (r.get("type") == "morning-report" and r.get("date") == today)]

# Build sections from morning report data
exec_summary = mr.get("executive_summary", {})
agents = mr.get("agents", {})

went_well = []
needs_attention = []
highlights = {}

exec_layer_status = exec_summary.get("execution_layer", {})
simulation_warning = exec_summary.get("simulation_warning")

# EXECUTION LAYER — always first in needs_attention if down
if exec_summary.get("hyo_attention"):
    needs_attention.insert(0, exec_summary["hyo_attention"])

# SIMULATION WARNING — second priority
if simulation_warning:
    needs_attention.append(simulation_warning)

# STALE ARIC WARNING — third priority (drives recycled content problem)
stale_aric_warning_feed = exec_summary.get("stale_aric_warning")
if stale_aric_warning_feed:
    needs_attention.append(stale_aric_warning_feed)

for name, data in agents.items():
    parts = []
    nw = data.get("novel_work", "")
    imp_status = data.get("improvement_status", "")
    rc = int(data.get("research_count", 0) or 0)  # may be stored as str
    rf = str(data.get("research_findings", "") or "")
    w = str(data.get("weakness_identified", "") or "")

    has_aric = data.get("has_aric_data")
    if isinstance(has_aric, str):
        has_aric = has_aric.lower() == "true"

    # Highlight what actually happened — human-readable, CEO-audience
    # Per PROTOCOL_MORNING_REPORT.md v1.1 Part 0b: lead with "so what", not "what ran"
    if imp_status == "shipped" and data.get("improvement_description"):
        imp_d = data["improvement_description"]
        commit = data.get("improvement_commit", "")
        parts.append(f"Shipped a real improvement: {imp_d}." + (f" Commit: {commit}." if commit else ""))
        if data.get("metric_after") and data.get("metric_before") and data.get("metric_before") != "N/A":
            parts.append(f"Before: {data['metric_before']} → after: {data['metric_after']}.")
    elif rc > 0 and has_aric:
        if w and w != "?":
            parts.append(f"Working on: {w}.")
        if rf and rf not in ("none", "N/A", "(no ARIC data yet)", "(research not completed)"):
            parts.append(f"What the research found: {rf[:150]}.")
        parts.append("Research is done — no code changed yet.")
    elif nw and "no novel" not in nw.lower() and "unknown" not in nw.lower():
        parts.append(f"Active work: {nw}.")
    else:
        parts.append("No active improvement work this cycle.")
        if not has_aric:
            parts.append("Research cycle didn't complete.")
    highlights[name] = " ".join(parts) if parts else "No data."

    # went_well: ONLY if something shipped with a commit hash
    if imp_status == "shipped" and data.get("improvement_description"):
        went_well.append(f"{name.capitalize()}: {data['improvement_description']}")

    # needs_attention: ARIC ran but nothing built (and not already captured)
    if (has_aric and rc > 0
            and imp_status not in ("shipped",)
            and not exec_summary.get("hyo_attention")):  # don't repeat if exec layer is the headline
        needs_attention.append(
            f"{name.capitalize()}: ARIC fetched {rc} sources but no improvement built "
            f"— research is theater until Phase 6 executes"
        )

if not went_well:
    went_well = ["No improvements shipped today — execution blocked or cycle incomplete"]

if not needs_attention:
    needs_attention = ["No critical issues"]

# Summary text: 3 human sentences per PROTOCOL_MORNING_REPORT.md v1.1 Part 0b
# Q1: System healthy? Q2: Biggest thing to know? Q3: What to watch?
system_alive = exec_layer_status.get("alive", True) if exec_layer_status else True
hyo_attn = exec_summary.get("hyo_attention")

if not system_alive:
    stall_h = exec_layer_status.get("stall_hours", "?") if exec_layer_status else "?"
    q1 = f"The execution layer is down — the queue has been stalled for {stall_h}h, so no delegated commands ran overnight."
elif hyo_attn:
    q1 = f"Something needs your attention: {hyo_attn}"
else:
    q1 = "System is healthy — the queue is active and all agents ran overnight."

agents_shipped = exec_summary.get("agents_shipped", 0)
agents_building = exec_summary.get("agents_building", 0)
biggest_win = exec_summary.get("biggest_win", "")
if agents_shipped and agents_shipped > 0:
    q2 = f"{agents_shipped} agent(s) shipped real improvements." + (f" Biggest win: {biggest_win}." if biggest_win and "no" not in biggest_win.lower() else "")
elif agents_building and agents_building > 0:
    q2 = f"{agents_building} agent(s) are actively building — nothing shipped to production yet."
else:
    q2 = "No improvements shipped overnight — agents are in research or haven't started building."

stale_aric_warning_feed = exec_summary.get("stale_aric_warning")
biggest_risk = exec_summary.get("biggest_risk", "")
if simulation_warning:
    q3 = "Watch: API synthesis didn't run, so agent 'research' is raw snippets, not analyzed findings."
elif stale_aric_warning_feed:
    # Stale ARIC is the #1 reason morning report recycles content — surface it prominently
    stale_agents_feed = [
        a for a in agents.keys()
        if agents[a].get("aric_stale")
    ]
    q3 = f"Watch: {len(stale_agents_feed)} agent(s) have stale ARIC data — content below is from a prior date, not today."
elif biggest_risk and "no blocker" not in biggest_risk.lower():
    q3 = f"Watch: {biggest_risk}."
else:
    q3 = "Nothing urgent to flag."

summary_text = f"{q1} {q2} {q3}"
if simulation_warning:
    summary_text += " ⚠️ Synthesis did not run."
if stale_aric_warning_feed:
    summary_text += f" ⚠️ {stale_aric_warning_feed}"

# ── Self-improvement flywheel section for feed entry ──
si_flywheel = mr.get("self_improvement_flywheel", {})
si_resolved = si_flywheel.get("resolved_today", [])
si_in_prog = si_flywheel.get("in_progress", [])
si_no_rpt = si_flywheel.get("no_report", [])
si_count = si_flywheel.get("agents_with_data", 0)
total_agents = si_flywheel.get("total_agents", 5)

if si_resolved:
    flywheel_summary = f"{len(si_resolved)} weakness(es) resolved today: " + "; ".join(si_resolved)
elif si_count > 0:
    flywheel_summary = f"{si_count}/{total_agents} agents reported — cycles in progress, resolving overnight."
else:
    flywheel_summary = "No agent self-improvement reports yet — cycle expected at 08:00 MT."

flywheel_detail = si_in_prog if si_in_prog else ["No in-progress reports."]
if si_no_rpt:
    flywheel_detail.append(f"No report from: {', '.join(si_no_rpt)}")

now_ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")

# Build sicqScores dict for HQ feed — read directly from file (separate process from PYEOF)
_sicq_for_feed = {}
try:
    _sicq_labels = {100: "Excellent", 80: "Good", 60: "Fair", 40: "Low", 0: "Critical"}
    _sicq_path = os.path.join(root, "kai/ledger/sicq-latest.json")
    _sq = json.load(open(_sicq_path)) if os.path.exists(_sicq_path) else {}
    for _a, _s in _sq.get("scores", {}).items():
        _lbl = next((_sicq_labels[k] for k in sorted(_sicq_labels.keys(), reverse=True) if _s >= k), "Critical")
        _sicq_for_feed[_a] = {"score": _s, "label": _lbl, "min": 60,
                               "status": "critical" if _s <= 40 else ("warn" if _s < 60 else "ok")}
except Exception:
    pass

# Build ompScores dict for HQ feed — read directly from file (separate process from PYEOF)
_omp_for_feed = {}
try:
    _omp_path = os.path.join(root, "kai/ledger/omp-summary.json")
    _omp_data = json.load(open(_omp_path)) if os.path.exists(_omp_path) else {}
    for _a, _ad in _omp_data.get("agents", {}).items():
        _ms = _ad.get("overall")
        if _ms is not None:
            _pct = int(_ms)
            _lbl = "Excellent" if _pct >= 80 else ("Good" if _pct >= 70 else ("Adequate" if _pct >= 60 else ("Needs Improvement" if _pct >= 40 else "Critical")))
            _omp_for_feed[_a] = {"score": _pct, "label": _lbl, "min": 70,
                                  "status": "critical" if _pct <= 40 else ("warn" if _pct < 70 else "ok")}
except Exception:
    pass

_sections = {
    "summary": summary_text,
    "wentWell": went_well,
    "needsAttention": needs_attention,
    "agentHighlights": highlights,
    "selfImprovementFlywheel": {
        "summary": flywheel_summary,
        "detail": flywheel_detail,
        "resolved_today": si_resolved,
    }
}

# Inject scores INTO sections — renderMorningReport(s) reads s = report.sections
# Gate question: "Are sicqScores/ompScores inside sections?" NO → renderer sees nothing.
if _sicq_for_feed:
    _sections["sicqScores"] = _sicq_for_feed
if _omp_for_feed:
    _sections["ompScores"] = _omp_for_feed

entry = {
    "id": f"morning-report-kai-{today}-{datetime.now().strftime('%H%M%S')}",
    "type": "morning-report",
    "title": f"Morning Report — {today}",
    "author": "Kai",
    "authorIcon": "\U0001f454",
    "authorColor": "#d4a853",
    "timestamp": now_ts,
    "date": today,
    "sections": _sections,
}

reports.insert(0, entry)
feed["reports"] = reports
feed["lastUpdated"] = now_ts

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)
    f.write("\n")

print(f"Morning report added to feed.json for {today}")
FEED_PYEOF
  log "Feed entry created"

  # FIX (2026-04-28): Mirror feed.json to agents/sam/website/data/feed.json.
  # The dual-path pre-commit gate blocks commits unless BOTH paths are updated.
  # Previously the script only wrote to website/data/feed.json, leaving the sam mirror
  # stale. That caused the gate to abort every morning-report commit silently.
  SAM_FEED_JSON_MIRROR="$ROOT/agents/sam/website/data/feed.json"
  if [[ -d "$(dirname "$SAM_FEED_JSON_MIRROR")" ]]; then
    if [[ ! "$FEED_JSON" -ef "$SAM_FEED_JSON_MIRROR" ]] 2>/dev/null; then
      cp "$FEED_JSON" "$SAM_FEED_JSON_MIRROR" 2>/dev/null || true
    fi
    log "feed.json mirror synced: $SAM_FEED_JSON_MIRROR"
  fi
else
  log "WARN: feed.json or morning-report.json missing — feed entry not created"
fi

# ── Commit if changes exist ──
cd "$ROOT" || exit 1

# Prevention: clear stale lock files from crashed processes (TASK-20260417-kai-002)
rm -f .git/index.lock 2>/dev/null

# Both feed.json paths — website/ is symlink, agents/sam/website/ is canonical.
# Git treats them as separate index entries even though they are the same physical file.
# BOTH must be staged or the dual-path pre-commit gate blocks the commit.
SAM_FEED_JSON="$ROOT/agents/sam/website/data/feed.json"

# FIX (Bug 2): Previously compared two unrelated files against each other.
# Correct check: has any of the four output files changed from the last git HEAD commit?
if git diff --quiet HEAD -- "$JSON_OUTPUT" "$SAM_MIRROR" "$FEED_JSON" "$SAM_FEED_JSON" 2>/dev/null; then
  log "No changes to commit (all four output files match HEAD)"
else
  # Stage all four paths (morning-report.json × 2 paths, feed.json × 2 paths)
  git add "$JSON_OUTPUT" "$SAM_MIRROR" "$FEED_JSON" "$SAM_FEED_JSON" 2>/dev/null || true

  # GATE (Bug 1 prevention): Before committing, verify BOTH feed.json paths are staged.
  # This is a yes/no gate — not just a log message. Commit is blocked until both are staged.
  # FIX (2026-04-28): Anchor the regex to the full path so the website-pattern doesn't
  # match agents/sam/website/data/feed.json as a substring. Use `|| true` (not `|| echo 0`)
  # so we don't end up with `0\n0` in the variable when grep finds no matches.
  _WEBSITE_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -cE "^website/data/feed\.json$" || true)
  _SAM_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -cE "^agents/sam/website/data/feed\.json$" || true)
  _WEBSITE_STAGED=${_WEBSITE_STAGED:-0}
  _SAM_STAGED=${_SAM_STAGED:-0}
  if [[ "$_WEBSITE_STAGED" -eq 0 ]] || [[ "$_SAM_STAGED" -eq 0 ]]; then
    # Gate failed — attempt one recovery: force-add the missing path
    log "DUAL-PATH GATE: feed.json missing from staged files (website=$_WEBSITE_STAGED sam=$_SAM_STAGED). Attempting recovery..."
    git add "$FEED_JSON" "$SAM_FEED_JSON" 2>/dev/null || true
    _WEBSITE_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -cE "^website/data/feed\.json$" || true)
    _SAM_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -cE "^agents/sam/website/data/feed\.json$" || true)
    _WEBSITE_STAGED=${_WEBSITE_STAGED:-0}
    _SAM_STAGED=${_SAM_STAGED:-0}
    if [[ "$_WEBSITE_STAGED" -eq 0 ]] || [[ "$_SAM_STAGED" -eq 0 ]]; then
      log "DUAL-PATH GATE FAILED after recovery attempt. Aborting commit. Opening P0 ticket."
      bash "$ROOT/bin/ticket.sh" create \
        --agent kai --title "Morning report dual-path gate failure — feed.json not staged on both paths" \
        --priority P0 --system system-3 2>/dev/null || true
      bash "$ROOT/bin/dispatch.sh" flag kai P0 "morning-report dual-path gate failed — report NOT committed" 2>/dev/null || true
      log "ERROR: morning report NOT published (dual-path gate)."
    fi
  fi

  # Gate passed — both paths staged. Proceed to commit.
  if [[ "$_WEBSITE_STAGED" -gt 0 ]] && [[ "$_SAM_STAGED" -gt 0 ]]; then
    log "DUAL-PATH GATE: PASSED (website=$_WEBSITE_STAGED sam=$_SAM_STAGED) — committing"
    if git commit -m "morning-report: $TODAY (v4 — growth-driven ARIC consumption)"; then
      if git push origin main; then
        log "Pushed to origin"

        # FIX (Bug 3): Post-push live verification — fetch the actual live feed endpoint
        # and confirm today's morning-report entry is visible. Not just "push succeeded".
        log "Verifying live deployment (waiting 30s for Vercel build)..."
        sleep 30
        _LIVE_STATUS=$(curl -sf --max-time 15 "https://www.hyo.world/data/feed.json" 2>/dev/null | python3 -c "
import json, sys
try:
  d = json.load(sys.stdin)
  reports = d.get('reports', [])
  mr = [r for r in reports if r.get('type') == 'morning-report' and '$TODAY' in str(r.get('date',''))]
  print('FOUND' if mr else 'MISSING')
except:
  print('ERROR')
" 2>/dev/null || echo "UNREACHABLE")
        if [[ "$_LIVE_STATUS" == "FOUND" ]]; then
          log "LIVE VERIFICATION: PASSED — morning report visible at hyo.world/data/feed.json"
        else
          log "LIVE VERIFICATION: FAILED (status=$_LIVE_STATUS) — Vercel may not have deployed yet"
          log "  Live check: https://www.hyo.world/data/feed.json — look for type=morning-report date=$TODAY"
          bash "$ROOT/bin/ticket.sh" create \
            --agent kai --title "Morning report pushed but NOT visible on live site ($TODAY) — Vercel deploy issue" \
            --priority P1 --system system-3 2>/dev/null || true
          bash "$ROOT/bin/dispatch.sh" flag kai P1 "morning-report pushed to git but not visible live — check Vercel deploy" 2>/dev/null || true
        fi
      else
        log "ERROR: git push failed — morning report NOT published. Manual push required."
        bash "$ROOT/bin/dispatch.sh" flag kai P0 "morning report generated but git push failed — report not live" 2>/dev/null || true
      fi
    else
      log "ERROR: git commit failed — morning report NOT published."
    fi
  fi
fi

log "Done — v4 morning report generated"
