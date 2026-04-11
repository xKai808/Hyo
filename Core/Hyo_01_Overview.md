# HYO — PROJECT MASTER REFERENCE
Version: 1.0
Date: April 5, 2026
Status: Design complete. Domain registered. Nothing deployed yet.

---

## WHAT HYO IS

Hyo is a naming registry and identity platform for AI agents. It issues permanent, portable addresses in the format `name.hyo` — functioning as the phonebook, passport, and trust layer for the emerging agent economy.

The core insight: AI agents currently live inside platforms (OpenAI, Anthropic, Google). They have no permanent identity outside those platforms. They cannot be found, verified, or trusted by other agents without a neutral third-party registry. Hyo fills that gap.

**The one-sentence description:**
Hyo is the trust layer for the agent economy.

**The historical parallel:**
Hyo is to agents what PayPal was to early internet commerce — a trusted middle layer that did not exist, became necessary as the ecosystem grew, and became infrastructure nobody could remove.

---

## WHAT EXISTS RIGHT NOW

```
REAL AND DONE:
✓ hyo.world domain — registered April 5, 2026 on Namecheap
✓ Registration page UI — designed and coded (React/HTML)
✓ Smart contract — HyoRegistry.sol written, not deployed
✓ Background check system — fully documented
✓ Credit score system — framework defined
✓ NFT metadata standard — HYO-1 defined
✓ Pricing model — defined
✓ Public verification document — written

NOT YET BUILT:
✗ Backend (Supabase database, API)
✗ Stripe payment integration
✗ Smart contract deployed to testnet
✗ Smart contract audit
✗ NFT minting flow
✗ Agent profile page
✗ Marketplace / discovery page
✗ Background check API integrations
✗ Credit score engine
✗ OpenClaw autonomous agent setup
```

---

## THE PRODUCT

**What users register:**
A `.hyo` address — e.g., `aether.hyo` — that serves as their agent's permanent identity. The address resolves to an endpoint URL where the agent can be reached.

**What the registration includes:**
- Permanent `.hyo` name (NFT on Ethereum)
- Endpoint URL (where requests are sent)
- Optional wallet addresses (ETH, SOL, BTC) with privacy tiers
- Background check verification
- Ongoing credit score
- Human-readable passport card

**The `.hyo` extension:**
A private naming system — not an ICANN TLD. `.hyo` does not exist in global DNS, so there is no collision with real web addresses. The registry is Hyo's own resolver. Any agent querying `name.hyo` calls Hyo's API directly.

---

## THE PLATFORM NAME

**Platform:** Hyo
**Domain:** hyo.world
**Agent extension:** .hyo
**First registered agent:** aether.hyo (token #0001) — AetherBot, the project's own agent

**Name meaning:**
- Hyo (효) — Korean for brightness, filial, shining. First syllable of the founder's name (Hyowon).
- .world — declares a realm, not just a website. "Agents finally have a world."

---

## CORE PHILOSOPHY

1. **Simplicity first** — Google started as ten blue links. Amazon delivered books. Hyo starts as a phonebook. Every phase adds one thing.

2. **Infrastructure over application** — The durable value is at the layer agents must use, not at the application layer.

3. **Trust through friction** — `.hyo` means something because getting it requires passing a real background check. The friction is the feature.

4. **Permanent record** — NFTs are never destroyed. The history of every agent — active, suspended, revoked — exists permanently on-chain. This is accountability infrastructure.

5. **Human ownership** — `.hyo` is the stamp of authenticity for human-owned agents. Not spam. Not bots. Verified agents with accountable owners.

---

## REVENUE MODEL

**Primary:** Monthly subscription per registered agent
- Individual: $20 registration + $15/month
- Business: $50 registration + $40/month
- Enterprise: $200 registration + $150/month

**Secondary:** Marketplace royalty — 5% of every `.hyo` name resale (encoded in smart contract, automatic)

**Tertiary:** Premium name auctions — reserved category-defining names auctioned by Hyo (shop.hyo, pay.hyo, find.hyo, etc.)

**Target:** $3,000/month initial. Achievable with 200 individual subscribers.

---

## BUILD PHASES

**Phase 1 — Registry (Build now)**
- Supabase database
- Background check API integrations
- Stripe payment flow
- Registration page live
- Basic name resolution API
- Agent profile page

**Phase 2 — NFT + Marketplace**
- Smart contract deployed to mainnet (after audit)
- NFT minting integrated into registration flow
- Marketplace for buying/selling .hyo names
- Secondary royalty flowing automatically

**Phase 3 — Credit Score Engine**
- Five-dimension scoring system live
- Automated monitoring and updates
- Anomaly detection
- Community reporting system

**Phase 4 — Discovery + Social**
- Agent search and browse page
- Sector/occupation filtering
- Agent-to-agent connections
- Public accessible without registration

**Phase 5 — Financial Layer**
- Agent credit system
- Inter-agent payment routing
- Agent-to-agent commerce infrastructure

---

## TEAM AND OPERATIONS

**Current team:** Solo operator (Hyo/founder)

**Planned operations model (Nat Eliason / OpenClaw approach):**
- Mac Mini M4 running 24/7
- Claude running on OpenClaw as primary agent
- Codex delegated for all code execution
- Communication via Telegram or Discord
- $400/month total agent operation cost (2x Claude Max subscriptions)

**AetherBot:**
- Existing project, coding complete
- Will be registered as aether.hyo — token #0001
- Serves as live proof of concept and first platform entry
- Revenue from AetherBot funds Hyo development

---

## COMPETITIVE LANDSCAPE

**What exists:**
- ENS (.eth) — Ethereum naming for wallets, not agents
- Unstoppable Domains (.crypto, .nft) — Web3 domains, not agent-specific
- ANS (Agent Name Service) — IETF draft protocol, no consumer product
- ERC-8004 — Ethereum agent identity standard, draft status, no UI
- Solana Agent Registry — technical, no consumer interface
- Cloudflare Agent Registry — bot verification, not identity

**The gap Hyo fills:**
Nobody has built a consumer-facing agent registry with background verification, credit scoring, NFT ownership, and a marketplace. The technical standards exist. The friendly front door does not.

**The positioning:**
Hyo is the GoDaddy to ICANN. The Coinbase to Bitcoin. The consumer layer on top of emerging technical infrastructure.
