# MCP Server Tunnel Setup

This directory contains a one-command tunnel setup that connects the MCP server (running on `localhost:3847`) to the outside world, allowing Cowork (running in a sandbox) to reach it.

## Quick Start

### One-time tunnel (ephemeral)
```bash
kai tunnel
```
Starts a tunnel using the best available method (cloudflared → localtunnel → ngrok). The URL is saved to `tunnel.url` and printed to the console.

### Persistent tunnel daemon
```bash
kai tunnel-daemon install
```
Installs and starts a launchd daemon that keeps the tunnel running across reboots.

## Files

- **tunnel.sh** — Main tunnel script with auto-detection and method fallbacks
- **com.hyo.mcp-tunnel.plist** — launchd daemon configuration (persistent)
- **tunnel.url** — (Auto-created) Contains the current public tunnel URL
- **TUNNEL.md** — This file

## Tunnel Methods

### 1. Cloudflared (Primary — Recommended)
**What:** Cloudflare's free tunnel. No account needed for quick tunnels. Most reliable.

**Install:**
```bash
brew install cloudflared
```

**Quick tunnel (expires in 1 hour):**
```bash
kai tunnel --method cloudflared
```

**Named tunnel (persistent, requires Cloudflare account):**
```bash
kai tunnel --method cloudflared --named
```
This creates a named tunnel that you can configure to route through your domain.

### 2. Localtunnel (Fallback)
**What:** NPX-based tunnel. Zero installation required, just needs npm/Node.

**Install:**
None needed if you have npm/Node.

**Run:**
```bash
kai tunnel --method localtunnel
```

**Caveats:** Subdomain is random each run (unless `LOCALTUNNEL_SUBDOMAIN` env var set). URL changes on restart.

### 3. Ngrok (Fallback)
**What:** Popular tunnel service. Free tier available.

**Install:**
```bash
brew install ngrok
# OR create account at ngrok.com and auth
```

**Run:**
```bash
kai tunnel --method ngrok
```

## Usage with Cowork

1. **Start the tunnel:**
   ```bash
   kai tunnel
   ```
   Output will include the public URL, e.g.:
   ```
   https://abcd1234.trycloudflare.com
   ```

2. **Configure Cowork MCP connector:**
   - In Cowork settings, go to Connector → MCP
   - Add new connector with:
     - **URL:** Paste the public URL from step 1
     - **Name:** `hyo-mcp` (or your preferred name)

3. **Use it:**
   Cowork can now call the MCP server from inside the sandbox.

## Persistent Daemon Setup

### Install daemon
```bash
kai tunnel-daemon install
```
This:
- Copies the plist to `~/Library/LaunchAgents/com.hyo.mcp-tunnel.plist`
- Loads it with `launchctl`
- Starts the tunnel on login
- Automatically restarts on crash

### Manage daemon
```bash
kai tunnel-daemon start    # Start the tunnel
kai tunnel-daemon stop     # Stop the tunnel
kai tunnel-daemon status   # Check if running
kai tunnel-daemon logs     # Follow logs in real-time
kai tunnel-daemon uninstall # Remove daemon
```

### View daemon logs
```bash
tail -f /tmp/hyo-mcp-tunnel.log
```

## Troubleshooting

### "MCP server not responding at localhost:3847"
Make sure the MCP server is running:
```bash
# In a separate terminal, from agents/sam/mcp-server/
node server.js --transport sse --port 3847
```

Or check if it's running via launchd:
```bash
launchctl list com.hyo.mcp-server
```

### "cloudflared not found and cannot be installed"
Install manually:
```bash
brew install cloudflared
```

### Tunnel URL is random / keeps changing
You're using localtunnel (fallback method). To get a stable URL:
1. Install cloudflared: `brew install cloudflared`
2. Use named tunnel: `kai tunnel --method cloudflared --named`
3. Or set up persistent daemon: `kai tunnel-daemon install`

### Cowork can't reach the tunnel
1. **Verify the URL is correct:**
   ```bash
   cat agents/sam/mcp-server/tunnel.url
   ```
   Should print the public URL.

2. **Test the URL from your browser:**
   ```
   https://your-tunnel-url/mcp
   ```
   Should return JSON (or error if server is down).

3. **Check Cowork settings:**
   Make sure the URL in the MCP connector matches exactly (including `https://`).

## Architecture Notes

- The MCP server itself (`server.js`, port 3847) is separate from the tunnel.
- The tunnel is a **proxy** that forwards external requests to `localhost:3847`.
- Each tunnel method has different properties:
  - **cloudflared:** Fast, reliable, free, widely used
  - **localtunnel:** Zero setup, unpredictable, good for testing
  - **ngrok:** Popular, free tier available, good custom domain support
- The daemon (`com.hyo.mcp-tunnel.plist`) ensures the tunnel restarts if it crashes.

## Environment Variables

- `HYO_ROOT` — Path to Hyo project root (defaults to `~/Documents/Projects/Hyo`)
- `HYO_DOMAIN` — Domain to route through cloudflared named tunnel (e.g., `mcp.hyo.world`)
- `LOCALTUNNEL_SUBDOMAIN` — Subdomain for localtunnel (defaults to `hyo-mcp`)

## See Also

- `agents/sam/mcp-server/server.js` — The actual MCP server
- `agents/sam/mcp-server/com.hyo.mcp-server.plist` — Daemon for the MCP server itself
- `bin/kai.sh` — Main dispatcher (commands: `kai tunnel`, `kai tunnel-daemon`)
