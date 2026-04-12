# hyo-mini-mcp — Setup Guide

This MCP server runs on the Mac Mini and gives Claude Cowork the ability to execute commands, push to git, and deploy — eliminating the copy/paste bottleneck.

## Quick Start (5 minutes)

### 1. Install dependencies

```bash
cd ~/Documents/Projects/Hyo/agents/sam/mcp-server
npm install
```

### 2. Test locally

```bash
node server.js --transport sse --port 3847
# In another terminal:
curl http://localhost:3847/health
# Should return: {"ok":true,"server":"hyo-mini-mcp","ts":"..."}
```

### 3. Add auth token (recommended)

```bash
# Generate a random token
export HYO_MCP_TOKEN=$(openssl rand -hex 32)
echo "$HYO_MCP_TOKEN" > ~/.hyo-mcp-token
chmod 600 ~/.hyo-mcp-token

# Start with auth
HYO_MCP_TOKEN=$(cat ~/.hyo-mcp-token) node server.js --transport sse --port 3847
```

### 4. Keep it running with launchd

```bash
cp com.hyo.mcp-server.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hyo.mcp-server.plist
```

Check it's running:
```bash
launchctl print gui/$(id -u)/com.hyo.mcp-server
# Or:
curl http://localhost:3847/health
```

### 5. Expose to Cowork

**Option A: Tailscale (recommended)**
```bash
brew install tailscale
# Open Tailscale app and sign in
# Your Mini gets a hostname like: mac-mini.tailnet-xxxxx.ts.net
# The MCP URL becomes: http://mac-mini.tailnet-xxxxx.ts.net:3847
```

**Option B: Cloudflare Tunnel**
```bash
brew install cloudflare/cloudflare/cloudflared
cloudflared tunnel login
cloudflared tunnel create hyo-mcp
cloudflared tunnel route dns hyo-mcp mcp.hyo.world
cloudflared tunnel run --url http://localhost:3847 hyo-mcp
```

**Option C: ngrok (quick testing)**
```bash
brew install ngrok
ngrok http 3847
# Note the https://xxxx.ngrok-free.app URL
```

### 6. Connect in Cowork

Go to **Settings → Connectors → Add custom connector** and enter:
- Name: `Mac Mini`
- URL: your Tailscale/Cloudflare/ngrok URL
- Auth: Bearer token (if you set HYO_MCP_TOKEN)

Once connected, Cowork can call tools like `execute_command`, `git_push`, `deploy`, `kai`.

## For Claude Code (local use)

Add to `~/.claude/claude_code_config.json`:

```json
{
  "mcpServers": {
    "hyo-mini": {
      "command": "node",
      "args": ["~/Documents/Projects/Hyo/agents/sam/mcp-server/server.js"],
      "env": {
        "HYO_ROOT": "~/Documents/Projects/Hyo"
      }
    }
  }
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `execute_command` | Run any shell command on the Mini |
| `git_push` | Push to origin with pre-deploy validation |
| `deploy` | Full pipeline: validate → push → health check |
| `read_file` | Read any file in the Hyo project |
| `write_file` | Write to any file in the Hyo project |
| `kai` | Run kai.sh subcommands directly |

## Security

- Commands matching dangerous patterns are blocked (rm -rf /, sudo, mkfs, etc.)
- Optional bearer token auth (set `HYO_MCP_TOKEN` env var)
- All file operations are sandboxed to HYO_ROOT
- Path traversal attempts are blocked
- Output truncated at 50KB to prevent memory issues
- 60s command timeout (120s for kai subcommands)

## Troubleshooting

**Server won't start:**
```bash
# Check if port is in use
lsof -i :3847
# Check logs
cat /tmp/hyo-mcp-server.log
```

**Cowork can't connect:**
- Verify the URL is reachable: `curl <your-url>/health`
- Check Tailscale is connected: `tailscale status`
- Check auth token matches between server and connector config

**Command hangs:**
- Default timeout is 60s. Long-running commands may be killed.
- Use `timeout` parameter in execute_command for longer operations.
