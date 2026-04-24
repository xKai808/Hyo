import json, time
from datetime import datetime
two_h_ago = time.time() - 7200
hyo = "/sessions/zen-dreamy-babbage/mnt/Hyo"
flags = []
try:
    with open(f"{hyo}/kai/ledger/log.jsonl") as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("action") == "FLAG":
                sev = e.get("severity", "")
                if sev in ("P0", "P1"):
                    ts = e.get("ts", "")
                    try:
                        t = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                    except Exception:
                        continue
                    if t >= two_h_ago:
                        flags.append(e)
except FileNotFoundError:
    print("log.jsonl missing")
    raise SystemExit
print(f"Found {len(flags)} P0/P1 FLAGs in last 2h")
for f_ in flags[-15:]:
    print(json.dumps(f_)[:250])
