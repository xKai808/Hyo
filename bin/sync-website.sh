#!/usr/bin/env bash
# bin/sync-website.sh — Enforce single-source-of-truth for website files
#
# Until the dual-path is fully resolved (website/ symlinked to agents/sam/website/),
# this script syncs agents/sam/website/ -> website/ and catches drift.
#
# Usage:
#   bash bin/sync-website.sh          # sync and report
#   bash bin/sync-website.sh --check  # check only, exit 1 if drifted
#
# Wire this into: sam.sh deploy, pre-commit hook, verify-render.sh

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
SRC="$ROOT/agents/sam/website"
DST="$ROOT/website"
CHECK_ONLY=false

[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

drifted=0
synced=0

# Files to sync (the ones that matter — add as needed)
SYNC_FILES=(
  "hq.html"
  "index.html"
  "aurora.html"
  "marketplace.html"
  "research.html"
  "api/hq-push.js"
  "api/hq-data.js"
  "api/hq.js"
  "api/hq-auth.js"
  "api/health.js"
  "api/_hq-store.js"
  "api/aurora-subscribe.js"
  "api/register-founder.js"
  "api/marketplace-request.js"
  "data/aether-metrics.json"
  "data/feed.json"
  "vercel.json"
)

for f in "${SYNC_FILES[@]}"; do
  src_file="$SRC/$f"
  dst_file="$DST/$f"

  if [[ ! -f "$src_file" ]]; then
    continue
  fi

  if [[ ! -f "$dst_file" ]]; then
    echo "MISSING: $f (exists in agents/sam/website/ but not website/)"
    if ! $CHECK_ONLY; then
      mkdir -p "$(dirname "$dst_file")"
      cp "$src_file" "$dst_file"
      echo "  -> COPIED"
      ((synced++))
    else
      ((drifted++))
    fi
    continue
  fi

  if ! diff -q "$src_file" "$dst_file" > /dev/null 2>&1; then
    echo "DRIFTED: $f"
    if ! $CHECK_ONLY; then
      cp "$src_file" "$dst_file"
      echo "  -> SYNCED"
      ((synced++))
    else
      ((drifted++))
    fi
  fi
done

if $CHECK_ONLY; then
  if [[ $drifted -gt 0 ]]; then
    echo "DRIFT DETECTED: $drifted files differ between agents/sam/website/ and website/"
    echo "Run: bash bin/sync-website.sh (without --check) to fix"
    exit 1
  else
    echo "OK: all tracked files in sync"
    exit 0
  fi
else
  echo "Sync complete: $synced files updated"
fi
