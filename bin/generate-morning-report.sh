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
    if "shipped" in improvement_status.lower() or "building" in novel_work.lower():
        growth_trajectories.append("expanding")
    else:
        growth_trajectories.append("maintaining")

    if "no" in novel_work.lower() or "unknown" in novel_work.lower():
        risks.append(f"{agent_name}: {novel_work}")

    if "shipped" in improvement_status.lower():
        wins.append(f"{agent_name}: {novel_work}")

    # Compile agent report
    agent_reports[agent_name] = {
        "novel_work": novel_work,
        "weakness_identified": weakness_research.get("weakness", "?"),
        "research_conducted": weakness_research.get("sources", "none"),
        "research_findings": weakness_research.get("findings", "none"),
        "research_count": weakness_research.get("count", 0),
        "improvement_status": improvement_status,
        "improvement_description": aric.get("improvement_built", {}).get("description") if aric else "N/A",
        "metric_before": metric_move.get("before") if metric_move else "N/A",
        "metric_after": metric_move.get("after") if metric_move else "N/A",
        "metric_moved": bool(metric_move),
        "external_opportunity_type": external.get("type") if external else "none",
        "external_opportunity_desc": external.get("description") if external else "none",
        "has_aric_data": aric is not None,
        "aric_cycle_date": aric.get("cycle_date", "unknown") if aric else None
    }

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD EXECUTIVE SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

# Growth trajectory
expanding_count = growth_trajectories.count("expanding")
trajectory = "expanding" if expanding_count >= 3 else ("maintaining" if expanding_count >= 1 else "declining")

biggest_risk = risks[0] if risks else "No major blockers identified"
biggest_win = wins[0] if wins else "Focus on growth identification"

# Determine if Hyo attention needed
hyo_attention = None
no_novel = [a for a in agents_list if "no" in agent_reports[a]["novel_work"].lower()]
if len(no_novel) > 1:
    hyo_attention = f"{len(no_novel)} agents have no active novel work — growth cycle may be stalled"

# ═══════════════════════════════════════════════════════════════════════════════
# GENERATE JSON OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

# ── API usage summary (SE-011-003: visibility on daily API spend) ──
api_spend_summary = ""
try:
    from datetime import date as _date
    ledger = os.path.join(root, "kai", "ledger", "api-usage.jsonl")
    if os.path.exists(ledger):
        by_prov = defaultdict(lambda: {"cost": 0.0, "calls": 0})
        total = 0.0
        calls = 0
        with open(ledger) as _f:
            for _line in _f:
                try:
                    _e = json.loads(_line)
                except Exception:
                    continue
                if _e.get("date") != today:
                    continue
                _c = float(_e.get("cost_usd", 0) or 0)
                _p = _e.get("provider", "?")
                by_prov[_p]["cost"] += _c
                by_prov[_p]["calls"] += 1
                total += _c
                calls += 1
        parts = [f"{p}=${info['cost']:.2f}" for p, info in sorted(by_prov.items(), key=lambda x: -x[1]["cost"])]
        api_spend_summary = f"${total:.2f} ({calls} calls)" + (f" — {', '.join(parts)}" if parts else "")
    else:
        api_spend_summary = "$0.00 (0 calls) — ledger not started"
except Exception as _api_err:
    api_spend_summary = f"error: {_api_err}"

report = {
    "generated": now_mt,
    "date": today,
    "version": "v4-growth-driven",
    "executive_summary": {
        "growth_trajectory": trajectory,
        "trajectory_confidence": f"{expanding_count}/{len(agents_list)} agents expanding",
        "biggest_risk": biggest_risk,
        "biggest_win": biggest_win,
        "kai_focus": "Enabling research access (MCP servers) + monitoring growth cycle execution",
        "hyo_attention": hyo_attention,
        "api_spend_today": api_spend_summary
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

# ── Commit if changes exist ──
cd "$ROOT" || exit 1

# Prevention: clear stale lock files from crashed processes (TASK-20260417-kai-002)
rm -f .git/index.lock 2>/dev/null

if git diff --quiet "$JSON_OUTPUT" 2>/dev/null; then
  log "No changes to commit"
else
  git add "$JSON_OUTPUT" "$SAM_MIRROR" 2>/dev/null || true
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
