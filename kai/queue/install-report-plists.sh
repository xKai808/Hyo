#!/usr/bin/env bash
# kai/queue/install-report-plists.sh — Install all reporting launchd plists
# Run once on the Mac Mini. Safe to re-run (unloads first).

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
PLIST_SRC="$ROOT/kai/queue"
PLIST_DST="$HOME/Library/LaunchAgents"

PLISTS=(
  "com.hyo.nel-daily"
  "com.hyo.sam-daily"
  "com.hyo.aether-daily"
  "com.hyo.kai-daily"
  "com.hyo.report-check"
  "com.hyo.weekly-report"
)

for name in "${PLISTS[@]}"; do
  src="$PLIST_SRC/${name}.plist"
  dst="$PLIST_DST/${name}.plist"
  
  if [[ ! -f "$src" ]]; then
    echo "SKIP: $src not found"
    continue
  fi
  
  # Unload if already loaded
  launchctl unload "$dst" 2>/dev/null || true
  
  cp "$src" "$dst"
  launchctl load "$dst"
  echo "LOADED: $name"
done

echo "All report plists installed."
