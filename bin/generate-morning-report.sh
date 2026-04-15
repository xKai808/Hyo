#!/usr/bin/env bash
# bin/generate-morning-report.sh — Two-version morning report generator
#
# Produces TWO outputs:
#   1. INTERNAL: website/data/morning-report.json — technical metrics for Kai
#   2. FEED: appends to website/data/feed.json — human-readable narrative for Hyo
#
# v2 (2026-04-14): Rewritten to read ACTUAL agent outputs (sentinel logs, cipher
# scans, research findings, analysis files, self-reviews) instead of just
# evolution.jsonl metadata. Each agent section is unique because it's built from
# what the agent actually did, not a template.
#
# Called by:
#   - com.hyo.morning-report launchd plist (05:00 MT daily)
#   - healthcheck.sh auto-remediation (when morning report is stale)
#   - nel-qa-cycle.sh Phase 7.5 auto-remediation
#   - dispatch.sh simulation Phase 6 auto-remediation
#
# Usage: bash bin/generate-morning-report.sh
#        HYO_ROOT=/path/to/Hyo bash bin/generate-morning-report.sh

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
INTERNAL_OUTPUT="$ROOT/website/data/morning-report.json"
FEED_OUTPUT="$ROOT/website/data/feed.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
YESTERDAY=$(TZ="America/Denver" date -v-1d +%Y-%m-%d 2>/dev/null || TZ="America/Denver" date -d "yesterday" +%Y-%m-%d 2>/dev/null || echo "unknown")
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
MONTH_KEY=$(echo "$TODAY" | cut -c1-7)
LOG_TAG="[morning-report]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

log "Generating morning report v2 for $TODAY"

# ── Sync agent profiles from PLAYBOOKs before generating report ──
SYNC_SCRIPT="$ROOT/bin/sync-agent-profiles.sh"
if [[ -x "$SYNC_SCRIPT" ]]; then
  bash "$SYNC_SCRIPT" 2>&1 | tail -2
  log "Agent profiles synced from PLAYBOOKs"
fi

# ── Generate both reports via Python ──

python3 - "$INTERNAL_OUTPUT" "$FEED_OUTPUT" "$TODAY" "$YESTERDAY" "$NOW_MT" "$MONTH_KEY" "$ROOT" <<'PYEOF'
import json, sys, os, re, glob
from pathlib import Path

internal_path = sys.argv[1]
feed_path     = sys.argv[2]
today         = sys.argv[3]
yesterday     = sys.argv[4]
now_mt        = sys.argv[5]
month_key     = sys.argv[6]
root          = sys.argv[7]

# ══════════════════════════════════════════════════════════════════════════════
# DATA GATHERING — Read actual agent outputs, not just metadata
# ══════════════════════════════════════════════════════════════════════════════

def parse_growth(agent_name):
    """Parse GROWTH.md for an agent — extract weaknesses, improvements, goals."""
    path = os.path.join(root, "agents", agent_name, "GROWTH.md")
    if not os.path.exists(path):
        return None
    text = open(path).read()
    result = {"weaknesses": [], "improvements": [], "goals": []}

    # Extract weaknesses (### W1: Title lines)
    for m in re.finditer(r'### W(\d): (.+)', text):
        wnum = m.group(1)
        title = m.group(2).strip()
        # Find severity
        sev_m = re.search(rf'### W{wnum}:.*?\n.*?\*\*Severity:\*\*\s*(P\d)', text[m.start():], re.DOTALL)
        severity = sev_m.group(1) if sev_m else "?"
        result["weaknesses"].append({"id": f"W{wnum}", "title": title, "severity": severity})

    # Extract improvements (### I1: Title lines)
    for m in re.finditer(r'### I(\d): (.+)', text):
        inum = m.group(1)
        title = m.group(2).strip()
        # Find status
        stat_m = re.search(rf'### I{inum}:.*?\*\*Status:\*\*\s*(.+?)$', text[m.start():], re.DOTALL | re.MULTILINE)
        status = stat_m.group(1).strip() if stat_m else "unknown"
        # Find ticket
        tick_m = re.search(rf'### I{inum}:.*?\*\*Ticket:\*\*\s*(.+?)$', text[m.start():], re.DOTALL | re.MULTILINE)
        ticket = tick_m.group(1).strip() if tick_m else ""
        result["improvements"].append({"id": f"I{inum}", "title": title, "status": status, "ticket": ticket})

    # Extract goals (numbered list after ## Goals)
    goals_m = re.search(r'## Goals.*?\n((?:\d+\..+\n?)+)', text)
    if goals_m:
        for line in goals_m.group(1).strip().splitlines():
            g = re.sub(r'^\d+\.\s*', '', line).strip()
            if g:
                result["goals"].append(g[:120])

    return result

def read_improvement_tickets(agent_name):
    """Read improvement tickets for an agent from the ticket ledger."""
    ledger = os.path.join(root, "kai", "tickets", "tickets.jsonl")
    tickets = []
    if not os.path.exists(ledger):
        return tickets
    with open(ledger) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                t = json.loads(line)
                if t.get("owner") == agent_name and t.get("ticket_type") == "improvement":
                    tickets.append(t)
            except:
                pass
    return tickets

def read_file_head(path, max_chars=3000):
    """Read first N chars of a file, return empty string if missing."""
    try:
        with open(path) as f:
            return f.read(max_chars)
    except:
        return ""

def read_file_lines(path, max_lines=50):
    """Read first N lines, return list."""
    try:
        with open(path) as f:
            return [l.rstrip() for _, l in zip(range(max_lines), f)]
    except:
        return []

def find_latest_file(directory, pattern, max_age_days=2):
    """Find the most recent file matching pattern in directory."""
    matches = sorted(glob.glob(os.path.join(directory, pattern)), reverse=True)
    return matches[0] if matches else None

def parse_sentinel(text):
    """Extract structured data from sentinel report markdown."""
    result = {"passed": 0, "failed": 0, "new_issues": [], "recurring": [], "escalations": [], "resolved": []}
    for line in text.splitlines():
        m = re.match(r'\*\*This run:\*\*\s*(\d+)\s*passed,\s*(\d+)\s*failed', line)
        if m:
            result["passed"] = int(m.group(1))
            result["failed"] = int(m.group(2))
        if line.startswith("- **P") and "##" not in line:
            # Extract priority and description
            pm = re.match(r'- \*\*P(\d)\*\*\s*`([^`]+)`\s*—\s*(.*)', line)
            if pm:
                entry = {"priority": int(pm.group(1)), "check": pm.group(2), "detail": pm.group(3).rstrip()}
                # Determine section by context (crude but effective)
                if "day " in entry["detail"] or "failing" in entry["detail"]:
                    result["recurring"].append(entry)
                else:
                    result["new_issues"].append(entry)
        if line.startswith("- **P") and "escalated" in line.lower():
            result["escalations"].append(line.strip("- ").strip())
        if line.startswith("- `") and "##" not in line and "Resolved" in text[:text.find(line)] if line in text else False:
            result["resolved"].append(line.strip("- ").strip())
    return result

def parse_cipher(text):
    """Extract structured data from cipher log."""
    result = {"ran": False, "clean": False, "findings": 0, "layers_run": [], "layers_skipped": []}
    for line in text.splitlines():
        if "cipher" in line.lower() and ("run" in line.lower() or "scheduled" in line.lower()):
            result["ran"] = True
        if "RESULT: CLEAN" in line:
            result["clean"] = True
        if "skipped" in line.lower():
            m = re.search(r'Layer \d+: (\w+)', line)
            if m:
                result["layers_skipped"].append(m.group(1))
        elif "Layer" in line and "✓" in line:
            m = re.search(r'Layer \d+: (.+?)—', line)
            if m:
                result["layers_run"].append(m.group(1).strip())
        fm = re.search(r'(\d+) findings', line)
        if fm:
            result["findings"] = int(fm.group(1))
    return result

def parse_research(text):
    """Extract structured data from research findings markdown."""
    result = {"sources_checked": 0, "successful": 0, "failed_sources": [],
              "successful_sources": [], "follow_ups": [], "has_analysis": False}
    for line in text.splitlines():
        m = re.match(r'\*\*Sources checked:\*\*\s*(\d+)', line)
        if m: result["sources_checked"] = int(m.group(1))
        m = re.match(r'\*\*Successful:\*\*\s*(\d+)', line)
        if m: result["successful"] = int(m.group(1))
        if "— FAILED" in line:
            src = line.replace("###", "").replace("— FAILED", "").strip()
            result["failed_sources"].append(src)
        elif line.startswith("### ") and "FAILED" not in line and "Follow" not in line and "Analysis" not in line:
            result["successful_sources"].append(line.replace("###", "").strip())
        if "open" in line.lower() and line.strip().startswith("- ["):
            result["follow_ups"].append(line.strip("- ").strip()[:100])
    if "## My Analysis" in text:
        analysis_section = text.split("## My Analysis")[1][:500]
        if "no direct matches" not in analysis_section.lower():
            result["has_analysis"] = True
    return result

def parse_aether_metrics(path):
    """Read aether trading metrics."""
    try:
        with open(path) as f:
            d = json.load(f)
        cw = d.get("currentWeek", d.get("currentPeriod", {}))
        return {
            "balance": cw.get("currentBalance", "?"),
            "trades": cw.get("totalTrades", "?"),
            "winRate": cw.get("winRate", "?"),
            "pnl": cw.get("pnl", "?"),
            "strategies": len(cw.get("strategies", [])),
            "dailyPnl": cw.get("dailyPnl", [])
        }
    except:
        return None

def parse_self_review(text):
    """Extract key findings from agent self-review."""
    issues = []
    for line in text.splitlines():
        if line.strip().startswith("- ✗"):
            issues.append(line.strip("- ✗ ").strip()[:100])
    return issues[:5]

def parse_simulation(text):
    """Extract simulation results."""
    result = {"has_plan": False, "agents_covered": []}
    for line in text.splitlines():
        if line.startswith("### "):
            agent = line.replace("###", "").strip()
            if agent:
                result["agents_covered"].append(agent)
                result["has_plan"] = True
    return result

# ══════════════════════════════════════════════════════════════════════════════
# GATHER ALL AGENT DATA
# ══════════════════════════════════════════════════════════════════════════════

# --- Healthcheck ---
hc = {"status": "unknown", "issues": 0, "warnings": 0}
hc_path = os.path.join(root, "kai", "queue", "healthcheck-latest.json")
try:
    with open(hc_path) as f:
        hc = json.load(f)
except: pass

# --- Simulation outcomes ---
sim = {"passed": 0, "failed": 0}
sim_path = os.path.join(root, "kai", "ledger", "simulation-outcomes.jsonl")
try:
    with open(sim_path) as f:
        lines = [l.strip() for l in f if l.strip()]
        if lines:
            sim = json.loads(lines[-1])
except: pass

# --- Known issues ---
ki_count = 0
ki_path = os.path.join(root, "kai", "ledger", "known-issues.jsonl")
try:
    with open(ki_path) as f:
        ki_count = sum(1 for l in f if '"status":"active"' in l or '"status": "active"' in l)
except: pass

# --- Nel: sentinel + cipher + research ---
nel_sentinel_path = find_latest_file(
    os.path.join(root, "agents", "nel", "logs"), f"sentinel-{today}.md")
if not nel_sentinel_path:
    nel_sentinel_path = find_latest_file(
        os.path.join(root, "agents", "nel", "logs"), f"sentinel-{yesterday}.md")
nel_sentinel = parse_sentinel(read_file_head(nel_sentinel_path)) if nel_sentinel_path else None

nel_cipher_path = find_latest_file(
    os.path.join(root, "agents", "nel", "logs"), f"cipher-{today}*.log")
if not nel_cipher_path:
    nel_cipher_path = find_latest_file(
        os.path.join(root, "agents", "nel", "logs"), f"cipher-{yesterday}*.log")
nel_cipher = parse_cipher(read_file_head(nel_cipher_path)) if nel_cipher_path else None

nel_research_path = find_latest_file(
    os.path.join(root, "agents", "nel", "research"), f"findings-{today}.md")
nel_research = parse_research(read_file_head(nel_research_path)) if nel_research_path else None

# --- Ra: newsletter output + research ---
ra_newsletter_exists = False
ra_newsletter_file = None
for pattern in [f"*{today}*", f"*{yesterday}*"]:
    matches = glob.glob(os.path.join(root, "agents", "ra", "output", pattern))
    if matches:
        ra_newsletter_exists = True
        ra_newsletter_file = os.path.basename(matches[0])
        break

ra_research_path = find_latest_file(
    os.path.join(root, "agents", "ra", "research"), f"findings-{today}.md")
ra_research = parse_research(read_file_head(ra_research_path)) if ra_research_path else None

# --- Sam: logs + research ---
sam_research_path = find_latest_file(
    os.path.join(root, "agents", "sam", "research"), f"findings-{today}.md")
sam_research = parse_research(read_file_head(sam_research_path)) if sam_research_path else None

# --- Aether: trading metrics + analysis + self-review + research ---
aether_metrics = parse_aether_metrics(
    os.path.join(root, "website", "data", "aether-metrics.json"))

aether_analysis_path = find_latest_file(
    os.path.join(root, "agents", "aether", "analysis"), f"Analysis_{today}.txt")
aether_analysis_preview = read_file_head(aether_analysis_path, 500) if aether_analysis_path else ""

aether_review_path = find_latest_file(
    os.path.join(root, "agents", "aether", "logs"), f"self-review-{today}.md")
aether_self_review = parse_self_review(read_file_head(aether_review_path)) if aether_review_path else []

aether_research_path = find_latest_file(
    os.path.join(root, "agents", "aether", "research"), f"findings-{today}.md")
aether_research = parse_research(read_file_head(aether_research_path)) if aether_research_path else None

# --- Dex: research + integrity ---
dex_research_path = find_latest_file(
    os.path.join(root, "agents", "dex", "research"), f"findings-{today}.md")
dex_research = parse_research(read_file_head(dex_research_path)) if dex_research_path else None

# --- Simulation report ---
sim_report_path = find_latest_file(
    os.path.join(root, "agents", "nel", "logs"), f"simulation-{today}.md")
sim_report = parse_simulation(read_file_head(sim_report_path)) if sim_report_path else None

# --- Agent Growth Plans ---
agent_growth = {}
agent_imp_tickets = {}
for agent_name in ["nel", "ra", "sam", "aether", "dex"]:
    agent_growth[agent_name] = parse_growth(agent_name)
    agent_imp_tickets[agent_name] = read_improvement_tickets(agent_name)

# ══════════════════════════════════════════════════════════════════════════════
# BUILD THE INTERNAL REPORT (for Kai — technical, structured)
# ══════════════════════════════════════════════════════════════════════════════

internal = {
    "date": today,
    "generatedAt": now_mt,
    "generatedBy": "bin/generate-morning-report.sh v2",
    "systemHealth": {
        "healthcheck": {
            "status": hc.get("status", "?"),
            "issues": hc.get("issues", 0),
            "warnings": hc.get("warnings", 0)
        },
        "simulation": {
            "passed": sim.get("passed", 0),
            "failed": sim.get("failed", 0)
        },
        "knownIssues": ki_count
    },
    "trading": aether_metrics or {},
    "agents": {
        "nel": {
            "sentinel": nel_sentinel,
            "cipher": nel_cipher,
            "research": {
                "sources_checked": nel_research["sources_checked"] if nel_research else 0,
                "successful": nel_research["successful"] if nel_research else 0,
                "failed": nel_research["failed_sources"] if nel_research else [],
                "follow_ups": nel_research["follow_ups"] if nel_research else []
            }
        },
        "ra": {
            "newsletter_produced": ra_newsletter_exists,
            "research": {
                "sources_checked": ra_research["sources_checked"] if ra_research else 0,
                "successful": ra_research["successful"] if ra_research else 0,
                "successful_sources": ra_research["successful_sources"] if ra_research else []
            }
        },
        "sam": {
            "research": {
                "sources_checked": sam_research["sources_checked"] if sam_research else 0,
                "successful": sam_research["successful"] if sam_research else 0
            }
        },
        "aether": {
            "analysis_exists": bool(aether_analysis_path),
            "self_review_issues": aether_self_review,
            "research": {
                "sources_checked": aether_research["sources_checked"] if aether_research else 0,
                "successful": aether_research["successful"] if aether_research else 0,
                "follow_ups": aether_research["follow_ups"] if aether_research else []
            }
        },
        "dex": {
            "research": {
                "sources_checked": dex_research["sources_checked"] if dex_research else 0,
                "successful": dex_research["successful"] if dex_research else 0,
                "follow_ups": dex_research["follow_ups"] if dex_research else []
            }
        }
    }
}

with open(internal_path, "w") as f:
    json.dump(internal, f, indent=2)
print(f"Internal report written: {internal_path}")

# ══════════════════════════════════════════════════════════════════════════════
# BUILD THE EXTERNAL REPORT (for Hyo — human-readable narrative)
# GROWTH-FIRST: Lead with what each agent is improving, what they're building,
# what weaknesses they identified. Operational status is secondary context.
# ══════════════════════════════════════════════════════════════════════════════

def build_agent_narrative(agent_name, growth, imp_tickets, ops_context):
    """Build a growth-first narrative for an agent.

    Structure:
    1. GROWTH: What weaknesses are being addressed? What improvements are in progress?
    2. GOALS: What has the agent set for itself?
    3. EXECUTION: What did the agent actually build/change? (not just 'researched')
    4. BLOCKED: If something didn't execute, why? What's the fix?
    5. CONTEXT: Brief operational status (secondary)
    """
    parts = []

    # --- GROWTH: Weaknesses + Improvements ---
    if growth:
        # Show what weaknesses are being worked on
        active_imps = [i for i in growth.get("improvements", []) if i.get("status") not in ("planned", "unknown", "")]
        planned_imps = [i for i in growth.get("improvements", []) if i.get("status") in ("planned", "unknown", "")]

        if active_imps:
            for imp in active_imps:
                parts.append(f"Building: {imp['title']} (status: {imp['status']}).")
        else:
            # Show what weaknesses were identified and what the plan is
            weaknesses = growth.get("weaknesses", [])
            if weaknesses:
                for w in weaknesses:
                    parts.append(f"Weakness {w['id']} ({w['severity']}): {w['title'][:120]}.")
            if planned_imps:
                for imp in planned_imps[:2]:
                    parts.append(f"Planned fix: {imp['title'][:120]}.")
                parts.append(f"Status: researching, not yet building. Next step: start executing {planned_imps[0]['id']}.")

        # Show goals
        goals = growth.get("goals", [])
        if goals:
            parts.append(f"Current goal: {goals[0][:100]}.")
    else:
        parts.append("No growth plan yet — needs GROWTH.md with identified weaknesses and improvement proposals.")

    # --- IMPROVEMENT TICKETS ---
    if imp_tickets:
        open_count = sum(1 for t in imp_tickets if t.get("status") in ("OPEN", "ACTIVE"))
        in_progress = [t for t in imp_tickets if t.get("status") == "ACTIVE"]
        if in_progress:
            for t in in_progress[:2]:
                parts.append(f"In progress: {t['title'][:80]} ({t['id']}).")
        elif open_count > 0:
            # Tickets exist but none are being worked — flag it
            parts.append(f"{open_count} improvement ticket(s) open but none in progress. Next step: pick one and start building.")

    # --- OPERATIONAL CONTEXT (secondary) ---
    if ops_context:
        parts.append(ops_context)

    return " ".join(parts)

# --- Build operational context per agent (brief, not the main story) ---

# Nel ops context
nel_ops = ""
if nel_sentinel:
    p, f_ = nel_sentinel["passed"], nel_sentinel["failed"]
    nel_ops = f"Ops: sentinel {p}/{p+f_} passing."
    if nel_sentinel["recurring"]:
        worst = nel_sentinel["recurring"][0]
        day_m = re.search(r'day\s+(\d+)', worst['detail'])
        day_count = day_m.group(1) if day_m else "multiple"
        nel_ops += f" {worst['check']} failing {day_count} runs straight."
    if nel_cipher and nel_cipher.get("clean"):
        nel_ops += " Cipher: clean."
    if nel_research and nel_research["failed_sources"]:
        nel_ops += f" Research: {nel_research['successful']}/{nel_research['sources_checked']} sources reachable."
nel_narrative = build_agent_narrative("nel", agent_growth.get("nel"), agent_imp_tickets.get("nel", []), nel_ops)

# Ra ops context
ra_ops = f"Ops: newsletter {'shipped' if ra_newsletter_exists else 'NOT produced (sandbox blocks sources)'}."
if ra_research:
    ra_ops += f" Research: {ra_research['successful']}/{ra_research['sources_checked']} sources."
ra_narrative = build_agent_narrative("ra", agent_growth.get("ra"), agent_imp_tickets.get("ra", []), ra_ops)

# Sam ops context
sam_log_path = os.path.join(root, "agents", "sam", "logs")
sam_logs = sorted(glob.glob(os.path.join(sam_log_path, f"*{today}*")), reverse=True) if os.path.isdir(sam_log_path) else []
sam_ops = f"Ops: {'active' if sam_logs else 'no activity today — needs scheduled trigger'}."
sam_narrative = build_agent_narrative("sam", agent_growth.get("sam"), agent_imp_tickets.get("sam", []), sam_ops)

# Aether ops context
aether_ops = ""
if aether_metrics:
    bal = aether_metrics.get("balance", "?")
    wr = aether_metrics.get("winRate", "?")
    pnl = aether_metrics.get("pnl", "?")
    aether_ops = f"Ops: ${bal} balance, {wr}% WR, ${pnl} net P&L."
if aether_analysis_path:
    gpt_status = "GPT verified" if "GPT_VERIFIED: YES" in aether_analysis_preview else "GPT pending"
    aether_ops += f" Analysis written ({gpt_status})."
aether_narrative = build_agent_narrative("aether", agent_growth.get("aether"), agent_imp_tickets.get("aether", []), aether_ops)

# Dex ops context
dex_ops = ""
dex_evo_path = os.path.join(root, "agents", "dex", "evolution.jsonl")
try:
    with open(dex_evo_path) as f:
        lines = [l.strip() for l in f if l.strip()]
        if lines:
            last_evo = json.loads(lines[-1])
            assess = last_evo.get("assessment", "")
            if assess:
                dex_ops = f"Ops: {assess[:80]}."
except: pass
if not dex_ops:
    dex_ops = "Ops: no activity logged today."
dex_narrative = build_agent_narrative("dex", agent_growth.get("dex"), agent_imp_tickets.get("dex", []), dex_ops)

# --- Build executive summary from actual findings ---
summary_parts = []

# What's working
working = []
blocked = []

if ra_newsletter_exists:
    working.append("newsletter shipped")
if nel_sentinel and nel_sentinel["passed"] > 0:
    working.append(f"sentinel {nel_sentinel['passed']}/{nel_sentinel['passed'] + nel_sentinel['failed']} checks passing")
if nel_cipher and nel_cipher["clean"]:
    working.append("no secret leaks")
if aether_metrics and aether_metrics.get("balance") and aether_metrics["balance"] != "?":
    working.append(f"AetherBot at ${aether_metrics['balance']}")

# What's blocked and WHY
if not ra_newsletter_exists:
    blocked.append("newsletter blocked — sandbox can't reach external sources, needs Mini migration")
if nel_sentinel and nel_sentinel["failed"] > 0:
    recurring = nel_sentinel.get("recurring", [])
    if recurring:
        worst = recurring[0]
        day_m = re.search(r'day\s+(\d+)', worst['detail'])
        day_count = day_m.group(1) if day_m else "multiple"
        blocked.append(f"{worst['check']} failing {day_count} straight runs — needs root-cause fix on Mini")
sim_fails = sim.get("failed", 0)
if sim_fails > 0:
    blocked.append(f"simulation has {sim_fails} failures — regression investigation needed")

if working:
    summary_parts.append(f"Working: {', '.join(working)}.")
if blocked:
    summary_parts.append(f"Blocked: {'; '.join(blocked)}.")
if not blocked:
    summary_parts.append("Nothing actively blocked.")

exec_summary = " ".join(summary_parts)

# --- What went well / needs attention (with specifics, not templates) ---
went_well = []
needs_attention = []

if ra_newsletter_exists:
    went_well.append("Newsletter produced and delivered on schedule.")
if nel_sentinel and nel_sentinel["passed"] >= nel_sentinel["failed"]:
    went_well.append(f"Sentinel passed {nel_sentinel['passed']} of {nel_sentinel['passed'] + nel_sentinel['failed']} checks.")
if nel_cipher and nel_cipher["clean"]:
    went_well.append("Cipher security scan: clean, zero findings.")
if aether_analysis_path:
    went_well.append("Aether daily analysis produced.")

# Research activity (specific, not "actively growing")
research_active = []
for name, res in [("Nel", nel_research), ("Ra", ra_research), ("Aether", aether_research), ("Dex", dex_research)]:
    if res and res["successful"] > 0:
        research_active.append(f"{name} ({res['successful']} sources)")
if research_active:
    went_well.append(f"Research active: {', '.join(research_active)}.")

if not ra_newsletter_exists:
    needs_attention.append("No newsletter today — Ra's pipeline is blocked on sandbox network restrictions. Move to Mini launchd.")
if nel_sentinel and nel_sentinel["failed"] > 0:
    for iss in nel_sentinel.get("new_issues", [])[:2]:
        needs_attention.append(f"New sentinel issue (P{iss['priority']}): {iss['check']} — {iss['detail'][:80]}.")
    for iss in nel_sentinel.get("recurring", [])[:2]:
        needs_attention.append(f"Persistent failure: {iss['check']} — {iss['detail'][:80]}. Needs root-cause fix.")
if sim_fails > 0:
    needs_attention.append(f"Simulation: {sim.get('passed', 0)} pass / {sim_fails} fail. Investigate what regressed.")
if ki_count > 10:
    needs_attention.append(f"{ki_count} known issues accumulating — schedule a cleanup sprint.")

agent_highlights = {
    "nel": nel_narrative,
    "ra": ra_narrative,
    "sam": sam_narrative,
    "aether": aether_narrative,
    "dex": dex_narrative
}

# ── Feed entry ──
morning_entry = {
    "id": f"mr-{today}",
    "type": "morning-report",
    "title": "Morning Report",
    "author": "Kai",
    "authorIcon": "\U0001F454",
    "authorColor": "#d4a853",
    "timestamp": now_mt,
    "date": today,
    "sections": {
        "summary": exec_summary,
        "wentWell": went_well,
        "needsAttention": needs_attention,
        "agentHighlights": agent_highlights
    }
}

# Read existing feed.json, replace today's morning report
feed = {"lastUpdated": now_mt, "today": today, "agents": {}, "reports": [], "history": {}}
if os.path.exists(feed_path):
    try:
        with open(feed_path) as f:
            feed = json.load(f)
    except: pass

feed["lastUpdated"] = now_mt
feed["today"] = today
feed["reports"] = [r for r in feed.get("reports", []) if r.get("id") != morning_entry["id"]]
feed["reports"].append(morning_entry)
feed["reports"].sort(key=lambda r: r.get("timestamp", ""), reverse=True)

if month_key not in feed.get("history", {}):
    months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    m_idx = int(month_key.split("-")[1]) - 1
    label = f"{months[m_idx]} {month_key.split('-')[0]}"
    feed["history"][month_key] = {"label": label, "reports": []}

month_hist = feed["history"][month_key]
if morning_entry["id"] not in month_hist["reports"]:
    month_hist["reports"].append(morning_entry["id"])

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)
print(f"Feed entry written: {feed_path}")

PYEOF

if [[ $? -ne 0 ]]; then
  log "ERROR: Failed to generate reports"
  exit 1
fi

# ── Copy to sam/website mirror if needed ──
SAM_MIRROR_INTERNAL="$ROOT/agents/sam/website/data/morning-report.json"
SAM_MIRROR_FEED="$ROOT/agents/sam/website/data/feed.json"
if [[ -d "$(dirname "$SAM_MIRROR_INTERNAL")" ]]; then
  if [[ ! "$INTERNAL_OUTPUT" -ef "$SAM_MIRROR_INTERNAL" ]] 2>/dev/null; then
    cp "$INTERNAL_OUTPUT" "$SAM_MIRROR_INTERNAL" 2>/dev/null || true
  fi
  if [[ ! "$FEED_OUTPUT" -ef "$SAM_MIRROR_FEED" ]] 2>/dev/null; then
    cp "$FEED_OUTPUT" "$SAM_MIRROR_FEED" 2>/dev/null || true
  fi
  log "Mirrors synced"
fi

# ── Commit and push ──
cd "$ROOT" || exit 1
CHANGED=$(git diff --name-only "$INTERNAL_OUTPUT" "$FEED_OUTPUT" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$CHANGED" -gt 0 ]]; then
  git add "$INTERNAL_OUTPUT" "$FEED_OUTPUT" 2>/dev/null
  git add "$SAM_MIRROR_INTERNAL" "$SAM_MIRROR_FEED" 2>/dev/null
  git commit -m "morning-report: $TODAY (v2 — real agent outputs)" 2>/dev/null
  git push origin main 2>/dev/null && log "Pushed to origin" || log "Push failed (will retry next cycle)"
else
  log "No changes to commit"
fi

log "Done — v2 morning report generated"
