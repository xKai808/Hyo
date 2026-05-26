# Morning report blocker — 2026-05-26

**Scheduled task**: `kai-morning-report` (cowork)
**Status**: NOT GENERATED — three compounding faults

## Faults

1. **Stale git lock on Mini**
   `~/Documents/Projects/Hyo/.git/index.lock` exists with mtime 2026-05-26 02:12 MT. Same lock observed blocking the enforcer commit at 11:12:08Z (see `kai/queue/completed/cmd-1779793926-34724.json` — exit_code=0 reported but stderr is `fatal: Unable to create '.../.git/index.lock': File exists`). Lock cannot be removed from the Cowork mount (`Operation not permitted`).

2. **HTTP bridge unreachable from Cowork sandbox**
   `submit.py` reports `[bridge] Unreachable, falling back to filesystem queue...` for `100.77.143.7:9876`. Tailscale path from this sandbox to the Mini is not connecting.

3. **Filesystem-queue writes from sandbox don't reach the worker**
   Four submissions made from this session:
   - cmd-1779794292-5 (`echo HELLO_BRIDGE`)
   - cmd-1779794240-3 (`echo HELLO_FROM_QUEUE`)
   - cmd-1779794184-3 (`rm -f .git/index.lock`)
   - cmd-1779794073-3 (morning-report generator retry)
   - cmd-1779793827-3 (morning-report generator initial)

   All five disappeared from `kai/queue/pending/` after submission, but none appear in `completed/`, `failed/`, or `running/`. `kai/queue/worker.log` last activity is `2026-05-26T11:12:09Z IDLE: no pending commands` and the worker has not logged any of these submissions. Conclusion: the sandbox→Mini queue path is one-way broken right now — writes to `pending/` from the mount are not being observed by the worker on the Mini.

## Today's feed state
- `website/data/feed.json` `today` field: `2026-05-26`
- Latest morning-report entry: `morning-report-kai-2026-05-25-070000` (2026-05-25)
- No `morning-report-kai-2026-05-26-*` entry present.

## Required next-session actions (Mini-side)
1. `rm -f ~/Documents/Projects/Hyo/.git/index.lock` directly on the Mini.
2. Verify bridge daemon is running: `launchctl list | grep com.hyo.bridge` (or whatever label is used) — restart if dead.
3. Investigate why writes into `kai/queue/pending/` from the Cowork mount aren't being picked up by `worker.sh --watch` (fswatch may be ignoring mount-origin events).
4. Run `bash bin/generate-morning-report.sh` directly on the Mini to back-fill today's morning report onto HQ.
5. Open a P1 ticket on the queue/bridge path so this doesn't recur silently the next time a scheduled task runs from Cowork.

## Why the scheduled task couldn't self-correct
The task spec forbids running `generate-morning-report.sh` directly in the Cowork sandbox (stale data + no git push). With both queue paths down and no Mini access, the correct behavior was to surface the blocker rather than ship a bad report. This file is the surface.
