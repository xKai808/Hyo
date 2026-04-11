# HyoRegistry — Premium Name Marketplace

**Version:** 1.0.0
**Status:** Spec · Pre-implementation
**Owner:** Hyo
**Companion docs:** `HyoRegistry_Notes.md`, `HyoRegistry_CreditSystem.md`, `HyoRegistry_Reviews.md`

## Principle

Short handles are scarce, memorable, and carry outsized trust. They should not be claimable through the public registration flow on a first-come basis. Hyo holds every one, two, and three-letter handle at genesis, and they are released only through a dedicated marketplace with auction and fixed-price mechanics. This protects the most valuable names from being squatted, funds the dispute reserve, and gives Hyo a lever to release names deliberately over time.

## Scope of the reserve

Three classes of handles are held by the registry at mint time. Together they represent **48,988 handles** across all tiers using the character set `[a-z0-9]`.

**One-letter (36 total).** `a.hyo` through `z.hyo` and `0.hyo` through `9.hyo`. These are the most valuable handles on the registry. They are sold only through sealed-bid auction with aggressive reserve prices. No one-letter handle will ever be released through fixed-price sale.

**Two-letter (1,296 total).** All combinations of `[a-z0-9][a-z0-9]`. Sold through sealed-bid auction with moderate reserves. Hyo may release small batches quarterly to manage scarcity and market response.

**Three-letter (46,656 total).** All combinations of `[a-z0-9][a-z0-9][a-z0-9]`. Sold at fixed price, first come first served. Three-letter handles are the introductory tier for operators who want a premium name without auction drama.

Standard handles (four characters and longer) remain claimable through the public registration flow at standard pricing. The marketplace does not touch them.

## Pricing

Prices are initial values set at launch. The platform operator may adjust them after the first round of data.

**One-letter reserve floor:** 1 ETH equivalent (≈ $3,500 at launch). Winning bids have trended well above floor in analogous markets (ENS, domain resellers).

**Two-letter reserve floor:** 0.25 ETH equivalent (≈ $875 at launch). Releases are batched and scheduled.

**Three-letter fixed price:** $499 per handle, denominated in USD, payable in ETH or USDC on Base. No auction, no waiting — first valid request with payment wins the handle.

All prices are in addition to standard registration and monthly subscription fees. A premium handle buys you the handle; you still run through the normal registration flow to attach it to an agent.

## Auction mechanics (one and two-letter)

Auctions are **sealed-bid, second-price** (Vickrey-style). Bidders submit one maximum bid. At auction close, the highest bidder wins and pays the second-highest bid price plus one reserve increment. If only one valid bid exists, the winner pays the reserve floor.

**Auction windows:**
- One-letter: closes on the last day of each calendar quarter.
- Two-letter: closes on the last day of each calendar month.

**Bid validity:**
- Bid must be at or above the current reserve floor for the tier.
- Bidder must have an approved buyer profile (verified email + wallet).
- Bid is locked — no cancellation after submission.
- Max one active bid per handle per bidder per window.

**Why second-price sealed-bid:** it removes the incentive to game timing (no sniping benefit) and discourages the winner's-curse pattern where bidders overpay in open auctions. Bidders can honestly submit their max valuation and trust the mechanism.

**Tie resolution:** if two identical top bids come in, the earlier-submitted bid wins. Timestamp precision to the millisecond, taken server-side at request receipt.

**Funds handling:** bids are not held at submission time. Winning bidders have 48 hours to complete payment after the window closes. Non-payment forfeits to the runner-up, who then has 24 hours. A handle that fails to sell is returned to the hold pool and can be re-listed in the next window.

## Fixed-price mechanics (three-letter)

Three-letter handles sold through the marketplace page are listed as "held" or "available" in real time. Clicking a held handle shows the price ($499 initial). Paying mints the handle immediately — the operator can then attach it to an agent through the normal registration flow, or save it for later.

A three-letter handle purchased from the marketplace carries the same on-chain `reserved: true` provenance attribute as auction-won handles. It's a provenance mark, not a restriction.

**Cooldown:** Once purchased, a three-letter handle cannot be re-listed for sale by the new owner for 180 days. This prevents immediate flipping and gives real users a window to build on the name.

## Revenue split

Every premium sale splits three ways:

- **40% to the buyback pool.** Used to reacquire rare handles from secondary markets, either through proactive offers or through right-of-first-refusal clauses on resales. The pool funds the long-term scarcity of the premium tier.
- **40% to the dispute reserve fund.** Same fund described in `HyoRegistry_CreditSystem.md` — backstops refunds to customers burned by deregistered agents. Using marketplace revenue to fund this is intentional: the best names subsidize the trust infrastructure that makes the whole registry work.
- **20% to platform operations.** The smallest slice. Hyo's share covers the platform's operating costs (gas sponsorship, hosting, dispute adjudication) but is explicitly capped at one-fifth of revenue. The rest goes back to the registry.

This split is visible on the marketplace page so buyers understand what their money funds. The 40/40/20 ratio is not arbitrary — the two larger pools serve the entire registry, while the smallest pool serves only the platform operator. It signals the right alignment.

## Provenance and NFT attributes

Every handle sold through the marketplace carries permanent NFT attributes reflecting its origin:

```json
{
  "attributes": [
    { "trait_type": "Origin", "value": "Marketplace" },
    { "trait_type": "Tier", "value": "Two-letter" },
    { "trait_type": "Release", "value": "2026-Q2 Auction" },
    { "trait_type": "Reserved at Genesis", "value": "true" }
  ]
}
```

These are immutable after mint. They exist to mark the handle as historically reserved and give it collector value independent of the agent attached to it.

## Access control on the contract

The `HyoRegistry.sol` contract needs two new admin functions to support this marketplace, both `onlyPlatform`:

1. `mintReserved(address to, string handle, bytes32 originHash)` — mints a held handle to the buyer's address and tags it with the `reserved` attribute. Called by the platform wallet after auction payment clears or fixed-price purchase completes.

2. `holdHandle(string handle)` — at deploy time, seeds the reserve. Iterates through all 48,988 short handles and marks them as held. Alternatively (cheaper gas) the contract uses a bitmask or Merkle-tree check to treat all length-≤3 handles as held without explicit storage.

The Merkle-tree approach is preferred for gas: at contract deploy, compute a Merkle root over the full list of reserved handles. The `register()` function rejects any handle where the Merkle proof validates against the reserved root, unless the caller is the platform wallet calling `mintReserved()`. This is O(log n) per check and avoids 49k storage writes at deploy time.

## Integration with the registration flow

The public registration form (`register.html`) validates the agent handle client-side to reject one, two, and three-character names before the user hits continue. The error message links to `marketplace.html` with pre-populated tier selection.

The server-side endpoint (`/api/checkout`) enforces the same check independently so the client-side guard cannot be bypassed. A request with a premium handle through the standard checkout is rejected with a clear redirect message.

The founder registration (`founder-register.html`) allows premium handles, since Hyo holds them and can mint any one directly. This is how `aurora.hyo` and future short-name Hyo agents get created without going through the marketplace.

## What the user sees

The marketplace page (`marketplace.html`, already built) displays:

- **Header copy** explaining the reserve and why it exists
- **Three tier cards** showing count, description, and price mechanics
- **How-it-works panel** explaining the auction and fixed-price rules
- **Request form** with real-time handle classification — type a handle, see instantly whether it's one, two, three, or four-plus letters
- **Submit** posts to `/api/marketplace-request` which queues the request

A future build adds live inventory display (which three-letter handles are still available, which auctions are currently open) and a public ledger of past auction results for price discovery.

## Anti-gaming and integrity

Three known attack vectors are addressed explicitly.

**Sybil bidding.** One wallet uses many identities to run up the second-price in a Vickrey auction. Countered by requiring KYC-lite verification (verified email + wallet with prior transaction history) before bids are accepted, and by excluding identical bids from the same IP address or payment source from the same auction.

**Auction collusion.** Multiple bidders coordinate to suppress prices. Countered by the sealed-bid structure (bidders don't know each other's bids) and by Hyo's right to refuse any auction result it deems collusive, with handle returning to the next window and a full refund.

**Flip chains.** A buyer wins a handle and immediately resells for profit. Countered by the 180-day cooldown on three-letter handles and a voluntary right-of-first-refusal on one and two-letter handles: if the holder wants to sell within 12 months of acquisition, they must offer to the platform at cost basis first.

## Open questions

- Do we allow cryptocurrency payment only, or also credit card via Stripe for three-letter fixed-price? Current default: both. Stripe for $499 three-letter, crypto only for auctions (auction complexity + chargeback risk makes Stripe unsuitable).
- Does the buyback pool have governance, or is it operator-directed? Current default: operator-directed for the first year, governance token consideration later.
- Should auction results be publicly viewable immediately or delayed for privacy? Current default: winning handles announced immediately, bid amounts delayed 30 days.

## Change log

**1.0.0** — 2026-04-10 — Initial spec. Reserve scope, pricing, auction and fixed-price mechanics, revenue split, Merkle-tree approach, integration with registration, anti-gaming measures.
