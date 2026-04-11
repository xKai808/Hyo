# HYO REGISTRY — DEPLOYMENT & INTEGRATION NOTES
Version: 1.2.0
Date: April 2026

**Change log**
- **1.2.0 (2026-04-10)** — added four subsystems: founder registration
  bypass (hyo-operator agents pay no fees and mint to any tier including
  reserved premium handles); credit system (four tiers, unlock gates by
  time + volume + diversity, escrow with dispute reserve fund); premium
  name marketplace (1/2/3-letter handles held by registry, auction +
  fixed-price); review system (dual-output customer trust signal +
  operator feedback export, anti-fatigue rules, credit score integration).
  Contract requires two new admin functions: `mintReserved` and
  `holdHandle` (or Merkle-root approach). Full specs live in companion
  docs — see "Companion specs" section below.
- **1.1.0 (2026-04-10)** — target chain switched to Base; added
  Stripe-sponsored gas section. No contract code changes required;
  the existing platform-as-caller architecture already supports
  sponsored gas natively once deployed on an L2.
- **1.0.0 (2026-04-05)** — initial notes

---

## COMPANION SPECS

These four documents together define the full registry behavior. This
file covers deployment and the base contract; the companions cover the
four subsystems layered on top.

- `HyoRegistry_CreditSystem.md` — four-tier credit ladder, unlock gates,
  escrow, dispute reserve fund, credit score composition, on-chain vs
  off-chain split.
- `HyoRegistry_Marketplace.md` — premium name reserve (48,988 handles
  held at genesis), auction and fixed-price mechanics, revenue split
  (40% buyback pool / 40% dispute reserve / 20% operations), Merkle-tree
  reserved handle check.
- `HyoRegistry_Reviews.md` — dual-output review system, 5-star rating
  with optional text and tags, anti-fatigue rules, recency-weighted
  quality factor, operator JSON/CSV/webhook export, sybil and
  collusion defenses.
- `agents/` — directory of agent manifests. `aurora.hyo.json` is the
  first entry. Use as template for future Hyo-operated agents.

## FOUNDER REGISTRATION BYPASS

Hyo-operated agents (`operator === "hyo"`) must skip the standard
Stripe-gated registration flow entirely. The website ships a
`founder-register.html` page that:

- Validates a founder token server-side (env var `HYO_FOUNDER_TOKEN`,
  never hardcoded in the HTML).
- Allows claiming reserved premium handles (1/2/3-letter) that the
  public flow rejects.
- Assigns the agent to any initial tier including `founding` (a pseudo
  tier that bypasses probation and pays zero platform fees).
- POSTs to `/api/register-founder` instead of `/api/checkout`.
- Calls `contract.mintReserved()` with a signed transaction from the
  platform wallet, sponsoring the gas as usual.

The token is verified by a single backend check:
`req.body.token === process.env.HYO_FOUNDER_TOKEN`. Rotate quarterly.
The page also validates client-side length (>=16 chars) so obviously
invalid submissions don't reach the backend.

This is how `aurora.hyo` and all future internal agents get minted.
The public registration flow is unchanged; the founder flow is an
entirely separate page with its own route and its own backend endpoint.

---

## BEFORE DEPLOYMENT

### Mandatory Steps
1. Professional security audit — budget $5,000-$15,000
2. Testnet deployment and full function testing (Sepolia)
3. Integration testing with backend API
4. Legal review of royalty and revocation mechanisms

### Dependencies
Install OpenZeppelin v5:
```
npm install @openzeppelin/contracts
```

---

## CONSTRUCTOR PARAMETERS

```
platformAddress   → Your backend server's ETH wallet
                    This wallet calls admin functions
                    (suspend, restore, revoke, lapse, register)

royaltyReceiver   → Wallet that receives 5% secondary sale royalties
                    Can be your personal wallet or a multisig

baseURI           → URL prefix for metadata JSON files
                    Example: "https://hyo.world/metadata/"
                    Token #1 resolves to: https://hyo.world/metadata/1.json
```

---

## BACKEND INTEGRATION FLOW

### Registration Flow
```
1. User submits registration form
2. Stripe payment confirmed
3. Background check passes all layers
4. Backend calls: contract.register(name, endpoint, ownerWallet)
5. NFT minted to ownerWallet
6. Backend stores tokenId → Supabase record
7. Metadata JSON generated at baseURI/tokenId.json
8. Email confirmation sent to user
```

### Suspension Flow (Payment Lapse)
```
Day 1-3:   Stripe retry — no contract call
Day 4-14:  Warning emails — no contract call
Day 15:    Backend calls: contract.suspend(tokenId, "Payment lapse")
           Stripe subscription paused
Day 15+:   If payment received:
           Backend calls: contract.restore(tokenId)
           Stripe subscription resumed
           Prorated refund if applicable
Day 45:    If still unpaid:
           Backend calls: contract.lapse(tokenId)
           90-day hold begins
           Name held for original owner
Day 135:   Name released to pool
           Backend clears hold records
```

### Revocation Flow (Violation)
```
Violation confirmed by human review
→ Backend calls: contract.permanentlyRevoke(tokenId)
→ Name enters 90-day hold
→ Owner notified with appeal window
→ After 135 days: name released
```

---

## METADATA JSON STRUCTURE

Each tokenId maps to a JSON file at {baseURI}/{tokenId}.json

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
    "owner_wallet": "0x...",
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
      "tenure": { "score": 18, "max": 20, "months_active": 14 },
      "interaction_integrity": {
        "score": 23, "max": 25,
        "completion_rate": 0.97, "dispute_rate": 0.01,
        "interactions_total": 1203
      },
      "counterparty_quality": {
        "score": 19, "max": 20,
        "verified_hyo_rate": 0.91,
        "counterparty_diversity": 847
      },
      "scope_consistency": { "score": 18, "max": 20, "deviation_flag": false },
      "financial_integrity": {
        "score": 14, "max": 15,
        "wallet_linked": true,
        "payment_completion_rate": 0.99,
        "sanctions_clear": true,
        "transaction_limit_per_action": 500,
        "transaction_limit_per_day": 2000,
        "transaction_limit_per_month": 10000,
        "currency": "USD"
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

## KEY DESIGN DECISIONS

### Why platform address controls admin functions
The platform backend (not individual users) calls suspend/restore/revoke.
This is intentional — these are business decisions backed by the
background check system, payment processor, and credit score engine.
The platform address should be a secure server wallet, not a personal wallet.

### Why NFTs are never destroyed
Revoked tokens remain on-chain permanently as a historical record.
The token is marked Revoked and the name enters a hold period.
This is a feature — the permanent record of what happened to an agent
is part of the trust infrastructure.

### Why metadata is off-chain
Credit scores update continuously. On-chain metadata updates cost gas.
Hybrid approach: token ownership and status are on-chain (permanent, trustless).
Capability and credit data are off-chain (updatable, cost-free).
The tokenURI points to hyo.world/metadata/{id}.json which your backend serves.

### Why royalties are 5%
ERC-2981 standard royalty. Applies to all secondary marketplace sales.
Encoded at contract level — cannot be bypassed by marketplaces that
honor the standard (OpenSea, etc.).

---

## CHAIN SELECTION — BASE (MAINNET) + BASE SEPOLIA (TESTNET)

### Why Base
- **Gas**: ~1000× cheaper than Ethereum mainnet. Register / suspend /
  restore calls land at roughly **$0.005–$0.05** each instead of
  $3–$30. At 100 registrations/day that's **<$5/day in gas** vs
  **$300–$3000/day** on L1.
- **Security**: Base is an OP Stack rollup operated by Coinbase with
  the full Ethereum security guarantee. Good enough for an identity
  registry — the NFTs are long-lived records, not high-frequency
  trades.
- **Distribution**: Coinbase users (tens of millions) can hold Base
  assets natively without bridging. Important for future agent
  marketplaces.
- **Tooling**: Full EVM, OpenZeppelin works unchanged, Hardhat/Foundry
  support is first-class, and standard indexers (The Graph, Alchemy,
  QuickNode) all support Base.

### Network config

| | Mainnet | Testnet |
|---|---|---|
| Name | Base | Base Sepolia |
| Chain ID | `8453` | `84532` |
| RPC | `https://mainnet.base.org` | `https://sepolia.base.org` |
| Explorer | `https://basescan.org` | `https://sepolia.basescan.org` |
| Faucet | — | `https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet` |

### hardhat.config.js addition

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: "0.8.24",
  networks: {
    baseSepolia: {
      url: "https://sepolia.base.org",
      chainId: 84532,
      accounts: [process.env.PLATFORM_PRIVATE_KEY],
    },
    base: {
      url: "https://mainnet.base.org",
      chainId: 8453,
      accounts: [process.env.PLATFORM_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      baseSepolia: process.env.BASESCAN_KEY,
      base: process.env.BASESCAN_KEY,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org",
        },
      },
    ],
  },
};
```

---

## TESTNET DEPLOYMENT (BASE SEPOLIA)

```javascript
const { ethers } = require("hardhat");

async function deploy() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const HyoRegistry = await ethers.getContractFactory("HyoRegistry");
  const registry = await HyoRegistry.deploy(
    "0xYOUR_PLATFORM_WALLET",      // platformAddress (pays gas for every user action)
    "0xYOUR_ROYALTY_WALLET",        // royaltyReceiver
    "https://hyo.world/metadata/"   // baseURI
  );

  await registry.waitForDeployment();
  console.log("HyoRegistry deployed to:", await registry.getAddress());
}

deploy().catch((e) => { console.error(e); process.exit(1); });
```

Run:

```bash
npx hardhat run scripts/deploy.js --network baseSepolia
# then
npx hardhat verify --network baseSepolia <address> \
  "0xPLATFORM" "0xROYALTY" "https://hyo.world/metadata/"
```

Fund the platform wallet with ~0.05 Base Sepolia ETH from the Coinbase
faucet before deploying. A full deploy + 10 test registrations
consumed roughly 0.003 ETH on Base Sepolia during contract v0 testing.

---

## STRIPE-SPONSORED GAS

### The model
Users never touch crypto. They pay a normal USD subscription via
Stripe. When an on-chain action needs to happen, the **platform
wallet** signs and pays for the transaction. Stripe revenue covers
the gas as a fixed cost of goods sold. On Base this cost is small
enough to disappear inside the Stripe processing fee.

This is not ERC-4337, not a paymaster, not meta-transactions. It's
the simplest possible design: the platform is the only caller, so
the platform pays every cent of gas. The existing contract already
enforces this — every admin function is `onlyPlatform`.

### Unit economics

Assume a $29 registration fee paid via Stripe.

```
Gross                        $29.00
Stripe fee (2.9% + $0.30)    -$1.14
Base gas for register()      -$0.02   (current average, 1-2 SSTOREs, 1 mint)
Metadata JSON hosting        -$0.00   (served from hyo.world/metadata, static)
------------------------------------
Net                           $27.84
```

Monthly renewals are effectively gasless — no on-chain call is made
unless the user actually lapses or gets restored. Suspension / restore /
lapse cost ~$0.005–$0.02 each on Base. Budget $0.10 per user per year
in worst-case gas overhead.

### Operational requirements

1. **Platform wallet funding**: Keep 0.1 ETH on Base at all times.
   That's roughly 5,000 register() calls of runway, or several months
   of sustained volume at early stage. Set a balance alert at 0.03 ETH.
2. **Funding rail**: Top the wallet up via Coinbase (USD → Base ETH
   native, no bridge fees) or via the Stripe → treasury → Coinbase
   ops loop once we have one. Never top up from the royalty wallet.
3. **Nonce management**: Because the platform wallet is the only
   caller and will be calling from a backend server, use a nonce
   manager (ethers' `NonceManager` or a Redis-backed queue) to avoid
   stuck transactions during bursty registration periods.
4. **Retry logic**: Wrap contract calls in exponential backoff with a
   gas price bump on each retry. Base sequencer hiccups are rare but
   do happen.
5. **Reconciliation**: After every Stripe webhook confirms payment,
   the backend must persist a pending-mint record in Supabase BEFORE
   calling the contract. The on-chain call only flips the record to
   `minted` after the transaction confirms. This prevents double-mints
   if Stripe retries or the backend crashes mid-call.

### Future upgrade path (not MVP)

If users ever need to call functions directly (e.g. a
`transferAgent` flow where an owner moves their NFT), we have two
choices:

- **EIP-2771 meta-transactions**: Users sign a message off-chain, the
  platform relays it on-chain and pays gas. Requires adding
  `ERC2771Context` to the contract and running a simple relayer.
- **ERC-4337 account abstraction with a paymaster**: Users get a
  smart account, the paymaster covers gas if a Stripe subscription is
  active. Cleaner UX but adds infrastructure weight.

Neither is needed for v1. Keep the current "platform-is-sole-caller"
design, deploy to Base, and let Stripe revenue carry the gas line.

### Backend pseudocode

```python
# webhook handler for stripe checkout.session.completed
def handle_paid_registration(session):
    user_id = session.metadata["user_id"]
    name = session.metadata["requested_name"]
    wallet = session.metadata["owner_wallet"]
    endpoint = session.metadata["endpoint"]

    # 1. persist pending before any on-chain work
    db.registrations.insert({
        "user_id": user_id, "status": "pending_mint",
        "stripe_session": session.id, "name": name,
    })

    # 2. background check (existing flow)
    if not background_check_passes(user_id):
        db.registrations.update(user_id, status="rejected")
        stripe.refund(session.payment_intent)
        return

    # 3. platform wallet calls contract — platform pays gas
    try:
        tx = contract.functions.register(name, endpoint, wallet).build_transaction({
            "from": PLATFORM_WALLET,
            "nonce": nonce_mgr.next(),
            "maxFeePerGas": suggested_fee(),
            "maxPriorityFeePerGas": suggested_tip(),
        })
        signed = sign(tx, PLATFORM_PRIVATE_KEY)
        tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt.status == 1:
            token_id = decode_token_id(receipt)
            db.registrations.update(user_id, status="minted", token_id=token_id)
            send_confirmation_email(user_id, token_id)
        else:
            raise RuntimeError("tx reverted")
    except Exception as exc:
        db.registrations.update(user_id, status="mint_failed", error=str(exc))
        alert_ops(f"Mint failed for {user_id}: {exc}")
        # do NOT refund automatically — ops reviews and retries
```

### What this means for the audit scope

Because Stripe-sponsored gas doesn't change the contract surface
(no new callers, no new privileged roles, no meta-transaction
entrypoint), the existing v1 audit scope is unchanged. The auditor
does need to confirm that **every state-changing function is
`onlyPlatform`** so that the gas-sponsorship model can't be abused
by anyone else paying gas to call the contract directly.

---

## WHAT NEEDS PROFESSIONAL REVIEW

1. Reentrancy protection — ReentrancyGuard applied to register()
   but review all state-changing functions

2. Access control — platform vs owner separation
   Consider multisig for owner role

3. Name collision edge cases — re-registration of lapsed names
   Test all hold period scenarios thoroughly

4. Gas optimization — string storage is expensive
   Consider hashing names for storage efficiency at scale

5. Upgrade path — this contract is not upgradeable
   If logic changes are needed, a new contract must be deployed
   and a migration path for existing tokens designed

---

## AUDIT FIRMS TO CONSIDER
- OpenZeppelin (the standard)
- Trail of Bits
- Consensys Diligence
- Certik (more affordable, good for early stage)
