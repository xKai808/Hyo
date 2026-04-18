# Nel Active Tasks

Last updated: 2026-04-17T18:45:36-0600

## In Progress

- **nel-cve-track-001** [P1] Track CVE-2026-33032 and CVE-2026-34197 — check NVD in 48h for package mapping
  - Created: 2026-04-17T18:45:36-0600
  - Method: Check https://nvd.nist.gov for package info, cross-ref against requests/cryptography/node
  - Status: OPEN

- **nel-snyk-002** [P1] Integrate pip-audit or snyk into nel.sh QA cycle for automated dep scanning
  - Created: 2026-04-17T18:45:36-0600
  - Method: Add pip-audit --dry-run to sentinel phase, output to nel-qa log
  - Status: OPEN

- **nel-rate-limit-upgrade** [P2] Upgrade in-memory rate limiting to Vercel KV for cross-lambda consistency
  - Created: 2026-04-17T18:45:36-0600
  - Status: QUEUED — waiting on Vercel KV budget approval

## Recently Completed

- **nel-security-2026-04-17** [P1] API security vulnerabilities — SHIPPED 2026-04-17T18:45:36-0600
  - Fixed: removed hq-fallback-secret hardcoded fallback (silent downgrade risk)
  - Fixed: added rate limiting to auth endpoint (10 req/60s per IP, 429 on breach)
  - CVE cross-reference: CVE-1999-0095 not applicable, Node v22.22.0 patched, Python deps current
  - Verified: code review passed, published report to HQ feed
