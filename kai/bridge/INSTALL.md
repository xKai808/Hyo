# HTTP Bridge — Installation Guide

**What this does:** Runs a tiny HTTP server on the Mini that accepts commands from Cowork sessions. Eliminates the 30-120s mount-sync latency that makes the filesystem queue unusable from Cowork.

**Time to install:** ~2 minutes.

---

## Step 1: Find the Mini's local IP

Run this on the Mini:

```bash
ipconfig getifaddr en0
```

Note the IP (e.g., `192.168.1.42`).

## Step 2: Update config.json

```bash
cd ~/Documents/Projects/Hyo
# Replace MINI_IP_HERE with the actual IP from Step 1
sed -i '' 's/MINI_IP_HERE/192.168.1.42/' kai/bridge/config.json
```

(Replace `192.168.1.42` with the actual IP.)

## Step 3: Test the server manually first

```bash
cd ~/Documents/Projects/Hyo
python3 kai/bridge/server.py
```

You should see:
```
[...] START: binding 0.0.0.0:9876, root=/Users/hyo/Documents/Projects/Hyo
[...] READY: accepting connections
```

Test it from another terminal:
```bash
curl http://localhost:9876/health
```

Expected:
```json
{"status": "ok", "uptime_s": ..., "commands_processed": 0, "root": "..."}
```

Test a command (use the token from `agents/nel/security/founder.token`):
```bash
TOKEN=$(cat ~/Documents/Projects/Hyo/agents/nel/security/founder.token)
curl -X POST http://localhost:9876/exec \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"command": "echo hello from bridge", "timeout": 10}'
```

Expected:
```json
{"stdout": "hello from bridge\n", "stderr": "", "exit_code": 0, "duration_s": 0.01, "command": "echo hello from bridge"}
```

Press Ctrl+C to stop the test server.

## Step 4: Install the launchd daemon

```bash
cp ~/Documents/Projects/Hyo/kai/bridge/com.hyo.bridge.plist ~/Library/LaunchAgents/com.hyo.bridge.plist
```

```bash
launchctl load ~/Library/LaunchAgents/com.hyo.bridge.plist
```

Verify it's running:
```bash
launchctl list | grep com.hyo.bridge
curl http://localhost:9876/health
```

## Step 5: Allow firewall access (if needed)

If the Mac has the firewall enabled, you may need to allow Python through:

System Settings > Network > Firewall > Options > Add `python3`

Or temporarily for testing:
```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/bin/python3
```

---

## Troubleshooting

**Server won't start:**
```bash
# Check logs
cat /tmp/hyo-bridge.log
tail -20 ~/Documents/Projects/Hyo/kai/bridge/bridge.log
```

**Port already in use:**
```bash
lsof -i :9876
# Kill the existing process if needed
kill $(lsof -ti :9876)
```

**Reload after changes:**
```bash
launchctl unload ~/Library/LaunchAgents/com.hyo.bridge.plist
launchctl load ~/Library/LaunchAgents/com.hyo.bridge.plist
```

**Stop the daemon:**
```bash
launchctl unload ~/Library/LaunchAgents/com.hyo.bridge.plist
```

---

## Architecture

```
Cowork sandbox                        Mac Mini (local network)
┌──────────────┐    HTTP POST         ┌──────────────────────┐
│  client.py   │ ──────────────────>  │  server.py (:9876)   │
│  submit.py   │    /exec             │  ├─ auth check       │
│  (bridge     │ <──────────────────  │  ├─ safety check     │
│   first)     │    JSON result       │  └─ subprocess.run() │
└──────────────┘                      └──────────────────────┘
       │                                       │
       │ fallback (if bridge down)             │
       ▼                                       │
  filesystem queue                    worker.sh (existing)
  kai/queue/pending/                  polls pending/
```

- **Bridge path:** ~100ms round trip (HTTP over LAN)
- **Queue path:** 30-120s+ (filesystem mount sync latency)
- submit.py tries bridge first, falls back to queue automatically
