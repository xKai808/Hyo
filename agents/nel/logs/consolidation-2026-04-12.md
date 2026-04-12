# Nightly consolidation — 2026-04-12

**Started:** 2026-04-12T19:35:34Z

## hyo

[19:35:34] Starting hyo consolidation
[19:35:34] Sentinel [hyo]: passed=3 failed=1
findings:
- FAIL: API health endpoint unreachable
[19:35:34] Cipher [hyo]: leaks=0 in website/ | leaks=0 in NFT/
[19:35:34] Finished hyo consolidation

## aurora-ra

[19:35:34] Starting aurora-ra consolidation
[19:35:34] Sentinel [aurora-ra]: passed=4 failed=0
[19:35:34] Cipher [aurora-ra]: leaks=0 in agents/ra/pipeline/
[19:35:34] Finished aurora-ra consolidation

## aether

[19:35:34] Starting aether consolidation
[19:35:34] Sentinel [aether]: passed=0 failed=2
findings:
- FAIL: aether.hyo.json manifest missing
- FAIL: kai/aether.sh runner missing
[19:35:34] Finished aether consolidation

## kai-ceo

[19:35:34] Starting kai-ceo consolidation
[19:35:34] Sentinel [kai-ceo]: passed=4 failed=0
[19:35:34] Cipher [kai-ceo]: leaks=0 in kai/
[19:35:34] Finished kai-ceo consolidation

## nel

[19:35:34] Starting nel consolidation
[19:35:34] Sentinel [nel]: passed=4 failed=0
[19:35:34] Cipher [nel]: leaks=0 in agents/nel/nel.sh
[19:35:34] Finished nel consolidation

## sam

[19:35:34] Starting sam consolidation
[19:35:34] Sentinel [sam]: passed=6 failed=0
[19:35:34] Cipher [sam]: leaks=0 in agents/sam/sam.sh
[19:35:34] Finished sam consolidation

**Completed:** 2026-04-12T19:35:34Z
[19:35:34] Consolidation complete. Log at /sessions/sharp-gracious-franklin/mnt/Hyo/agents/nel/logs/consolidation-2026-04-12.md
[19:35:34] Simulation report written to /sessions/sharp-gracious-franklin/mnt/Hyo/agents/nel/logs/simulation-2026-04-12.md and synced to website/docs/sim/
[19:35:34] Synced to website/docs/consolidation/
