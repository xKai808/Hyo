# Daily Bottleneck Audit — 2026-06-01 (Monday)

**Auditor:** Kai (scheduled `kai-daily-audit`, Cowork sandbox)
**Method:** File-tool read pass. `daily-audit.sh` and `dispatch.sh` could NOT run — see Tooling Blocker.
**Verdict:** System is in a chronic, self-reinforcing dead-loop. No new root causes since ~2026-05-06; the same five structural breaks remain unresolved 14–27 days later. **Needs Hyo intervention on the Mini** — autonomous remediation is structurally unable to fix dead launchd plists.

---

## 0. Tooling blocker (why the script didn't run)

The Cowork Linux sandbox failed to boot on every `bash` attempt:

```
useradd: cannot create directory /sessions/sharp-great-volta  (exit 12)
```

This is the same harness fault logged across 60+ prior sandbox-fired scheduled runs (documented through 2026-05-29 in KAI_TASKS). Consequence for this run:
- `kai/queue/daily-audit.sh` — could not execute (needs bash).
- `bin/dispatch.sh flag …` — could not execute (needs bash). **No flags were dispatched this run.** The findings below must be flagged from the Mini.
- All findings below were gathered by reading source files directly via the file tools, which hit the real filesystem and are reliable.

Authoritative audit continues to run on the Mini via the daily plist; this sandbox run is supplemental.

---

## 1. Headline: the data layer is 27 days stale

| File | Last written | Age | Pipeline that feeds it |
|---|---|---|---|
| `kai/ledger/verified-state.json` | 2026-05-05T18:59 | **~27 days** | `kai-session-prep.sh` (should run every 15 min) |
| `kai/ledger/session-handoff.json` | 2026-05-05T18:59 | **~27 days** | `kai-session-prep.sh` |

`kai-session-prep.sh` has not written since 2026-05-05. The "single authoritative source of current state" (per CLAUDE.md VERIFIED STATE RULE) is dead. Every session that boots and trusts these files is operating on 27-day-old truth. This was flagged daily from `flag-kai-005` (05-06) through `flag-kai-022` (05-18) and never resolved.

Note: agent `ACTIVE.md` files ARE current (all stamped 2026-06-01T07:59:5x by the morning sweep) — so the agent runners and the cascade dispatcher are alive. It is specifically the `kai-session-prep.sh` state-precompute and several other plists that are dead.

---

## 2. P0/P1 structural bottlenecks (all chronic, none resolved)

### B1 — DELEGATED→DONE transition is broken system-wide (the meta-bug)
No agent's `[AUTO-REMEDIATE]` / `SAFEGUARD` ticket ever transitions out of `DELEGATED`. The cascade dispatcher fires, agents ACK `DELEGATED`, work never completes, flags accrete forever. Self-named in `flag-kai-020` / `aether-003` / `sam-005`.
Longest-stuck examples (all still `DELEGATED` today):
- `nel-006` — since 2026-05-06 (**~26 days**)
- `sam-005` / `aether-002` / `aether-003` / `nel-005` — since 2026-05-17 (**~15 days**)
- `dex-002` — since 2026-05-23 (**~9 days**)
- `ra-002/003/004`, `sam-002/003/004`, `nel-002/003/004` — 05-27 to 05-29 (3–5 days)

**Fix the system already specified (still not built):** a pathway-closer daemon, OR each runner must call `dispatch close` on completion. Until this lands, every flag is a one-way street and all audit metrics grow without bound. **This is the single highest-leverage fix in the system** — it unblocks B2 and the entire backlog.

### B2 — Ra newsletter pipeline dark since 2026-05-05 (~27 days)
No newsletter has rendered since 2026-05-05. Gather works (`.input.md` files keep landing); the render phase silently fails. The `[AUTO-REMEDIATE]` cascades (`ra-002/003/004`) are **no-ops** — they record `DELEGATED` but never produce a newsletter (blocked by B1). Root ticket: `TASK-20260421-ra-P0-runner-exit2`. This is the longest-running real P0 in the system.
Also note two mis-targeted sentinel checks (documented but un-fixed for 3+ weeks): `aurora-ran-today` tests `newsletters/${TODAY}.md` (a path Ra never produces — should proxy `agents/ra/output/YYYY-MM-DD.html` mtime <25h); `scheduled-tasks-fired` greps `aurora-*.log` (none since 2026-04-11 — pure false positive).

### B3 — hyo-inbox.jsonl flooded — real Hyo messages are unfindable
`dex-002`: `kai/ledger/hyo-inbox.jsonl` ballooned to **52,616 lines / 14.7MB**, of which ~52,588 are SLA-breach auto-spam. `weekly-maintenance.sh` (which trims the inbox) has been **dead since 2026-04-25** — contradicting the CLAUDE.md claim that it runs every Saturday 02:00. Root cause is B1: the never-closing TASK-20260505-* tickets re-spam the inbox forever. **Any genuine Hyo message is currently buried.**

### B4 — Aether kill-switch causes permanent false flags
`aether-002`: Aether KILL-SWITCH has been active since 2026-05-13 (Hyo refused `aether.sh`), but `daily-audit.sh` still flags "no runner output" and a false "evolution.jsonl 80h stale" (the file never existed). The audit script must read the kill-switch / skip-stamp and stop flagging a deliberately-stopped agent.

### B5 — daily-audit.sh HYO_ROOT path bug
`flag-kai-009/011/013/014`: when run outside the Mini, `daily-audit.sh` defaults to `$HOME/Documents/Projects/Hyo`, which doesn't exist in the sandbox, producing 5 phantom FAIL / 8 phantom GAP entries. Needs an `export HYO_ROOT` / `cd $ROOT` guard at the top of the script (or the SKILL.md task must set it). Proposed 2026-05-10, still un-fixed.

### B6 — Dex recurrent-pattern count climbing
`kai-001` (today): Dex Phase 4 reports **622 recurrent patterns** (up from 615). Detection without remediation — needs a root-cause fix, not more counting.

---

## 3. Stale items >48h without status update

Effectively the entire Kai and per-agent In-Progress + Queued lists. Every `[AUTO-REMEDIATE]`/`SAFEGUARD` item is 3–26 days old and still `DELEGATED` (B1). Queued flags `flag-nel-001..018`, `flag-kai-001..023`, `flag-sam-001`, `flag-ra-001`, `flag-aether-001`, `flag-dex-001` date from 2026-05-05/06/22 and are untouched. The last-known `verified-state.json` (05-05) already listed 9 stale tickets and 50+ open P0s; that snapshot has only grown since.

## 4. [NEEDS HYO] — physical / credential actions only Hyo can do
1. **Run `launchctl list | grep com.hyo` on the Mini** and restart the dead plists — at minimum `kai-session-prep`, `weekly-maintenance`, the Ra render trigger, `session-close`, and the dispatch-sync. This is the unblock for B1/B2/B3 and the 27-day state staleness.
2. `RESEND_API_KEY` → Vercel env (Aurora retention email).
3. Stripe webhook endpoint registration + confirm `STRIPE_WEBHOOK_SECRET`.
4. bore.pub tunnel down (`S18-013`) — Kai cannot reach the Mini via the queue; filesystem fallback only.
5. Real OpenAI API key (`HYO-REQUIRED-001`).

## 5. Automation gaps open >7 days (de facto >40 days)
Lychee + TruffleHog + Semgrep install (Nel QA), Vercel KV migration (Sam W2), Sam launchd trigger, Aurora → Mini launchd migration. All pre-session-17, still open.

---

## 6. Actions taken / not taken this run
- **Taken:** Full read-pass audit; this report written to `kai/ledger/daily-audit-2026-06-01.md`.
- **NOT taken (bash down):** `daily-audit.sh` did not run; no `dispatch flag` calls were made; no commit/push. Flags B1–B6 must be raised from the Mini.
- **Deliberately skipped:** did not hand-edit `kai/ledger/ACTIVE.md`. It is regenerated by the runner/dispatch system (stamped 07:59:58Z today); a manual sandbox write would create exactly the dual-write drift the audit is meant to catch. Audit findings live in this dated report instead.

## 7. One recommendation, ranked
**Build the pathway-closer for B1 first.** It is the keystone: B2 (newsletter no-op), B3 (inbox flood), and the entire stale-ticket backlog all stem from `DELEGATED` never closing. Every other fix is downstream of it. Second: restart the dead plists on the Mini (Hyo, §4.1) to stop the 27-day state staleness. Everything else is noise until those two land.
