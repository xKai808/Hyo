#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/bin/watch-deploy.sh
#
# File watcher that auto-deploys to Vercel when website/ changes.
# Uses fswatch (macOS) — install: brew install fswatch
# Run once in background: nohup kai watch &
#
# Debounces: waits 5s after last change before deploying,
# so rapid multi-file edits batch into one deploy.

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
WEBSITE="$ROOT/website"
LOGS="$ROOT/kai/logs"
LOCKFILE="/tmp/hyo-deploy.lock"
DEBOUNCE=5

mkdir -p "$LOGS"

log() { printf '[%s] watch-deploy: %s\n' "$(date +%H:%M:%S)" "$*"; }

if ! command -v fswatch >/dev/null 2>&1; then
  echo "fswatch not installed. Run: brew install fswatch"
  exit 1
fi

log "watching $WEBSITE for changes..."

fswatch -r -l "$DEBOUNCE" \
  --exclude '.git' --exclude 'node_modules' --exclude '.vercel' \
  "$WEBSITE" | while read -r _; do

  # drain any queued events from the debounce window
  while read -r -t 1 _; do :; done

  # skip if a deploy is already running
  if [[ -f "$LOCKFILE" ]]; then
    log "deploy already in progress, skipping"
    continue
  fi

  touch "$LOCKFILE"
  log "changes detected — deploying..."

  LOGF="$LOGS/autodeploy-$(date -u +%Y%m%dT%H%M%SZ).log"
  if "$ROOT/bin/kai.sh" deploy > "$LOGF" 2>&1; then
    log "deploy succeeded — see $LOGF"
  else
    log "deploy FAILED — see $LOGF"
  fi

  rm -f "$LOCKFILE"
done
