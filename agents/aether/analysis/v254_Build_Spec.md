# AetherBot v254 Build Specification
**Author:** Kai | **Date:** 2026-04-09 | **Status:** READY FOR BUILD
**Evidence base:** 2 trading days (4/8, 4/9), 46+ sessions, verified by GPT cross-check

---

## P0: TIME-BASED EXIT + STAGED BDI=0 EXIT

### Problem
HOLD1 strategy holds positions when BDI drops to 0, waits 1 poll (~17s), then forces a full exit. 4 of 5 BDI=0 forced exits on 4/9 occurred in the last 4 minutes of the 15-min window when liquidity is draining. The forced exit fills at catastrophic slippage (-$0.19 to -$0.29 per contract).

**Impact:** -$11.63 on 4/9, -$26.75 single trade on 4/8. This is 81% of daily losses.

### Root Cause
Liquidity drains as settlement approaches. Market makers pull quotes in the final 2-4 minutes. By the time BDI hits 0, the order book is empty and any exit gets terrible fills.

### Specification

#### A. Time-Based Pre-emptive Exit (new logic)

```
IF position_held_time > (window_duration * 0.67)  # >10 min into 15-min window
AND BDI < 50
AND position_is_losing:
    TRIGGER staged_exit(reason="TIME_BDI_LOW")
```

This fires BEFORE BDI hits 0. At 10+ minutes with BDI < 50, the book is thinning and the position is unlikely to recover. Exit while there's still some liquidity.

#### B. Staged Exit (replaces HOLD1 -> FORCED_EXIT_AFTER_HOLD1)

Current flow:
```
BDI drops to 0 -> HOLD1 (wait 1 poll) -> FORCED_EXIT full position -> catastrophic slippage
```

New flow:
```
BDI drops to 0 -> CHECK:
  IF position is profitable:
    -> HARVEST what possible at current levels
    -> HOLD for 2 more polls (34s)
    -> IF BDI recovers > 50: resume normal management
    -> IF BDI stays 0 after 2 polls: staged_exit
  IF position is losing:
    -> staged_exit immediately

staged_exit:
  -> Sell 50% of position at best available bid
  -> Wait 1 poll (17s)
  -> Sell remaining 50% at best available bid
  -> Log as STAGED_EXIT (not FORCED_EXIT)
```

The staged approach avoids dumping the entire position into an empty book at once.

#### C. BDI Recovery Detection

```
IF BDI was 0 but recovers to > 50 within 2 polls:
    CANCEL pending exit
    RESUME normal position management
    LOG as BDI_RECOVERY event
```

This prevents premature exits when BDI=0 is transient (a brief quote gap, not a real liquidity drain).

### Testing
- Backtest against all BDI=0 events from 4/8 and 4/9 logs
- Simulate: what would staged_exit have filled at vs FORCED_EXIT actual fills?
- Key metric: average slippage per contract on staged vs forced

### Files to Modify
- `bot.py`: exit logic in the position management section
- Look for: `FORCED_EXIT_AFTER_HOLD1`, `EXIT_PENDING_BDI0_HOLD1`, `STOP HOLD`
- Add: `TIME_BDI_LOW` trigger, `STAGED_EXIT` flow, `BDI_RECOVERY` detection

### Estimated Effort: 3-4 hours
### Expected Impact: Recover $5-11/day (based on 4/9 data: $11.63 from 5 events, assume 50-90% recovery)

---

## P1.1: FIX HARVEST BELOW ENTRY (Anchor Gate)

### Problem
SPHI_DECAY harvest algorithm sells contracts below entry price. This means "profit harvesting" is actually creating losses.

**Evidence (4/9):**
- Trade 6: YES@0.84 -> harvested 1c @ 0.78 = -$0.06
- Trade 8: NO@0.87 -> harvested 2c @ 0.81 = -$0.12  
- Trade 23: YES@0.53 -> harvested 4c @ 0.46 = -$0.28
- Total visible: -$0.46/day

**Evidence (4/8):**
- SPHI_DECAY sold below entry on at least 1 confirmed trade
- Same root cause: anchor price set below entry

### Root Cause
The `anchor` price in SPHI_DECAY is derived from the order book (`ob_bid`), not from the entry price. When the OB bid drops below entry, the anchor follows it down, and the algorithm happily sells at a loss thinking it's harvesting profit.

### Specification

```
BEFORE any HARVEST SPHI_DECAY execution:
    IF side == YES:
        IF harvest_price < entry_price - 0.02:
            SKIP harvest
            LOG "HARVEST BLOCKED | below entry gate | harvest {harvest_price} < entry {entry_price} - 0.02"
    IF side == NO:
        IF harvest_price > entry_price + 0.02:
            SKIP harvest  
            LOG "HARVEST BLOCKED | below entry gate | harvest {harvest_price} > entry {entry_price} + 0.02"
```

The 0.02 buffer accounts for spread and minor slippage. The key constraint: **never sell for less than you bought**.

For YES positions: harvest_price must be >= entry_price - 0.02
For NO positions: harvest_price must be <= entry_price + 0.02

(Remember: NO contracts profit when price goes DOWN, so "selling below entry" for NO means selling at a HIGHER price than entry.)

### Testing
- Apply gate to all HARVEST DONE events from 4/8 and 4/9
- Count: how many harvests would have been blocked?
- Measure: what's the net P&L impact?

### Files to Modify
- `bot.py`: SPHI_DECAY harvest execution section
- Look for: `HARVEST SPHI_DECAY`, `ob_bid`, `anchor`
- Add: entry price check before execution

### Estimated Effort: 1 hour
### Expected Impact: +$0.50/day minimum (blocks visible loss harvests), possibly more

---

## P1.2: DEBUG OB PARSER (ABSENT bids/asks)

### Problem
96 out of 96 HARVEST MISS events on 4/9 show `yes_bids:ABSENT | no_bids:ABSENT` in diagnostics. The order book parser cannot find bid/ask arrays in the Kalshi API response.

### Diagnosis Steps (not code changes yet)
1. Log the raw Kalshi OB API response for one ticker (just the first 500 chars)
2. Compare against what the parser expects
3. Check if Kalshi changed their API response format
4. Check if the "ABSENT" string is a default/fallback in the parser

### If Format Changed
- Update parser to match new format
- Harvest success rate should improve from 11% to 40-60%

### If Books Are Genuinely Empty
- The "ABSENT" result is correct and the harvest system needs a different approach
- Consider: time-based harvest targets instead of OB-dependent

### Estimated Effort: 2h diagnosis + 4h fix (if format change)
### Expected Impact: Harvest rate 11% -> 50%+ = significant P&L improvement

---

## Priority Summary

| Priority | Fix | Effort | Daily Impact | Status |
|----------|-----|--------|-------------|--------|
| P0 | Time-based exit + staged BDI=0 | 3-4h | +$5-11/day | SPEC READY |
| P1.1 | Harvest entry gate | 1h | +$0.50/day | SPEC READY |
| P1.2 | OB parser debug | 2-6h | +$1-3/day | NEEDS DIAGNOSIS |
| P2 | BPS reversal | 1h | +$0.50-1.50/day | NEEDS 5+ DAYS DATA |

**Combined P0+P1.1 expected impact: +$5.50-11.50/day**
**Current daily burn: $10.06/day**
**If v254 delivers even the low end, AetherBot covers the full monthly burn.**

---

*This spec is the build requirements document. It does not contain code.
The operator or builder should reference the bot.py source directly for implementation.*
