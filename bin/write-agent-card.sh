#!/usr/bin/env bash
# bin/write-agent-card.sh — Write agent-card.json for morning report WHAT IMPROVED section
# Version: 1.0 | Created: 2026-05-06
#
# Usage:
#   bash bin/write-agent-card.sh \
#     --agent nel \
#     --metric health_score \
#     --before 65 \
#     --after 71 \
#     --what "Rebuilt check architecture to bypass Mini dependency" \
#     --commit "abc123" \
#     --next-metric health_score \
#     --next-target 75 \
#     --next-how "Add supply chain CVE scan"
#
# Output: agents/{agent}/data/agent-card.json
# Read by: bin/generate-morning-report-v7.sh → WHAT IMPROVED section
#
# PROTOCOL: This replaces HQ narrative reflection publishing.
# Agents write structured deltas here. Morning report reads deltas.
# Hyo sees: "Nel health_score 65 → 71 (+6): rebuilt check architecture"
# Not: 800 words of narrative.

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"

# ── Parse arguments ───────────────────────────────────────────────────────────
AGENT=""
METRIC=""
METRIC_BEFORE=""
METRIC_AFTER=""
WHAT_CHANGED=""
COMMIT=""
NEXT_METRIC=""
NEXT_TARGET=""
NEXT_HOW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)        AGENT="$2";        shift 2 ;;
    --metric)       METRIC="$2";       shift 2 ;;
    --before)       METRIC_BEFORE="$2";shift 2 ;;
    --after)        METRIC_AFTER="$2"; shift 2 ;;
    --what)         WHAT_CHANGED="$2"; shift 2 ;;
    --commit)       COMMIT="$2";       shift 2 ;;
    --next-metric)  NEXT_METRIC="$2";  shift 2 ;;
    --next-target)  NEXT_TARGET="$2";  shift 2 ;;
    --next-how)     NEXT_HOW="$2";     shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Validate required fields ──────────────────────────────────────────────────
if [[ -z "$AGENT" || -z "$METRIC" || -z "$METRIC_AFTER" ]]; then
  echo "ERROR: --agent, --metric, and --after are required" >&2
  exit 1
fi

# ── Default before to previous card's after (or 0 if no prior card) ──────────
DATA_DIR="$HYO_ROOT/agents/$AGENT/data"
CARD_PATH="$DATA_DIR/agent-card.json"
mkdir -p "$DATA_DIR"

if [[ -z "$METRIC_BEFORE" ]]; then
  if [[ -f "$CARD_PATH" ]]; then
    METRIC_BEFORE=$(python3 -c "
import json
try:
    with open('$CARD_PATH') as f:
        card = json.load(f)
    print(card.get('metric_after', 0))
except:
    print(0)
")
  else
    METRIC_BEFORE=0
  fi
fi

# ── Resolve git commit if not provided ───────────────────────────────────────
if [[ -z "$COMMIT" ]]; then
  COMMIT=$(cd "$HYO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
fi

# ── Write agent-card.json ─────────────────────────────────────────────────────
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

python3 - << PYEOF
import json, os

card = {
    "agent": "$AGENT",
    "date": "$TODAY",
    "metric_name": "$METRIC",
    "metric_before": float("$METRIC_BEFORE") if "." in "$METRIC_BEFORE" else int("$METRIC_BEFORE"),
    "metric_after": float("$METRIC_AFTER") if "." in "$METRIC_AFTER" else int("$METRIC_AFTER"),
    "what_changed": "$WHAT_CHANGED" or "Ran scheduled cycle",
    "commit": "$COMMIT",
    "next_target": {
        "metric": "$NEXT_METRIC" or "$METRIC",
        "target": float("$NEXT_TARGET") if "." in "${NEXT_TARGET:-0}" else int("${NEXT_TARGET:-0}"),
        "how": "$NEXT_HOW" or "Continue improving $METRIC"
    }
}

with open("$CARD_PATH", "w") as f:
    json.dump(card, f, indent=2)

delta = card["metric_after"] - card["metric_before"]
sign = "+" if delta >= 0 else ""
print(f"agent-card: {card['agent']} {card['metric_name']} {card['metric_before']} → {card['metric_after']} ({sign}{delta})")
PYEOF

# ── Also write to dual-path (website/) if it differs from agents/ ─────────────
WEBSITE_DATA="$HYO_ROOT/website/data/agent-cards"
AGENTS_DATA="$HYO_ROOT/agents/sam/website/data/agent-cards"
for dir in "$WEBSITE_DATA" "$AGENTS_DATA"; do
  if [[ -d "$(dirname "$dir")" ]]; then
    mkdir -p "$dir"
    cp "$CARD_PATH" "$dir/${AGENT}-card.json" 2>/dev/null || true
  fi
done
