#!/bin/bash

set -euo pipefail

# Cloudflare Tunnel Setup for Dashboard Server
# This script configures a persistent tunnel to localhost:8420 via Cloudflare Tunnel
# Usage: ./setup_dashboard_tunnel.sh

DASHBOARD_PORT=8420
CLOUDFLARED_BIN=""
PLIST_PATH="${HOME}/Library/LaunchAgents/com.kai.dashboard-tunnel.plist"
PLIST_SOURCE="$(dirname "$0")/com.kai.dashboard-tunnel.plist"
LOG_DIR="${HOME}/Documents/Projects/Kai/logs"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Check and install cloudflared if needed
log_info "Checking cloudflared installation..."

if command -v cloudflared &> /dev/null; then
    CLOUDFLARED_BIN="$(command -v cloudflared)"
    log_info "cloudflared found at: $CLOUDFLARED_BIN"
else
    log_warn "cloudflared not found, installing via Homebrew..."

    if ! command -v brew &> /dev/null; then
        log_error "Homebrew not installed. Please install Homebrew first: https://brew.sh"
        exit 1
    fi

    brew install cloudflared
    CLOUDFLARED_BIN="$(command -v cloudflared)"
    log_info "cloudflared installed at: $CLOUDFLARED_BIN"
fi

# Step 2: Verify cloudflared is executable
if [ ! -x "$CLOUDFLARED_BIN" ]; then
    log_error "cloudflared is not executable at: $CLOUDFLARED_BIN"
    exit 1
fi

# Step 3: Create log directory if needed
if [ ! -d "$LOG_DIR" ]; then
    log_info "Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi

# Step 4: Verify plist source exists
if [ ! -f "$PLIST_SOURCE" ]; then
    log_error "plist file not found at: $PLIST_SOURCE"
    log_error "Expected location: $(dirname "$0")/com.kai.dashboard-tunnel.plist"
    exit 1
fi

# Step 5: Copy plist to LaunchAgents
log_info "Installing launchd plist..."
mkdir -p "$(dirname "$PLIST_PATH")"

# Backup existing plist if present
if [ -f "$PLIST_PATH" ]; then
    log_warn "Existing plist found, creating backup: ${PLIST_PATH}.bak"
    cp "$PLIST_PATH" "${PLIST_PATH}.bak"
fi

cp "$PLIST_SOURCE" "$PLIST_PATH"
chmod 644 "$PLIST_PATH"
log_info "Plist installed at: $PLIST_PATH"

# Step 6: Load the launchd service
log_info "Loading launchd service..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

# Step 7: Brief startup delay and status check
sleep 2
if launchctl list | grep -q "com.kai.dashboard-tunnel"; then
    log_info "Service loaded successfully"
else
    log_warn "Service may not be running yet, checking logs..."
fi

# Step 8: Output tunnel information
log_info "Cloudflare Tunnel setup complete!"
log_info "Dashboard will be accessible on port $DASHBOARD_PORT"
log_info ""
log_info "To access your dashboard:"
log_info "  1. Ensure your dashboard server is running on localhost:$DASHBOARD_PORT"
log_info "  2. The tunnel will start automatically (or check 'launchctl list' to verify)"
log_info "  3. Run: cloudflared tunnel info to get your public URL"
log_info ""
log_info "Tunnel logs: $LOG_DIR/tunnel.log"
log_info ""
log_info "To view service status:"
log_info "  launchctl list com.kai.dashboard-tunnel"
log_info ""
log_info "To stop the tunnel:"
log_info "  launchctl unload '$PLIST_PATH'"
log_info ""
log_info "To start the tunnel:"
log_info "  launchctl load '$PLIST_PATH'"
