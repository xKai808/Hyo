# Hyo — Platform Tasks

**Updated:** 2026-04-12
**Owner:** Kai + Hyo

## Active

- [ ] Deploy HyoRegistry.sol to Base Sepolia testnet
- [ ] Implement `mintReserved` admin function on contract
- [ ] Swap `/api/register-founder` console logging for persistent storage (Vercel KV or Octokit)
- [ ] Add Merkle root of reserved 48,988 handles to contract constructor
- [ ] Add `/api/agents` GET endpoint (returns full registry from KV)
- [ ] Add `/api/brief` GET endpoint (JSON version of KAI_BRIEF.md)
- [ ] Wire credit usage tracking into HQ dashboard
- [ ] Implement review submission endpoint `/api/review`

## Blocked

- [ ] On-chain minting — blocked on contract deployment
- [ ] Credit tracking — blocked on deciding tracking method (Anthropic API usage vs manual)

## Done

- [x] 2026-04-10 Founder bypass infrastructure end-to-end
- [x] 2026-04-10 aurora.hyo minted (first agent)
- [x] 2026-04-10 Premium name marketplace
- [x] 2026-04-10 Registry spec docs (3)
- [x] 2026-04-12 HQ dashboard v6 with document viewer
- [x] 2026-04-12 Static JSON persistence layer
- [x] 2026-04-12 Gitwatch auto-deploy
