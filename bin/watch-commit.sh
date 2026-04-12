#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/bin/watch-commit.sh
#
# Watches the website/ folder for changes, auto-commits and pushes to GitHub.
# Vercel's GitHub integration handles the deploy automatically.
#
# Requires: brew install fswatch
# Run once: nohup kai gitwatch &
#
# Debounces 10s so rapid edits (e.g. Kai editing from Cowork) batch into one commit.

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
WEBSITE="$ROOT/website"
LOGS="$ROOT/kai/logs"
LOCKFILE="/tmp/hyo-gitwatch.lock"
DEBOUNCE=10

mkdir -p "$LOGS"

log() { printf '[%s] gitwatch: %s\n' "$(date +%H:%M:%S)" "$*"; }

if ! command -v fswatch >/dev/null 2>&1; then
  echo "fswatch not installed. Run: brew install fswatch"
  exit 1
fi

if ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  echo "No git remote 'origin' configured. Set up GitHub first."
  exit 1
fi

log "watching $WEBSITE for changes → auto-commit + push"

fswatch -r -l "$DEBOUNCE" \
  --exclude '.git' --exclude 'node_modules' --exclude '.vercel' \
  "$WEBSITE" | while read -r _; do

  # drain queued events
  while read -r -t 1 _; do :; done

  # skip if already running
  if [[ -f "$LOCKFILE" ]]; then
    log "commit already in progress, skipping"
    continue
  fi

  touch "$LOCKFILE"

  # check if there are actual changes
  if git -C "$ROOT" diff --quiet HEAD -- website/ 2>/dev/null && \
     [[ -z "$(git -C "$ROOT" ls-files --others --exclude-standard website/)" ]]; then
    log "no git-visible changes, skipping"
    rm -f "$LOCKFILE"
    continue
  fi

  STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  log "changes detected — committing..."

  cd "$ROOT"
  git add website/
  git commit -m "auto: website update $STAMP" --no-gpg-sign 2>/dev/null || {
    log "nothing to commit"
    rm -f "$LOCKFILE"
    continue
  }

  log "pushing to origin..."
  if git push origin main 2>&1 | tee -a "$LOGS/gitwatch.log"; then
    log "pushed — Vercel will auto-deploy"
  else
    log "push FAILED — see $LOGS/gitwatch.log"
  fi

  rm -f "$LOCKFILE"
done
