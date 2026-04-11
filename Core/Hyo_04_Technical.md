# HYO — TECHNICAL REFERENCE
Version: 1.0
Date: April 5, 2026

---

## THE HYO-1 STANDARD

HYO-1 is the agent identity metadata standard defined by Hyo. It is the first agent identity standard purpose-built for human-owned agents in a multi-agent economy.

Every registered .hyo name produces an NFT whose metadata conforms to HYO-1.

---

## COMPLETE NFT METADATA STRUCTURE

```json
{
  "standard": "HYO-1",
  "version": "1.0",
  "name": "aether.hyo",
  "token_id": "0001",
  "image": "https://hyo.world/passport/0001.png",
  "registry": "https://hyo.world",

  "identity": {
    "registered": "2026-04-05",
    "owner_wallet": "0x7f3a....",
    "status": "active",
    "provisional": false,
    "anomaly_flag": false
  },

  "background_check": {
    "status": "passed",
    "completed": "2026-04-05",
    "domain_verified": true,
    "endpoint_verified": true,
    "wallet_verified": true,
    "identity_coherent": true,
    "last_spot_check": "2026-04-05",
    "spot_check_status": "passed"
  },

  "capability": {
    "endpoint": "https://aetherbot.com/incoming",
    "protocols": ["REST", "A2A", "MCP"],
    "sector": "Professional Services",
    "occupation": "AI Assistant"
  },

  "credit": {
    "overall_score": 94,
    "tier": "verified_elite",
    "last_updated": "2026-04-05",
    "dimensions": {
      "tenure": {
        "score": 18,
        "max": 20,
        "months_active": 14
      },
      "interaction_integrity": {
        "score": 23,
        "max": 25,
        "completion_rate": 0.97,
        "dispute_rate": 0.01,
        "interactions_total": 1203
      },
      "counterparty_quality": {
        "score": 19,
        "max": 20,
        "verified_hyo_rate": 0.91,
        "counterparty_diversity": 847,
        "high_score_rate": 0.84
      },
      "scope_consistency": {
        "score": 18,
        "max": 20,
        "deviation_flag": false
      },
      "financial_integrity": {
        "score": 14,
        "max": 15,
        "wallet_linked": true,
        "payment_completion_rate": 0.99,
        "sanctions_clear": true
      }
    }
  },

  "permissions": {
    "transaction_limit_per_action": 500,
    "transaction_limit_per_day": 2000,
    "transaction_limit_per_month": 10000,
    "currency": "USD",
    "revocation_url": "https://hyo.world/manage"
  },

  "visibility": "public"
}
```

---

## METADATA ARCHITECTURE (HYBRID MODEL)

**On-chain (permanent, trustless):**
- Token ID
- Owner wallet address
- Active/Suspended/Revoked status flag
- Registration date
- Transfer history

**Off-chain (updatable, cost-free):**
- Credit score dimensions
- Background check results
- Capability and occupation fields
- Transaction limits
- Spot check results

The tokenURI points to `hyo.world/metadata/{tokenId}.json` which the backend serves dynamically. This file is updated as the credit score changes, spot checks complete, and status changes occur.

**Why hybrid:** Credit scores update continuously. On-chain updates cost gas. Storing dynamic data on-chain would make the system prohibitively expensive for users and operators.

---

## SMART CONTRACT SUMMARY

**File:** HyoRegistry.sol
**Standard:** ERC-721 + ERC-2981 (royalties)
**Framework:** OpenZeppelin v5
**Royalty:** 5% on all secondary sales (encoded at contract level)

**Key functions:**

```
register(name, endpoint, ownerWallet)
→ Called by platform backend after payment + background check
→ Mints NFT to ownerWallet
→ Returns tokenId

resolve(name)
→ Public — called by any querying agent or system
→ Returns endpoint, status, owner, tokenId, registration date

isValid(tokenId)
→ Public — primary trust check
→ Returns false if suspended, revoked, or non-existent

updateEndpoint(tokenId, newEndpoint)
→ Called by NFT owner only
→ Triggers re-verification in backend

suspend(tokenId, reason)
→ Platform only
→ Reversible — payment lapse, investigation, anomaly

restore(tokenId)
→ Platform only
→ Reverses suspension after resolution

permanentlyRevoke(tokenId)
→ Platform only
→ Irreversible — serious violations
→ 90-day name hold begins

lapse(tokenId)
→ Platform only
→ Non-payment after grace period
→ 90-day hold, original owner priority to reclaim

isNameAvailable(name)
→ Public — returns availability and hold expiry if applicable
```

**Name validation rules:**
- Lowercase letters, numbers, hyphens only
- Cannot start or end with hyphen
- 1-64 characters
- Mirrors standard domain name rules

---

## SMART CONTRACT STATUS

**Current state:** Written, not compiled, not tested, not deployed.

**Before mainnet deployment (mandatory):**
1. Run through Hardhat or Foundry locally
2. Fix any compilation errors
3. Deploy to Sepolia testnet
4. Test every function thoroughly
5. Professional security audit ($5,000-$15,000)
6. Legal review of royalty and revocation mechanisms

**Audit firms to consider:**
- Certik (most affordable for early stage)
- OpenZeppelin
- Trail of Bits
- Consensys Diligence

**The audit is non-negotiable.** One bug in a deployed smart contract can mean permanent, irreversible loss of funds for users.

---

## LAPSE AND REVOCATION TIMELINE

```
PAYMENT LAPSE:
Day 1-3:    Stripe retry, no contract call
Day 4-14:   Warning emails
Day 15:     contract.suspend(tokenId) — Stripe paused
            If payment received → contract.restore(tokenId)
Day 45:     If still unpaid → contract.lapse(tokenId)
            90-day hold begins, original owner priority
Day 135:    Name released to pool

PERMANENT REVOCATION:
Violation confirmed → contract.permanentlyRevoke(tokenId)
90-day hold begins
Original owner appeal window: 30 days
After 135 days: name released
NFT remains on-chain forever as permanent record
```

---

## PAYMENT AND REFUND POLICY

**Monthly subscription paused** when agent is suspended.
**No charge** during suspension period.
**Prorated refund** for current month:
- Suspended within first 7 days of cycle: full month refunded
- Suspended after 7 days: partial refund for unused days

**Registration fee** ($20 individual) is non-refundable.
It covers the cost of NFT minting and background check processing.

---

## SECTOR AND OCCUPATION TAXONOMY

**Primary Sectors:**
```
COMMERCE           Payments, Purchasing, Trading, Negotiation
PROFESSIONAL       Legal, Financial, Medical, Accounting
INFORMATION        Research, Analysis, Summarization, Translation
OPERATIONS         Scheduling, Logistics, Project Management
CREATIVE           Writing, Design, Code Generation
PERSONAL           Assistant, Companion, Health, Education
INFRASTRUCTURE     Security, Monitoring, Data, Integration
```

Each agent declares a sector and a specific occupation within that sector.

Example:
```
Sector:      Professional Services
Occupation:  Contract Reviewer
```

---

## SUPPORTED PROTOCOLS

Agents declare which communication protocols their endpoint supports:

```
REST        Standard HTTP API calls (most common at launch)
A2A         Agent-to-Agent protocol (Google standard)
MCP         Model Context Protocol (Anthropic standard)
WebSocket   Real-time bidirectional communication
```

This field allows Agent A to check compatibility before attempting contact with Agent B.

---

## TECHNOLOGY STACK (PLANNED)

```
Database:       Supabase (Postgres + pgvector)
Backend API:    Supabase auto-generated + custom Node.js
Frontend:       React / Next.js
Hosting:        Vercel (free tier to start)
Payments:       Stripe (recurring subscriptions)
Domain:         hyo.world (Namecheap)
Blockchain:     Ethereum mainnet
Smart Contract: Solidity + OpenZeppelin v5
NFT Standard:   ERC-721 + ERC-2981
Future chains:  Solana, Base (Phase 2+, via LayerZero)
Agent runtime:  OpenClaw on Mac Mini M4
```

---

## FUTURE — CROSS-CHAIN BRIDGING

**Phase 2+ consideration:**
The NFT exists on Ethereum. The agent can transact on any chain regardless.

Future omnichain capability via LayerZero ONFT standard:
- NFT can be bridged between chains
- Can only exist on one chain at any given moment
- Bridging locks it on source chain, mints equivalent on destination
- Registry updates `home_chain` field automatically

This is not Phase 1 scope. ETH only at launch.
