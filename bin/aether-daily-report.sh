#!/usr/bin/env bash
# bin/aether-daily-report.sh — Aether's daily agent report
# Runs at 22:30 MT — before the 23:00 analysis.
# Covers: trading session summary, research conducted, issues tracked.
set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
HYO_ROOT="$ROOT" bash "$ROOT/bin/daily-agent-report.sh" aether
