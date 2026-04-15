#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# install.sh — Deploy all Hyo launchd maintenance plists
# Run on the Mac Mini: bash kai/launchd/install.sh
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
PLIST_DIR="$ROOT/kai/launchd"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

mkdir -p "$LAUNCH_DIR"

echo "═══ Installing Hyo Maintenance Daemons ═══"
echo ""

# Make all scripts executable
chmod +x "$ROOT/bin/ticket.sh" \
         "$ROOT/bin/business-monitor.sh" \
         "$ROOT/bin/escalate-blocked.sh" \
         "$ROOT/bin/memory-compact.sh" \
         "$ROOT/kai/queue/healthcheck.sh" \
         "$ROOT/agents/"*/verify.sh \
         2>/dev/null || true

for plist in "$PLIST_DIR"/com.hyo.*.plist; do
  [[ ! -f "$plist" ]] && continue
  label=$(basename "$plist" .plist)
  dest="$LAUNCH_DIR/$(basename "$plist")"

  # Unload existing if present
  if launchctl list | grep -q "$label" 2>/dev/null; then
    echo "  Unloading existing $label..."
    launchctl unload "$dest" 2>/dev/null || true
  fi

  # Copy and load
  cp "$plist" "$dest"
  launchctl load "$dest"
  echo "  ✅ $label loaded"
done

echo ""
echo "═══ Installed Daemons ═══"
echo ""

# Verify all are running
for plist in "$PLIST_DIR"/com.hyo.*.plist; do
  [[ ! -f "$plist" ]] && continue
  label=$(basename "$plist" .plist)
  if launchctl list | grep -q "$label" 2>/dev/null; then
    echo "  ✅ $label — active"
  else
    echo "  ❌ $label — NOT loaded"
  fi
done

echo ""
echo "Schedule:"
echo "  com.hyo.healthcheck       → every 15 min (SLA + system health)"
echo "  com.hyo.business-monitor  → every 30 min (tickets, newsletter, feed)"
echo "  com.hyo.escalate-blocked  → every hour (blocked ticket escalation)"
echo "  com.hyo.memory-compact    → 02:30 AM MTN (archive, compress, rotate)"
echo ""
echo "Existing daemons (from prior installs):"
launchctl list | grep "com.hyo" 2>/dev/null || echo "  (none)"
echo ""
echo "Done. All maintenance daemons installed."
