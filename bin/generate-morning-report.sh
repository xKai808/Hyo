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
    """Read aric-latest.json for an agent. This is Phase 7 output."""
    path = os.path.join(root, "agents", agent_name, "research", "aric-latest.json")
    data = read_json_safe(path)
    if data:
        # Add flag that data came from ARIC
        data["_source"] = "aric-phase7"
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

# ═══════════════════════════════════════════════════════════════════════════════
# GATHER DATA PER AGENT
# ═══════════════════════════════════════════════════════════════════════════════

agents_list = ["nel", "ra", "sam", "aether", "dex"]
agent_reports = {}
growth_trajectories = []
risks = []
wins = []

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

    # Compile agent report
    agent_reports[agent_name] = {
        "novel_work": novel_work,
        "weakness_identified": weakness_research.get("weakness", "?"),
        "research_conducted": weakness_research.get("sources", "none"),
        "research_findings": weakness_research.get("findings", "none"),
        "research_count": weakness_research.get("count", 0),
        "improvement_status": improvement_status,
        "improvement_description": aric.get("improvement_built", {}).get("description") if aric else "N/A",
        "improvement_commit": (aric.get("improvement_built", {}).get("commit") if aric else None),
        "metric_before": metric_move.get("before") if metric_move else "N/A",
        "metric_after": metric_move.get("after") if metric_move else "N/A",
        "metric_moved": bool(metric_move),
        "external_opportunity_type": external.get("type") if external else "none",
        "external_opportunity_desc": external.get("description") if external else "none",
        "has_aric_data": aric is not None,
        "aric_cycle_date": aric.get("cycle_date", "unknown") if aric else None,
        # ── v6 new fields (PROTOCOL_MORNING_REPORT.md Part 2) ──
        "shipped_since_last": shipped_since_last,
        "highest_priority_issue": highest_priority_issue,
        "next_action": next_action,
        "action_type": action_type,
        "priority_evidence": priority_evidence,
        "improvement_status_detail": improvement_status_detail,
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

report = {
    "generated": now_mt,
    "date": today,
    "version": "v6-action-engine",
    "executive_summary": {
        "system_online": exec_layer["alive"],
        "execution_layer": exec_layer,
        "simulation_warning": simulation_warning,
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
    """Build a 3-5 sentence narrative for one agent, growth-focused."""
    parts = []

    # Novel work
    novel = report["novel_work"]
    if "no" not in novel.lower() and "unknown" not in novel.lower():
        parts.append(f"**{name.upper()}** is {novel}.")
    else:
        parts.append(f"**{name.upper()}** has no active novel work — {novel}.")
        return " ".join(parts)

    # Weakness + research
    weakness = report["weakness_identified"]
    sources = report["research_conducted"]
    findings = report["research_findings"]
    if sources != "none" and sources != "(no ARIC data yet)":
        parts.append(f"Identified weakness: {weakness}. Researched: {sources}. Finding: {findings}.")
    elif weakness != "?":
        parts.append(f"Weakness identified: {weakness}. Research in progress.")

    # Metric movement
    if report["metric_moved"]:
        parts.append(f"Metric moved: {report['metric_before']} → {report['metric_after']}.")

    # External expansion
    if report["external_opportunity_type"] != "none":
        parts.append(f"Pursuing {report['external_opportunity_type']} expansion: {report['external_opportunity_desc']}.")

    # ARIC status
    if not report["has_aric_data"]:
        parts.append("⚠️ No ARIC Phase 7 data — cycle may not have run.")

    return " ".join(parts)

# Build narrative per agent
print("\n" + "="*80)
print("MORNING REPORT — " + today)
print("="*80 + "\n")

print(f"Growth trajectory: {trajectory} ({expanding_count}/{len(agents_list)} expanding)")
print(f"Biggest risk: {biggest_risk}")
print(f"Biggest win: {biggest_win}")
print(f"API spend today: {api_spend_summary}")
if hyo_attention:
    print(f"⚠️ NEEDS ATTENTION: {hyo_attention}")
print()

for agent_name in agents_list:
    narrative = build_agent_narrative(agent_name, agent_reports[agent_name])
    print(narrative)
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

    # Highlight what actually happened
    # NOTE: no char limits — full text is displayed in HQ, truncation causes cut-off
    if imp_status == "shipped" and data.get("improvement_description"):
        parts.append(f"Shipped: {data['improvement_description']}.")
    elif rc > 0 and has_aric:
        parts.append(f"Identified weakness: {w}." if w and w != "?" else "Weakness unclear.")
        parts.append(f"Fetched {rc} sources.")
        if rf and rf not in ("none", "N/A", "(no ARIC data yet)", "(research not completed)"):
            parts.append(f"Key finding: {rf}")
    else:
        parts.append(nw if nw and "no novel" not in nw.lower() else "No cycle data — ARIC may not have run.")
    highlights[name] = " ".join(parts) if parts else "No active work this cycle."

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

# Summary text: honest, execution-first
system_status = "offline" if exec_layer_status and not exec_layer_status.get("alive", True) else "online"
summary_text = (
    f"System: {system_status}. "
    f"Growth: {exec_summary.get('growth_trajectory', '?')} "
    f"({exec_summary.get('trajectory_confidence', '?')} with actual shipped work). "
    f"API spend: {exec_summary.get('api_spend_today', '?')}."
)
if simulation_warning:
    summary_text += " ⚠️ Synthesis phase did not run."

now_ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")
entry = {
    "id": f"morning-report-kai-{today}-{datetime.now().strftime('%H%M%S')}",
    "type": "morning-report",
    "title": f"Morning Report — {today}",
    "author": "Kai",
    "authorIcon": "\U0001f454",
    "authorColor": "#d4a853",
    "timestamp": now_ts,
    "date": today,
    "sections": {
        "summary": summary_text,
        "wentWell": went_well,
        "needsAttention": needs_attention,
        "agentHighlights": highlights
    }
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
else
  log "WARN: feed.json or morning-report.json missing — feed entry not created"
fi

# ── Commit if changes exist ──
cd "$ROOT" || exit 1

# Prevention: clear stale lock files from crashed processes (TASK-20260417-kai-002)
rm -f .git/index.lock 2>/dev/null

if git diff --quiet "$JSON_OUTPUT" "$FEED_JSON" 2>/dev/null; then
  log "No changes to commit"
else
  git add "$JSON_OUTPUT" "$SAM_MIRROR" "$FEED_JSON" 2>/dev/null || true
  if git commit -m "morning-report: $TODAY (v4 — growth-driven ARIC consumption)"; then
    if git push origin main; then
      log "Pushed to origin"
    else
      log "ERROR: git push failed — morning report NOT published. Manual push required."
      # Flag for sentinel
      local dispatch_bin="$ROOT/bin/dispatch.sh"
      if [[ -x "$dispatch_bin" ]]; then
        bash "$dispatch_bin" flag kai P0 "morning report generated but git push failed — report not live" 2>/dev/null || true
      fi
    fi
  else
    log "ERROR: git commit failed — morning report NOT published."
  fi
fi

log "Done — v4 morning report generated"
