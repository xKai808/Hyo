#!/usr/bin/env bash
# sync-website-data.sh — Sync data files from agents/sam/website/ to website/
#
# WHY: website/ and agents/sam/website/ are separate directories in git.
# Vercel serves from website/. If we update agents/sam/website/data/ but not
# website/data/, production shows stale data. This happened in session 10
# (SE-010-011) and cost hours of debugging.
#
# WHEN: Run before every git commit that touches website data.
# HOW: Called from pre-commit hook or manually via `kai sync-data`
#
# PERMANENT FIX: Change Vercel root directory to agents/sam/website/
# and remove the website/ directory from git entirely.

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
WEBSITE_DIR="$HYO_ROOT/website"
AGENTS_DIR="$HYO_ROOT/agents/sam/website"

if [[ ! -d "$WEBSITE_DIR/data" ]] || [[ ! -d "$AGENTS_DIR/data" ]]; then
  echo "[sync-website-data] ERROR: Missing data directories"
  exit 1
fi

# Sync all data files from agents/sam/website/data/ to website/data/
changed=0
for f in "$AGENTS_DIR"/data/*.json; do
  fname=$(basename "$f")
  target="$WEBSITE_DIR/data/$fname"

  if [[ ! -f "$target" ]] || ! diff -q "$f" "$target" > /dev/null 2>&1; then
    cp "$f" "$target"
    echo "[sync-website-data] Synced: data/$fname"
    changed=$((changed + 1))
  fi
done

if [[ $changed -eq 0 ]]; then
  echo "[sync-website-data] All data files in sync."
else
  echo "[sync-website-data] Synced $changed file(s). Run 'git add website/data/' to stage."
fi
