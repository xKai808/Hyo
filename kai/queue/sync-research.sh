#!/usr/bin/env bash
# kai/queue/sync-research.sh — Sync research files from agents/ra/research/ to website/docs/research/
# Run after any Ra archive operation to keep the website copy in sync.

set -euo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
SRC="$ROOT/agents/ra/research"
DST="$ROOT/website/docs/research"

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: source not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DST/entities" "$DST/topics" "$DST/lab" "$DST/briefs"

# Sync top-level files
for f in index.md trends.md archive-summary.md; do
  [[ -f "$SRC/$f" ]] && cp "$SRC/$f" "$DST/$f"
done

# Sync subdirectories
for dir in entities topics lab briefs; do
  if [[ -d "$SRC/$dir" ]]; then
    cp "$SRC/$dir"/*.md "$DST/$dir/" 2>/dev/null || true
  fi
done

echo "Research synced: $(find "$DST" -name '*.md' | wc -l | tr -d ' ') files"
