#!/usr/bin/env bash
# bin/kai-daily-report.sh — Kai's own daily CEO report
# Distinct from the morning report (which is a system health overview).
# Kai's daily report covers: decisions made, work delegated, what shipped,
# system changes, and what Kai is tracking going forward.
# Runs at 23:30 MT to cover the full day.

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
HYO_ROOT="$ROOT" bash "$ROOT/bin/daily-agent-report.sh" kai
