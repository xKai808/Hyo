#!/usr/bin/env bash
# install-tunnel.sh — Install or reinstall the cloudflared tunnel launchd daemon
# Run on Mac Mini: bash agents/sam/mcp-server/install-tunnel.sh
#
# This script:
#   1. Verifies cloudflared is installed
#   2. Stops any existing tunnel daemon
#   3. Copies the plist to ~/Library/LaunchAgents/
#   4. Loads the daemon
#   5. Waits for tunnel to come up
#   6. Reports the tunnel URL

set -euo pipefail

PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/com.hyo.mcp-tunnel.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.hyo.mcp-tunnel.plist"
LABEL="com.hyo.mcp-tunnel"
LOG="/tmp/hyo-mcp-tunnel.log"

echo "=== Hyo MCP Tunnel Installer ==="

# 1. Verify cloudflared
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "ERROR: cloudflared not found. Install: brew install cloudflared"
  exit 1
fi
echo "✓ cloudflared found: $(which cloudflared)"

# 2. Stop existing daemon (ignore errors if not loaded)
echo "Stopping existing daemon (if any)..."
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
sleep 1

# 3. Copy plist
echo "Installing plist to $PLIST_DST"
cp "$PLIST_SRC" "$PLIST_DST"

# 4. Clear old log
> "$LOG"

# 5. Load daemon
echo "Loading daemon..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "✓ Daemon loaded"

# 6. Wait for tunnel URL (up to 15 seconds)
echo "Waiting for tunnel to establish..."
for i in $(seq 1 15); do
  if grep -q "trycloudflare.com" "$LOG" 2>/dev/null; then
    TUNNEL_URL=$(grep -o 'https://[^ ]*trycloudflare.com' "$LOG" | head -1)
    echo ""
    echo "✓ Tunnel is live: $TUNNEL_URL"

    # Save URL for other scripts
    echo "$TUNNEL_URL" > "$(dirname "$PLIST_SRC")/tunnel.url"
    echo "✓ URL saved to agents/sam/mcp-server/tunnel.url"
    exit 0
  fi

  # Check for errors
  if grep -q "Operation not permitted" "$LOG" 2>/dev/null; then
    echo ""
    echo "ERROR: TCC is blocking the daemon. Grant Full Disk Access to cloudflared:"
    echo "  System Settings → Privacy & Security → Full Disk Access → add /opt/homebrew/bin/cloudflared"
    echo ""
    echo "Or run manually in a terminal tab:"
    echo "  cloudflared tunnel --url http://localhost:3847"
    exit 2
  fi

  printf "."
  sleep 1
done

echo ""
echo "WARNING: Tunnel didn't come up in 15s. Check: cat $LOG"
exit 1
