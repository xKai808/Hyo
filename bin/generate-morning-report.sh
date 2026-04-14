#!/usr/bin/env bash
# bin/generate-morning-report.sh — Two-version morning report generator
#
# Produces TWO outputs:
#   1. INTERNAL: website/data/morning-report.json — technical, for Kai to parse
#   2. FEED: appends to website/data/feed.json — human-readable, for Hyo's HQ feed
#
# Called by:
#   - com.hyo.morning-report launchd plist (05:00 MT daily)
#   - healthcheck.sh auto-remediation (when morning report is stale)
#   - nel-qa-cycle.sh Phase 7.5 auto-remediation
#   - dispatch.sh simulation Phase 6 auto-remediation
#
# After generating, commits and pushes so Vercel picks it up.
#
# Usage: bash bin/generate-morning-report.sh
#        HYO_ROOT=/path/to/Hyo bash bin/generate-morning-report.sh

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
INTERNAL_OUTPUT="$ROOT/website/data/morning-report.json"
FEED_OUTPUT="$ROOT/website/data/feed.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
MONTH_KEY=$(echo "$TODAY" | cut -c1-7)
LOG_TAG="[morning-report]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

log "Generating morning report for $TODAY"

# ── Sync agent profiles from PLAYBOOKs before generating report ──
SYNC_SCRIPT="$ROOT/bin/sync-agent-profiles.sh"
if [[ -x "$SYNC_SCRIPT" ]]; then
  bash "$SYNC_SCRIPT" 2>&1 | tail -2
  log "Agent profiles synced from PLAYBOOKs"
fi

# ── Gather data ──

# Simulation
SIM_SUMMARY="No simulation data"
SIM_FILE="$ROOT/kai/ledger/simulation-outcomes.jsonl"
if [[ -f "$SIM_FILE" ]]; then
  LAST_SIM=$(tail -1 "$SIM_FILE" 2>/dev/null)
  if [[ -n "$LAST_SIM" ]]; then
    SIM_SUMMARY=$(python3 -c "
import json, sys
s = json.loads(sys.stdin.read())
print(f\"{s.get('passed',0)} pass / {s.get('failed',0)} fail\")
" <<< "$LAST_SIM" 2>/dev/null || echo "Parse error")
  fi
fi

# Healthcheck
HC_SUMMARY="No healthcheck data"
HC_FILE="$ROOT/kai/queue/healthcheck-latest.json"
if [[ -f "$HC_FILE" ]]; then
  HC_SUMMARY=$(python3 -c "
import json
with open('$HC_FILE') as f:
  h = json.load(f)
print(f\"{h.get('status','?')}: {h.get('issues',0)} issues, {h.get('warnings',0)} warnings\")
" 2>/dev/null || echo "Parse error")
fi

# Aether trading
AETHER_SUMMARY="No trading data"
AETHER_JSON="$ROOT/website/data/aether-metrics.json"
if [[ -f "$AETHER_JSON" ]]; then
  AETHER_SUMMARY=$(python3 -c "
import json
with open('$AETHER_JSON') as f:
  d = json.load(f)
cw = d.get('currentWeek', d.get('currentPeriod', {}))
bal = cw.get('currentBalance', '?')
trades = cw.get('totalTrades', '?')
wr = cw.get('winRate', '?')
strats = len(cw.get('strategies', []))
print(f'Balance: \${bal}, Trades: {trades}, Win rate: {wr}, Strategies: {strats}')
" 2>/dev/null || echo "Parse error")
fi

# Known issues
KNOWN_ISSUES_COUNT=0
KI_FILE="$ROOT/kai/ledger/known-issues.jsonl"
if [[ -f "$KI_FILE" ]]; then
  KNOWN_ISSUES_COUNT=$(grep -c '"status":"active"' "$KI_FILE" 2>/dev/null || echo "0")
fi

# Newsletter
NEWSLETTER_STATUS="not produced"
for nl in "$ROOT/agents/ra/output/"*"$TODAY"*; do
  if [[ -f "$nl" ]]; then
    NEWSLETTER_STATUS="produced"
    break
  fi
done

# ── Generate both reports via Python ──

python3 - "$INTERNAL_OUTPUT" "$FEED_OUTPUT" "$TODAY" "$NOW_MT" "$MONTH_KEY" \
          "$SIM_SUMMARY" "$HC_SUMMARY" "$AETHER_SUMMARY" \
          "$KNOWN_ISSUES_COUNT" "$NEWSLETTER_STATUS" "$ROOT" <<'PYEOF'
import json, sys, os

internal_path = sys.argv[1]
feed_path     = sys.argv[2]
today         = sys.argv[3]
now_mt        = sys.argv[4]
month_key     = sys.argv[5]
sim_summary   = sys.argv[6]
hc_summary    = sys.argv[7]
aether_summary= sys.argv[8]
known_issues  = int(sys.argv[9])
newsletter_st = sys.argv[10]
root          = sys.argv[11]

# ── Helpers ──

def read_evolution(agent):
    """Read latest evolution entry for an agent."""
    evo = os.path.join(root, "agents", agent, "evolution.jsonl")
    if not os.path.exists(evo):
        return None
    last = None
    with open(evo) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: last = json.loads(line)
            except: pass
    return last

def read_active(agent):
    """Read ACTIVE.md for an agent."""
    path = os.path.join(root, "agents", agent, "ledger", "ACTIVE.md")
    if not os.path.exists(path):
        return {"tasks": 0, "lines": []}
    tasks = 0
    lines = []
    with open(path) as f:
        for line in f:
            if line.startswith("- "):
                tasks += 1
                lines.append(line.strip("- \n")[:80])
    return {"tasks": tasks, "lines": lines[:5]}

def read_agent_profile(agent):
    """Read agent profile from feed.json if it exists."""
    if os.path.exists(feed_path):
        try:
            with open(feed_path) as f:
                fd = json.load(f)
            return fd.get("agents", {}).get(agent, {})
        except:
            pass
    return {}

# ── Build agent data ──

AGENTS = ["nel", "sam", "ra", "aether", "dex"]
agent_data = {}
for a in AGENTS:
    evo = read_evolution(a)
    active = read_active(a)
    agent_data[a] = {
        "evolution": evo,
        "active": active,
        "score": evo.get("metrics", {}).get("improvement_score", "?") if evo else "?",
        "assessment": evo.get("assessment", "")[:100] if evo else "",
        "reflection": evo.get("reflection", {}) if evo else {}
    }

# ── Determine what went well / needs attention ──

went_well = []
needs_attention = []

if "HEALTHY" in hc_summary:
    went_well.append("System healthcheck is clean — all infrastructure checks passing")
else:
    needs_attention.append(f"Healthcheck flagged some issues ({hc_summary}) — most are persistent from previous cycles and need root-cause fixes")

if "0 fail" in sim_summary:
    went_well.append("All simulation tests passed — the delegation lifecycle is working end-to-end")
else:
    needs_attention.append(f"Simulation caught failures ({sim_summary}) — something regressed and needs investigation before it spreads")

if newsletter_st == "produced":
    went_well.append("Newsletter went out on schedule — the content pipeline is reliable")
else:
    needs_attention.append("No newsletter today — Ra's pipeline can't reach external sources from the sandbox. Needs to move to the Mini.")

if known_issues > 10:
    needs_attention.append(f"{known_issues} known issues are piling up — we're accumulating faster than we're resolving. Time for a cleanup sprint.")

# Check each agent for notable items
for a in AGENTS:
    d = agent_data[a]
    refl = d.get("reflection", {})
    bn = refl.get("bottleneck", "none")
    if bn and bn != "none":
        needs_attention.append(f"{a.capitalize()} is blocked: {bn[:80]}")
    growth = refl.get("domain_growth", "")
    if "active" in str(growth).lower():
        went_well.append(f"{a.capitalize()} is actively growing — researching its domain and proposing improvements")

# ═══ VERSION 1: INTERNAL REPORT (for Kai) ═══
# This is technical, metric-heavy, for Kai to parse and critique

internal = {
    "date": today,
    "generatedAt": now_mt,
    "generatedBy": "bin/generate-morning-report.sh",
    "executiveSummary": f"Morning report for {today}. Simulation: {sim_summary}. Health: {hc_summary}. Trading: {aether_summary}.",
    "agentReports": [],
    "kaiReport": {
        "simulation": sim_summary,
        "healthcheck": hc_summary,
        "knownIssues": known_issues,
        "newsletter": newsletter_st
    },
    "systemHealth": {
        "queueWorker": "check healthcheck-latest.json",
        "simulation": sim_summary,
        "healthcheck": hc_summary
    },
    "trading": {"summary": aether_summary},
    "wentWell": went_well,
    "needsAttention": needs_attention,
    "improvements": [
        "Review and close stale known issues",
        "Check agent evolution scores for regressions"
    ]
}

for a in AGENTS:
    d = agent_data[a]
    internal["agentReports"].append({
        "agent": a,
        "activeTasks": d["active"]["tasks"],
        "score": d["score"],
        "assessment": d["assessment"],
        "topTasks": d["active"]["lines"][:3],
        "reflection": d["reflection"]
    })

with open(internal_path, "w") as f:
    json.dump(internal, f, indent=2)
print(f"Internal report written: {internal_path}")

# ═══ VERSION 2: FEED ENTRY (for Hyo) ═══
# This is human-readable, conversational, posted to the HQ feed.
# Written as if Kai is talking to Hyo over coffee.

# ── Build conversational agent highlights ──
agent_highlights = {}
for a in AGENTS:
    d = agent_data[a]
    refl = d.get("reflection", {})
    score = d.get("score", "?")
    assess = d.get("assessment", "")
    bn = refl.get("bottleneck", "none")
    growth = refl.get("domain_growth", "")
    learning = refl.get("learning", "")
    has_data = bool(assess or (score != "?" and score != 0))

    if not has_data:
        agent_highlights[a] = f"Quiet cycle from {a.capitalize()} — no new data came in. Need to check if the runner executed or if there's a scheduling issue."
        continue

    parts = []

    # Lead with what matters, in natural language
    if a == "nel":
        if isinstance(score, (int, float)):
            if score >= 85:
                parts.append(f"Nel's quality score hit {score} this cycle — solid improvement")
            elif score >= 70:
                parts.append(f"Nel is at {score} — functional but not where we want to be")
            else:
                parts.append(f"Nel's score dropped to {score}, which is below target")
        if "fail" in assess.lower():
            parts.append("Same persistent failures that need Mini access to resolve")
        if "active" in str(growth).lower():
            parts.append("Actively researching security patterns and growing domain expertise")

    elif a == "sam":
        if "test" in assess.lower() and "fail" in assess.lower():
            parts.append(f"Sam has test failures to address: {assess[:60]}")
        elif "improved" in assess.lower():
            parts.append(f"Sam's test coverage improved: {assess[:60]}")
        else:
            parts.append("Platform is stable" if "routine" in assess.lower() or not assess else assess[:80])
        if bn and bn != "none":
            parts.append(f"Main blocker: {bn[:60]}")

    elif a == "ra":
        if newsletter_st == "produced":
            parts.append("Newsletter went out on schedule — Ra's pipeline is delivering")
        else:
            parts.append("Ra couldn't produce a newsletter today — the sandbox blocks source fetches")
        if "active" in str(growth).lower():
            parts.append("Working on editorial voice and source diversification in the meantime")

    elif a == "aether":
        if "standby" in assess.lower() or "no trades" in assess.lower():
            parts.append("Aether is in standby — no live trades happening")
            parts.append("Waiting on exchange API keys to move from replay mode to live tracking")
        elif "trade" in assess.lower():
            parts.append(assess[:80])
        if "out-of-sync" in str(bn).lower() or "out-of-sync" in assess.lower():
            parts.append("Dashboard sync issue persists — data exists but HQ can't render it")

    elif a == "dex":
        if assess:
            parts.append(assess[:80])
        else:
            parts.append("Dex ran its integrity sweep")
        if "stagnant" in str(growth).lower():
            parts.append("Needs to start its research loop to stay sharp")

    agent_highlights[a] = ". ".join(parts) + "." if parts else f"No update from {a.capitalize()} this cycle."

# ── Build conversational executive summary ──
# Written like a person summarizing their morning, not a dashboard
summary_parts = []

# Overall vibe
good_count = len(went_well)
bad_count = len(needs_attention)
if good_count > bad_count:
    summary_parts.append("Mostly a good night.")
elif bad_count > good_count:
    summary_parts.append("A few things need attention from overnight.")
else:
    summary_parts.append("Mixed bag overnight.")

# Highlights
if newsletter_st == "produced":
    summary_parts.append("The newsletter went out on schedule.")
if "0 fail" in sim_summary:
    summary_parts.append("All simulations passed.")
elif "fail" in sim_summary:
    summary_parts.append(f"The simulation suite caught some failures ({sim_summary}), which needs investigation.")

if "ISSUES" in hc_summary or "issues" in hc_summary:
    summary_parts.append(f"Healthcheck reported {hc_summary.lower()} — mostly persistent items from previous cycles.")

# Trading context
if "0" in str(aether_summary) and "Trades: 0" in aether_summary or "Trades: ?" in aether_summary:
    summary_parts.append("No trading activity — Aether is in standby until we get live API keys.")
elif aether_summary and aether_summary != "No trading data":
    summary_parts.append(f"Trading: {aether_summary}.")

exec_summary = " ".join(summary_parts)

# The feed entry
morning_entry = {
    "id": f"mr-{today}",
    "type": "morning-report",
    "title": "Morning Report",
    "author": "Kai",
    "authorIcon": "\U0001F454",  # tie emoji
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

# Read existing feed.json, add new entry, deduplicate by id
feed = {"lastUpdated": now_mt, "today": today, "agents": {}, "reports": [], "history": {}}
if os.path.exists(feed_path):
    try:
        with open(feed_path) as f:
            feed = json.load(f)
    except:
        pass

# Update metadata
feed["lastUpdated"] = now_mt
feed["today"] = today

# Remove existing morning report for today (if re-running)
feed["reports"] = [r for r in feed.get("reports", []) if r.get("id") != morning_entry["id"]]

# Add new entry
feed["reports"].append(morning_entry)

# Sort by timestamp descending
feed["reports"].sort(key=lambda r: r.get("timestamp", ""), reverse=True)

# Update history index
if month_key not in feed.get("history", {}):
    months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    m_idx = int(month_key.split("-")[1]) - 1
    label = f"{months[m_idx]} {month_key.split('-')[0]}"
    feed["history"][month_key] = {"label": label, "reports": []}

# Add report id to month history if not already there
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
  # Internal report already written to website/data/ which IS agents/sam/website/data/ via symlink
  # But if they're separate dirs, copy
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
  git commit -m "morning-report: $TODAY (internal + feed)" 2>/dev/null
  git push origin main 2>/dev/null && log "Pushed to origin" || log "Push failed (will retry next cycle)"
else
  log "No changes to commit"
fi

log "Done — internal + feed reports generated"
