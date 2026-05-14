#!/usr/bin/env bash
echo "*** AETHERBOT KILL-SWITCH 2026-05-13 (Hyo): aether-daily-report refused. AetherBot pipeline halted. Remove this block only with explicit approval. ***" >&2
exit 1
# bin/aether-daily-report.sh — Aether's daily agent report
# Runs at 22:30 MT — before the 23:00 analysis.
# Covers: trading session summary, research conducted, issues tracked.
set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
HYO_ROOT="$ROOT" bash "$ROOT/bin/daily-agent-report.sh" aether
