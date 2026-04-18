#!/usr/bin/env bash
# ssh-tunnel.sh — Start a public SSH tunnel so Hyo can reach the Mini from anywhere.
# Uses localhost.run (zero account, zero install on the Pro side).
#
# Usage: bash bin/ssh-tunnel.sh
# Output: SSH command for Hyo to use from any machine

set -euo pipefail

LOG=/tmp/ssh-tunnel.log
PID_FILE=/tmp/ssh-tunnel.pid

# Kill any existing tunnel
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$OLD_PID" ]]; then
        kill "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

echo "[ssh-tunnel] Starting localhost.run SSH tunnel..."
rm -f "$LOG"

# Start tunnel in background
ssh -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -R 22:localhost:22 nokey@localhost.run \
    > "$LOG" 2>&1 &

TUNNEL_PID=$!
echo "$TUNNEL_PID" > "$PID_FILE"

echo "[ssh-tunnel] Tunnel PID: $TUNNEL_PID — waiting for URL..."
sleep 6

# Extract URL from log
URL=$(grep -oE '[a-f0-9-]+\.localhost\.run' "$LOG" 2>/dev/null | head -1 || echo "")

if [[ -z "$URL" ]]; then
    echo "[ssh-tunnel] Could not get URL. Log output:"
    cat "$LOG"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SSH TUNNEL ACTIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  From any device, run:"
echo "  ssh kai@${URL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Write URL to file so Kai can read it
echo "$URL" > /tmp/tunnel-url.txt
echo "[ssh-tunnel] URL written to /tmp/tunnel-url.txt"
echo "[ssh-tunnel] Tunnel is running in background (PID $TUNNEL_PID)"
echo "[ssh-tunnel] To stop: kill $TUNNEL_PID"
