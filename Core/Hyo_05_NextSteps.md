# HYO — NEXT STEPS AND OPEN QUESTIONS
Version: 1.0
Date: April 5, 2026

---

## WHAT WAS ACCOMPLISHED TODAY (April 5, 2026)

In one working session, the following was designed and documented:

- Platform named (Hyo), domain registered (hyo.world, $2.48)
- .hyo private extension declared
- Registration UI built (React/HTML, functional)
- Background check system designed and documented (6 layers, decision matrix, known attack vectors)
- Credit score system designed (5 dimensions, tier structure, update frequency)
- NFT metadata standard defined (HYO-1)
- Smart contract written (HyoRegistry.sol, ERC-721 + ERC-2981)
- Pricing model defined (3 tiers, psychology-informed)
- Public verification document written
- Competitive landscape researched
- Nat Eliason / OpenClaw operations model researched and planned

---

## IMMEDIATE NEXT STEPS (In Order)

### Step 1 — AetherBot Revenue (This Week)
AetherBot is the existing project with completed code. It needs to generate revenue to fund Hyo development. Before spending more time on Hyo infrastructure, clarify what AetherBot does and what it needs to start making money.

**Open question:** What does AetherBot currently do and what does it need to generate consistent revenue?

### Step 2 — Supabase Database (Week 1-2)
Set up the Hyo database. One table to start.

```sql
TABLE: agents
  agent_name       TEXT PRIMARY KEY
  endpoint_url     TEXT NOT NULL
  owner_email      TEXT NOT NULL
  wallet_eth       TEXT
  wallet_sol       TEXT
  wallet_btc       TEXT
  wallet_visibility TEXT DEFAULT 'private'
  status           TEXT DEFAULT 'active'
  created_at       TIMESTAMP DEFAULT NOW()
  verified         BOOLEAN DEFAULT FALSE
  nft_minted       BOOLEAN DEFAULT FALSE
  token_id         INTEGER
  provisional      BOOLEAN DEFAULT FALSE
  sector           TEXT
  occupation       TEXT
  protocols        TEXT[]
```

### Step 3 — Stripe Integration (Week 2)
Set up three products:
- Individual: $20 one-time + $15/month
- Business: $50 one-time + $40/month
- Enterprise: $200 one-time + $150/month

Payment confirmation triggers database entry.
Failed payment triggers suspension flow (15-day grace period).

### Step 4 — Registration Page Live (Week 2-3)
Connect the existing UI to Supabase + Stripe.
No NFT minting yet — centralized database only.
Get to a working registration flow first.

### Step 5 — Background Check API Integrations (Week 3-4)
- Google Safe Browsing API (free, register for key)
- Whois lookup API ($50-100/month)
- Etherscan API (free, register for key)
- Spamhaus (free at low volume)
Build the decision engine that runs all checks automatically.

### Step 6 — First Registrations
Get 10 developers to register as beta users.
Learn what breaks. Learn what confuses people.
This data validates the concept before spending on smart contract work.

### Step 7 — Smart Contract Testnet (Month 2)
Deploy HyoRegistry.sol to Sepolia testnet.
Test every function.
Fix compilation errors and edge cases.

### Step 8 — Smart Contract Audit (Month 2-3)
Budget: $5,000-$15,000
Start with Certik for early-stage affordability.
Do not deploy to mainnet without this.

### Step 9 — Mainnet + NFT Minting (Month 3-4)
After audit passes, deploy to Ethereum mainnet.
Integrate minting into registration flow.
Existing registrations migrated to NFTs (retroactive minting).
aether.hyo minted as token #0001.

### Step 10 — OpenClaw Operations Setup (Month 2-3)
Mac Mini M4 ($599) — not Mac Neo.
OpenClaw installed.
Claude running 24/7.
Telegram or Discord command channel set up.
Three-layer memory system configured for Hyo project context.
Codex integrated for code execution.

---

## OPEN DECISIONS (Not Yet Made)

**1. What chain for NFT?**
Decision: Ethereum mainnet.
Rationale: Most credible for ownership assets, ENS precedent.
Status: Decided.

**2. Royalty percentage?**
Decision: 5% (encoded as ROYALTY_FEE = 500 in contract).
Status: Decided.

**3. Metadata storage?**
Decision: Hybrid (Option A) — ownership on-chain, dynamic data off-chain.
Status: Decided.

**4. Which reserved names to hold before launch?**
Status: NOT YET DECIDED. Must decide before public launch.
Suggested categories: pay.hyo, find.hyo, shop.hyo, send.hyo, book.hyo, legal.hyo, medical.hyo, trade.hyo.
Register these under your own account before opening registration.

**5. Technical co-founder?**
The full build requires development skills beyond what's achievable solo.
Smart contract + backend integration + security are the critical gaps.
With a working MVP and paying customers, equity partnership becomes realistic.
Status: Consider after first 10 paying users.

**6. AetherBot integration?**
AetherBot becomes aether.hyo — token #0001, the platform's proof of concept.
What AetherBot does and how it earns revenue is the funding mechanism.
Status: Define AetherBot's revenue model before anything else.

---

## THINGS TO BUILD (Full List)

### Phase 1 (Core Registry)
- [ ] Supabase database schema
- [ ] Background check API integrations
- [ ] Stripe payment integration (3 tiers)
- [ ] Registration page backend connection
- [ ] Basic name resolution API endpoint
- [ ] Agent profile page
- [ ] Suspension/restoration flow
- [ ] Email notification system
- [ ] Admin dashboard (manual review queue)

### Phase 2 (NFT)
- [ ] Smart contract testnet deployment
- [ ] Smart contract audit
- [ ] Smart contract mainnet deployment
- [ ] NFT minting integrated into registration
- [ ] Metadata JSON generation and hosting
- [ ] Passport image generation (aether.hyo card)
- [ ] Retroactive minting for Phase 1 registrations

### Phase 3 (Marketplace)
- [ ] Name listing flow
- [ ] Buy/sell interface
- [ ] Automated ownership transfer on sale
- [ ] Royalty distribution verification
- [ ] Premium name auction system

### Phase 4 (Credit Score Engine)
- [ ] Five-dimension calculator
- [ ] Update scheduler (real-time/daily/weekly/monthly)
- [ ] Anomaly detection system
- [ ] Remediation pathway generator
- [ ] Score history storage
- [ ] Owner notification system

### Phase 5 (Discovery)
- [ ] Agent search and browse page
- [ ] Sector/occupation/tier filtering
- [ ] Public access without registration
- [ ] Agent-to-agent connection requests
- [ ] Featured listings (premium placement)

### Phase 6 (Operations)
- [ ] Mac Mini M4 setup
- [ ] OpenClaw installation
- [ ] Claude agent configured with Hyo project memory
- [ ] Telegram/Discord command channel
- [ ] Codex delegation workflow
- [ ] Heartbeat monitoring
- [ ] Cron job scheduling

---

## MEMORY CONTEXT FOR FUTURE SESSIONS

When starting a new conversation about this project, upload these files:
1. Hyo_01_Overview.md
2. Hyo_02_BackgroundCheck.md
3. Hyo_03_CreditScore.md
4. Hyo_04_Technical.md
5. Hyo_05_NextSteps.md (this file)
6. HyoRegistry.sol (the smart contract)
7. HyoRegistry_Notes.md (deployment notes)

State at the start: "I am working on Hyo (hyo.world), an agent registry platform. The attached documents contain the complete project context. Pick up where we left off."

---

## KEY NUMBERS TO REMEMBER

```
Domain registered:      hyo.world ($2.48, April 5 2026)
Registration fee:       $20 individual / $50 business / $200 enterprise
Monthly fee:            $15 / $40 / $150
Royalty:               5% secondary sales
Revenue target:         $3,000/month initial
Users needed at $15:    200 individual subscribers
Smart contract audit:   $5,000-$15,000 (mandatory)
Operations cost:        $400/month (2x Claude Max)
Mac Mini M4:           $599 (preferred over Mac Neo for 24/7 operation)
Token #0001:           aether.hyo (AetherBot)
```

---

## HONEST ASSESSMENT OF WHERE THINGS STAND

The intellectual infrastructure is solid. The thinking is coherent. The documents are real.

The gap between these documents and a working product is significant. Key honest constraints:

1. No code has been compiled or tested
2. No backend exists
3. No paying users exist
4. Smart contract needs a developer, testnet deployment, and audit
5. The full vision requires either technical learning, hiring, or a co-founder

The right path: validate demand with a simple centralized registration system first. That costs two weeks of work and $0 in additional investment. If people register and pay, the project is real and deserves the investment in smart contracts and audits.

AetherBot generating revenue is the most important near-term milestone. That revenue funds everything else.
