#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/agents/sam/mcp-server/tunnel.sh
#
# One-command MCP tunnel setup: connects localhost:3847 to the outside world
# so Cowork (running in sandbox) can reach the MCP server.
#
# Auto-detects available tunnel method (cloudflared > localtunnel > ngrok)
# Saves the public URL to tunnel.url for other scripts to read.
#
# Usage:
#   tunnel.sh                    # Start tunnel (best available method)
#   tunnel.sh --method cloudflared   # Force cloudflared
#   tunnel.sh --method localtunnel   # Force localtunnel
#   tunnel.sh --help             # Show this help

set -euo pipefail

# ---- config ---------------------------------------------------------------
MCP_PORT="3847"
MCP_HOST="localhost"
MCP_URL="http://${MCP_HOST}:${MCP_PORT}"

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${HYO_ROOT:-}" ]] && [[ -d "$HYO_ROOT" ]]; then
  ROOT="$HYO_ROOT"
else
  # Navigate up from agents/sam/mcp-server to repo root
  ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi

TUNNEL_URL_FILE="$SCRIPT_DIR/tunnel.url"

# ---- color helpers ----------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$RST" "$BOLD" "$*" "$RST"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- help ---------------------------------------------------------------
show_help() {
  cat <<EOF
${BOLD}tunnel.sh${RST} — MCP server tunnel setup

${BOLD}Usage:${RST}
  tunnel.sh                       Start tunnel (best available method)
  tunnel.sh --method cloudflared  Force cloudflared
  tunnel.sh --method localtunnel  Force localtunnel
  tunnel.sh --method ngrok        Force ngrok
  tunnel.sh --help                Show this help

${BOLD}Configuration:${RST}
  MCP_PORT=$MCP_PORT (localhost:$MCP_PORT)
  Tunnel URL saved to: $TUNNEL_URL_FILE

${BOLD}Methods (by preference):${RST}
  1. cloudflared  — Free, no account, most reliable
                   Requires: brew install cloudflared
  2. localtunnel  — Zero install, npx-based
                   No account needed, subdomain random
  3. ngrok        — Free tier available
                   Requires: brew install ngrok or account

${BOLD}Cowork Integration:${RST}
  After tunnel starts, it prints the public URL.
  Add to Cowork MCP connector:
    URL: <printed-public-url>
    Name: hyo-mcp

EOF
}

# ---- method detection -----------------------------------------------
detect_cloudflared() {
  if command -v cloudflared >/dev/null 2>&1; then
    return 0
  fi
  # Try to install
  if command -v brew >/dev/null 2>&1; then
    warn "cloudflared not found; installing via brew..."
    brew install cloudflared 2>/dev/null && return 0
  fi
  return 1
}

detect_localtunnel() {
  if command -v npx >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

detect_ngrok() {
  if command -v ngrok >/dev/null 2>&1; then
    return 0
  fi
  # Try to install
  if command -v brew >/dev/null 2>&1; then
    warn "ngrok not found; installing via brew..."
    brew install ngrok 2>/dev/null && return 0
  fi
  return 1
}

# ---- tunnel runners -------------------------------------------------

run_cloudflared_quick() {
  hdr "Starting cloudflared tunnel (quick ephemeral)"
  say "${DIM}This creates a temporary tunnel that expires in 1 hour.${RST}"
  say "For persistent tunnel, use: tunnel.sh --method cloudflared --named"
  say ""

  # Quick tunnel: no setup needed
  cloudflared tunnel --url "$MCP_URL" 2>&1 | tee -a "$TUNNEL_URL_FILE.log" | while IFS= read -r line; do
    if [[ "$line" =~ https?://.*\.trycloudflare\.com ]]; then
      url="${BASH_REMATCH[0]}"
      echo "$url" > "$TUNNEL_URL_FILE"
      ok "Public URL: ${BOLD}$url${RST}"
      say ""
      say "Add to Cowork MCP connector settings:"
      say "  URL: $url"
      say ""
    fi
    say "$line"
  done
}

run_cloudflared_named() {
  hdr "Setting up cloudflared named tunnel (persistent)"

  # Check if tunnel already exists
  local tunnel_name="hyo-mcp"
  if cloudflared tunnel list 2>/dev/null | grep -q "$tunnel_name"; then
    ok "Tunnel '$tunnel_name' already exists"
  else
    say "Creating named tunnel '$tunnel_name'..."
    cloudflared tunnel create "$tunnel_name"
    ok "Tunnel created"
  fi

  # Route DNS if domain is configured
  local domain="${HYO_DOMAIN:-mcp.hyo.world}"
  if [[ -n "$domain" ]] && ! cloudflared tunnel route dns "$tunnel_name" "$domain" 2>&1 | grep -q "already exists"; then
    say "Routing DNS: $domain → $tunnel_name"
    ok "DNS configured for $domain"
  fi

  say "Running tunnel..."
  cloudflared tunnel run "$tunnel_name" 2>&1 | tee -a "$TUNNEL_URL_FILE.log" | while IFS= read -r line; do
    say "$line"
  done
}

run_localtunnel() {
  hdr "Starting localtunnel (npx)"
  say "${DIM}Random subdomain assigned each run (use cloudflared for persistence).${RST}"
  say ""

  # Random subdomain or user-provided
  local subdomain="${LOCALTUNNEL_SUBDOMAIN:-hyo-mcp}"
  npx localtunnel --port "$MCP_PORT" --subdomain "$subdomain" 2>&1 | tee -a "$TUNNEL_URL_FILE.log" | while IFS= read -r line; do
    if [[ "$line" =~ https?://.*\.loca\.lt ]]; then
      url="${BASH_REMATCH[0]}"
      echo "$url" > "$TUNNEL_URL_FILE"
      ok "Public URL: ${BOLD}$url${RST}"
      say ""
      say "Add to Cowork MCP connector settings:"
      say "  URL: $url"
      say ""
    fi
    say "$line"
  done
}

run_ngrok() {
  hdr "Starting ngrok tunnel"
  say "${DIM}Requires ngrok account for custom domains.${RST}"
  say ""

  ngrok http "$MCP_PORT" 2>&1 | tee -a "$TUNNEL_URL_FILE.log" | while IFS= read -r line; do
    if [[ "$line" =~ https?://[0-9a-f]+\.ngrok(?:\.|-[a-z]+\.)io ]]; then
      url="${BASH_REMATCH[0]}"
      echo "$url" > "$TUNNEL_URL_FILE"
      ok "Public URL: ${BOLD}$url${RST}"
      say ""
      say "Add to Cowork MCP connector settings:"
      say "  URL: $url"
      say ""
    fi
    say "$line"
  done
}

# ---- main dispatch ------------------------------------------------
main() {
  local method=""
  local named=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --method)
        method="$2"
        shift 2
        ;;
      --named)
        named="yes"
        shift
        ;;
      *)
        err "unknown flag: $1"
        show_help
        exit 1
        ;;
    esac
  done

  # Create log dir
  mkdir -p "$(dirname "$TUNNEL_URL_FILE")"

  # Ensure MCP server is running on localhost
  if ! curl -sS "http://$MCP_HOST:$MCP_PORT/mcp" >/dev/null 2>&1; then
    warn "MCP server not responding at $MCP_URL"
    warn "Make sure the server is running: node $SCRIPT_DIR/server.js --transport sse --port $MCP_PORT"
    say ""
    read -p "Continue anyway? (y/N) " -r
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
  else
    ok "MCP server is running at $MCP_URL"
  fi

  say ""

  # Auto-detect or use specified method
  if [[ -n "$method" ]]; then
    case "$method" in
      cloudflared)
        detect_cloudflared || die "cloudflared not found and cannot be installed"
        if [[ "$named" == "yes" ]]; then
          run_cloudflared_named
        else
          run_cloudflared_quick
        fi
        ;;
      localtunnel)
        detect_localtunnel || die "npx not found"
        run_localtunnel
        ;;
      ngrok)
        detect_ngrok || die "ngrok not found and cannot be installed"
        run_ngrok
        ;;
      *)
        die "unknown method: $method (cloudflared|localtunnel|ngrok)"
        ;;
    esac
  else
    # Auto-detect: try in order of preference
    hdr "Auto-detecting tunnel method"
    if detect_cloudflared; then
      ok "cloudflared available"
      run_cloudflared_quick
    elif detect_localtunnel; then
      warn "cloudflared not available, using localtunnel"
      run_localtunnel
    elif detect_ngrok; then
      warn "cloudflared and localtunnel not available, using ngrok"
      run_ngrok
    else
      die "No tunnel method available (install: cloudflared, node/npx, or ngrok)"
    fi
  fi
}

main "$@"
