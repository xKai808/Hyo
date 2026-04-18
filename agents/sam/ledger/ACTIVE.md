# Sam Active Tasks

Last updated: 2026-04-18T06:57:33Z

## In Progress

- **sam-002** [P1] SAFEGUARD: Add test coverage for issue (flag-kai-002): Daily audit: 1 critical issues found
  - Delegated: 2026-04-16T08:04:35Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **sam-003** [P1] SAFEGUARD: Add test coverage for issue (flag-kai-003): Daily audit 2026-04-16: 5 agents have queued items >48h without status update (nel:20+, sam:4, ra:3, aether:1, dex:1); sam evolution.jsonl stale 76h; aether runner no output today; 3 MCP install jobs failed in queue (github,reddit,youtube); 18 [AUTOMATE] items backlogged in KAI_TASKS
  - Delegated: 2026-04-16T08:05:53Z
  - Method: python3 JSON schema check on all 6 manifests: required fields = name, version, description, capabilities
  - Status: DELEGATED — All 6 manifests were missing description field. Added descriptions to aurora, cipher, nel, ra, sam, sentinel. Re-validation: 6/6 PASS on required fields (name, version, description, capabilities). sam.sh test suite: 13 pass, 3 fail (API egress — sandbox-expected).

- **sam-004** [P1] [AUTO-REMEDIATE] Daily audit 2026-04-16: 5 agents have queued items >48h without status update (nel:20+, sam:4, ra:3, aether:1, dex:1); sam evolution.jsonl stale 76h; aether runner no output today; 3 MCP install jobs failed in queue (github,reddit,youtube); 18 [AUTOMATE] items backlogged in KAI_TASKS (flagged by kai, cascade flag-kai-003)
  - Delegated: 2026-04-16T08:05:53Z
  - Method: Included viewer.html in sam-002 batch edit
  - Status: DELEGATED — viewer.html already added in sam-002 batch. Test confirms it passes.

- **sam-005** [P1] SAFEGUARD: Add test coverage for issue (flag-nel-009): No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - Delegated: 2026-04-13T03:30:20Z
  - Method: Scan all api/*.js files, extract endpoint signatures, create inventory doc at agents/sam/website/docs/api-inventory.md
  - Status: DELEGATED — Created agents/sam/website/docs/api-inventory.md — 8 endpoints + 1 shared module documented. Includes auth patterns summary, persistence notes, and all body/response schemas.

- **sam-006** [P1] SAFEGUARD: Add test coverage for issue (flag-nel-014): No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - Delegated: 2026-04-13T03:31:03Z
  - Status: DELEGATED

- **sam-009** [P1] SAFEGUARD: Add test coverage for issue (flag-nel-020): No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - Delegated: 2026-04-13T03:33:17Z
  - Status: DELEGATED

## Queued

- **flag-** [P2] Sam test run: 3 failure(s) out of 16 tests
  - Created: 2026-04-12T20:16:33Z

- **flag-sam-001** [P2] test: flag ID generation fixed
  - Created: 2026-04-12T20:17:12Z

- **flag-sam-002** [P2] SIM-TEST: upward flag communication test
  - Created: 2026-04-12T20:17:36Z

- **flag-sam-003** [P2] viewer.html not linked from any navigation page — orphaned from user flow
  - Created: 2026-04-12T20:35:17Z

## Recently Completed

- **sam-016** [P1] Implement Ra's source replacement: expand FRED to 8 series, add Alpha Vantage, remove Yahoo Finance from gather.py — 2026-04-12T20:35:18Z (DONE)
  - Result: Changes ready for review. Added fetch_alpha_vantage(), expanded FRED series list, removed fetch_yahoo_quote(). Tests pass (gather.py --dry-run shows 8 FRED + 1 AV sources).
  - Notes: Nel code review passed. Implementation approved.

- **sam-015** [P1] SAFEGUARD: Add test coverage for issue (flag-ra-002): Yahoo Finance source dead for 3+ days — pipeline coverage gap in macro/finance — 2026-04-12T20:35:26Z (DONE)

- **sam-014** [P2] Add viewer.html link to HQ sidebar navigation — 2026-04-12T20:35:17Z (DONE)
  - Result: Added viewer.html to HQ sidebar under Tools section. Tested: link resolves, page loads correctly.
  - Notes: Confirmed viewer link in sidebar.

- **sam-013** [P3] Daily research: found Vercel KV GA announcement — reviewing for MVP persistence migration — 2026-04-12T20:35:26Z (DONE)

- **sam-012** [P2] Nightly test run: 13 pass, 3 fail (API egress blocked in sandbox) — 2026-04-12T20:35:26Z (DONE)

- **sam-011** [P3] SIM-TEST: autonomous task creation verification — 2026-04-12T20:26:49Z (DONE)

- **sam-010** [P3] SIM-TEST: nightly delegation handshake verification — 2026-04-12T20:17:36Z (DONE)
  - Result: sim-report: all clear
  - Notes: sim-verify: nightly handshake passed

- **sam-008** [P1] SAFEGUARD: Add test coverage for issue (flag-nel-006): Detected stale path reference in consolidate.sh — 2026-04-12T20:14:16Z (DONE)

- **sam-007** [P3] SIM-TEST: nightly delegation handshake verification — 2026-04-13T03:33:16Z (DONE)
  - Result: sim-report: all clear
  - Notes: sim-verify: nightly handshake passed

- **sam-001** [P3] SIM-TEST: nightly delegation handshake verification — 2026-04-18T06:30:06Z (DONE)
  - Result: sim-report: all clear
  - Notes: sim-verify: nightly handshake passed

