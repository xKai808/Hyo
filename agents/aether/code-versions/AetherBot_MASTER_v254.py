import os
import time
import uuid
import base64
import datetime as dt
import json
import re
from decimal import Decimal, ROUND_DOWN
from collections import defaultdict, deque
import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

API_KEY_ID = os.environ.get("AETHERBOT_KEY", "PASTE_YOUR_AETHERBOT_KEY_ID_HERE")
PRIVATE_KEY_PATH = os.path.expanduser("~/Documents/Projects/AetherBot/AethelBot.txt")
BASE_URL = "https://api.elections.kalshi.com/trade-api/v2"
SERIES_TICKER = "KXBTC15M"

# v254: AetherBot sends one-way Telegram alerts (entries, exits, settlements).
# Kai bot owns the getUpdates polling — AetherBot never polls, only sends.
# Control is file-based: Kai writes .stop_flag / .pause_flag, AetherBot reads them.
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")

_CONTROL_DIR = os.path.expanduser("~/Documents/Projects/AetherBot")
_STOP_FLAG   = os.path.join(_CONTROL_DIR, ".stop_flag")
_PAUSE_FLAG  = os.path.join(_CONTROL_DIR, ".pause_flag")

_bot_paused       = False
_bot_stop_flag    = False

def send_telegram_alert(message: str):
    """One-way alert — sends to Telegram but never reads/polls."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            data={"chat_id": TELEGRAM_CHAT_ID, "text": message},
            timeout=5,
        )
    except Exception:
        pass

def drain_telegram_queue():
    """No-op — Kai bridge owns getUpdates polling, AetherBot never polls."""
    pass

def check_telegram_commands():
    """v254: File-based control — Kai writes flag files, AetherBot reads them.
    .stop_flag  -> clean stop after current poll
    .pause_flag -> monitoring only, no entries or exits
    Remove .pause_flag to resume.
    """
    global _bot_paused, _bot_stop_flag
    if os.path.exists(_STOP_FLAG):
        _bot_stop_flag = True
        print("KAI CMD | /stop flag detected")
        try:
            os.remove(_STOP_FLAG)
        except Exception:
            pass
    if os.path.exists(_PAUSE_FLAG):
        if not _bot_paused:
            _bot_paused = True
            print("KAI CMD | /pause flag detected")
    else:
        if _bot_paused:
            _bot_paused = False
            print("KAI CMD | /resume — pause flag removed")

# SETTLEMENT TRACKING
PENDING_TRADES_FILE      = os.path.expanduser("~/aetherbot_pending_trades.json")
PENDING_SETTLEMENTS_FILE = os.path.expanduser("~/aetherbot_pending_settlements.json")
LIVE_STATE_FILE      = os.path.expanduser("~/aetherbot_live_state.json")
pending_trades = {}
settled_tickers  = set()
_ticker_pnl_log  = {}   # ticker -> list of (reason, pnl) for close summary
_session_trades  = []   # {outcome, reason, side, pnl} per settled trade
_session_started = None # datetime of first settlement this run
_session_start_balance = None  # Kalshi balance at first settlement this run
_session_running_pnl   = 0.0   # cumulative P&L this run (for display when API lags)
# v190: pending settlement queue — trades whose Kalshi balance hasn't confirmed yet.
# Re-polled each run_bot cycle until balance moves or 20 attempts exceeded.
# Each entry: {reason, side, entry_px, total_c, legs_str, internal_pnl,
#              pre_bal, ticker, attempt, outcome}
_pending_settlement_queue = []

# RISK: $5 in VOLATILE/LOW_VOLUME/STABLE regime, $8 in MODERATE/UNKNOWN (v207).
# Chop environments get smaller size — thin books make exits harder.
# See get_risk_dollars().
MIN_EXECUTABLE_PRICE = Decimal("0.40")
MAX_EXECUTABLE_PRICE = Decimal("0.99")
MIN_SECONDS_LEFT_TO_TRADE = 10
MAX_SECONDS_LEFT_TO_TRADE = 780

TIER_88_SECONDS = 240
TIER_90_SECONDS = 180
TIER_93_SECONDS = 120
TIER_95_SECONDS = 240

SLOW_POLL = 30
FAST_POLL = 10
FAST_POLL_WINDOW = 240
HISTORY_LEN = 12

RECENT_ABS_PCTS = deque(maxlen=8)

# BPS SETTINGS
BPS_MIN_SCORE = 2

# PAQ — Price Action Quality score (0-6)
# Three components each 0-2: Context + State + Expansion
# PAQ >= 5 = Strong, 3-4 = Moderate, < 3 = Weak (reject for bps_premium)
PAQ_STRONG   = 5
PAQ_MODERATE = 3

# Profit-protection trail distances by family
TRAIL_DIST = {
    "bps_premium":     Decimal("0.06"),
    "bps_late":        Decimal("0.06"),
    "PAQ_EARLY_AGG":   Decimal("0.08"),
    "PAQ_EARLY_CONS":  Decimal("0.08"),
    "PAQ_PENDING_ALIGN": Decimal("0.08"),
    "confirm_standard":Decimal("0.10"),
    "confirm_late":    Decimal("0.10"),
}
TRAIL_ACTIVATE_PRICE  = Decimal("0.88")   # Stage 1: side price must reach this
TRAIL_ACTIVATE_GAIN   = Decimal("0.12")   # Stage 1: gain from entry must meet this
TRAIL_STAGE3_PRICE    = Decimal("0.95")   # Stage 3: endgame tightening activates
TRAIL_STAGE3_DIST     = Decimal("0.05")   # Stage 3: compressed trail distance
TRAIL_STABILIZE_READS = 2                 # poll cycles after entry before trail can activate
TRAIL_STABILIZE_SECS  = 60                # minimum seconds after entry before trail can activate

# Partial Profit Harvest — proactive inventory reduction while book is still liquid
HARVEST_S1_PRICE      = Decimal("0.88")   # legacy price gate (fallback)
HARVEST_S2_PRICE      = Decimal("0.94")   # legacy price gate (fallback)
HARVEST_MAX_RATIO     = Decimal("0.85")   # v231: raised from 0.75 to support second S1 pass
# Math: first S1 = 60% of 10c = 6c. Budget = 8.5c.
# Second S1: min(6c, budget_left=2.5c, remaining-1) = 2c. Total: 8c = 80%. 25% still rides.
HARVEST_CONFIRM_READS = 2                 # consecutive reads before firing
HARVEST_TRANCHE_RATIO = Decimal("0.33")   # S2/S3 tranche size: 33% of entry contracts
HARVEST_S1_TRANCHE_RATIO = Decimal("0.60") # v231: S1 tranche: 60% of entry contracts
# S1 fires 60% up front to lock majority before any reversal.
# S2/S3 use 0.33 on the remaining 40% — natural progression.
# 9-day data: 161 S1 fires at avg 0.877, book supports 60% at that zone on weekdays.

# Family-specific gain thresholds per market regime
# Derived from 3/18 MFE analysis:
#   bps_premium    median MFE +0.174  → S1 at +0.12-0.15, S2 at +0.20-0.22
#   PAQ_EARLY_AGG  median MFE +0.210  → S1 at +0.10-0.12, S2 at +0.18-0.22
#   PAQ_EARLY_CONS median MFE +0.208  → S1 at +0.10,       S2 at +0.20
#   confirm_*      smaller MFE        → single harvest only, later threshold
#
# Format: {family: {regime: (S1_gain, S2_gain, S3_gain)}}
# Harvest gains as % of entry price.
# 60-70% weight towards "not leaving anything on the table" — S1 fires at ~p35 of win MFE.
# S1 is also set above each family's max loss peak to avoid false harvests on losers.
# VOLATILE -15% on thresholds (thin book, capture while liquid).
# STABLE   +15% on thresholds (deep book, let it run longer).
HARVEST_UPSIDE_FRACS = {
    # Fractions of remaining upside (1.00 - entry) per regime
    # S_trigger = entry + (1.00 - entry) * fraction
    # Scales automatically at any entry — never exceeds 1.00
    "VOLATILE":   (0.25, 0.50, 0.72),  # fast flip risk — capture early
    "MODERATE":   (0.35, 0.60, 0.80),  # standard balance
    "STABLE":     (0.40, 0.65, 0.85),  # slower moves — wait for more
    "LOW_VOLUME": (0.20, 0.40, 0.60),  # thin book — take quickly
    "UNKNOWN":    (0.35, 0.60, 0.80),  # default to MODERATE
}
HARVEST_MIN_GAIN_PER_CONTRACT = Decimal("0.12")  # min $0.12/contract — $0.36 on 3c tranche minimum
# Remaining-upside framework — replaces legacy % of entry tables

# Strategy 1 — Time-compressed trail (activates earlier when near expiry)
TRAIL_S1_PRICE_GATE   = Decimal("0.82")   # held price must be >= this to activate S1
TRAIL_S1_SECS_GATE    = 360               # seconds_left must be <= this
TRAIL_S1_DIST_MID     = Decimal("0.05")   # 181-360s trail distance
TRAIL_S1_DIST_LATE    = Decimal("0.03")   # <=180s trail distance

# Strategy 3 — Time-decay mid-zone exit
TRAIL_S3_ZONE_LOW     = Decimal("0.40")   # held price lower bound for mid-zone
TRAIL_S3_ZONE_HIGH    = Decimal("0.82")   # held price upper bound for mid-zone
TRAIL_S3_SECS_GATE    = 240               # seconds_left must be <= this

# ── Session-aware parameter overrides ─────────────────────────────────────
# Session windows in MTN (all log timestamps are MTN):
#   17:00-21:00 MTN — BTC Deep Night: strongest signal quality, cleanest PAQ builds
#   21:00-03:00 MTN — Asia Open: quieter but longer trends
#   03:00-05:00 MTN — EU Morning: lumpiest microstructure
#   05:00-09:00 MTN — NY Open: kill zone (institutional sell pressure)
#   09:00-14:00 MTN — NY Prime: moderate, active
#   14:00-17:00 MTN — NY Close: kill zone
SESSION_EU_MORNING_ABS_BOOST   = 0.02   # extra abs% floor added during 00-03 MTN
SESSION_EU_MORNING_S3_SECS     = 200    # tighter S3 gate during EU morning (vs 240)
# EU_MORNING harvest: book dies at 0.93-0.94, not 0.999 like night.
# 3/17 data: 19 EU_MORNING misses started at held=0.93. Night misses only at 1.0000.
# Harvest earlier and at smaller gain to capture before book thins.
SESSION_EU_MORNING_HARVEST_S1_PRICE = Decimal("0.82")  # trigger earlier than standard 0.88
SESSION_EU_MORNING_HARVEST_S1_GAIN  = Decimal("0.10")  # smaller gain requirement
SESSION_EU_MORNING_HARVEST_S2_PRICE = Decimal("0.88")  # S2 where standard S1 would fire
SESSION_EU_MORNING_HARVEST_S2_GAIN  = Decimal("0.15")  # still profitable tranche
SESSION_EU_MORNING_HARVEST_S1_SECS  = 480              # wider window — catch it while liquid
SESSION_ASIA_OPEN_TIER_C_CEIL  = Decimal("0.85")  # softer TIER_C ceiling during 21-00 MTN
TRAIL_S3_MIN_AGE      = 120               # min trade age in seconds before S3 can fire
TRAIL_S3_BPS_BLOCK    = 3                 # block exit if BPS on-side >= this (momentum override)
TRAIL_S3_LADDER_OFFSETS = [Decimal("0.10"), Decimal("0.18"), Decimal("0.28"), Decimal("0.40")]

# Mid-zone TP — PAQ-dynamic gain threshold to arm compressed trail
MID_ZONE_GAIN_STRONG   = Decimal("0.28")  # PAQ 5-6: let it ride more
MID_ZONE_GAIN_MODERATE = Decimal("0.22")  # PAQ 3-4: balanced
MID_ZONE_GAIN_WEAK     = Decimal("0.15")  # PAQ 0-2: tighter, less confidence
MID_ZONE_TRAIL_DIST    = Decimal("0.06")  # compressed trail distance once armed
MID_ZONE_ARMED_READS   = 2                # confirmation reads before floor can fire after MZ arms

# PAQ entry family constants
PAQ_PENDING_MAX_SECONDS  = 720    # PAQ_PENDING_ALIGN window
PAQ_PENDING_MIN_PAQ      = 5      # PAQ floor for pending-align family
PAQ_PENDING_MIN_PRICE    = Decimal("0.40")
PAQ_PENDING_MAX_PRICE    = Decimal("0.75")
PAQ_PENDING_CONSEC       = 2      # consecutive qualifying checks required
PAQ_EARLY_AGG_MAX_SECS   = 780
PAQ_EARLY_CONS_MAX_SECS  = 720

# CONFIRMATION-FAMILY STOP PARAMETERS
CONF_REVERSAL_BPS        = 1   # Trigger A: BPS opposite by 1 + damage gate
CONF_FAST_REVERSAL_BPS   = 2   # Trigger B: BPS opposite by 2, immediate
CONF_ENTRY_DAMAGE        = Decimal("0.12")
CONF_PEAK_GIVEBACK       = Decimal("0.18")
CONF_LOSS_OF_DOM         = Decimal("0.72")
CONF_OPPOSITE_RISE       = Decimal("0.28")
CONF_PINNED_HELD         = Decimal("0.94")
CONF_PINNED_OPP          = Decimal("0.06")
CONF_LATE_WINDOW         = 45
CONF_LATE_OPP_MIN        = Decimal("0.35")
# legacy alias
NON_BPS_PRICE_DROP_THRESHOLD = Decimal("0.28")
NON_BPS_BPS_REVERSAL = 2

# EARLIER ENTRY SETTINGS
EARLY_ENTRY_MIN_PRICE   = Decimal("0.72")
EARLY_ENTRY_MAX_PRICE   = Decimal("0.88")
EARLY_ENTRY_MIN_BPS     = 3        # live BPS must be >= +3 (YES) or <= -3 (NO)
EARLY_ENTRY_PERSIST_BPS = 2        # persistence threshold (2 of last 3 >= +2 / <= -2)
EARLY_ENTRY_MIN_ABS     = 0.04     # minimum abs%
EARLY_ENTRY_ABS_DECAY   = 0.03     # block if abs has decayed > this from 3-check peak
EARLY_ENTRY_MIN_SECS    = 180
EARLY_ENTRY_MAX_SECS    = 600
EARLY_ENTRY_BPS_WEAKEN  = 2        # block if live BPS is this far below recent best
# Day-mode BPS abs thresholds (used by get_bps_min_abs)
BPS_ABS_481_600 = 0.10
BPS_ABS_361_480 = 0.12
BPS_ABS_241_360 = 0.14
BPS_ABS_121_240 = 0.16
BPS_ABS_0_120   = 0.18
# Night-mode BPS abs thresholds (softened)
BPS_ABS_NIGHT_481_600 = 0.09
BPS_ABS_NIGHT_361_480 = 0.10
BPS_ABS_NIGHT_241_360 = 0.11
BPS_ABS_NIGHT_121_240 = 0.13
BPS_ABS_NIGHT_0_120   = 0.15
# Premium directional abs floor by time window (replaces single EARLY_ENTRY_MIN_ABS)
BPS_PREM_ABS_481_600  = 0.04
BPS_PREM_ABS_361_480  = 0.05
BPS_PREM_ABS_241_360  = 0.06
BPS_PREM_ABS_180_240  = 0.07

# RAPID STOP-LOSS LADDER
STOP_LOSS_LADDER_OFFSETS = [
    Decimal("-0.02"),  # anchor+0.02: try above best bid first
    Decimal("-0.01"),  # anchor+0.01
    Decimal("0.00"),   # at anchor (best bid)
    Decimal("0.02"),   # anchor-0.02
    Decimal("0.04"),   # anchor-0.04
    Decimal("0.07"),   # anchor-0.07
    Decimal("0.10"),   # anchor-0.10: wide floor, any exit beats dead book
]
STOP_LOSS_MIN_PRICE = Decimal("0.05")
STOP_LOSS_MAX_PRICE = Decimal("0.98")
STOP_LOSS_REPRICE_DELAY = 0.20
STOP_LOSS_MAX_ATTEMPTS = 7

# Note: STOP_FIRST/SECOND/THIRD/FOURTH_CROSS_PRICE constants removed.
# The stop-loss ladder now derives its price from the live orderbook via
# get_best_exit_price_from_orderbook(); see execute_rapid_stop_loss_exit().

btc_prices = deque(maxlen=12)

last_seen_ticker = None
fallback_strike_cache = {}  # ticker -> locked BTC-spot strike when Kalshi TBD
prev_paq_score   = None   # last computed PAQ score for status line (None = no data)
prev_paq_bucket  = ""     # "STRONG" / "MODERATE" / "WEAK" / ""
prev_paq_ctx     = None   # last context sub-score (0-2)
prev_paq_state   = None   # last state sub-score (0-2)
prev_paq_exp     = None   # last expansion sub-score (0-2)
_paq_fail_logged = False  # suppress repeated PAQ candle failure messages
_paq_pending_yes_count = 0   # consecutive checks qualifying for PAQ_PENDING_ALIGN YES
_paq_pending_no_count  = 0   # consecutive checks qualifying for PAQ_PENDING_ALIGN NO
last_logged_event_key = None
clean_ticker_reads = defaultdict(int)

# v252: live_bps initialized at module level so all helper functions that reference it
# as a global always find a valid value even before run_bot() computes it each poll.
live_bps = 0.0

# live position state
last_side = None
last_entry_price = None
last_entry_time = None
last_traded_ticker = None
trail_harvested_ticker  = None   # ticker of last Stage 3 trail exit (same-direction block)
trail_harvested_side    = None   # side that was harvested
trail_harvested_time    = None   # time of harvest (UTC internally, display in MTN)
trail_harvested_exit_px = None   # price at harvest exit
flip_logged_ticker = None
last_entry_reason = None
last_entry_bps = None
last_entry_paq = None   # PAQ score at time of entry (for PHI post-entry health score)
_paq_stop_fired       = False  # latch — prevents repeated PAQ stop restarts per position
_any_stop_fired       = False  # master stop authority — once ANY stop ladder starts, all others blocked
# v229: Post-partial tail management
# After CONTRACT_VELOCITY_PARTIAL fills, remainder enters a dead zone:
# PAQ stop blocked, trail blocked, CHOP never arms if BPS stays on-side.
# Tail-risk mode re-arms a dedicated recovery exit on remaining contracts.
_tail_risk_mode       = False  # True after CONTRACT_VELOCITY_PARTIAL partial fill
_tail_risk_entry_px   = None   # entry price of the original position (for recovery threshold)
_last_gate_result     = ""     # READY/BLOCKED — set each poll, appended to status line
_last_entry_block     = ""     # block reason — set each poll, appended to status line
_last_entry_class     = ""     # entry class — set on entry, shown in BUY SNAPSHOT
_pending_regime_display = ""   # regime label — appended to next status line
_entry_exposure_capped = False  # True when second same-side entry forced to LOW sizing
# Profit-protection state
trail_high_water      = None   # highest held-side price seen since entry
trail_active          = False  # True once Stage 1 activation threshold met
trail_reads_post_peak = 0      # poll cycles since high-water last updated (anti-wick)
trail_below_floor_cnt = 0      # consecutive reads below trail floor (1 needed to fire)
trail_activation_reads = 0     # reads since trail_active first set — floor blocked for first 3
harvest_s1_done       = False  # True once Stage 1 harvest executed this position
harvest_s1_count      = 0      # v231: number of S1 fires this position (max 2)
harvest_s1_fire_px    = None   # v231: held price when S1 last fired (zone reference)
harvest_s1_zone_left  = False  # v231: True once price retreated below S1 zone after first fire

# v234: WES (Weekday Early Scout) lane state
# WES enters cheap (0.40-0.60) early in viable sessions, exits 100% at entry+0.15 or stops at entry-0.15.
# v244: ceiling tightened from 0.65 to 0.60. Data: 9-session audit shows 0.59-0.65 bucket runs 29%
# stop rate vs 7-8% in 0.40-0.58 band. Per-signal EV rises from $0.41 to $0.45 at 0.60 ceiling.
# Completely separate from harvest system. No S1/S2/S3 stages. No PHI. No trail.
# Data basis: 73% S1 hit rate in viable windows, break-even at 50% with symmetric ±0.15 spread.
_wes_active          = False   # True when a WES position is open
_wes_entry_px        = None    # Entry price for WES position
_wes_contracts       = 0       # Contracts held under WES
_wes_s1_target       = None    # entry + 0.15 — full exit trigger
_wes_stop_target     = None    # entry - 0.15 — full stop trigger
_wes_side            = None    # "yes" or "no"
_wes_entry_secs      = None    # seconds_left when WES armed (for 300s promotion window)

# v238: WES promotion state — tracks when a main family promotes a WES scout
# Promotion: WES stays in, main family adds contracts, main family owns exit
# Harvest + stop triggers reference parent entry price — same as standalone main strategy
_wes_promoted            = False   # True once promoted; disables WES S1/stop exits
_wes_parent_family       = None    # which family promoted ("bps_premium" or "PAQ_STRUCT_GATE")
_wes_parent_entry_px     = None    # parent's actual fill price (for harvest/stop triggers)
_wes_parent_contracts    = 0       # contracts added by parent at parent's price
_wes_combined_avg_px     = None    # (wes_c*wes_px + parent_c*parent_px)/(wes_c+parent_c) — P&L accounting only
harvest_s2_done       = False  # True once Stage 2 harvest executed this position
harvest_s3_done       = False  # True once Stage 3 harvest executed this position
harvest_s1_reads      = 0      # consecutive reads in S1 harvest zone
harvest_s2_reads      = 0      # consecutive reads in S2 harvest zone
harvest_s3_reads      = 0      # consecutive reads in S3 harvest zone
harvest_miss_streak   = 0      # consecutive misses at same price zone
_harvest_diag_fired   = {}     # (ticker, stage) -> bool — one-shot miss diagnostic per ticker per stage
harvest_miss_anchor   = None   # price zone of last miss (for cooldown)
harvest_miss_bdi_last = 0      # BDI at last miss (for refresh detection)

# ── Market regime classifier ──────────────────────────────────────
_regime               = "UNKNOWN"  # STABLE / MODERATE / VOLATILE / LOW_VOLUME / UNKNOWN
_book_env             = "UNKNOWN"  # real-time book classification (poll 1 available)
_book_total_depth     = 0          # total contracts both sides within $0.10
_book_spread          = 0.0        # YES_bid + NO_bid - 1.00 (vig)
_book_asymmetry       = 0.0        # abs(yes_depth - no_depth) / total_depth
_regime_poll_count    = 0          # polls since last ticker start
_regime_abs_samples   = []         # abs% history for current ticker
_regime_bps_samples   = []         # BPS history for current ticker
_regime_spread_samples = []        # book spread (1 - YES - NO) history
REGIME_CALIBRATION_POLLS = 8      # ~5 minutes at 35s/poll
harvest_total_sold    = 0      # contracts harvested so far this position
last_exit_side        = None   # side of most recently closed position on this ticker
last_exit_time        = None   # datetime position was closed
last_exit_price       = None   # avg exit price of most recently closed position
trail_mz_armed        = False  # True once mid-zone TP threshold crossed
trail_mz_armed_reads  = 0      # reads since MZ armed (confirmation gate)
trail_s3_zone_cnt     = 0      # consecutive reads in S3 mid-zone (needs 2 to fire)
last_entry_reads      = 0      # poll cycles since current entry (stabilization lockout)
last_entry_abs        = 0.0    # abs% at time of entry (for PAQ_STRUCT continuity check)
_paq_struct_derisked  = False  # True once PAQ_STRUCT de-risk partial exit has fired
# ── BCDP: BPS Consecutive Directional Persistence ──────────────────────────────
_bps_history          = deque(maxlen=8)  # rolling last 8 BPS values (v221: expanded from 5 for weekend stability gate)
_bcdp                 = 0      # raw consecutive same-signed BPS count
_bcdp_clean           = False  # True when BCDP>=1 and NO opposing sign in full 5-poll window
_bcdp_pending_display = ""     # appended to next status line

# v245: BDI=0 exit hold tracking — single-hold-max rule
# Once any armed exit fires and BDI=0, we defer exactly one poll.
# On second BDI=0 with same position still open, escalate: force full ladder regardless of book depth.
_bdi0_hold_count      = 0     # consecutive BDI=0 holds on current armed exit (0 or 1 before escalation)
_bdi0_hold_px         = None  # price at first hold (for escalation delta logging)
# v247: forced next-poll exit after BDI=0 HOLD1.
# After a HOLD1, stop conditions (PAQ latched, BPS threshold unmet) may not re-qualify
# on subsequent polls, leaving the position silently exposed to settlement.
# _bdi0_exit_pending bridges the gap: forces an exit attempt at the top of the next poll
# regardless of stop-condition state, before normal family evaluation.
_bdi0_exit_pending    = False  # True after first BDI=0 hold; cleared after forced attempt

_paq_zero_streak      = 0      # consecutive checks where PAQ == 0 (for PAQ0 immediate)
_paq_bps_soft_yes_cnt = 0      # consecutive PAQ1 + BPS<=-1 checks for held YES
_paq_bps_soft_no_cnt  = 0      # consecutive PAQ1 + BPS>=+1 checks for held NO
_paq_agg_opp_yes_cnt  = 0      # consecutive PAQ_AGG opposite-BPS reads for held YES (PAQ>=4: needs 2)
_paq_agg_opp_no_cnt   = 0      # consecutive PAQ_AGG opposite-BPS reads for held NO  (PAQ>=4: needs 2)
_fc_yes_cnt           = 0      # BCDP_FAST_COMMIT consecutive YES reads
_fc_no_cnt            = 0      # BCDP_FAST_COMMIT consecutive NO reads
_paq_struct_yes_cnt   = 0      # consecutive PAQ>=4 + BPS>=1 reads for YES (PAQ_STRUCT_GATE)
_paq_struct_no_cnt    = 0      # consecutive PAQ>=4 + BPS<=-1 reads for NO (PAQ_STRUCT_GATE)
_paq_struct_loss_ticker = None  # ticker of last PAQ_STRUCT loss (cooldown gate)

# ── Chop-watch state (PAQ persistence gate) ───────────────────────────────────
# When adverse BPS is admitted (abs >= chop floor), tracks PAQ for 3 polls.
# CHOP_RECOVERY: PAQ returns to >= 3 within 2 polls → hold + add on dip
# Stop outcomes: STOP FILLED | STOP UNFILLED | STOP HOLD | STOP PARTIAL
_chop_watch_active    = False  # True while in reversal review window
_chop_watch_polls     = 0      # polls since adverse admission
_chop_watch_paq_low   = 0      # consecutive polls where PAQ stayed <= 1
_chop_dip_price       = None   # contract price when chop-watch started (dip entry reference)
_chop_watch_bps_start = 0.0    # BPS when chop-watch opened
last_entry_contracts = 0
last_bps_opposite_count = 0
_weekend_struct_entry = False  # v222: True when current position is STRUCT on a weekend (ladder exit mode)
_wsl_entry_secs       = 900    # v222: seconds_left at time of weekend STRUCT entry (for elapsed calc)


price_history = defaultdict(lambda: {"yes": deque(maxlen=HISTORY_LEN), "no": deque(maxlen=HISTORY_LEN)})

SESSION = requests.Session()
SESSION.headers.update({"Content-Type": "application/json"})

def load_private_key(path: str):
    with open(path, "rb") as f:
        return serialization.load_pem_private_key(f.read(), password=None)

PRIVATE_KEY = load_private_key(PRIVATE_KEY_PATH)

def create_signature(timestamp_ms: str, method: str, path: str) -> str:
    path_without_query = path.split("?")[0]
    message = f"{timestamp_ms}{method.upper()}{path_without_query}".encode("utf-8")
    signature = PRIVATE_KEY.sign(
        message,
        padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=padding.PSS.DIGEST_LENGTH),
        hashes.SHA256(),
    )
    return base64.b64encode(signature).decode("utf-8")

def signed_request(method: str, path: str, params=None, json_data=None):
    timestamp_ms = str(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))
    full_path = f"/trade-api/v2{path}"
    sig = create_signature(timestamp_ms, method, full_path)
    headers = {
        "KALSHI-ACCESS-KEY": API_KEY_ID,
        "KALSHI-ACCESS-SIGNATURE": sig,
        "KALSHI-ACCESS-TIMESTAMP": timestamp_ms,
        "Content-Type": "application/json",
    }
    url = BASE_URL + path
    if method.upper() == "GET":
        return SESSION.get(url, headers=headers, params=params, timeout=10)
    elif method.upper() == "POST":
        return SESSION.post(url, headers=headers, json=json_data, timeout=10)
    elif method.upper() == "DELETE":
        return SESSION.delete(url, headers=headers, timeout=10)
    return None

def to_decimal(v):
    if v is None: return None
    try: return Decimal(str(v))
    except: return None

def get_open_kalshi_market():
    resp = signed_request("GET", "/markets", params={"series_ticker": SERIES_TICKER, "status": "open", "limit": 5})
    if resp.status_code != 200:
        print("Market fetch failed:", resp.status_code, resp.text)
        return None
    markets = resp.json().get("markets", [])
    if not markets: return None
    return min(markets, key=lambda m: m["close_time"])

_ob_diag_logged = False  # v254: one-time OB response structure log

def get_orderbook(ticker: str):
    global _ob_diag_logged
    try:
        resp = signed_request("GET", f"/markets/{ticker}/orderbook")
        if resp.status_code != 200:
            return None
        data = resp.json()
        # v254: one-time diagnostic — log the top-level keys and structure
        # of the raw Kalshi OB response so we can detect format changes.
        if not _ob_diag_logged:
            _ob_diag_logged = True
            _raw_keys = list(data.keys()) if data else []
            _ob_obj = data.get("orderbook_fp", data.get("orderbook"))
            _ob_keys = list(_ob_obj.keys()) if isinstance(_ob_obj, dict) else type(_ob_obj).__name__
            print(f"          -> OB_FORMAT_DIAG | raw_keys: {_raw_keys} | orderbook_keys: {_ob_keys}")
        return data.get("orderbook_fp", data.get("orderbook"))
    except Exception:
        return None

def get_best_bid(ticker: str, side: str) -> Decimal | None:
    """Return the single best (highest) bid price on the held side.
    This is what an IOC sell order at this price will immediately fill against.
    """
    try:
        ob = get_orderbook(ticker)
        if ob is None:
            return None
        key = "yes_dollars" if side == "yes" else "no_dollars"
        levels = ob.get(key) or ob.get(key.replace("_dollars", "")) or []
        if not levels:
            return None
        # Levels sorted worst→best, last entry is best bid
        best = levels[-1]
        px = float(best[0])
        if px > 1.0:
            px = px / 100
        return Decimal(str(round(px, 4)))
    except Exception:
        return None


def get_bdi(ticker: str, side: str, ref_price: float, window: float = 0.05) -> int:
    """Book Depth Index — sum of bid contracts on the held side within
    a 5-cent window below the reference price.

    This is the single number that tells AetherBot whether any action
    (entry, harvest, stop) will actually execute in the current book.

    Args:
        ticker:    market ticker
        side:      "yes" or "no"
        ref_price: current held price (or entry price for confirmation)
        window:    price window below ref_price to sum (default 0.05)

    Returns:
        integer contract count available within the window.
        0 means the book is effectively dead at this price.
    """
    try:
        ob = get_orderbook(ticker)
        if ob is None:
            return 0
        # yes_dollars / no_dollars: sorted worst→best, last entry = best bid
        # Format: [[price_str, qty_str], ...]
        key = "yes_dollars" if side == "yes" else "no_dollars"
        levels = ob.get(key) or ob.get(key.replace("_dollars", "")) or []
        if not levels:
            return 0
        floor_price = ref_price - window
        total = 0
        for level in levels:
            try:
                px  = float(level[0])
                qty = float(level[1])
                # orderbook_fp quantities are fixed-point (e.g. "800.00" = 8 contracts)
                # Divide by 100 to get actual contract count
                if qty > 100:
                    qty = qty / 100
                if px >= floor_price:
                    total += int(qty)
            except (IndexError, ValueError, TypeError):
                continue
        return total
    except Exception:
        return 0


def get_prices(market):
    yes = to_decimal(market.get("yes_ask_dollars")) or to_decimal(market.get("yes_price_dollars"))
    no = to_decimal(market.get("no_ask_dollars")) or to_decimal(market.get("no_price_dollars"))
    return yes, no

def get_bid_prices(market):
    """Return the BID prices — what buyers are currently paying. Used for stop-loss exit pricing."""
    yes_bid = to_decimal(market.get("yes_bid_dollars"))
    no_bid  = to_decimal(market.get("no_bid_dollars"))
    return yes_bid, no_bid

def get_stop_loss_exit_price(side: str, yes_price: Decimal, no_price: Decimal, market=None):
    """
    Get the best available sell price for a stop-loss exit.

    Priority:
    1. Use the live BID price from fresh market data — this is what buyers will
       actually pay right now and will fill an IOC order reliably.
    2. Fall back to the ask-derived estimate only if bid data is unavailable.
    """
    try:
        # Priority 1: use actual bid price from market data
        if market is not None:
            yes_bid, no_bid = get_bid_prices(market)
            if side == "yes" and yes_bid is not None and yes_bid > 0:
                px = yes_bid
                if px < STOP_LOSS_MIN_PRICE: px = STOP_LOSS_MIN_PRICE
                if px > STOP_LOSS_MAX_PRICE: px = STOP_LOSS_MAX_PRICE
                return px.quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
            if side == "no" and no_bid is not None and no_bid > 0:
                px = no_bid
                if px < STOP_LOSS_MIN_PRICE: px = STOP_LOSS_MIN_PRICE
                if px > STOP_LOSS_MAX_PRICE: px = STOP_LOSS_MAX_PRICE
                return px.quantize(Decimal("0.0001"), rounding=ROUND_DOWN)

        # Priority 2: derive from opposite ask (legacy fallback)
        if side == "yes":
            if no_price is None: return None
            px = Decimal("1.00") - Decimal(str(no_price)) - Decimal("0.02")
        else:
            if yes_price is None: return None
            px = Decimal("1.00") - Decimal(str(yes_price)) - Decimal("0.02")
        if px < STOP_LOSS_MIN_PRICE: px = STOP_LOSS_MIN_PRICE
        if px > STOP_LOSS_MAX_PRICE: px = STOP_LOSS_MAX_PRICE
        return px.quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
    except Exception:
        return None

def get_best_exit_price_from_orderbook(ticker: str, side: str, qty: int):
    """
    FIX 2: Walk the live orderbook bid ladder to find the best (highest)
    price at which we can sell `qty` contracts right now.
    Returns the worst-fill price across qty contracts, or None if book is thin.
    """
    try:
        ob = get_orderbook(ticker)
        if ob is None:
            return None
        bids_key = "yes_bids" if side == "yes" else "no_bids"
        bids = ob.get(bids_key, [])
        if not bids:
            return None
        remaining = qty
        worst_price = None
        for level in bids:
            raw_price = level.get("price") or level.get("price_dollars")
            level_qty = int(level.get("quantity", level.get("count", 0)))
            if raw_price is None or level_qty <= 0:
                continue
            px = to_decimal(raw_price)
            if px is None or px <= 0:
                continue
            if px > Decimal("1"):
                px = px / Decimal("100")
            worst_price = px
            remaining -= level_qty
            if remaining <= 0:
                break
        if worst_price is None:
            return None
        worst_price = max(STOP_LOSS_MIN_PRICE, min(STOP_LOSS_MAX_PRICE, worst_price))
        return worst_price.quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
    except Exception as e:
        print(f"ORDERBOOK PRICE ERROR: {e}")
        return None

def abs_drop_too_large(max_drop=0.095, checks=3):
    arr = list(RECENT_ABS_PCTS)
    if len(arr) < checks:
        return False
    recent = arr[-checks:]
    peak = max(recent)
    current = recent[-1]
    return (peak - current) > max_drop

def conviction_score(reason: str, paq: int, bcdp_n: int, bcdp_clean: bool,
                     abs_pct: float, seconds_left: float,
                     entry_price: float | None = None) -> float:
    """
    Single unified conviction score (0–10) at entry time.
    Drives risk tier multiplier — no new gates, no new families.

    Components (all values already in scope at entry):
      PAQ         0–6   → 0.00–3.50  (primary signal quality)
      BCDP        0–5C  → 0.00–2.00  (directional persistence)
      ABS         0%+   → 0.00–2.00  (BTC actually moving)
      Time        0s+   → 0.00–1.00  (room to act)

    Soft modifiers (additive, not gates):
      Family trust: confirm_late / confirm_standard get −0.5
                    PAQ_EARLY_AGG / PAQ_EARLY_CONS get +0.3 (proven earners)
      Entry near 0.50: if abs(entry_price − 0.50) < 0.10 AND abs_pct < 0.05%
                       apply −0.5 (market uncertainty + low movement = weak)

    Tiers:
      LOW  < 5.0  → 0.70×
      MID  5–7    → 1.00×
      HIGH ≥ 7.0  → 1.40×

    v199: Data basis — 67 trades from March 23:
      HIGH (≥7): 11W/2L 85% WR +$14.45 avg +$1.11
      MID (5-7): 28W/10L 74% WR −$7.72 avg −$0.20
      LOW (<5):  10W/6L  62% WR −$12.80 avg −$0.80
    """
    # ── Core setup score ─────────────────────────────────────────────
    paq_score  = min(paq / 6.0, 1.0) * 3.5
    bcdp_score = (min(bcdp_n, 5) / 5.0) * 1.5 + (0.5 if bcdp_clean else 0.0)
    abs_score  = min(abs_pct / 0.30, 1.0) * 2.0   # caps contribution at 0.30%
    secs_score = min(seconds_left / 600.0, 1.0) * 1.0

    score = paq_score + bcdp_score + abs_score + secs_score

    # ── Family soft modifier ──────────────────────────────────────────
    # Grounded in realized P&L per-family — not permanent caps
    _family_mod = {
        "PAQ_EARLY_AGG":   +0.3,
        "PAQ_EARLY_CONS":  +0.3,
        "confirm_late":    -0.5,
        "confirm_standard":-0.3,
    }.get(reason, 0.0)
    score += _family_mod

    # ── Entry uncertainty penalty ─────────────────────────────────────
    # Only fires when BOTH conditions are true: price near coin-flip AND
    # BTC barely moving. Either alone is fine; together = weak setup.
    if (entry_price is not None
            and abs(entry_price - 0.50) < 0.10
            and abs_pct < 0.05):
        score -= 0.5

    return max(0.0, min(score, 10.0))


def conviction_multiplier(score: float) -> tuple[Decimal, str]:
    """Map conviction score to risk multiplier and tier label."""
    if score >= 7.0:
        return Decimal("1.40"), "HIGH"
    if score >= 5.0:
        return Decimal("1.00"), "MID"
    return Decimal("0.70"), "LOW"


def get_risk_dollars(price_dollars: Decimal, reason: str = "", seconds_left: float = 0,
                      current_abs_pct: float | None = None, side: str | None = None) -> Decimal:
    """Risk tiered by market regime:
      $3  — PAQ_STRUCT_GATE on weekends (v222 ladder mode, validation phase).
             Worst-case stop loss ~$0.30-0.60/trade. Scale to $5 after validation.
      $5  — VOLATILE:   BTC moving fast, book thin due to speed.
             LOW_VOLUME: BTC frozen near strike, book thin due to absence.
             STABLE:     Book appears calm but confirmed losses cluster here.
                         March 24 data: STABLE = 0W/4L -$7.59 vs VOLATILE 83% WR +$28.81.
                         Low ABS + tight spread = deceptive calm, not real safety.
                         Exits are as thin as VOLATILE when BTC moves.
      $8  — MODERATE / UNKNOWN. Normal book conditions.
    """
    if reason == "BCDP_FAST_COMMIT":
        return Decimal("9.00")   # v230: scaled with base (was 7.50)
    if reason == "PAQ_STRUCT_GATE" and is_weekend_window():
        return Decimal("3")   # v222/v223: capped exits, capped sizing — scale after clean weekend sessions
    # v234: PAQ_STRUCT_GATE BTC_DEEP_NIGHT weekday → $10
    # Data: 3W/0L, avg BDI 142, zero stop-unfilled, zero thin-book entries in weekday BTC_DN.
    # Simulation: actual $2.12 → projected $3.42 at $10 base (+$1.30/cycle, +$7/month).
    # Safest risk increase in dataset — only clean ✓ SAFE scenario in risk simulation.
    if (reason == "PAQ_STRUCT_GATE"
            and not is_weekend_window()
            and get_session_label() == "BTC_DEEP_NIGHT"):
        return Decimal("10")
    if _regime in ("VOLATILE", "LOW_VOLUME", "STABLE"):
        return Decimal("5")
    # v250: PAQ_EARLY_AGG NY_PRIME $20 base risk
    # Data basis (5 weekdays 3/30-4/3): 18W/2L 90% WR +$48.78 actual.
    # Simulation at $20: +$155.81 net (3.19x multiplier). 0 stop-losses in dataset.
    # Both losses were settled losses (not stops). Conviction multiplier still applied
    # after this base — HIGH (1.30x) → $26, MID (1.00x) → $20, LOW (0.70x) → $14.
    # BDI clamp (BDI<25 → max 3c, BDI<50 → max 5c) still enforced downstream.
    # Scoped to weekday NY_PRIME only — overnight cap and weekend rules unchanged.
    if (reason == "PAQ_EARLY_AGG"
            and not is_weekend_window()
            and get_session_label() == "NY_PRIME"):
        return Decimal("20")
    # v231: session-gated $10 base — NY_PRIME (all other families)
    # Data basis (8 days, 3/23-3/30):
    #   NY_PRIME: 81% WR  +$23.63  2 stop_unfill → $10 supported
    #   ASIA_OPEN / BTC_DEEP_NIGHT / EU_MORNING: $8 (adequate but thinner books)
    if not is_weekend_window() and get_session_label() == "NY_PRIME":
        return Decimal("10")
    return Decimal("8")

def calc_count(price_dollars: Decimal, reason: str = "", seconds_left: float = 0,
               current_abs_pct: float | None = None, side: str | None = None) -> int:
    risk = get_risk_dollars(price_dollars, reason, seconds_left, current_abs_pct, side)
    if price_dollars <= 0:
        return 1
    count = int((risk / price_dollars).to_integral_value(rounding=ROUND_DOWN))
    return max(1, count)

def get_risk_bucket(reason: str, seconds_left: float, price_dollars: Decimal | None = None,
                     current_abs_pct: float | None = None, side: str | None = None) -> str:
    # Must match get_risk_dollars() exactly — used in BUY SNAPSHOT logging
    if _regime in ("VOLATILE", "LOW_VOLUME", "STABLE"):
        return "$5 thin"
    if (reason == "PAQ_EARLY_AGG"
            and not is_weekend_window()
            and get_session_label() == "NY_PRIME"):
        return "$20 PAQ_AGG_NY_PRIME"
    if not is_weekend_window() and get_session_label() == "NY_PRIME":
        return "$10 NY_PRIME"
    return "$8 normal"

def get_bps_min_abs(seconds_left):
    """Return minimum abs% required for BPS-family entries, by time window and session.
    Used exclusively by the bps_late branch (10–179s). bps_premium uses get_prem_abs_floor().
    v241: replaced dt.datetime.now().hour with get_mtn_hour() — canonical DST-aware MTN source.
    v243: reverts v242's 17:00 night-window extension. No bps_late entries exist in
    BTC_DEEP_NIGHT 17-18:xx in 7-day dataset — extension was not data-supported.
    Night window: 19:00–06:00 MTN (original design intent, restored)."""
    hour = get_mtn_hour()
    is_night = 19 <= hour or hour <= 6
    if is_night:
        if 481 <= seconds_left <= 600: return BPS_ABS_NIGHT_481_600
        if 361 <= seconds_left <= 480: return BPS_ABS_NIGHT_361_480
        if 241 <= seconds_left <= 360: return BPS_ABS_NIGHT_241_360
        if 121 <= seconds_left <= 240: return BPS_ABS_NIGHT_121_240
        if   0 <= seconds_left <= 120: return BPS_ABS_NIGHT_0_120
        return 999.0
    if 481 <= seconds_left <= 600: return BPS_ABS_481_600
    if 361 <= seconds_left <= 480: return BPS_ABS_361_480
    if 241 <= seconds_left <= 360: return BPS_ABS_241_360
    if 121 <= seconds_left <= 240: return BPS_ABS_121_240
    if   0 <= seconds_left <= 120: return BPS_ABS_0_120
    return 999.0


def get_prem_abs_floor(seconds_left):
    """Return abs% floor for entries, tightening as time shortens.
    During EU Morning (06-09 UTC / 23-02 MST), adds SESSION_EU_MORNING_ABS_BOOST
    to require more directional confirmation before entry — 39% dead-abs reads
    in that session make low-abs entries unreliable.
    """
    if 481 <= seconds_left <= 600: base = BPS_PREM_ABS_481_600
    elif 361 <= seconds_left <= 480: base = BPS_PREM_ABS_361_480
    elif 241 <= seconds_left <= 360: base = BPS_PREM_ABS_241_360
    else: base = BPS_PREM_ABS_180_240
    if get_session_label() == "EU_MORNING":
        base += SESSION_EU_MORNING_ABS_BOOST
    return base

def get_mtn_hour() -> int:
    """Return current MTN hour (0-23).
    MTN = MDT (UTC-6) Mar-Nov, MST (UTC-7) Nov-Mar.
    Single canonical time source — all session logic derives from this.
    """
    import datetime as _dt
    now_utc = _dt.datetime.now(_dt.timezone.utc)
    year = now_utc.year
    # DST start: second Sunday in March at 2am
    mar1 = _dt.date(year, 3, 1)
    dst_start = _dt.datetime(year, 3, 1 + (6 - mar1.weekday()) % 7 + 7,
                             2, 0, 0, tzinfo=_dt.timezone.utc)
    # DST end: first Sunday in November at 2am
    nov1 = _dt.date(year, 11, 1)
    dst_end = _dt.datetime(year, 11, 1 + (6 - nov1.weekday()) % 7,
                           2, 0, 0, tzinfo=_dt.timezone.utc)
    offset = -6 if dst_start <= now_utc < dst_end else -7
    return (now_utc.hour + offset) % 24


def get_session_label() -> str:
    """Return trading session label based on MTN hour.
    Derives from get_mtn_hour() — no UTC math.
    All windows in MTN.

    Active trading windows:
      17:00-05:00 MTN — overnight + early AM (best performance)
      09:00-14:00 MTN — NY Prime (moderate, monitoring)

    Kill zones (no new entries):
      05:00-09:00 MTN — NY Open (institutional whipsaw)
      14:00-17:00 MTN — NY Close (low edge, high reversal)
    """
    h = get_mtn_hour()
    if  5 <= h <   9: return "NY_OPEN"           # 05:00-09:00 MTN ← kill zone
    if  9 <= h <  14: return "NY_PRIME"          # 09:00-14:00 MTN
    if 14 <= h <  17: return "NY_CLOSE"          # 14:00-17:00 MTN ← kill zone
    if 17 <= h <  21: return "BTC_DEEP_NIGHT"    # 17:00-21:00 MTN
    if 21 <= h <= 23: return "ASIA_OPEN"         # 21:00-00:00 MTN
    if  0 <= h <   3: return "ASIA_OPEN"         # 00:00-03:00 MTN (midnight wrap)
    return                   "EU_MORNING"        # 03:00-05:00 MTN


def is_weekend() -> bool:
    """Return True if current UTC day is Saturday or Sunday.
    Used for weekend-specific trading rules (v221).
    Saturday = isoweekday 6, Sunday = isoweekday 7.
    """
    import datetime as _dt
    return _dt.datetime.now(_dt.timezone.utc).isoweekday() in (6, 7)

def is_weekend_window() -> bool:
    """Return True during the extended no-trade weekend window (v250):
    Friday 23:00 MTN (end of EVENING) through Monday 09:59 MTN (NY_PRIME opens at 10:00).
    Prior window was Friday 17:00+ — extended to protect full EVENING session on Fridays
    and block Monday OVERNIGHT/EU_MORNING/NY_OPEN until NY_PRIME depth is available.
    Derives from get_mtn_hour() — uses canonical DST-aware MTN offset.
    """
    import datetime as _dt
    now_utc = _dt.datetime.now(_dt.timezone.utc)
    year = now_utc.year
    mar1 = _dt.date(year, 3, 1)
    dst_start = _dt.datetime(year, 3, 1 + (6 - mar1.weekday()) % 7 + 7,
                             2, 0, 0, tzinfo=_dt.timezone.utc)
    nov1 = _dt.date(year, 11, 1)
    dst_end = _dt.datetime(year, 11, 1 + (6 - nov1.weekday()) % 7,
                           2, 0, 0, tzinfo=_dt.timezone.utc)
    offset = -6 if dst_start <= now_utc < dst_end else -7
    now_mtn = now_utc + _dt.timedelta(hours=offset)
    wd = now_mtn.weekday()   # 0=Mon, 4=Fri, 5=Sat, 6=Sun
    hr = now_mtn.hour
    # Friday EVENING closes at 23:00 MTN — block from then through end of Sunday
    if (wd == 4 and hr >= 23) or wd in (5, 6):
        return True
    # Monday: block OVERNIGHT/EU_MORNING/NY_OPEN until NY_PRIME opens at 10:00 MTN
    if wd == 0 and hr < 10:
        return True
    return False

# ==================== NEW STRIKE PARSER (Step 1) ====================
def parse_numeric_text(value):
    if value is None:
        return None
    try:
        s = str(value).replace("$", "").replace(",", "").strip()
        m = re.search(r"(-?\\d+(?:\\.\\d+)?)", s)
        if not m:
            return None
        return float(m.group(1))
    except Exception:
        return None

def looks_like_timecode_from_ticker(ticker: str, candidate: float) -> bool:
    """
    Reject values like 141000 from KXBTC15M-26MAR141000-00.
    """
    try:
        if not ticker:
            return False
        m = re.search(r"-(\\d{2}[A-Z]{3})(\\d{6})-\\d{2}$", ticker)
        if not m:
            return False
        hhmmss = int(m.group(2))
        return abs(candidate - hhmmss) < 0.5
    except Exception:
        return False

def get_market_strike(market, current_btc=None):
    """
    Pick the most plausible strike.
    Priority:
    1) explicit numeric strike fields
    2) numeric values parsed from descriptive text fields
    Then reject obvious ticker-timecode mistakes and absurd outliers.
    """
    ticker = str(market.get("ticker", ""))

    candidates = []

    # explicit fields first
    for field in ("floor_strike", "strike_price", "strike"):
        raw = market.get(field)
        val = parse_numeric_text(raw)
        if val is not None and val > 0:
            candidates.append((field, val))

    # descriptive text fallback
    for field in ("title", "subtitle", "yes_sub_title", "no_sub_title"):
        raw = market.get(field)
        if raw:
            val = parse_numeric_text(raw)
            if val is not None and val > 0:
                candidates.append((field, val))

    if not candidates:
        return None

    # remove obvious ticker-timecode mistakes like 141000 from ...141000-00
    filtered = []
    for source, val in candidates:
        if looks_like_timecode_from_ticker(ticker, val):
            continue
        filtered.append((source, val))

    if not filtered:
        return None

    # if BTC is known, choose the closest plausible value to spot
    if current_btc is not None and current_btc > 0:
        plausible = []
        for source, val in filtered:
            ratio = val / current_btc
            # wide enough to avoid false skips, narrow enough to reject absurd junk
            if 0.70 <= ratio <= 1.30:
                plausible.append((source, val, abs(val - current_btc)))

        if plausible:
            plausible.sort(key=lambda x: x[2])
            return float(plausible[0][1])

        # no plausible strike near BTC -> reject
        return None

    # BTC unavailable: accept any filtered candidate that looks like a
    # plausible BTC price (between 10,000 and 200,000) so early-cycle
    # reads don't all get skipped just because Binance was slow
    for source, val in filtered:
        if 10_000 <= val <= 200_000:
            return float(val)

    # nothing passed — give up
    return None

def get_live_position_contracts(ticker: str):
    """Query Kalshi portfolio positions API for the given ticker.
    Returns contracts owned from API when possible.

    CRITICAL SAFETY NET: if the API returns 0 but local memory shows a live
    position on the same ticker, return local memory. This prevents the API
    returning an empty list (wrong field name, propagation delay, network hiccup)
    from silently killing a stop-loss exit — the failure mode observed in v71
    where PAQ STOP printed but no ladder started (lost -$4.62 to full settlement).
    """
    global last_traded_ticker, last_entry_contracts
    api_qty = None
    try:
        resp = signed_request("GET", "/portfolio/positions", params={"ticker": ticker, "limit": 10})
        if resp.status_code == 200:
            data = resp.json()
            # Kalshi may return field as market_positions, positions, or nested
            positions = data.get("market_positions", data.get("positions", []))
            for pos in positions:
                t = (pos.get("market_id") or pos.get("ticker") or
                     pos.get("market_ticker") or pos.get("event_ticker") or "")
                if t == ticker:
                    qty = pos.get("position", pos.get("contracts_owned",
                          pos.get("quantity", 0)))
                    api_qty = max(0, int(qty))
                    break
            if api_qty is None:
                api_qty = 0  # ticker not found in positions list
        else:
            print(f"          → POS QUERY HTTP {resp.status_code} — using local")
    except Exception as e:
        print(f"          → POS QUERY FAILED — using local")

    # Safety net: API said 0 but local memory disagrees
    local_qty = max(0, int(last_entry_contracts)) if ticker == last_traded_ticker else 0
    if api_qty == 0 and local_qty > 0:
        print(f"          → POS WARNING | API 0 local {local_qty}")
        return local_qty
    if api_qty is not None:
        return api_qty
    # API call failed entirely — use local memory
    return local_qty

def get_order_status(order_id: str):
    try:
        resp = signed_request("GET", f"/portfolio/orders/{order_id}")
        if resp.status_code == 200:
            data = resp.json()
            return data.get("order", data)
        return None
    except Exception:
        return None

def cancel_order(order_id: str):
    try:
        resp = signed_request("DELETE", f"/portfolio/orders/{order_id}")
        return resp.status_code in (200, 204)
    except Exception:
        return False

def execute_rapid_stop_loss_exit(ticker: str, side: str, yes_price: Decimal, no_price: Decimal, reason_label: str, ladder_override=None, metrics=None, market=None, ob_snapshot=None, pre_drop_anchor=None, max_contracts=None):
    remaining = get_live_position_contracts(ticker)
    if remaining <= 0:
        # Classify: did the API genuinely find zero, or was this a false-zero?
        # The safety net in get_live_position_contracts already resolves API/local
        # disagreements — if we still get 0 here, it's real (or both agree = 0).
        print(f"          → STOP BLOCKED | {reason_label} | no position")
        return {
            "status": "no_exit",
            "filled_qty": 0,
            "avg_exit_price": None,
            "remaining_qty": 0,
            "note": "NO_POSITION",
        }
    global _any_stop_fired
    _any_stop_fired = True   # block all other stop mechanisms for this position

    # BDI-aware stop sizing: send what the book can absorb.
    # If BDI >= remaining → full exit (normal path).
    # If BDI < remaining → partial exit at BDI contracts, hold remainder.
    # If BDI == 0 → book is dead, no ladder attempt, position held.
    # Single orderbook call for both BDI and best bid — reused for anchor below
    _stop_ob = ob_snapshot if ob_snapshot is not None else get_orderbook(ticker)
    _stop_ob_key = "yes_dollars" if side == "yes" else "no_dollars"
    _stop_ob_levels = (_stop_ob.get(_stop_ob_key) or []) if _stop_ob else []
    _ref_price = float(yes_price if side == "yes" else no_price)
    # v184: widen BDI scan to ±0.10 — buyers above ref price are better
    # fills; buyers below are still reachable with wider ladder.
    _stop_bdi_ceil  = _ref_price + 0.10
    _stop_bdi_floor = _ref_price - 0.10
    _stop_bdi = 0
    for _lvl in _stop_ob_levels:
        try:
            _lpx = float(_lvl[0])
            if _lpx > 1.0: _lpx /= 100
            _lqty = float(_lvl[1])
            if _lqty > 100: _lqty /= 100
            if _stop_bdi_floor <= _lpx <= _stop_bdi_ceil:
                _stop_bdi += int(_lqty)
        except Exception:
            pass

    if _stop_bdi == 0:
        # v245: single-hold-max rule.
        # First BDI=0 on this position: defer one poll, record price, arm escalation.
        # Second BDI=0: escalate — force full ladder regardless of book depth.
        # Rationale: BDI=0 hold is a timing bet that liquidity returns before price
        # moves further adverse. 8-session data shows this bet fails in ~90% of cases,
        # turning manageable losses into larger ones. One deferral is kept to handle
        # momentary book gaps; a second hold is never allowed.
        global _bdi0_hold_count, _bdi0_hold_px, _bdi0_exit_pending
        if _bdi0_hold_count == 0:
            _bdi0_hold_px      = float(yes_price if side == "yes" else no_price)
            _bdi0_hold_count   = 1
            _bdi0_exit_pending = True  # v247: arm forced exit on next poll
            print(f"          → STOP HOLD | {reason_label} | {side.upper()} | BDI 0 \u2019{_bdi0_hold_px:.4f} {remaining}c held | EXIT_PENDING_BDI0_HOLD1")
            return {
                "status": "unfilled",
                "filled_qty": 0,
                "avg_exit_price": None,
                "remaining_qty": remaining,
                "note": "BDI_ZERO",
            }
        # _bdi0_hold_count >= 1: escalate — no further courtesy holds on this position
        _px_now   = float(yes_price if side == "yes" else no_price)
        _px_delta = round(_px_now - (_bdi0_hold_px or _px_now), 4)
        print(
            f"          → EXIT_ESCALATED_AFTER_BDI0 | {reason_label} | {side.upper()} | {remaining}c"
            f" | hold_px {(_bdi0_hold_px or 0):.4f} → now {_px_now:.4f} ({_px_delta:+.4f})"
            f" | forcing full ladder"
        )
        _stop_bdi = remaining  # bypass BDI sizing — attempt entire remaining position

    exit_qty = min(remaining, _stop_bdi)
    # Environment partial cap: if caller requested max_contracts, honour it
    if max_contracts is not None and max_contracts < exit_qty:
        exit_qty = max_contracts
    _exit_mode = "FULL" if exit_qty == remaining else f"PARTIAL {exit_qty}/{remaining}"
    print(f"          → STOP | {side.upper()} | {reason_label} | {_exit_mode} | {exit_qty}/{remaining}c")
    total_filled_qty = 0
    total_filled_notional = Decimal("0")
    live_remaining = exit_qty
    # Anchor priority — always use current executable bid, never stale pre-drop:
    # 1. trigger snapshot bid — where the book IS right now
    # 2. orderbook best bid — from same snapshot used for BDI
    # 3. held price — last resort
    # pre_drop_anchor: used for detection/severity logging only, NOT for order placement.
    # Rationale: once price snapped from 0.67 to 0.49, the book is no longer at 0.67.
    # Anchoring there guarantees misses. Current bid is where fills actually happen.
    locked_anchor = yes_price if side == "yes" else no_price
    locked_anchor_source = "fallback"
    if pre_drop_anchor is not None and pre_drop_anchor > Decimal("0.01"):
        _severity = float(pre_drop_anchor) - float(yes_price if side == "yes" else no_price)
        print(f"          → STOP SEVERITY | pre_drop {float(pre_drop_anchor):.4f} | current {float(yes_price if side == 'yes' else no_price):.4f} | snap {_severity:.4f}")
    if market is not None:
        _yes_bid_s, _no_bid_s = get_bid_prices(market)
        _snap_bid = _yes_bid_s if side == "yes" else _no_bid_s
        if _snap_bid is not None and _snap_bid > Decimal("0.01"):
            locked_anchor = _snap_bid
            locked_anchor_source = "snap_bid"
    if locked_anchor_source == "fallback" and _stop_ob_levels:
        try:
            _best_px = float(_stop_ob_levels[-1][0])
            if _best_px > 1.0: _best_px /= 100
            if _best_px > 0.01:
                locked_anchor = Decimal(str(round(_best_px, 2)))
                locked_anchor_source = "ob_best_bid"
        except Exception:
            pass

    if locked_anchor is None or locked_anchor <= 0:
        locked_anchor = yes_price if side == "yes" else no_price
        locked_anchor_source = "fallback_passthrough"
    print(f"          → STOP ANCHOR | {float(locked_anchor):.4f} [{locked_anchor_source}]")

    _ladder = ladder_override if ladder_override is not None else STOP_LOSS_LADDER_OFFSETS[:STOP_LOSS_MAX_ATTEMPTS]
    for idx, offset in enumerate(_ladder, start=1):
        # All attempts use the same locked anchor — no re-fetch drift
        anchor = locked_anchor

        # Attempt 1: order at best bid (offset=0.00). Each retry steps down
        # by the ladder offset to increase fill probability.
        px = anchor - offset
        if px < STOP_LOSS_MIN_PRICE:
            px = STOP_LOSS_MIN_PRICE
        if px > STOP_LOSS_MAX_PRICE:
            px = STOP_LOSS_MAX_PRICE
        px = px.quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
        if live_remaining <= 0:
            break
        resp = place_exit_order(ticker, side, px, live_remaining)
        if resp.status_code not in (200, 201):
            time.sleep(STOP_LOSS_REPRICE_DELAY)
            continue
        payload = resp.json() if resp.content else {}
        order_data = payload.get("order", payload)
        order_id = order_data.get("order_id") or order_data.get("id")
        if not order_id:
            time.sleep(STOP_LOSS_REPRICE_DELAY)
            continue
        filled_count_this_order = 0
        full_fill = False
        remaining_count_this_order = None
        for _ in range(3):
            status_data = get_order_status(order_id)
            if status_data:
                status = str(status_data.get("status", "")).lower()
                fill_count_fp = status_data.get("fill_count_fp", status_data.get("filled_count", 0))
                try:
                    filled_count_this_order = int(Decimal(str(fill_count_fp)))
                except Exception:
                    filled_count_this_order = 0
                remaining_count_fp = status_data.get("remaining_count_fp")
                try:
                    remaining_count_this_order = int(Decimal(str(remaining_count_fp))) if remaining_count_fp is not None else None
                except Exception:
                    remaining_count_this_order = None
                if status == "filled" or (remaining_count_this_order == 0 and filled_count_this_order > 0):
                    full_fill = True
                    break
            time.sleep(0.1)
        if filled_count_this_order > 0:
            total_filled_qty += filled_count_this_order
            total_filled_notional += px * Decimal(str(filled_count_this_order))
            live_remaining = max(0, live_remaining - filled_count_this_order)
        if full_fill and filled_count_this_order == 0:
            cancel_success = cancel_order(order_id)
            time.sleep(STOP_LOSS_REPRICE_DELAY)
            continue
        if full_fill and live_remaining <= 0 and total_filled_qty > 0:
            avg_exit_price = (total_filled_notional / Decimal(str(total_filled_qty))).quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
            print(f"          → STOP FILL | attempt {idx} | {float(avg_exit_price):.4f}")
            return {
                "status": "full_exit",
                "filled_qty": total_filled_qty,
                "avg_exit_price": avg_exit_price,
                "remaining_qty": 0,
                "note": f"FULL_FILL_ATTEMPT_{idx}",
            }
        if live_remaining > 0:
            cancel_success = cancel_order(order_id)
            time.sleep(STOP_LOSS_REPRICE_DELAY)
    if total_filled_qty > 0:
        avg_exit_price = (total_filled_notional / Decimal(str(total_filled_qty))).quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
        print(f"          → STOP PARTIAL | {total_filled_qty}c @ {float(avg_exit_price):.4f} | {live_remaining}c held")
        return {
            "status": "partial_exit",
            "filled_qty": total_filled_qty,
            "avg_exit_price": avg_exit_price,
            "remaining_qty": live_remaining,
            "note": f"PARTIAL_EXIT_AFTER_LADDER_FILLED_{total_filled_qty}",
        }
    return {
        "status": "no_exit",
        "filled_qty": 0,
        "avg_exit_price": None,
        "remaining_qty": live_remaining,
        "note": "EXIT_FAILED_AFTER_ALL_ATTEMPTS",
    }

def compute_bcdp(bps_hist):
    """Raw BPS Consecutive Directional Persistence.
    Counts consecutive same-signed BPS values from newest backward.
    BPS=0 is skipped (flat = ignored, not a break).
    Returns int 0-5.
    """
    current_sign = None
    for b in reversed(list(bps_hist)):
        if b > 0: current_sign = 1; break
        elif b < 0: current_sign = -1; break
    if current_sign is None: return 0
    count = 0
    for b in reversed(list(bps_hist)):
        if b == 0: continue
        if (b > 0 and current_sign == 1) or (b < 0 and current_sign == -1):
            count += 1
        else:
            break
    return count


def compute_bcdp_clean(bps_hist):
    """BCDP_CLEAN: True when BCDP >= 1 AND no opposing sign anywhere in
    the full 5-poll window. A 'dirty' signal has a recent flip lurking
    even if current streak looks clean.
    Returns bool.
    """
    current_sign = None
    for b in reversed(list(bps_hist)):
        if b > 0: current_sign = 1; break
        elif b < 0: current_sign = -1; break
    if current_sign is None: return False
    for b in bps_hist:
        if b == 0: continue
        if (b > 0 and current_sign == -1) or (b < 0 and current_sign == 1):
            return False  # opposing sign found anywhere in window
    return compute_bcdp(bps_hist) >= 1


def _active_regime():
    """Resolve effective regime with MODERATE as fallback for ambiguous states."""
    r = _regime if _regime not in ("UNKNOWN", None, "") else "MODERATE"
    if _book_env == "LOW_VOLUME" and r != "LOW_VOLUME":
        return "LOW_VOLUME"
    return r


def premium_bps_mag_pass(bps_history) -> tuple:
    """Environment-calibrated bps_premium magnitude floor.
    Returns (passes: bool, note: str)

    VOLATILE/MODERATE: 2 of 5 with |BPS| >= 3  — real commitment required
    STABLE:            1 of 5 with |BPS| >= 2  — slow grind, lower bar
    LOW_VOLUME:        3 of 5 with |BPS| >= 3  — noise env, raise bar
    Fallback:          MODERATE rules
    """
    r = _active_regime()
    hist = list(bps_history)
    if r == "LOW_VOLUME":
        count = sum(1 for b in hist if abs(b) >= 3)
        return count >= 3, f"mag LOW_VOL {count}/5>=3"
    elif r == "STABLE":
        count = sum(1 for b in hist if abs(b) >= 2)
        return count >= 1, f"mag STABLE {count}/5>=2"
    else:  # VOLATILE, MODERATE, fallback
        count = sum(1 for b in hist if abs(b) >= 3)
        return count >= 2, f"mag {r} {count}/5>=3"


def get_post_entry_phi(paq_now: int, paq_entry: int, live_bps: float,
                       entry_bps: float, held_px: float, entry_px: float,
                       bdi: int, side: str) -> int:
    """Post-entry health score 0–100. Higher = thesis intact, let it run.
    Lower = thesis degrading, tighten protection.

    Components:
      PAQ decay:      each point of PAQ drop from entry costs 15pts
                      (most important — PAQ is the structural signal)
      BPS flip:       if BPS has flipped sign vs entry, costs 8pts per unit of divergence
      Price giveback: fraction of move given back costs up to 25pts
      BDI penalty:    thin book (BDI<20) costs up to 20pts
                      (signals exit difficulty if thesis reverses)

    Design: does NOT penalize for low abs at entry — that is already gated
    at entry. PHI only measures post-entry degradation.
    """
    # PAQ decay — main signal
    paq_decay = max(0, paq_entry - paq_now) * 15

    # BPS flip — directional signal reversed
    bps_flipped = (entry_bps > 0 and live_bps < 0) or (entry_bps < 0 and live_bps > 0)
    bps_penalty = abs(live_bps - entry_bps) * 8 if bps_flipped else 0

    # Price giveback — how much of the move has reversed
    if side == "yes":
        move = entry_px - held_px   # positive = price fell below entry (bad)
    else:
        move = held_px - entry_px   # positive = price rose above NO entry (bad)
    giveback_pct = max(0.0, move) / max(entry_px, 0.01)
    giveback_penalty = min(25, giveback_pct * 150)

    # BDI thin-book penalty
    bdi_penalty = max(0, 20 - bdi) * 1.0  # up to 20pts when BDI→0

    phi = 100 - paq_decay - bps_penalty - giveback_penalty - bdi_penalty
    return max(0, min(100, int(phi)))


def paq_struct_continuity_check(entry_abs: float, current_abs: float) -> tuple:
    """Environment-calibrated PAQ_STRUCT abs continuity decision.
    Returns (should_derisk: bool, note: str)

    VOLATILE:    Never derisk — stop system handles flat abs in fast markets
    LOW_VOLUME:  3 polls / +0.020% — act sooner, book is thin
    STABLE:      6 polls / +0.015% — more patience, slow commits are valid
    MODERATE:    4 polls / +0.030% — baseline
    Fallback:    MODERATE rules
    """
    r = _active_regime()
    if r == "VOLATILE":
        return False, "VOLATILE skip"
    recent = list(RECENT_ABS_PCTS)
    recent3 = recent[-3:] if len(recent) >= 3 else []
    improvement = current_abs - entry_abs
    if r == "LOW_VOLUME":
        polls_needed, imp_thresh, trend_delta = 3, 0.020, 0.015
    elif r == "STABLE":
        polls_needed, imp_thresh, trend_delta = 6, 0.015, 0.010
    else:  # MODERATE / fallback
        polls_needed, imp_thresh, trend_delta = 4, 0.030, 0.020
    if last_entry_reads < polls_needed:
        return False, f"{r} {last_entry_reads}/{polls_needed} polls"
    trending = len(recent3) >= 3 and recent3[-1] > recent3[0] + trend_delta
    committed = improvement >= imp_thresh
    if committed or trending:
        return False, f"{r} committed {improvement:+.3f} or trending"
    return True, f"{r} no commit {improvement:+.3f}<{imp_thresh} after {last_entry_reads}p"


def classify_book_environment(ob, abs_pct: float) -> str:
    """Real-time book environment from a single orderbook snapshot.
    Available from poll 1 — no calibration window needed.

    Signals:
      total_depth   : sum of all bid contracts within $0.10 on both sides
      spread        : YES_bid + NO_bid - 1.00  (vig — higher = thinner book)
      asymmetry     : directional bias from depth imbalance (0=balanced, 1=fully one-sided)

    Classification:
      VOLATILE   : deep + wide spread + high abs — real move, real participation
      LOW_VOLUME : shallow + wide spread + low abs — noise, not signal
      MODERATE   : medium depth, normal spread
      STABLE     : deep + tight spread — liquid, slow
    """
    global _book_total_depth, _book_spread, _book_asymmetry
    if ob is None:
        return "UNKNOWN"
    try:
        def sum_depth(levels, floor=0.0):
            total = 0
            for lvl in (levels or []):
                try:
                    px  = float(lvl[0]); qty = float(lvl[1])
                    if px > 1.0: px /= 100
                    if qty > 100: qty /= 100
                    if px >= floor:
                        total += int(qty)
                except Exception:
                    pass
            return total

        yes_levels = ob.get("yes_dollars") or []
        no_levels  = ob.get("no_dollars")  or []

        # Best bids
        yes_best = float(yes_levels[-1][0]) / (100 if float(yes_levels[-1][0]) > 1 else 1) if yes_levels else 0.0
        no_best  = float(no_levels[-1][0])  / (100 if float(no_levels[-1][0]) > 1  else 1) if no_levels  else 0.0

        # Spread: cost to cross — higher = thinner book
        _book_spread = max(0.0, round(yes_best + no_best - 1.0, 4))

        # Depth within $0.10 of best bid on each side
        yes_depth = sum_depth(yes_levels, floor=yes_best - 0.10)
        no_depth  = sum_depth(no_levels,  floor=no_best  - 0.10)
        _book_total_depth = yes_depth + no_depth

        # Asymmetry: how one-sided is the depth (0=balanced, 1=all on one side)
        if _book_total_depth > 0:
            _book_asymmetry = abs(yes_depth - no_depth) / _book_total_depth
        else:
            _book_asymmetry = 0.0

        # Classification
        deep   = _book_total_depth >= 150
        medium = _book_total_depth >= 50
        thin   = _book_total_depth < 50
        wide   = _book_spread >= 0.06
        tight  = _book_spread < 0.03
        moving = abs_pct >= 0.08

        if thin and wide and not moving:
            return "LOW_VOLUME"   # nobody home, BPS is noise
        elif (deep or medium) and wide and moving:
            return "VOLATILE"     # real participation behind real movement
        elif deep and tight:
            return "STABLE"       # liquid, slow
        elif medium or deep:
            return "MODERATE"
        else:
            return "LOW_VOLUME"   # shallow book regardless of spread
    except Exception:
        return "UNKNOWN"


def update_market_regime(abs_pct: float, bps: float, yes_price, no_price):
    global _regime, _pending_regime_display
    """
    Collect microstructure data each poll and classify the market regime.
    After REGIME_CALIBRATION_POLLS reads (~5 min), outputs one of:
      VOLATILE   : genuine BTC movement — high abs AND wide BPS range.
                   Fast committed moves. Thin books due to speed, not absence.
      LOW_VOLUME : BTC frozen near strike — low abs BUT wide BPS range.
                   Price oscillates on thin order flow noise, not real BTC signal.
                   Books thin due to absence of participation, not speed.
                   Take profits fast — upside is fragile, reversal is random.
      MODERATE   : balanced conditions — directional but not extreme.
      STABLE     : deep book, slow movement — hold longer.
    Key distinction: VOLATILE = abs high + bps_range high.
                     LOW_VOLUME = abs LOW + bps_range high (noise, not signal).
    Continues updating via rolling 20-sample window thereafter.
    """
    global _regime, _regime_poll_count, _regime_abs_samples, _regime_bps_samples, _regime_spread_samples

    _regime_poll_count += 1
    _regime_abs_samples.append(abs_pct)
    _regime_bps_samples.append(float(bps))
    spread = float(yes_price or 0.5) + float(no_price or 0.5) - 1.0  # vig: >0 = thin book
    _regime_spread_samples.append(spread)

    if len(_regime_abs_samples) > 20:
        _regime_abs_samples.pop(0)
        _regime_bps_samples.pop(0)
        _regime_spread_samples.pop(0)

    if _regime_poll_count >= REGIME_CALIBRATION_POLLS:
        avg_abs  = sum(_regime_abs_samples) / len(_regime_abs_samples)
        bps_rng  = max(_regime_bps_samples) - min(_regime_bps_samples)
        avg_sprd = sum(_regime_spread_samples) / len(_regime_spread_samples)

        old_regime = _regime
        sess = get_session_label()
        # Session-aware regime biasing.
        # EU_MORNING / EU_ACTIVE: historically choppy — thin books, stop failures confirmed.
        # BTC_DEEP_NIGHT / ASIA_OPEN: more directional — BTC commits, trends hold.
        # Bias adjusts the VOLATILE threshold so session character is priced in
        # before the rolling window has enough data.
        _chop_session  = sess in ("EU_MORNING", "EU_ACTIVE")
        _trend_session = sess in ("BTC_DEEP_NIGHT", "ASIA_OPEN")
        if _chop_session:
            _vol_abs_thresh = 0.08   # easier to classify VOLATILE in chop sessions
            _vol_bps_thresh = 5
        elif _trend_session:
            _vol_abs_thresh = 0.20   # harder to classify VOLATILE in trending sessions
            _vol_bps_thresh = 10
        else:
            _vol_abs_thresh = 0.15   # standard
            _vol_bps_thresh = 8
        # LOW_VOLUME: BTC frozen (low abs) but BPS flipping (thin-book noise).
        # Discriminator: bps_range wide relative to abs — the move is order-flow
        # noise, not genuine BTC pressure. Price oscillates randomly near fair value.
        # This is distinct from VOLATILE where both abs AND bps_range are elevated.
        _bps_noise_ratio = bps_rng / max(avg_abs * 100, 0.01)  # BPS range per unit of abs%
        _low_vol = avg_abs < 0.04 and bps_rng >= 3 and _bps_noise_ratio > 50

        if _low_vol:
            new_regime = "LOW_VOLUME"
        elif avg_abs > _vol_abs_thresh or bps_rng > _vol_bps_thresh or avg_sprd > 0.08:
            new_regime = "VOLATILE"
        elif avg_abs > 0.06 or bps_rng > 4 or avg_sprd > 0.04:
            new_regime = "MODERATE"
        else:
            new_regime = "STABLE"

        # Book-environment agreement check:
        # If rolling window and book env agree → high confidence, use it.
        # If they disagree → book env wins for VOLATILE/LOW_VOLUME
        #   (instantaneous depth is more reliable for those two states).
        if _book_env != "UNKNOWN":
            if _book_env in ("VOLATILE", "LOW_VOLUME") and _book_env != new_regime:
                new_regime = _book_env  # book overrides window for thin/volatile states

        if new_regime != old_regime:
            _regime = new_regime
            _regime_display = {
                'VOLATILE':   'Volatile Market',
                'MODERATE':   'Moderate Market',
                'STABLE':     'Stable Market',
                'LOW_VOLUME': 'Low Volume',
            }.get(_regime, _regime)
            _pending_regime_display = _regime_display


def check_partial_harvest(yes_price, no_price, seconds_left, live_bps,
                           entry_price=None, entry_contracts=None,
                           trade_age_secs=0):
    """
    Remaining-upside harvest ladder.

    S_trigger = entry + (1.00 - entry) × regime_fraction
    Scales automatically at any entry — never exceeds 1.00.

      VOLATILE:   25% / 50% / 72% of remaining (capture early, flip risk high)
      MODERATE:   35% / 60% / 80% of remaining (standard balance)
      STABLE:     40% / 65% / 85% of remaining (wait for more)
      LOW_VOLUME: 20% / 40% / 60% of remaining (thin book — take quickly)

    Min gain floor: $0.06/contract. Hard ceiling: 0.96.
    Final 25% always rides to trail stop or settlement.
    """
    global harvest_s1_done, harvest_s2_done, harvest_s3_done
    global harvest_s1_reads, harvest_s2_reads, harvest_s3_reads
    global harvest_s1_count, harvest_s1_fire_px, harvest_s1_zone_left
    global harvest_total_sold

    if last_entry_contracts <= 0 or entry_price is None:
        return False, None, 0
    if yes_price is None or no_price is None:
        return False, None, 0

    held_px   = yes_price if last_side == "yes" else no_price
    entry_px  = Decimal(str(entry_price))
    gain      = held_px - entry_px
    remaining = last_entry_contracts

    # Dead-book gate: YES fills above 0.97 are structurally thin — NO buyers exist.
    # Log data confirms: every YES harvest miss at 0.98+ got zero fill.
    # NO-side: book stays liquid through 0.97+ (confirmed fills at 0.938, 0.958).
    # Gate: YES held >= 0.970 → skip harvest (book dead for YES sells).
    #        NO held >= 0.995 → skip (standard ceiling, NO-side fills well to 0.99).
    if last_side == "yes" and held_px >= Decimal("0.970"):
        harvest_s1_reads = harvest_s2_reads = harvest_s3_reads = 0
        return False, None, 0
    if last_side == "no" and held_px >= Decimal("0.995"):
        harvest_s1_reads = harvest_s2_reads = harvest_s3_reads = 0
        return False, None, 0

    # Budget: max 75% harvested (3 tranches of 25%), last 25% always rides
    max_harvestable = int(entry_contracts * HARVEST_MAX_RATIO)
    if harvest_total_sold >= max_harvestable:
        return False, None, 0

    # Regime → gain thresholds via remaining-upside fractions
    # S_trigger = entry + (1.00 - entry) × fraction
    # Scales automatically — never exceeds 1.00, proportional to position potential
    _effective_regime = _regime
    # Before rolling window calibrates (UNKNOWN), use real-time book env
    if _effective_regime == "UNKNOWN" and _book_env != "UNKNOWN":
        _effective_regime = _book_env
    elif _effective_regime == "UNKNOWN" and get_session_label() == "EU_MORNING":
        _effective_regime = "LOW_VOLUME"
    _fracs = HARVEST_UPSIDE_FRACS.get(_effective_regime, HARVEST_UPSIDE_FRACS["UNKNOWN"])
    _remaining_upside = Decimal("1.00") - entry_px
    g1 = (_remaining_upside * Decimal(str(_fracs[0]))).quantize(Decimal("0.001"))
    g2 = (_remaining_upside * Decimal(str(_fracs[1]))).quantize(Decimal("0.001"))
    g3 = (_remaining_upside * Decimal(str(_fracs[2]))).quantize(Decimal("0.001"))

    # Min gain floor — skip stage if gain/contract below threshold
    _min = HARVEST_MIN_GAIN_PER_CONTRACT
    if g1 < _min: g1 = _min
    if g2 < _min: g2 = max(_min, g1 + _min)
    if g3 < _min: g3 = max(_min, g2 + _min)

    # Hard ceiling — never attempt harvest above 0.96 (book dies above)
    _ceil = Decimal("0.96") - entry_px
    g1 = min(g1, _ceil * Decimal("0.40"))
    g2 = min(g2, _ceil * Decimal("0.70"))
    g3 = min(g3, _ceil * Decimal("0.95"))

    # YES-side urgency: fire harvests 15% earlier than calibrated thresholds.
    # YES books thin above 0.90 — harvest attempts at 0.93+ frequently get zero fill.
    # Data confirms: all YES harvest misses in tonight's log were at 0.91-0.96.
    # NO-side keeps full thresholds (confirmed fills at 0.93-0.97).
    if last_side == "yes":
        g1 = (g1 * Decimal("0.85")).quantize(Decimal("0.001"))
        g2 = (g2 * Decimal("0.85")).quantize(Decimal("0.001"))
        g3 = (g3 * Decimal("0.85")).quantize(Decimal("0.001"))

    # Cap thresholds to available headroom (dead-book ceiling is 0.97)
    # For late entries like 0.86, spread 3 tranches evenly across headroom
    # so all 3 have a chance to fire rather than all compressing to same level
    _headroom = Decimal("0.97") - entry_px
    if _headroom > Decimal("0.01"):
        _h = float(_headroom)
        # Space evenly: S1=33%, S2=66%, S3=99% of headroom (capped at originals)
        g1 = min(g1, Decimal(str(round(_h * 0.33, 3))))
        g2 = min(g2, Decimal(str(round(_h * 0.66, 3))))
        g3 = min(g3, Decimal(str(round(_h * 0.99, 3))))

    # Tranche size: floor(entry * 0.25), leave at least 1 contract live
    def tranche_count():
        raw = max(1, round(entry_contracts * float(HARVEST_TRANCHE_RATIO)))
        budget = max_harvestable - harvest_total_sold
        return min(raw, budget, remaining - 1)

    # Dynamic confirm reads per stage:
    # S1: 2 reads normally — confirm move is real before committing early noise
    #     EXCEPTION: 1 read when trade_age >= 300s AND position in profit
    #     After 5+ minutes, the first real profit window matters more than confirmation purity.
    #     Data: 04:23:33 YES=0.82 (+0.11) fired 1 of 2 reads then reverted — never captured.
    # S2: 1 read  — already in profit after S1, fire quickly on next qualifying read
    # S3: 1 read  — banked 50% already, lock third tranche immediately
    _aged_position = trade_age_secs >= 300
    _in_profit     = gain > Decimal("0")
    S1_READS = 1 if (_aged_position and _in_profit) else 2
    S2_READS = 1
    S3_READS = 1

    # ── WEEKEND FORCED HARVEST AT 0.90 (v221) ──────────────────────────
    # Data: weekend harvest fills 100% at 0.88-0.92, phantom book starts >0.95.
    # On losses that briefly hit 0.90 then reversed: forcing 50% exit at 0.90
    # saves $3.74 on losses, costs $1.12 on winners. Net +$2.87.
    # Grok raw-log confirmation: fills viable at 0.88-0.92 across 3/21-3/22.
    # Only fires once (uses harvest_s1_done as proxy), requires S1 not yet done,
    # position in profit above 0.90, and weekend day.
    _weekend_harvest_px = Decimal("0.90")
    if (is_weekend_window()
            and not harvest_s1_done
            and held_px >= _weekend_harvest_px
            and gain > Decimal("0")):
        _wknd_qty = max(1, int(entry_contracts * 0.50))
        budget = max_harvestable - harvest_total_sold
        _wknd_qty = min(_wknd_qty, budget, remaining - 1)
        if _wknd_qty > 0:
            return True, "WEEKEND_90", _wknd_qty

    # ── WEEKEND STRUCT LADDER (v222) ────────────────────────────────────────
    # Applies only to PAQ_STRUCT_GATE entries on Saturday/Sunday.
    # Fixed rungs: 25%@0.65, 25%@0.72, full close@0.80.
    # Rationale: STRUCT enters at 0.38–0.65 (coil). Books thin above 0.85.
    # Exit at 0.80 captures the directional commit before phantom zone.
    # Data: LOST $19.28 actual → WON $11.25 with this ladder. Net +$30.53.
    # AGG/bps/BCDP: completely unaffected — their harvest logic runs below.
    if _weekend_struct_entry and last_entry_price is not None:
        _wsl_entry = float(last_entry_price)
        _wsl_r1 = Decimal("0.65")
        _wsl_r2 = Decimal("0.72")
        _wsl_exit = Decimal("0.80")
        _wsl_r1_qty = max(1, round(entry_contracts * 0.25))
        _wsl_r2_qty = max(1, round(entry_contracts * 0.25))

        if not harvest_s1_done and held_px >= _wsl_r1 and gain > Decimal("0"):
            count = min(_wsl_r1_qty, remaining - 1)
            if count > 0:
                return True, "WSL_R1", count

        if harvest_s1_done and not harvest_s2_done and held_px >= _wsl_r2:
            count = min(_wsl_r2_qty, remaining - 1)
            if count > 0:
                return True, "WSL_R2", count

        if harvest_s1_done and held_px >= _wsl_exit:
            count = remaining  # full close — exit everything
            if count > 0:
                return True, "WSL_EXIT", count

        return False, None, 0  # STRUCT weekend: skip standard harvest ladder

    # ── Standard harvest ladder (all other families + non-weekend STRUCT) ─
    if not harvest_s3_done and harvest_s2_done and gain >= g3:
        harvest_s3_reads += 1
        harvest_s1_reads = harvest_s2_reads = 0
        if harvest_s3_reads >= S3_READS:
            count = tranche_count()
            if count > 0:
                return True, 3, count
    else:
        harvest_s3_reads = 0

    # ── Stage 2 ───────────────────────────────────────────────────
    if not harvest_s2_done and harvest_s1_done and gain >= g2:
        harvest_s2_reads += 1
        harvest_s1_reads = harvest_s3_reads = 0
        if harvest_s2_reads >= S2_READS:
            count = tranche_count()
            if count > 0:
                return True, 2, count
    else:
        harvest_s2_reads = 0

    # ── Stage 1 ───────────────────────────────────────────────────
    # v170: 25% gain OR trigger for PAQ_EARLY_AGG and bps_premium
    # When held price is >= 25% above entry, fire S1 immediately on 1 read.
    # Bypasses the 2-read + BDI confirmation that kills harvest windows
    # on pump-and-reverse trades (peak reached but never captured).
    # Scoped to mid-price entry families where this pattern recurs.
    # High-price entries (0.76+) have 25% threshold at 0.95+ — unreachable,
    # so this naturally does not interfere with confirm_late or high entries.
    # v231: S1 uses HARVEST_S1_TRANCHE_RATIO (0.60) not the global 0.33.
    # v231: S1 re-trigger allowed up to 2 total fires — price may retrace
    # back to S1 zone after first fire; second fire locks more on the bounce.
    # Cap at 2: third fire would be <5% of original position, noise.
    def s1_tranche_count():
        raw = max(1, round(entry_contracts * float(HARVEST_S1_TRANCHE_RATIO)))
        budget = max_harvestable - harvest_total_sold
        return min(raw, budget, remaining - 1)

    # v231: Zone-exit reset for S1 re-trigger
    # After first S1 fires, track whether price has retreated below the fire zone.
    # Re-trigger only once price genuinely exits (3% below first fire price) then
    # re-enters. Prevents double-fire on sticky tape at the same level.
    if harvest_s1_count == 1 and harvest_s1_fire_px is not None and not harvest_s1_zone_left:
        _zone_exit_threshold = harvest_s1_fire_px * 0.97
        if float(held_px) < _zone_exit_threshold:
            harvest_s1_zone_left = True

    # First S1: harvest_s1_count == 0
    # Re-trigger: harvest_s1_count == 1 AND price previously left zone (harvest_s1_zone_left)
    # No third pass — harvest_s1_count >= 2 blocks all S1 activity
    _s1_eligible = (harvest_s1_count == 0) or (harvest_s1_count == 1 and harvest_s1_zone_left)

    _gain_pct_trigger = (
        _s1_eligible
        and last_entry_reason in ("PAQ_EARLY_AGG", "bps_premium")
        and entry_px > Decimal("0")
        and gain / entry_px >= Decimal("0.25")
    )
    if _gain_pct_trigger:
        harvest_s1_reads += 1
        if harvest_s1_reads >= 1:   # single-read — no confirmation needed at 25% gain
            count = s1_tranche_count()
            if count > 0:
                return True, 1, count

    if _s1_eligible and gain >= g1:
        harvest_s1_reads += 1
        if harvest_s1_reads >= S1_READS:
            count = s1_tranche_count()
            if count > 0:
                return True, 1, count
    else:
        harvest_s1_reads = 0

    return False, None, 0


def execute_partial_harvest(ticker: str, side: str, yes_price: Decimal,
                             no_price: Decimal, stage: int, count: int,
                             held_px: Decimal, seconds_left: float = 999,
                             market=None):
    """
    Execute a partial harvest using an upward limit ladder.
    Tries to sell above current bid — in strong conditions, buyers are still
    chasing and we may achieve better fills than waiting for deterioration.

    Ladder: try at held_px+0.02, held_px+0.01, held_px, held_px-0.01
    Each attempt is IOC. If all miss, accepts held_px-0.02 as floor.
    """
    global harvest_s1_done, harvest_s2_done, harvest_total_sold
    global harvest_s1_reads, harvest_s2_reads  # needed for miss-reset
    global harvest_s1_count, harvest_s1_fire_px, harvest_s1_zone_left

    global harvest_miss_streak, harvest_miss_anchor, harvest_miss_bdi_last

    # ── Single locked orderbook snapshot (v201) ─────────────────────────
    # One get_orderbook() call feeds: BDI, mismatch gate, and miss diagnostic.
    # Prior approach called get_orderbook() separately for BDI and again for
    # the diagnostic — different book states, making the diagnostic misleading.
    # Now all three use the same snapshot taken before any order is placed.
    #
    # Anchor still uses get_bid_prices(market) — market object bid is more
    # reliable than orderbook for the actual executable price. Orderbook used
    # for depth and consistency checks only.
    _harvest_anchor = held_px - Decimal("0.02")  # fallback
    _mkt_bid = None
    if market is not None:
        _yes_bid, _no_bid = get_bid_prices(market)
        _mkt_bid = _yes_bid if side == "yes" else _no_bid
        if _mkt_bid is not None and _mkt_bid > Decimal("0.01"):
            _harvest_anchor = min(_mkt_bid, held_px).quantize(
                Decimal("0.01"), rounding=ROUND_DOWN
            )

    # Lock a single orderbook snapshot — used for BDI, mismatch gate, diagnostic
    _harv_ob_snap = get_orderbook(ticker) or {}
    _ob_key = "yes_dollars" if side == "yes" else "no_dollars"
    # v210: use same fallback as get_bdi/get_best_bid — API may return key as
    # "yes"/"no" instead of "yes_dollars"/"no_dollars" in some responses.
    # Without this fallback, _ob_levels_raw was always [] when key was "yes",
    # causing _harv_bdi=0 → HARVEST SKIP on every poll, mismatch gate unreachable.
    _ob_levels_raw = (_harv_ob_snap.get(_ob_key)
                      or _harv_ob_snap.get(_ob_key.replace("_dollars", ""))
                      or [])

    # Parse orderbook levels from locked snapshot
    _ob_parsed = []
    for _lvl in _ob_levels_raw:
        try:
            _lpx  = float(_lvl[0]) if not isinstance(_lvl, dict) else float(_lvl.get("price", 0))
            _lqty = float(_lvl[1]) if not isinstance(_lvl, dict) else float(_lvl.get("quantity", 0))
            if _lpx > 1.0:  _lpx  /= 100
            if _lqty > 100: _lqty /= 100
            if _lpx > 0.05:   # v209: raised from 0.01 — phantom levels appear at 0.001, 0.002, 0.010
                _ob_parsed.append((_lpx, _lqty))
        except Exception:
            pass

    # BDI from locked snapshot
    _harv_bdi = sum(int(q) for p, q in _ob_parsed
                    if float(held_px) - 0.05 <= p <= float(held_px) + 0.10)

    # ── Same-snapshot mismatch gate (v201, tightened v207, fixed v208/v209) ─
    # Phantom book pattern: yes_dollars shows levels at 0.001, 0.002, 0.010 —
    # real-looking quantity but at non-executable sub-nickel prices.
    # v208: raised filter from 0.01 to catch 0.001/0.002 levels.
    # v209: raised further to 0.05 — March 25 logs showed phantom levels at
    # 0.0100 slipping through the 0.01 filter. Any level below $0.05 is not
    # a real Kalshi binary market price. Filter now catches all known variants.
    # When _ob_levels_raw has entries but _ob_parsed is empty → phantom book.
    if _ob_levels_raw and not _ob_parsed:
        print(f"          → HARVEST MISMATCH | S{stage} | anchor {float(_harvest_anchor):.2f} | "
              f"phantom book ({len(_ob_levels_raw)} raw levels all sub-nickel) | skipping poll")
        return 0, None

    if _mkt_bid is not None and _mkt_bid > Decimal("0.01"):
        _anchor_f = float(_harvest_anchor)
        _near_anchor_depth = sum(int(q) for p, q in _ob_parsed
                                  if abs(p - _anchor_f) <= 0.05)
        if _near_anchor_depth == 0 and _harv_bdi > 20:
            print(f"          → HARVEST MISMATCH | S{stage} | anchor {_anchor_f:.2f} | "
                  f"BDI {_harv_bdi} but 0 depth within 0.05 | skipping poll")
            return 0, None

    # BDI=0: skip entirely
    if _harv_bdi == 0:
        print(f"          → HARVEST SKIP | S{stage} | {side.upper()} | BDI 0 near {float(held_px):.2f}")
        if stage == 1: harvest_s1_reads = 0
        if stage == 2: harvest_s2_reads = 0
        harvest_miss_streak = 0
        return 0, None

    # v247: NEAR_BDI gate — verify executable depth exists within ±0.05 of held price.
    # Root cause confirmed from 4/4–4/5 logs: BDI reports 100-800 but harvest
    # DIAG shows yes_bids:ABSENT. The book depth is all at penny prices (0.001-0.002)
    # which pass the >0.05 filter in _ob_parsed but are far from the harvest target.
    # _harv_bdi already uses the ±0.05/+0.10 window from held_px but can still pick
    # up depth that is within that window yet not at actionable bid prices.
    # NEAR_BDI uses a tighter ±0.05 symmetric window — if it can't fill the tranche,
    # skip this poll. Pure execution filter: does not change anchor, ladder, or offsets.
    _near_bdi = sum(int(q) for p, q in _ob_parsed if abs(p - float(held_px)) <= 0.05)
    if _near_bdi < count and _harv_bdi > 20:
        print(
            f"          → HARVEST_SKIP_NEAR_BDI | S{stage} | {side.upper()} | "
            f"near_bdi {_near_bdi} < {count}c needed | total_bdi {_harv_bdi} | held {float(held_px):.4f}"
        )
        harvest_miss_streak += 1
        harvest_miss_anchor   = float(_harvest_anchor)
        harvest_miss_bdi_last = _harv_bdi
        return 0, None

    # ── Miss cooldown: skip if book state unchanged since last miss ───────
    # After 3 consecutive misses at same price zone, stop attempting until
    # price moves 2c+ OR BDI improves meaningfully (25%+)
    _anchor_f = float(_harvest_anchor)
    if harvest_miss_streak >= 3 and harvest_miss_anchor is not None:
        _price_moved = abs(_anchor_f - harvest_miss_anchor) >= 0.02
        _bdi_improved = (harvest_miss_bdi_last > 0 and
                         _harv_bdi >= harvest_miss_bdi_last * 1.25)
        if not _price_moved and not _bdi_improved:
            print(f"          → HARVEST COOL | S{stage} | streak {harvest_miss_streak} | anchor {_anchor_f:.2f} unchanged")
            return 0, None
        else:
            harvest_miss_streak = 0  # book state changed — reset

    # ── Seconds-aware tranche sizing ──────────────────────────────────────
    # Late market books thin fast — smaller size = higher fill probability
    _secs_remain = seconds_left if seconds_left is not None else 999
    if _secs_remain < 120:
        count = min(count, 1)
    elif _secs_remain < 240:
        count = min(count, 2)

    # ── High-price thin-book tranche cap ──────────────────────────────────
    # At >= 0.90: cap at 1c always — near-settlement books have depth spread
    # across many 1-2c levels. 4c IOC can't find matching depth at one price.
    # Evidence 220030-30: NO 0.90-0.98, BDI 196-403, 4c → 8 consecutive MISS.
    # At 0.85-0.89: cap at 1c only when BDI < 150 (thin confirmation).
    # 1c fill at 0.97 on NO@0.55 entry = +$0.42/c — still strong P&L.
    if float(held_px) >= 0.90:
        count = min(count, 1)
    elif float(held_px) >= 0.85 and _harv_bdi < 150:
        count = min(count, 1)

    # ── BDI-aware size cap ───────────────────────────────────────────────
    _harv_send = min(count, _harv_bdi)
    if _harv_send < count:
        print(f"          → HARVEST PARTIAL | S{stage} | BDI {_harv_bdi} → sending {_harv_send}c")
    count = _harv_send

    # ── Execution mode: AGGRESSIVE from 0.82, STANDARD below ─────────────
    # Data: fills happen when we price at-or-below real bid.
    # STANDARD: bid-first ladder (0.00, -0.01, -0.02, -0.03, -0.04)
    # AGGRESSIVE: wider steps (0.00, -0.01, -0.02, -0.04, -0.06)
    # Both start at bid — never attempt above executable reality.
    _exec_eu_morning = get_session_label() == "EU_MORNING"
    _exec_agg_threshold = SESSION_EU_MORNING_HARVEST_S1_PRICE if _exec_eu_morning else Decimal("0.82")
    _harvest_aggressive = (held_px >= _exec_agg_threshold or _harv_bdi > 200)
    # v184: BDI widened upside to +0.10 to count better bids above held price.
    # Ladder: anchor first (proven executable), then probe +0.01 above,
    # then walk down to -0.05 floor. Above-anchor-first not yet proven —
    # starting at anchor keeps one foot in executable reality.
    # Evidence: all recent fills at anchor or near it (0.68, 0.87, 0.95, 0.96).
    if _harvest_aggressive:
        offsets = [Decimal("0.00"), Decimal("0.01"),
                   Decimal("-0.01"), Decimal("0.02"),
                   Decimal("-0.02"), Decimal("-0.03"),
                   Decimal("-0.04"), Decimal("-0.05")]
    else:
        offsets = [Decimal("0.00"), Decimal("0.01"),
                   Decimal("-0.01"), Decimal("-0.02"),
                   Decimal("-0.03"), Decimal("-0.04"),
                   Decimal("-0.05")]
    filled_qty = 0
    filled_notional = Decimal("0")
    _attempted_prices = []  # track for diagnostic

    mode_label = "AGGRESSIVE" if _harvest_aggressive else "STANDARD"

    # ── v254: Harvest entry gate ─────────────────────────────────────────
    # NEVER sell for less than entry price (with 0.02 buffer for spread).
    # Prior behavior: anchor derived from ob_bid could drop below entry,
    # causing "profit harvesting" to create losses.
    # Evidence (4/9): 3 loss harvests totaling -$0.46. Confirmed on 4/8.
    # For YES: harvest_anchor must be >= entry_price - 0.02
    # For NO:  harvest_anchor must be <= entry_price + 0.02
    #   (NO profits when price goes DOWN, so "below entry" = higher price)
    _hg_entry = last_entry_price if last_entry_price else held_px
    _hg_blocked = False
    if side == "yes":
        if _harvest_anchor < _hg_entry - Decimal("0.02"):
            _hg_blocked = True
    else:  # side == "no"
        # For NO positions, we sell NO contracts. Selling at a higher price than
        # entry means a loss (we bought NO cheap, it went up = we were wrong).
        # Actually: NO entry at 0.53 means we paid $0.53 per NO contract.
        # If NO price rises to 0.60, selling at 0.60 means we get more back (profit).
        # If NO price falls to 0.40, selling at 0.40 is a loss.
        # Harvest anchor for NO is based on NO-side bid price.
        # Block if anchor < entry - 0.02 (same logic as YES — lower price = worse fill)
        if _harvest_anchor < _hg_entry - Decimal("0.02"):
            _hg_blocked = True
    if _hg_blocked:
        print(
            f"          -> HARVEST BLOCKED | S{stage} | {side.upper()} | "
            f"anchor {float(_harvest_anchor):.4f} < entry {float(_hg_entry):.4f} - 0.02 | "
            f"would sell below cost basis"
        )
        return 0, None

    print(f"          -> HARVEST S{stage} | {side.upper()} {count}c | ob_bid {float(_harvest_anchor):.4f} | {mode_label} | BDI {_harv_bdi}")

    for offset in offsets:
        px = _harvest_anchor + offset
        if px < STOP_LOSS_MIN_PRICE or px > STOP_LOSS_MAX_PRICE:
            continue
        px = px.quantize(Decimal("0.0001"), rounding=ROUND_DOWN)
        _attempted_prices.append(float(px))
        resp = place_exit_order(ticker, side, px, count)
        if resp.status_code not in (200, 201):
            _err_body = resp.json() if resp.content else {}
            _err_msg = _err_body.get("error") or _err_body.get("message") or str(resp.status_code)
            _err_detail = _err_body.get("details", "")
            continue
        payload    = resp.json() if resp.content else {}
        order_data = payload.get("order", payload)
        order_id   = order_data.get("order_id") or order_data.get("id")
        if not order_id:
            continue
        # Step 1: check fill in CREATE response immediately
        try:
            fc = int(Decimal(str(order_data.get("fill_count_fp", "0"))))
        except Exception:
            fc = 0
        # v182: fill_count_fp may be 0 in CREATE response even on immediate fill —
        # fall back to fill_count (integer field) before deciding to poll
        if fc == 0:
            try:
                fc = int(order_data.get("fill_count", 0))
            except Exception:
                fc = 0
        _cr_status = str(order_data.get("status", "")).lower()
        # Step 2: if fc still 0, poll once after 0.3s regardless of status —
        # "filled" status with fc=0 means fill_count_fp was not populated in CREATE
        # response. Must poll to confirm actual fill count before treating as miss.
        if fc == 0 and _cr_status not in ("canceled", "cancelled"):
            import time as _t; _t.sleep(0.3)
            sd = get_order_status(order_id)
            if sd:
                try:
                    fc = int(Decimal(str(sd.get("fill_count_fp", "0"))))
                except Exception:
                    fc = 0
                if fc == 0:
                    try:
                        fc = int(sd.get("fill_count", 0))
                    except Exception:
                        fc = 0
        if fc > 0:
            filled_qty      += fc
            filled_notional += px * Decimal(str(fc))
            break
        cancel_order(order_id)

    if filled_qty > 0:
        avg_px   = (filled_notional / Decimal(str(filled_qty))).quantize(Decimal("0.0001"))
        est_gain = (float(avg_px) - float(last_entry_price)) * filled_qty
        harvest_total_sold += filled_qty
        harvest_miss_streak = 0
        harvest_miss_anchor = None
        if stage == 1:
            harvest_s1_done   = True
            harvest_s1_count += 1          # v231: track re-trigger count (max 2)
            harvest_s1_fire_px = float(held_px)  # v231: record zone reference price
            harvest_s1_zone_left = False   # v231: reset — price must leave zone again for any further trigger (none allowed at count=2)
            harvest_s1_reads  = 0          # reset reads so re-trigger can re-arm after zone exit
        if stage == 2: harvest_s2_done = True
        if stage == 3: harvest_s3_done = True
        print(f"          → HARVEST DONE | S{stage} | {filled_qty}c @ {float(avg_px):.4f} | +${est_gain:.2f}")
        # Telegram: only on final harvest stage (S3) or when all contracts harvested
        # — one signal per trade, not per stage. Entry and settlement cover the rest.
        _harv_remaining = max(0, last_entry_contracts - filled_qty)
        if stage == 3 or _harv_remaining == 0:
            send_telegram_alert(
                f"HARVEST DONE | {last_side.upper() if last_side else '?'} | "
                f"S{stage} {filled_qty}x@{float(avg_px):.2f} | "
                f"{_harv_remaining}x remain"
            )
        # Update position accounting for accurate settlement P&L
        if last_traded_ticker:
            update_pending_trade_exits(last_traded_ticker, "harvest", filled_qty, float(avg_px))
        return filled_qty, avg_px
    else:
        # v183: on miss with live book (BDI > 0), preserve read momentum —
        # set reads to 99 so check_partial_harvest fires execute again immediately
        # next poll if conditions still qualify. Resetting to 0 forced re-accumulation
        # through S1_READS before retrying, which burned the fill window before
        # dead-book gate fired. Evidence: 02:41:45 YES=0.967 BDI=431 MISS →
        # reads reset → 02:42:07 reads=1 needs 2 → 02:42:24 YES=0.978 dead-book gate.
        # On dead book (BDI=0) keep reset to 0 — no point retrying immediately.
        if _harv_bdi > 0:
            if stage == 1: harvest_s1_reads = 99
            if stage == 2: harvest_s2_reads = 99
        else:
            if stage == 1: harvest_s1_reads = 0
            if stage == 2: harvest_s2_reads = 0
        # Track miss streak for cooldown
        harvest_miss_streak += 1
        harvest_miss_anchor = float(_harvest_anchor)
        harvest_miss_bdi_last = _harv_bdi
        print(f"          → HARVEST MISS | S{stage}")

        # v248: Rich harvest miss diagnostic — fires on every miss when _harv_bdi > 0.
        # Prior version printed only the first two raw yes_dollars/no_dollars entries,
        # which was insufficient to determine whether _ob_parsed had real executable depth.
        # v248 prints: full parsed levels, internal vs external BDI, near-BDI at anchor,
        # depth at each attempted ladder rung, and raw vs parsed level counts.
        # Pure instrumentation — no behavior changes.
        global _harvest_diag_fired
        _diag_key = (ticker, stage)
        if _harv_bdi > 0:
            try:
                _mkt_bid_str = f"{float(_mkt_bid):.4f}" if _mkt_bid else "None"
                _anchor_f_d  = float(_harvest_anchor)

                # Full parsed levels (above 0.05 filter) — sorted by price descending
                _parsed_sorted = sorted(_ob_parsed, key=lambda x: x[0], reverse=True)
                _parsed_str    = [(round(p, 4), int(q)) for p, q in _parsed_sorted[:12]]

                # Raw level count vs parsed — reveals how many were filtered sub-nickel
                _raw_count    = len(_ob_levels_raw)
                _parsed_count = len(_ob_parsed)

                # Internal _harv_bdi already computed (±0.05 below / +0.10 above held_px)
                # Anchor-window depth: ±0.02 of actual order price — where IOC orders land
                _anchor_depth = sum(int(q) for p, q in _ob_parsed
                                    if abs(p - _anchor_f_d) <= 0.02)

                # Near-BDI: ±0.05 symmetric around held_px (v247 gate reference)
                _near_bdi_d   = sum(int(q) for p, q in _ob_parsed
                                    if abs(p - float(held_px)) <= 0.05)

                # Depth at each attempted ladder rung — what was actually available
                _rung_depth = []
                for _rp in _attempted_prices:
                    _rd = sum(int(q) for p, q in _ob_parsed if abs(p - _rp) <= 0.01)
                    _rung_depth.append((_rp, _rd))

                # yes_bids / no_bids presence (separate API key)
                _has_yes_bids    = "yes_bids" in _harv_ob_snap
                _has_no_bids     = "no_bids"  in _harv_ob_snap
                _yes_bids_sample = str(_harv_ob_snap.get("yes_bids", [])[:3]) if _has_yes_bids else "ABSENT"
                _no_bids_sample  = str(_harv_ob_snap.get("no_bids",  [])[:3]) if _has_no_bids  else "ABSENT"

                print(
                    f"          → HARVEST MISS DIAG | S{stage} {side.upper()} | "
                    f"held {float(held_px):.4f} | anchor {_anchor_f_d:.4f} | "
                    f"mkt_bid {_mkt_bid_str}"
                )
                print(
                    f"          → HARVEST MISS DIAG | int_bdi {_harv_bdi} | "
                    f"near_bdi(±0.05held) {_near_bdi_d} | anchor_depth(±0.02) {_anchor_depth} | "
                    f"raw_levels {_raw_count} | parsed_levels(>0.05) {_parsed_count}"
                )
                print(
                    f"          → HARVEST MISS DIAG | parsed_ob(top12): {_parsed_str}"
                )
                print(
                    f"          → HARVEST MISS DIAG | rung_depth(±0.01): {_rung_depth}"
                )
                print(
                    f"          -> HARVEST MISS DIAG | yes_bids:{_yes_bids_sample} | "
                    f"no_bids:{_no_bids_sample}"
                )

                # v254: Raw OB response dump — first 500 chars of the raw snapshot
                # Fires once per ticker per stage to diagnose ABSENT bids.
                # If yes_bids and no_bids are both ABSENT, the API response format
                # may have changed. This log captures the actual keys/structure.
                if _yes_bids_sample == "ABSENT" and _no_bids_sample == "ABSENT":
                    _raw_keys = list(_harv_ob_snap.keys()) if _harv_ob_snap else []
                    _raw_str = str(_harv_ob_snap)[:500] if _harv_ob_snap else "EMPTY"
                    print(
                        f"          -> OB_PARSER_DIAG | BOTH_ABSENT | keys: {_raw_keys}"
                    )
                    print(
                        f"          -> OB_PARSER_DIAG | raw(500): {_raw_str}"
                    )
            except Exception as _de:
                print(f"          -> HARVEST MISS DIAG ERROR | {_de}")

        return 0, None




def place_exit_order(ticker: str, side: str, price: Decimal, count: int):
    """IOC limit sell order for stop-loss and harvest exits."""
    payload = {
        "ticker": ticker,
        "action": "sell",
        "side": side,
        "count": int(count),
        "client_order_id": str(uuid.uuid4()),
        "time_in_force": "immediate_or_cancel",
        "reduce_only": True,
    }
    if side == "yes":
        payload["yes_price_dollars"] = quantize_price(price)
    else:
        payload["no_price_dollars"] = quantize_price(price)
    return signed_request("POST", "/portfolio/orders", json_data=payload)

def compute_btc_strike_metrics(btc_price, strike):
    if btc_price is None or strike is None or strike <= 0:
        return None
    try:
        signed = btc_price - strike
        return {
            "btc_price": btc_price,
            "strike": strike,
            "signed_diff": signed,
            "signed_pct": (signed / strike) * 100,
            "abs_diff": abs(signed),
            "abs_pct": abs((signed / strike) * 100),
        }
    except Exception:
        return None

def quantize_price(px: Decimal) -> str:
    return str(px.quantize(Decimal("0.0001"), rounding=ROUND_DOWN))

def place_limit_order(ticker: str, side: str, price: Decimal, count: int, reason: str = "", seconds_left: float = 0, current_abs_pct: float | None = None):
    """count must be pre-calculated in run_bot and passed explicitly — no internal recalculation."""
    payload = {
        "ticker": ticker,
        "action": "buy",
        "side": side,
        "count": count,
        "client_order_id": str(uuid.uuid4()),
    }
    if side == "yes":
        payload["yes_price_dollars"] = quantize_price(price)
    else:
        payload["no_price_dollars"] = quantize_price(price)
    return signed_request("POST", "/portfolio/orders", json_data=payload)

def update_history(ticker: str, yes_price: Decimal, no_price: Decimal):
    if yes_price: price_history[ticker]["yes"].append(float(yes_price))
    if no_price: price_history[ticker]["no"].append(float(no_price))

def last_n(values, n):
    arr = list(values)
    return arr[-n:] if len(arr) >= n else arr

def is_staircase(hist):
    arr = last_n(hist, 4)
    if len(arr) < 4: return False
    non_dec = sum(1 for i in range(1, len(arr)) if arr[i] >= arr[i-1])
    net = arr[-1] - arr[0]
    max_drop = max((arr[i-1] - arr[i] for i in range(1, len(arr)) if arr[i] < arr[i-1]), default=0)
    return non_dec >= 3 and max_drop <= 0.03 and net >= 0.1

def higher_high_low_trigger(side, hist):
    arr = last_n(hist, 6)
    if len(arr) < 6: return False
    drops = 0
    for i in range(1, len(arr)):
        if arr[i] < arr[i-1]: drops += 1
        else: drops = 0
        if drops >= 2: return False
    if side == "yes":
        return arr[-1] > arr[-3] and arr[-2] > arr[-5]
    return arr[-1] < arr[-3] and arr[-2] < arr[-5]

def rising(values, n):
    arr = last_n(values, n)
    return len(arr) == n and all(arr[i] > arr[i-1] for i in range(1, len(arr)))

def holding_near_high(values, lookback=3, tolerance=0.015):
    arr = list(values)
    if len(arr) < lookback: return False
    recent = arr[-lookback:]
    return recent[-1] >= max(recent) * (1 - tolerance)

def moderate_momentum(values): return rising(values, 3) or holding_near_high(values, 3, 0.015)
def strong_momentum(values): return rising(values, 4) or (rising(values, 3) and holding_near_high(values, 4, 0.01))
def light_momentum(values): return rising(values, 2) or holding_near_high(values, 3, 0.02)

def is_consistent_hold(values, x):
    arr = last_n(values, x)
    if len(arr) < x: return False
    return all(v >= 0.88 for v in arr) and all(arr[i] >= arr[i-1] for i in range(1, len(arr)))

def get_btc_snapshot():
    try:
        data = requests.get("https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&limit=6", timeout=5).json()
        closes = [float(r[4]) for r in data]
        return {"available": True, "current_price": closes[-1], "recent_move_pct": ((closes[-1] - closes[-6]) / closes[-6]) * 100}
    except: pass
    try:
        data = requests.get("https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT", timeout=5).json()
        return {"available": True, "current_price": float(data["price"]), "recent_move_pct": None}
    except: pass
    try:
        data = requests.get("https://api.coinbase.com/v2/prices/BTC-USD/spot", timeout=5).json()
        return {"available": True, "current_price": float(data["data"]["amount"]), "recent_move_pct": None}
    except: pass
    return {"available": False, "current_price": None, "recent_move_pct": None}

def _completed_candle_end_ts(period_seconds: int) -> int:
    """
    Return the Unix timestamp of the most recently COMPLETED candle boundary.
    E.g. for 3m (180s) at 07:43:45 UTC → returns timestamp of 07:42:00 close.
    We subtract one full period to ensure we only use closed candles.
    """
    import time as _time
    now = int(_time.time())
    # Floor to the current bucket start, then subtract one period = last completed close
    current_bucket_start = (now // period_seconds) * period_seconds
    return current_bucket_start  # this IS the end of the previous completed candle


def get_btc_candles(interval: str, limit: int):
    """
    Fetch BTC/USD OHLC candles with fallback chain:
    Bitstamp -> Kraken -> Binance -> Coinbase

    IMPORTANT: requests exactly `limit` completed candles, excluding the
    current still-forming candle. This ensures CSM only updates when a
    candle actually closes, not every 30-second poll.
    """
    import time as _time
    seconds = {"3m": 180, "5m": 300}.get(interval, 180)
    minutes = {"3m": 3,   "5m": 5}.get(interval, 3)

    # end_ts = last completed candle close (excludes current forming candle)
    end_ts   = _completed_candle_end_ts(seconds)
    start_ts = end_ts - seconds * (limit + 1)

    # 1. Bitstamp — confirmed working, no auth required
    # Bitstamp naturally excludes the current forming candle.
    # We fetch limit+1 and drop any candle whose timestamp >= current bucket
    # start to be absolutely safe, then take the last `limit` completed ones.
    try:
        now_ts = int(__import__("time").time())
        current_bucket_start = (now_ts // seconds) * seconds
        url = f"https://www.bitstamp.net/api/v2/ohlc/btcusd/?step={seconds}&limit={limit+1}"
        data = requests.get(url, timeout=5).json()
        raw = data.get("data", {}).get("ohlc", [])
        completed = [r for r in raw if int(r["timestamp"]) < current_bucket_start]
        if len(completed) >= 2:
            return [(float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"]))
                    for r in completed[-limit:]]
    except Exception:
        pass

    # 2. Kraken (valid intervals: 5m is closest to 3m)
    try:
        kr_interval = 5 if minutes == 3 else minutes
        url = f"https://api.kraken.com/0/public/OHLC?pair=XBTUSD&interval={kr_interval}&since={start_ts}"
        data = requests.get(url, timeout=5).json()
        raw = data.get("result", {}).get("XXBTZUSD", [])
        # Kraken includes current forming candle as last entry — drop it
        if len(raw) > 1:
            completed = [r for r in raw if int(r[0]) < end_ts]
            if len(completed) >= 2:
                return [(float(r[1]), float(r[2]), float(r[3]), float(r[4])) for r in completed[-limit:]]
    except Exception:
        pass

    # 3. Binance — last candle in response is still-forming, so exclude it
    try:
        url = f"https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval={interval}&limit={limit+1}"
        data = requests.get(url, timeout=5).json()
        if isinstance(data, list) and len(data) >= 3:
            completed = [r for r in data if int(r[6]) < end_ts * 1000]  # r[6] = close time ms
            if len(completed) >= 2:
                return [(float(r[1]), float(r[2]), float(r[3]), float(r[4])) for r in completed[-limit:]]
    except Exception:
        pass

    # 4. Coinbase Advanced
    try:
        gran_map = {180: "THREE_MINUTE", 300: "FIVE_MINUTE"}
        url = (
            f"https://api.coinbase.com/api/v3/brokerage/products/BTC-USD/candles"
            f"?start={start_ts}&end={end_ts}&granularity={gran_map[seconds]}&limit={limit}"
        )
        data = requests.get(url, timeout=5).json()
        raw = list(reversed(data.get("candles", [])))
        if len(raw) >= 2:
            return [(float(c["open"]), float(c["high"]), float(c["low"]), float(c["close"])) for c in raw]
    except Exception:
        pass

    return []


def get_paq_score(side: str, candles, current_btc, live_bps, prev1_bps,
                  current_abs: float, prem_abs: float):
    """
    Price Action Quality — 0 to 6 score across three components (each 0-2).

    Context  (0-2): Is recent 3m candle structure leaning our way?
    State    (0-2): Is live BTC pressing in our direction vs last candle?
    Expansion(0-2): Is the move extending (BPS growing, abs expanding)?

    Returns (score, ctx, state, exp, bucket) where bucket is STRONG/MODERATE/WEAK.
    Returns None on data failure.
    """
    global prev_paq_score, prev_paq_bucket, prev_paq_ctx, prev_paq_state, prev_paq_exp, _paq_fail_logged
    if candles is None or len(candles) < 2 or current_btc is None:
        if not _paq_fail_logged:
            print(f"{dt.datetime.now():%H:%M:%S} | PAQ | candle data unavailable — gate passing through")
            _paq_fail_logged = True
        return None
    _paq_fail_logged = False

    prev = candles[-2]  # second-to-last completed candle
    last = candles[-1]  # most recently completed candle
    prev_o, prev_h, prev_l, prev_c = prev
    last_o, last_h, last_l, last_c = last
    last_rng = max(last_h - last_l, 1e-8)

    yes = (side == "yes")

    # ── Context (0-2): structural backdrop ────────────────────────────
    ctx = 0
    if yes:
        if last_c > prev_c:          ctx += 1   # last close > prior close
        if last_h >= prev_h or (last_c - last_l) / last_rng >= 0.5:
            ctx += 1                             # higher high OR close in upper half
    else:
        if last_c < prev_c:          ctx += 1
        if last_l <= prev_l or (last_h - last_c) / last_rng >= 0.5:
            ctx += 1

    # ── State (0-2): live BTC location vs last candle ─────────────────
    state = 0
    if yes:
        if current_btc > last_c:     state += 1  # above last close
        top_q = last_l + 0.75 * last_rng
        if current_btc >= last_h or current_btc >= top_q:
            state += 1                            # above high or in top quartile
    else:
        if current_btc < last_c:     state += 1
        bot_q = last_h - 0.75 * last_rng
        if current_btc <= last_l or current_btc <= bot_q:
            state += 1

    # ── Expansion (0-2): is the move extending? ────────────────────────
    exp = 0
    if yes:
        if live_bps > prev1_bps:     exp += 1    # BPS growing
        if current_abs >= prem_abs + 0.02:
            exp += 1                              # abs meaningfully above floor
    else:
        if live_bps < prev1_bps:     exp += 1
        if current_abs >= prem_abs + 0.02:
            exp += 1

    score = ctx + state + exp
    bucket = "STRONG" if score >= PAQ_STRONG else ("MODERATE" if score >= PAQ_MODERATE else "WEAK")
    prev_paq_score  = score
    prev_paq_bucket = bucket
    prev_paq_ctx    = ctx
    prev_paq_state  = state
    prev_paq_exp    = exp
    return score, ctx, state, exp, bucket


def get_timeframe_bucket(s):
    if s <= 120: return "0-120s"
    if s <= 240: return "121-240s"
    if s <= 360: return "241-360s"
    if s <= 480: return "361-480s"
    if s <= 600: return "481-600s"
    return "outside"

def print_buy_snapshot(side, price, reason, seconds_left, contracts, recent_move_pct=None, metrics=None, live_bps=None):
    global _last_entry_class
    tf = get_timeframe_bucket(seconds_left)
    move = f"{recent_move_pct:+.2f}%" if recent_move_pct is not None else "N/A"
    strike_text = f"BTC {metrics['btc_price']:.2f} | beat {metrics['strike']:.2f} | signed {metrics['signed_pct']:+.3f}% | abs {metrics['abs_pct']:.3f}%" if metrics else "N/A"
    _total = round(float(price) * contracts, 2)
    _ec = _last_entry_class if _last_entry_class else ""
    print(f"          → BUY SNAPSHOT{(' | ' + _ec) if _ec else ''}")
    print(f"             Side:      {side.upper()} @ {float(price):.4f}")
    print(f"             Reason:    {reason}")
    print(f"             Seconds:   {int(seconds_left)}s")
    print(f"             Contracts: {contracts} | Total: ${_total:.2f}")
    if metrics:
        print(f"             BTC:       {metrics['btc_price']:.2f} | beat {metrics['strike']:.2f}")
        print(f"             Signed:    {metrics['signed_pct']:+.3f}%")
        print(f"             Abs:       {metrics['abs_pct']:.3f}%")

    # ── v211 data-collection tags ─────────────────────────────────────────
    # PAQ3_STRUCT_PILOT: log when PAQ=3 pre-breakout coil structure fires in
    # ASIA_OPEN or BTC_DEEP_NIGHT. Accumulating 15-20 modern-code samples
    # before any gate or conviction change. No logic impact.
    _snap_sess = get_session_label()
    _snap_paq  = prev_paq_score if prev_paq_score is not None else 0
    _snap_ctx  = metrics.get('ctx', -1) if metrics else -1
    _snap_st   = metrics.get('state', -1) if metrics else -1
    _snap_exp  = metrics.get('exp', -1) if metrics else -1
    _snap_bcdp = metrics.get('bcdp', '') if metrics else ''
    _snap_abs  = float(metrics['abs_pct']) if metrics else 0.0
    if (_snap_paq == 3
            and _snap_sess in ('ASIA_OPEN', 'BTC_DEEP_NIGHT')
            and _snap_abs >= 0.06):
        _pilot_note = f"PAQ3={_snap_paq} CTX{_snap_ctx} ST{_snap_st} EXP{_snap_exp} BCDP{_snap_bcdp}"
        print(f"             [PAQ3_STRUCT_PILOT] {_pilot_note}")

    # Session-BPS match tag: flag whether entry BPS direction matches
    # the session-preferred direction found in data analysis.
    # ASIA/EU: positive BPS 100% WR, negative BPS losing.
    # NY_PRIME: negative BPS dominant (100% WR), positive BPS also strong.
    # BTC_DEEP_NIGHT: mixed — no clear preference yet.
    if metrics and live_bps is not None:
        _snap_bps = live_bps
        _bps_match = None
        if _snap_sess in ('ASIA_OPEN', 'EU_MORNING'):
            # Prefer BPS matching direction: YES needs pos BPS, NO needs neg BPS
            _preferred = (_snap_bps > 0 and side == 'yes') or (_snap_bps < 0 and side == 'no')
            _bps_match = 'ALIGNED' if _preferred else 'COUNTER'
        elif _snap_sess == 'NY_PRIME':
            # Negative BPS dominant: NO with neg BPS or YES with neg BPS (reversal)
            _preferred = _snap_bps < 0
            _bps_match = 'ALIGNED' if _preferred else 'COUNTER'
        if _bps_match:
            print(f"             [BPS_SESSION] {_snap_sess} BPS{_snap_bps:+.1f} → {_bps_match}")

def format_main_status_line(now, yes, no, s, m):
    if m: return f"{now} | YES {yes:.4f} | NO {no:.4f} | {int(s)}s left | ABS {m['abs_pct']:.3f}"
    return f"{now} | YES {yes:.4f} | NO {no:.4f} | {int(s)}s left | ABS N/A"

def check_divergence_veto(s, side, move):
    if s > 300 or move is None: return False
    return (side == "yes" and move < -0.25) or (side == "no" and move > 0.25)

def log_rejection_once(ticker, s, side, label):
    global last_logged_event_key
    tf = get_timeframe_bucket(s)
    key = f"{ticker}|{side}|{tf}|rejection"
    if last_logged_event_key == key: return
    last_logged_event_key = key
    print(f"          → BLOCK | {side.upper()} | {label} | {int(s)}s")
    # telegram suppressed — entry rejections logged only
    # send_telegram_alert(f"REJECTED | {side.upper()} | {label} | {int(s)}s left")

def log_trigger_record(ticker, s, side, reason, yes_p, no_p, btc_ok, veto, outcome, contracts, risk_d, metrics=None):
    global last_logged_event_key
    if "TRADED" in outcome:
        key = f"{ticker}|{side}|{reason}|traded"
        if last_logged_event_key == key: return
        last_logged_event_key = key
    pass  # trigger record removed

def check_profit_protection(yes_price, no_price, seconds_left, live_bps, trade_entry_reads, entry_time=None, trade_age_secs=0):
    """
    Profit-protection trailing stop.  Runs AFTER hard invalidation, BEFORE soft stops.

    Stage 1 — Activation:
      Both must be true:
        side_price >= TRAIL_ACTIVATE_PRICE (0.88)
        gain_from_entry >= TRAIL_ACTIVATE_GAIN (0.12)
      Stabilization lockout: BOTH must pass:
        - minimum TRAIL_STABILIZE_READS (2) poll cycles post-entry
        - minimum TRAIL_STABILIZE_SECS (60s) elapsed since entry

    Stage 2 — Trailing:
      floor = high_water - family_trail_distance
      Requires 1 full poll cycle below floor before firing (anti-wick).
      Label: TRAIL_EXIT_STAGE2

    Stage 3 — Endgame tightening (side_price >= 0.95):
      floor = high_water - TRAIL_STAGE3_DIST (0.03)
      Immediate exit on BPS turning adverse (no floor-patience needed).
      Label: TRAIL_EXIT_STAGE3

    Returns (True, label, trigger_px) or (False, None, None).
    Updates trail_high_water, trail_active, trail_reads_post_peak, trail_below_floor_cnt.
    """
    global trail_high_water, trail_active, trail_reads_post_peak, trail_below_floor_cnt, last_entry_reads, trail_activation_reads
    global trail_mz_armed, trail_mz_armed_reads, trail_s3_zone_cnt
    global trail_mz_armed, trail_mz_armed_reads, trail_s3_zone_cnt

    if last_entry_contracts <= 0 or last_traded_ticker is None or last_entry_price is None:
        return False, None, None
    if yes_price is None or no_price is None:
        return False, None, None

    # Stabilization lockout — both gates must pass
    if trade_entry_reads < TRAIL_STABILIZE_READS:
        return False, None, None
    if entry_time is not None:
        elapsed = (dt.datetime.now(dt.timezone.utc) - entry_time).total_seconds()
        if elapsed < TRAIL_STABILIZE_SECS:
            return False, None, None

    held_px  = yes_price if last_side == "yes" else no_price
    entry_px = Decimal(str(last_entry_price))
    gain     = held_px - entry_px

    # Update high-water mark
    if trail_high_water is None or held_px > trail_high_water:
        trail_high_water = held_px
        trail_reads_post_peak = 0
    else:
        trail_reads_post_peak += 1

    # Stage 1: activate when price + gain threshold met
    if not trail_active:
        if held_px >= TRAIL_ACTIVATE_PRICE and gain >= TRAIL_ACTIVATE_GAIN:
            trail_active = True
            trail_activation_reads = 0
        else:
            return False, None, None
    else:
        trail_activation_reads += 1

    # Activation stabilization: block floor-exit for 3 reads after Stage 1 first fires.
    # Prevents immediate exit at borderline activation when floor is near entry price.
    _trail_armed = (trail_activation_reads >= 3)

    dist = TRAIL_DIST.get(last_entry_reason, Decimal("0.10"))

    # Pattern A: CTX=2, STATE=0, EXP=0 structural stall — tighten trail by 0.02.
    # Candle backdrop is bullish but BTC has faded back and momentum is absent.
    if (prev_paq_ctx is not None and prev_paq_state is not None and prev_paq_exp is not None
            and prev_paq_ctx == 2 and prev_paq_state == 0 and prev_paq_exp == 0):
        dist = max(Decimal("0.03"), dist - Decimal("0.02"))

    # Pattern B: CTX=0, STATE=0, EXP=0 — full structural collapse.
    # All three components absent simultaneously. In every session log this
    # preceded meaningful price deterioration within 2-4 reads.
    # Tighten an additional 0.02 beyond Pattern A (total 0.04 tighter than family dist).
    if (prev_paq_ctx is not None and prev_paq_state is not None and prev_paq_exp is not None
            and prev_paq_ctx == 0 and prev_paq_state == 0 and prev_paq_exp == 0):
        dist = max(Decimal("0.03"), dist - Decimal("0.02"))

    # ── Late NO mid-band emergency tightener ─────────────────────────────
    # For NO entries made at 0.70+, when the position has fallen back into
    # the 0.40-0.45 danger zone with <=240s left and opposite STATE>=1:
    # the trade is no longer a winner being tested — it is a vulnerable late
    # binary with collapsing exit quality. Arm at tightest dist immediately.
    if (last_side == "no"
            and last_entry_price is not None and last_entry_price >= Decimal("0.70")
            and seconds_left is not None and seconds_left <= 240
            and held_px < Decimal("0.45")
            and prev_paq_state is not None and prev_paq_state >= 1
            and _trail_armed):
        dist = Decimal("0.04")  # tightest possible — force next read to decide

    # ── Strategy 3: Time-decay mid-zone exit ─────────────────────────────
    # Fires when: held price in 0.40-0.82 zone AND seconds_left<=240 AND
    # TIME_DECAY_EXIT removed — forced mid-zone exits on countdown caused losses
    # on positions that would have settled profitably. Let the position ride.
    # MID_ZONE_PROTECT removed — compressed trail (0.06) triggered on normal
    # oscillation at 0.82-0.88, stopping out winning positions prematurely.
    trail_s3_zone_cnt = 0

    # ── Strategy 1: Time-compressed trail ────────────────────────────────
    # Tightens trail distance when near expiry with meaningful price (>=0.82).
    # 181-360s: use 0.05; <=180s: use 0.03.
    if (seconds_left is not None
            and held_px >= TRAIL_S1_PRICE_GATE
            and seconds_left <= TRAIL_S1_SECS_GATE
            and gain >= TRAIL_ACTIVATE_GAIN):
        s1_dist = TRAIL_S1_DIST_LATE if seconds_left <= 180 else TRAIL_S1_DIST_MID
        dist = min(dist, s1_dist)  # tighten only, never widen

    # Stage 3: endgame tightening
    if held_px >= TRAIL_STAGE3_PRICE or trail_high_water >= TRAIL_STAGE3_PRICE:
        stage3_floor = trail_high_water - TRAIL_STAGE3_DIST
        # Immediate exit if BPS turns adverse (no patience needed at endgame)
        bps_adverse = (last_side == "yes" and live_bps <= -1) or (last_side == "no" and live_bps >= 1)
        if bps_adverse:
            trail_below_floor_cnt = 0
            # Only trail-exit if held price is still above entry — never trail into a loss
            if held_px > Decimal(str(last_entry_price)):
                return True, "TRAIL_EXIT_STAGE3", float(stage3_floor)
        # Or if price crosses the tight floor (requires armed + 2 reads)
        if held_px < stage3_floor and _trail_armed:
            trail_below_floor_cnt += 1
            if trail_below_floor_cnt >= 2:   # 2 confirmed reads, not a wick
                trail_below_floor_cnt = 0
                if held_px > Decimal(str(last_entry_price)):
                    return True, "TRAIL_EXIT_STAGE3", float(stage3_floor)
        else:
            trail_below_floor_cnt = 0
        return False, None, None

    # Stage 2: normal trailing (requires armed — 3 reads post-activation)
    stage2_floor = trail_high_water - dist
    if held_px < stage2_floor and _trail_armed:
        trail_below_floor_cnt += 1
        if trail_below_floor_cnt >= 2:   # 2 consecutive reads = confirmed breach, not a wick
            trail_below_floor_cnt = 0
            if held_px > Decimal(str(last_entry_price)):
                return True, "TRAIL_EXIT_STAGE2", float(stage2_floor)
    else:
        trail_below_floor_cnt = 0

    return False, None, None


def check_paq_stop_loss(live_bps: float, yes_price=None, no_price=None, signed_pct=None, seconds_left=None, metrics=None):
    """
    PAQ stop — 3-layer hierarchy for seconds_left > 180:

    Layer 1 (immediate): PAQ == 0
    Layer 2 (confirmed): PAQ == 1 AND opposite BPS >= 1 for 2 consecutive checks
      YES held: BPS <= -1 x2
      NO  held: BPS >= +1 x2
    Layer 3 (immediate): hard opposite BPS flip regardless of PAQ
      YES held: BPS <= -2
      NO  held: BPS >= +2

    For seconds_left <= 180: same rules with no consec requirement on Layer 2.
    Pinned-price exception blocks Layer 2 only:
      <=120s left, price >=0.97, signed on-side, BPS not strongly adverse.
    """
    global _paq_zero_streak, _paq_bps_soft_yes_cnt, _paq_bps_soft_no_cnt, _paq_hard_flip_yes_cnt, _paq_hard_flip_no_cnt

    # ── WEEKEND STRUCT DELAYED STOP (v222) ───────────────────────────────
    # Applies only to PAQ_STRUCT_GATE weekend entries (ladder exit mode).
    # Stop level: entry price minus 0.10.
    # Delay: only activates after 300 seconds elapsed since entry.
    # Rationale: STRUCT coils oscillate near entry for 200-300s before
    # committing. An immediate stop fires on normal oscillation (false stop).
    # After 300s, if price hasn't moved toward ladder rungs, exit at -0.10.
    # Data: stop saved $21.87 across 5 never-hit-0.80 trades on 3/21+3/22.
    if _weekend_struct_entry and last_entry_price is not None and last_entry_contracts > 0:
        _wsl_stop_px = float(last_entry_price) - 0.10
        _wsl_held = float(yes_price) if last_side == "yes" else float(no_price) if no_price else None
        if _wsl_held is not None:
            _elapsed = max(0.0, _wsl_entry_secs - float(seconds_left or 0))
            if _elapsed >= 300 and _wsl_held <= _wsl_stop_px:
                print(f"          → WEEKEND_STRUCT_STOP | {last_side.upper()} | held {_wsl_held:.3f} <= stop {_wsl_stop_px:.3f} | {_elapsed:.0f}s elapsed")
                return True, "WEEKEND_STRUCT_STOP"
        return False, None
    # PAQ stop only applies to PAQ-family entries
    if last_entry_reason not in ("PAQ_PENDING_ALIGN", "PAQ_EARLY_AGG", "PAQ_EARLY_CONS", "PAQ_STRUCT_GATE"):
        _paq_zero_streak = 0
        _paq_bps_soft_yes_cnt = 0
        _paq_bps_soft_no_cnt  = 0
        return False, None
    if last_entry_contracts <= 0 or last_traded_ticker is None:
        _paq_zero_streak = 0
        _paq_bps_soft_yes_cnt = 0
        _paq_bps_soft_no_cnt  = 0
        return False, None
    if prev_paq_score is None:
        return False, None

    side = last_side
    late = (seconds_left is not None and seconds_left <= 180)

    # Track PAQ==0 streak
    if prev_paq_score == 0:
        _paq_zero_streak += 1
    else:
        _paq_zero_streak = 0

    # Track soft-BPS deterioration streaks
    if side == "yes":
        if prev_paq_score == 1 and live_bps <= -1:
            _paq_bps_soft_yes_cnt += 1
        else:
            _paq_bps_soft_yes_cnt = 0
        _paq_bps_soft_no_cnt = 0
    elif side == "no":
        if prev_paq_score == 1 and live_bps >= 1:
            _paq_bps_soft_no_cnt += 1
        else:
            _paq_bps_soft_no_cnt = 0
        _paq_bps_soft_yes_cnt = 0

    # Layer 1: PAQ == 0 — abs-gated + side-awareness + streak gates
    # 3/18 data: all 5 PAQ0_COLLAPSE events were abs < 0.08%, all unfilled stops,
    # all had market continue original thesis. PAQ=0 during low BTC movement
    # is a candle-structure consolidation pause, not a real reversal signal.
    #
    # abs gate:  < 0.04%  → suppress entirely (no BTC movement = noise)
    #            >= 0.04% → allow with streak gate
    # Streak: >300s needs 3 reads (was 2 — data shows PAQ flickers 0→2→0)
    #         <=300s needs 2 reads
    # Side-awareness: PAQ==0 for held NO means no bullish structure = favorable.
    #   Block if held NO and no_price >= 0.60.
    if prev_paq_score == 0:
        _paq0_abs = metrics.get("abs_pct", 0.0) if metrics else 0.0
        if _paq0_abs < 0.04:
            # Suppress: BTC not moving, PAQ drop is consolidation noise
            _paq_zero_streak = 0
        else:
            _no_side_winning = (side == "no" and no_price is not None and no_price >= Decimal("0.60"))
            if not _no_side_winning:
                _streak_needed = 3 if (seconds_left is not None and seconds_left > 300) else 2
                if _paq_zero_streak >= _streak_needed:
                    return True, "PAQ0_COLLAPSE"

    # Layer 3: hard BPS flip — abs-gated to prevent noise exits
    # abs < 0.04%:  suppress (pure orderbook noise, BTC not moving)
    # abs 0.04-0.08%: require 2 consecutive reads (moderate signal)
    # abs >= 0.08%: fire immediately (genuine BTC movement)
    _abs_for_hard = metrics.get("abs_pct", 0.0) if metrics else 0.0
    _hard_flip_yes = (side == "yes" and live_bps <= -2)
    _hard_flip_no  = (side == "no"  and live_bps >=  2)
    if _hard_flip_yes or _hard_flip_no:
        if _abs_for_hard >= 0.08:
            _paq_hard_flip_yes_cnt = 0
            _paq_hard_flip_no_cnt  = 0
            return True, "PAQ_HARD_BPS_FLIP"
        elif _abs_for_hard >= 0.04:
            if _hard_flip_yes:
                _paq_hard_flip_yes_cnt += 1
                _paq_hard_flip_no_cnt  = 0
                if _paq_hard_flip_yes_cnt >= 2:
                    _paq_hard_flip_yes_cnt = 0
                    return True, "PAQ_HARD_BPS_FLIP"
            else:
                _paq_hard_flip_no_cnt  += 1
                _paq_hard_flip_yes_cnt = 0
                if _paq_hard_flip_no_cnt >= 2:
                    _paq_hard_flip_no_cnt = 0
                    return True, "PAQ_HARD_BPS_FLIP"
        # else: abs < 0.04% — suppress, reset streak
        else:
            _paq_hard_flip_yes_cnt = 0
            _paq_hard_flip_no_cnt  = 0
    else:
        if side == "yes": _paq_hard_flip_yes_cnt = 0
        if side == "no":  _paq_hard_flip_no_cnt  = 0

    # Layer 2: PAQ==1 + soft opposite BPS — needs 2 checks unless late
    if prev_paq_score == 1:
        consec_needed = 1 if late else 2

        if side == "yes" and _paq_bps_soft_yes_cnt >= consec_needed:
            # Pinned-price exception
            if (seconds_left is not None and seconds_left <= 120
                    and yes_price is not None and yes_price >= Decimal("0.97")
                    and signed_pct is not None and signed_pct > 0
                    and live_bps >= 0):
                return False, None
            return True, "PAQ1_BPS_SOFT"

        if side == "no" and _paq_bps_soft_no_cnt >= consec_needed:
            if (seconds_left is not None and seconds_left <= 120
                    and no_price is not None and no_price >= Decimal("0.97")
                    and signed_pct is not None and signed_pct < 0
                    and live_bps <= 0):
                return False, None
            return True, "PAQ1_BPS_SOFT"

    return False, None


def check_flip_event(ticker, yes_p, no_p):
    global last_side, last_entry_price, last_entry_time, flip_logged_ticker, last_traded_ticker
    if not last_side or not last_entry_price or not last_entry_time or ticker != last_traded_ticker or flip_logged_ticker == ticker:
        return
    flipped = False
    if last_side == "yes":
        if (
            (no_p is not None and no_p >= Decimal("0.88"))
            or (yes_p is not None and yes_p <= Decimal("0.12"))
            or (yes_p is not None and no_p is not None and no_p > yes_p and no_p >= Decimal("0.75"))
        ):
            flipped = True
    elif last_side == "no":
        if (
            (yes_p is not None and yes_p >= Decimal("0.88"))
            or (no_p is not None and no_p <= Decimal("0.12"))
            or (yes_p is not None and no_p is not None and yes_p > no_p and yes_p >= Decimal("0.75"))
        ):
            flipped = True
    if not flipped: return
    secs = (dt.datetime.now(dt.timezone.utc) - last_entry_time).total_seconds()
    print(f"          → FLIP | {last_side.upper()} @ {last_entry_price:.4f} | {secs:.0f}s")
    # telegram suppressed — FLIP logged only
    # send_telegram_alert(f"FLIP DETECTED | entered {last_side.upper()} @ {last_entry_price:.4f} | {secs:.0f}s from entry")
    flip_logged_ticker = ticker

def load_pending_trades():
    global pending_trades
    try:
        if os.path.exists(PENDING_TRADES_FILE):
            with open(PENDING_TRADES_FILE, "r") as f:
                pending_trades = json.load(f)
        else:
            pending_trades = {}
    except Exception:
        pending_trades = {}

def save_pending_trades():
    try:
        with open(PENDING_TRADES_FILE, "w") as f:
            json.dump(pending_trades, f)
    except Exception:
        pass

def load_pending_settlements():
    """Reload unconfirmed settlements from disk on restart."""
    global _pending_settlement_queue
    try:
        if os.path.exists(PENDING_SETTLEMENTS_FILE):
            with open(PENDING_SETTLEMENTS_FILE, "r") as f:
                _pending_settlement_queue = json.load(f)
            if _pending_settlement_queue:
                print(f"PENDING SETTLEMENTS RESTORED | {len(_pending_settlement_queue)} unconfirmed trade(s) from prior session")
        else:
            _pending_settlement_queue = []
    except Exception:
        _pending_settlement_queue = []

def save_pending_settlements():
    try:
        with open(PENDING_SETTLEMENTS_FILE, "w") as f:
            json.dump(_pending_settlement_queue, f)
    except Exception:
        pass

def save_live_state():
    """Persist full position and trail state to disk every poll cycle.
    On restart, if ticker is still open, bot reloads this and resumes
    management instead of treating the position as an orphan.
    """
    global last_exit_side, last_exit_time, last_exit_price
    try:
        state = {
            "ticker":               last_traded_ticker,
            "side":                 last_side,
            "entry_price":          float(last_entry_price) if last_entry_price is not None else None,
            "entry_reason":         last_entry_reason,
            "entry_contracts":      last_entry_contracts,
            "entry_time":           last_entry_time.isoformat() if last_entry_time else None,
            "entry_bps":            last_entry_bps,
            "entry_paq":            last_entry_paq,
            # Trail state
            "trail_high_water":     float(trail_high_water) if trail_high_water is not None else None,
            "trail_active":         trail_active,
            "trail_activation_reads": trail_activation_reads,
            "trail_below_floor_cnt":  trail_below_floor_cnt,
            "trail_reads_post_peak":  trail_reads_post_peak,
            "trail_mz_armed":         trail_mz_armed,
            "trail_mz_armed_reads":   trail_mz_armed_reads,
            "trail_s3_zone_cnt":      trail_s3_zone_cnt,
            # Harvest state
            "harvest_s1_done":        harvest_s1_done,
            "harvest_s1_count":       harvest_s1_count,
            "harvest_s1_fire_px":     harvest_s1_fire_px,
            "harvest_s1_zone_left":   harvest_s1_zone_left,
            "harvest_s2_done":        harvest_s2_done,
            "harvest_s3_done":        harvest_s3_done,
            "harvest_s1_reads":       harvest_s1_reads,
            "harvest_s2_reads":       harvest_s2_reads,
            "harvest_s3_reads":       harvest_s3_reads,
            "harvest_total_sold":     harvest_total_sold,
            # v234: WES state — must persist across restarts so mid-position
            # WES exits fire correctly after bot restart (no open position lost)
            "wes_active":             _wes_active,
            "wes_entry_px":           _wes_entry_px,
            "wes_contracts":          _wes_contracts,
            "wes_s1_target":          _wes_s1_target,
            "wes_stop_target":        _wes_stop_target,
            "wes_side":               _wes_side,
            "wes_entry_secs":         _wes_entry_secs,
            # v238: WES promotion state — critical for restart during promoted position
            "wes_promoted":           _wes_promoted,
            "wes_parent_family":      _wes_parent_family,
            "wes_parent_entry_px":    _wes_parent_entry_px,
            "wes_parent_contracts":   _wes_parent_contracts,
            "wes_combined_avg_px":    _wes_combined_avg_px,
            # PAQ stop state
            "paq_stop_fired":         _paq_stop_fired,
            "paq_zero_streak":        _paq_zero_streak,
            "paq_agg_opp_yes_cnt":    _paq_agg_opp_yes_cnt,
            "paq_agg_opp_no_cnt":     _paq_agg_opp_no_cnt,
            "last_entry_reads":       last_entry_reads,
            # Exit tracking
            "last_exit_side":         last_exit_side,
            "last_exit_time":         last_exit_time.isoformat() if last_exit_time else None,
            "last_exit_price":        float(last_exit_price) if last_exit_price is not None else None,
            "saved_at":               dt.datetime.now(dt.timezone.utc).isoformat(),
        }
        with open(LIVE_STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)
    except Exception as e:
        print(f"LIVE STATE SAVE ERROR: {e}")


def load_live_state(current_ticker: str) -> bool:
    """Load persisted state if ticker matches current open market.
    Returns True if state was restored, False if no valid state found.
    """
    global last_traded_ticker, last_side, last_entry_price, last_entry_reason
    global last_entry_contracts, last_entry_time, last_entry_bps
    global trail_high_water, trail_active, trail_activation_reads
    global trail_below_floor_cnt, trail_reads_post_peak
    global trail_mz_armed, trail_mz_armed_reads, trail_s3_zone_cnt
    global harvest_s1_done, harvest_s2_done, harvest_s3_done, harvest_s1_reads, harvest_s2_reads, harvest_s3_reads, harvest_total_sold
    global _paq_stop_fired, _paq_zero_streak, _paq_agg_opp_yes_cnt, _paq_agg_opp_no_cnt
    global last_entry_reads, last_exit_side, last_exit_time, last_exit_price
    try:
        if not os.path.exists(LIVE_STATE_FILE):
            return False
        with open(LIVE_STATE_FILE, "r") as f:
            s = json.load(f)
        # Only restore if ticker matches
        if s.get("ticker") != current_ticker:
            return False
        # Only restore if position still exists
        if not s.get("side") or not s.get("entry_price"):
            return False
        # Verify position actually exists on Kalshi before restoring
        live_contracts = get_live_position_contracts(current_ticker)
        if live_contracts <= 0:
            print(f"LIVE STATE: ticker matches but no live position — skipping restore")
            return False

        last_traded_ticker   = s["ticker"]
        last_side            = s["side"]
        last_entry_price     = Decimal(str(s["entry_price"])) if s.get("entry_price") is not None else None
        last_entry_reason    = s.get("entry_reason")
        last_entry_contracts = live_contracts  # use live count, not saved (may have been harvested)
        last_entry_bps       = s.get("entry_bps")
        last_entry_paq       = s.get("entry_paq")
        if s.get("entry_time"):
            try:
                last_entry_time = dt.datetime.fromisoformat(s["entry_time"])
            except Exception:
                last_entry_time = dt.datetime.now(dt.timezone.utc)

        trail_high_water      = Decimal(str(s["trail_high_water"])) if s.get("trail_high_water") else None
        trail_active          = s.get("trail_active", False)
        trail_activation_reads= s.get("trail_activation_reads", 0)
        trail_below_floor_cnt = s.get("trail_below_floor_cnt", 0)
        trail_reads_post_peak = s.get("trail_reads_post_peak", 0)
        trail_mz_armed        = s.get("trail_mz_armed", False)
        trail_mz_armed_reads  = s.get("trail_mz_armed_reads", 0)
        trail_s3_zone_cnt     = s.get("trail_s3_zone_cnt", 0)

        harvest_s1_done       = s.get("harvest_s1_done", False)
        harvest_s1_count      = s.get("harvest_s1_count", 0)
        harvest_s1_fire_px    = s.get("harvest_s1_fire_px", None)
        harvest_s1_zone_left  = s.get("harvest_s1_zone_left", False)
        harvest_s2_done       = s.get("harvest_s2_done", False)
        harvest_s3_done    = s.get("harvest_s3_done", False)
        harvest_s1_reads   = s.get("harvest_s1_reads", 0)
        harvest_s2_reads   = s.get("harvest_s2_reads", 0)
        harvest_s3_reads   = s.get("harvest_s3_reads", 0)
        harvest_total_sold = s.get("harvest_total_sold", 0)

        # v234: restore WES state — critical for mid-position restart recovery
        global _wes_active, _wes_entry_px, _wes_contracts, _wes_s1_target, _wes_stop_target, _wes_side
        global _wes_entry_secs, _wes_promoted, _wes_parent_family, _wes_parent_entry_px, _wes_parent_contracts, _wes_combined_avg_px
        _wes_active      = s.get("wes_active", False)
        _wes_entry_px    = s.get("wes_entry_px", None)
        _wes_contracts   = s.get("wes_contracts", 0)
        _wes_s1_target   = s.get("wes_s1_target", None)
        _wes_stop_target = s.get("wes_stop_target", None)
        _wes_side        = s.get("wes_side", None)
        _wes_entry_secs  = s.get("wes_entry_secs", None)
        _wes_promoted        = s.get("wes_promoted", False)
        _wes_parent_family   = s.get("wes_parent_family", None)
        _wes_parent_entry_px = s.get("wes_parent_entry_px", None)
        _wes_parent_contracts= s.get("wes_parent_contracts", 0)
        _wes_combined_avg_px = s.get("wes_combined_avg_px", None)
        if _wes_active:
            _promo_str = f" PROMOTED→{_wes_parent_family}@{_wes_parent_entry_px}" if _wes_promoted else ""
            print(f"          → WES STATE RESTORED | {_wes_side} | entry {_wes_entry_px} | "
                  f"S1:{_wes_s1_target} stop:{_wes_stop_target} | {_wes_contracts}c{_promo_str}")

        _paq_stop_fired       = s.get("paq_stop_fired", False)
        _paq_zero_streak      = s.get("paq_zero_streak", 0)
        _paq_agg_opp_yes_cnt  = s.get("paq_agg_opp_yes_cnt", 0)
        _paq_agg_opp_no_cnt   = s.get("paq_agg_opp_no_cnt", 0)
        last_entry_reads      = s.get("last_entry_reads", 0)

        last_exit_side  = s.get("last_exit_side")
        last_exit_price = Decimal(str(s["last_exit_price"])) if s.get("last_exit_price") else None
        if s.get("last_exit_time"):
            try:
                last_exit_time = dt.datetime.fromisoformat(s["last_exit_time"])
            except Exception:
                last_exit_time = None

        saved_age = (dt.datetime.now(dt.timezone.utc) -
                     dt.datetime.fromisoformat(s["saved_at"])).total_seconds() if s.get("saved_at") else 999
        print(
            f"LIVE STATE RESTORED | {last_traded_ticker} | {last_side.upper()} | "
            f"entry {last_entry_price:.4f} | contracts {last_entry_contracts} | "
            f"high_water {float(trail_high_water):.4f} | trail_active {trail_active} | "
            f"state was {saved_age:.0f}s old"
        )
        return True
    except Exception as e:
        print(f"LIVE STATE LOAD ERROR: {e}")
        return False


def clear_live_state_file():
    """Remove state file after position is fully closed."""
    try:
        if os.path.exists(LIVE_STATE_FILE):
            os.remove(LIVE_STATE_FILE)
    except Exception:
        pass


def record_pending_trade(ticker, reason, side, entry_price, contracts, risk_dollars, abs_pct):
    pending_trades[ticker] = {
        "reason": reason,
        "side": side.lower(),
        "entry_price": float(entry_price),
        "contracts": int(contracts),
        "risk_dollars": float(risk_dollars),
        "abs_pct": float(abs_pct) if abs_pct is not None else None,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        # Intra-position exit tracking for accurate settlement P&L
        "harvested_contracts": 0,       # total contracts harvested
        "harvested_proceeds": 0.0,      # total proceeds from harvests
        "stopped_contracts":  0,        # total contracts exited via stop
        "stopped_proceeds":   0.0,      # total proceeds from stop exits
    }
    save_pending_trades()

def promote_pending_trade(ticker: str, wes_entry_px: float, wes_contracts: int,
                          parent_entry_px: float, parent_contracts: int,
                          combined_avg_px: float, parent_family: str):
    """v238/v239: Update pending trade record when WES scout is promoted to parent family.
    
    KEY ACCOUNTING PRINCIPLE (two separate prices, two separate roles):
    - last_entry_price (live var) = parent_entry_px  → harvest/stop TRIGGERS fire at parent thresholds
    - pending_trades["entry_price"] = combined_avg_px → settlement P&L uses correct weighted average
    
    This means: P&L reporting is accurate (WES contracts credited at 0.42, not 0.76),
    and harvest/stop triggers are identical to standalone parent family behaviour.
    
    Without this, check_settlements() would compute:
      settle_pnl = 9c × (1.0 - 0.76) = $2.16   ← wrong, uses only parent price
    With this:
      settle_pnl = 9c × (1.0 - 0.636) = $3.28  ← correct weighted average
    (example: WES 4c@0.42, parent 5c@0.76 → blended 0.636)
    """
    if ticker not in pending_trades:
        return
    t = pending_trades[ticker]
    t["entry_price"]       = combined_avg_px   # weighted avg for P&L accounting
    t["contracts"]         = wes_contracts + parent_contracts
    t["reason"]            = parent_family
    t["promoted"]          = True
    t["wes_entry_px"]      = wes_entry_px
    t["wes_contracts"]     = wes_contracts
    t["parent_entry_px"]   = parent_entry_px
    t["parent_contracts"]  = parent_contracts
    t["combined_avg_px"]   = combined_avg_px
    save_pending_trades()

def update_pending_trade_exits(ticker: str, exit_type: str, contracts: int, avg_price: float):
    """Called after any intra-position exit (harvest or stop) to update accounting."""
    if ticker not in pending_trades:
        return
    t = pending_trades[ticker]
    proceeds = contracts * avg_price
    if exit_type == "harvest":
        t["harvested_contracts"] = t.get("harvested_contracts", 0) + contracts
        t["harvested_proceeds"]  = t.get("harvested_proceeds", 0.0) + proceeds
    elif exit_type == "stop":
        t["stopped_contracts"] = t.get("stopped_contracts", 0) + contracts
        t["stopped_proceeds"]  = t.get("stopped_proceeds", 0.0) + proceeds
    save_pending_trades()


def print_full_exit_settlement(ticker: str):
    """Print WIN/LOSS SETTLED for a position fully exited via stops (no contracts remain to settle).
    Called before pending_trades.pop() so the trade record is still accessible.
    Mirrors the accounting logic in check_settlements() for stop-only exits."""
    global _ticker_pnl_log
    if ticker not in pending_trades:
        return
    trade = pending_trades[ticker]
    entry_price     = float(trade.get("entry_price", 0))
    total_contracts = int(trade.get("contracts", 0))
    harv_contracts  = int(trade.get("harvested_contracts", 0))
    harv_proceeds   = float(trade.get("harvested_proceeds", 0.0))
    stop_contracts  = int(trade.get("stopped_contracts", 0))
    stop_proceeds   = float(trade.get("stopped_proceeds", 0.0))
    # For a fully-stopped position, settled_contracts should be 0
    # We can't know the Kalshi settlement outcome yet, so treat remaining as unknown
    # If stop_contracts + harv_contracts == total_contracts, position is fully closed
    if stop_contracts + harv_contracts < total_contracts:
        return  # position not fully exited — let check_settlements handle it
    harv_pnl  = harv_proceeds  - (harv_contracts  * entry_price)
    stop_pnl  = stop_proceeds  - (stop_contracts  * entry_price)
    total_pnl = harv_pnl + stop_pnl
    outcome   = "WIN" if total_pnl > 0 else "LOSS"
    pnl_text  = f"+${total_pnl:.2f}" if total_pnl >= 0 else f"-${abs(total_pnl):.2f}"
    _entry_str = f"{trade['side'].upper()} @ {entry_price:.2f} ({total_contracts}c)"
    _legs = []
    if harv_contracts > 0:
        _legs.append(f"harvested {harv_contracts}c {harv_pnl:+.2f}")
    if stop_contracts > 0:
        _legs.append(f"stopped {stop_contracts}c {stop_pnl:+.2f}")
    _legs_str = " | ".join(_legs) if _legs else "fully stopped"
    # Fetch balance
    _bal_str = ""
    try:
        _bal_resp = signed_request("GET", "/portfolio/balance")
        if _bal_resp.status_code == 200:
            _bal_data = _bal_resp.json()
            _bal = float(_bal_data.get("balance", _bal_data.get("available_balance",
                         _bal_data.get("cash_balance", 0)))) / 100
            _bal_str = f" | bal ${_bal:.2f}"
    except Exception:
        pass
    msg = f"{outcome} SETTLED | {trade['reason']} | {_entry_str} | {_legs_str} | NET {pnl_text}" + _bal_str
    print(msg)
    send_telegram_alert(msg)
    if ticker not in _ticker_pnl_log:
        _ticker_pnl_log[ticker] = []
    _ticker_pnl_log[ticker].append((trade["reason"], total_pnl))

def get_market_details(ticker: str):
    resp = signed_request("GET", f"/markets/{ticker}")
    if resp.status_code != 200: return None
    try:
        data = resp.json()
        if isinstance(data, dict):
            return data.get("market", data)
        return None
    except Exception:
        return None

def get_settlement_side(market):
    if not market: return None
    result = market.get("result")
    if isinstance(result, str) and result.lower() in ("yes", "no"): return result.lower()
    winner = market.get("winner")
    if isinstance(winner, str) and winner.lower() in ("yes", "no"): return winner.lower()
    settlement_value = market.get("settlement_value")
    if settlement_value is not None:
        try:
            return "yes" if float(settlement_value) >= 0.5 else "no"
        except Exception: pass
    yes_settle = market.get("yes_settlement_dollars")
    no_settle = market.get("no_settlement_dollars")
    try:
        if yes_settle is not None and float(yes_settle) >= 0.99: return "yes"
        if no_settle is not None and float(no_settle) >= 0.99: return "no"
    except Exception: pass
    return None

def estimate_settled_pnl(entry_price, contracts, won):
    entry = float(entry_price)
    c = int(contracts)
    return c * (1.0 - entry) if won else -(c * entry)

def check_pending_settlements():
    """Re-poll Kalshi balance for trades whose settlement wasn't confirmed at close time.
    Fires once per new ticker (not every poll) to avoid log spam.

    Two-layer reconciliation (v203):
      Layer 1 — per-trade truth: use internal_pnl for each trade's NET.
                 Internal math (settle + harvest + stop) is stable per-trade.
                 Balance delta is NOT used as per-trade truth — harvest credits
                 land asynchronously and make the delta unstable.
      Layer 2 — account truth: compare sum of internal NETs vs observed balance
                 movement for the confirmed batch. Print one batch discrepancy
                 line if they diverge materially.

    This prevents the v202 bug where multiple trades all confirmed simultaneously
    each claimed the same single balance movement as their individual NET.
    """
    global _pending_settlement_queue, _session_running_pnl, _session_start_balance
    if not _pending_settlement_queue:
        return

    _current_ticker = last_seen_ticker or ""
    still_pending = []
    confirmed_this_cycle = []  # collect all confirmed trades this cycle for batch check

    # ── Step 1: fetch balance once for the whole cycle ────────────────────
    _cur_bal = None
    try:
        _r = signed_request("GET", "/portfolio/balance")
        if _r.status_code == 200:
            _d = _r.json()
            _cur_bal = float(_d.get("balance", _d.get("available_balance",
                             _d.get("cash_balance", 0)))) / 100
    except Exception:
        pass

    # ── Step 2: evaluate each pending settlement ──────────────────────────
    for _ps in _pending_settlement_queue:
        # Throttle: one check per ticker per trade
        if _ps.get("last_checked_ticker") == _current_ticker and _ps["attempt"] > 0:
            still_pending.append(_ps)
            continue
        _ps["last_checked_ticker"] = _current_ticker
        _ps["attempt"] += 1

        if _cur_bal is None:
            still_pending.append(_ps)
            continue

        _pre = _ps["pre_bal"]
        print(f"          → SETTLE RECHECK | {_ps['reason']} | attempt {_ps['attempt']} | "
              f"bal ${_cur_bal:.2f} | pre ${_pre:.2f}" if _pre else
              f"          → SETTLE RECHECK | {_ps['reason']} | attempt {_ps['attempt']} | "
              f"bal ${_cur_bal:.2f}")

        _bal_moved = _pre is not None and abs(_cur_bal - _pre) > 0.005
        _resolved = False

        if _bal_moved:
            # Balance moved — use internal P&L as per-trade truth (Layer 1)
            _trade_pnl = _ps["internal_pnl"]
            _outcome = "WIN" if _trade_pnl >= 0 else "LOSS"
            _net_text = f"+${_trade_pnl:.2f}" if _trade_pnl >= 0 else f"-${abs(_trade_pnl):.2f}"
            print(f"SETTLE CONFIRMED | {_outcome} | {_ps['reason']} | "
                  f"{_ps['side'].upper()} @ {_ps['entry_px']:.2f} ({_ps['total_c']}c) | "
                  f"NET {_net_text} | bal ${_cur_bal:.2f} "
                  f"(confirmed attempt {_ps['attempt']})")
            _session_running_pnl += _trade_pnl
            if _session_start_balance is None:
                _session_start_balance = _cur_bal - _trade_pnl
            _ps_ticker = _ps.get("ticker", "")
            if _ps_ticker not in _ticker_pnl_log:
                _ticker_pnl_log[_ps_ticker] = []
            _ticker_pnl_log[_ps_ticker].append((_ps["reason"], _trade_pnl))
            confirmed_this_cycle.append((_ps, _trade_pnl, _cur_bal))
            _resolved = True

        elif _ps["attempt"] >= 5:
            # Balance not moving — check market status directly
            try:
                _ps_ticker = _ps.get("ticker", "")
                _ps_market = get_market_details(_ps_ticker) if _ps_ticker else None
                _ps_status = str(_ps_market.get("status","")).lower() if _ps_market else ""
                _ps_settle_side = get_settlement_side(_ps_market) if _ps_market else None
                if _ps_status in ("settled","closed","resolved","finalized") and _ps_settle_side:
                    _ps_won = (_ps_settle_side == _ps.get("side","").lower())
                    _trade_pnl = _ps["internal_pnl"]
                    _ps_outcome = "WIN" if _ps_won else "LOSS"
                    _net_text = f"+${_trade_pnl:.2f}" if _trade_pnl >= 0 else f"-${abs(_trade_pnl):.2f}"
                    _session_running_pnl += _trade_pnl
                    if _session_start_balance is None:
                        _session_start_balance = _cur_bal - _trade_pnl
                    print(f"SETTLE CONFIRMED | {_ps_outcome} | {_ps['reason']} | "
                          f"{_ps.get('side','?').upper()} @ {_ps['entry_px']:.2f} ({_ps['total_c']}c) | "
                          f"NET {_net_text} | bal ${_cur_bal:.2f} (market confirmed, bal delta unavailable)")
                    if _ps_ticker not in _ticker_pnl_log:
                        _ticker_pnl_log[_ps_ticker] = []
                    _ticker_pnl_log[_ps_ticker].append((_ps["reason"], _trade_pnl))
                    confirmed_this_cycle.append((_ps, _trade_pnl, _cur_bal))
                    _resolved = True
            except Exception:
                pass

        elif _ps["attempt"] >= 20:
            _trade_pnl = _ps["internal_pnl"]
            _session_running_pnl += _trade_pnl
            _unres_text = f"+${_trade_pnl:.2f}" if _trade_pnl >= 0 else f"-${abs(_trade_pnl):.2f}"
            print(f"SETTLE UNRESOLVED | {_ps['reason']} | "
                  f"balance never moved after 20 polls | "
                  f"NET {_unres_text} (internal est)")
            _resolved = True

        if not _resolved:
            still_pending.append(_ps)

    # ── Step 3: batch account reconciliation (Layer 2) ───────────────────
    # Compare sum of internal NETs for confirmed batch vs observed balance move.
    # This is account-level validation only — does not overwrite per-trade NETs.
    if len(confirmed_this_cycle) > 1 and _cur_bal is not None:
        _batch_internal = sum(pnl for _, pnl, _ in confirmed_this_cycle)
        # Use the earliest pre_bal as the batch anchor
        _pre_bals = [ps["pre_bal"] for ps, _, _ in confirmed_this_cycle
                     if ps.get("pre_bal") is not None]
        if _pre_bals:
            _batch_pre = min(_pre_bals)  # earliest (lowest) pre_bal = before any credits
            _batch_kalshi = _cur_bal - _batch_pre
            _batch_disc = _batch_kalshi - _batch_internal
            if abs(_batch_disc) > 0.10:
                print(f"SETTLE BATCH | {len(confirmed_this_cycle)} trades | "
                      f"internal sum ${_batch_internal:+.2f} | "
                      f"kalshi delta ${_batch_kalshi:+.2f} | "
                      f"batch gap {_batch_disc:+.2f} (harvest timing)")

    _pending_settlement_queue = still_pending
    save_pending_settlements()
    if not _pending_settlement_queue:
        try:
            if os.path.exists(PENDING_SETTLEMENTS_FILE):
                os.remove(PENDING_SETTLEMENTS_FILE)
        except Exception:
            pass


def check_settlements():
    if not pending_trades: return
    to_remove = []
    _batch_confirmed = []  # collect all confirmed trades for batch reconciliation

    # ── Fetch pre-settlement balance ONCE for the whole batch ─────────────
    # v203: one snapshot before processing any trade in this cycle.
    # Each trade claiming its own pre/post delta caused multi-count of same move.
    _batch_pre_bal = None
    try:
        _pre_resp = signed_request("GET", "/portfolio/balance")
        if _pre_resp.status_code == 200:
            _d = _pre_resp.json()
            _batch_pre_bal = float(_d.get("balance", _d.get("available_balance",
                             _d.get("cash_balance", 0)))) / 100
    except Exception:
        pass

    for ticker, trade in list(pending_trades.items()):
        if ticker in settled_tickers: continue
        market = get_market_details(ticker)
        if not market: continue
        status = str(market.get("status", "")).lower()
        if status not in ("settled", "closed", "resolved", "finalized"): continue
        settled_side = get_settlement_side(market)
        if settled_side not in ("yes", "no"): continue
        won = trade["side"] == settled_side

        entry_price      = float(trade["entry_price"])
        total_contracts  = int(trade["contracts"])
        harv_contracts   = int(trade.get("harvested_contracts", 0))
        harv_proceeds    = float(trade.get("harvested_proceeds", 0.0))
        stop_contracts   = int(trade.get("stopped_contracts", 0))
        stop_proceeds    = float(trade.get("stopped_proceeds", 0.0))
        settled_contracts = max(0, total_contracts - harv_contracts - stop_contracts)

        settle_pnl = settled_contracts * (1.0 - entry_price) if won else -(settled_contracts * entry_price)
        harv_pnl   = harv_proceeds - (harv_contracts * entry_price)
        stop_pnl   = stop_proceeds - (stop_contracts * entry_price)
        _internal_net = settle_pnl + harv_pnl + stop_pnl

        # v159: record PAQ_STRUCT loss ticker for cooldown gate
        if _internal_net <= 0 and trade.get("reason") == "PAQ_STRUCT_GATE":
            global _paq_struct_loss_ticker
            _paq_struct_loss_ticker = ticker

        global _session_start_balance, _session_running_pnl

        # ── Per-trade truth: always use internal_pnl (Layer 1) ───────────
        # Balance delta is NOT used as per-trade NET. Harvest credits land
        # asynchronously and make balance delta unreliable per-trade.
        # Balance is used only for account-level batch validation (Layer 2).
        total_pnl = _internal_net
        outcome   = "WIN" if total_pnl > 0 else "LOSS"

        # Retry loop to detect whether Kalshi balance actually moved
        import time as _time
        _post_bal = _batch_pre_bal
        _bal_moved = False
        try:
            for _attempt in range(10):
                _time.sleep(1.0)
                _post_resp = signed_request("GET", "/portfolio/balance")
                if _post_resp.status_code == 200:
                    _d2 = _post_resp.json()
                    _b = float(_d2.get("balance", _d2.get("available_balance",
                               _d2.get("cash_balance", 0)))) / 100
                    if _batch_pre_bal is None or abs(_b - _batch_pre_bal) > 0.005:
                        _post_bal = _b
                        _bal_moved = True
                        break
                    _post_bal = _b
        except Exception:
            pass

        _verify_str = ""
        try:
            _ord_resp = signed_request("GET", "/portfolio/orders",
                                       params={"ticker": ticker, "limit": 5})
            if _ord_resp.status_code == 200:
                _orders = _ord_resp.json().get("orders", [])
                _fills = []
                for _o in _orders:
                    _fc = int(Decimal(str(_o.get("fill_count_fp", 0))))
                    if _fc > 0:
                        _raw_px = float(_o.get("avg_fill_price_dollars") or
                                        _o.get("yes_price_dollars") or
                                        _o.get("no_price_dollars") or 0)
                        _o_side   = _o.get("side", "?").lower()
                        _o_action = _o.get("action", "?")
                        _display_px = (1.0 - _raw_px) if _o_side == "no" else _raw_px
                        _fills.append(f"{_o_side.upper()} {_o_action} {_fc}c@{_display_px:.2f}")
                if _fills:
                    _verify_str = f" | orders: {' '.join(_fills[:4])}"
        except Exception:
            pass

        pnl_text  = f"+${total_pnl:.2f}" if total_pnl >= 0 else f"-${abs(total_pnl):.2f}"
        _entry_str = f"{trade['side'].upper()} @ {entry_price:.2f} ({total_contracts}c)"
        _legs = []
        if harv_contracts > 0: _legs.append(f"harvested {harv_contracts}c {harv_pnl:+.2f}")
        if stop_contracts  > 0: _legs.append(f"stopped {stop_contracts}c {stop_pnl:+.2f}")
        if settled_contracts > 0: _legs.append(f"settled {settled_contracts}c {settle_pnl:+.2f}")
        _legs_str = " | ".join(_legs) if _legs else "settled all"

        if _bal_moved:
            _bal_str = f" | bal ${_post_bal:.2f}"
            _session_running_pnl += total_pnl
            if _session_start_balance is None:
                _session_start_balance = _post_bal - total_pnl
            msg = f"{outcome} SETTLED | {trade['reason']} | {_entry_str} | {_legs_str} | NET {pnl_text}" + _bal_str + _verify_str
            print(msg)
            send_telegram_alert(msg)
            if ticker not in _ticker_pnl_log:
                _ticker_pnl_log[ticker] = []
            _ticker_pnl_log[ticker].append((trade["reason"], total_pnl))
            _batch_confirmed.append((_internal_net, _post_bal))
        else:
            # Balance not confirmed — enqueue for re-poll
            _pending_settlement_queue.append({
                "reason": trade["reason"], "side": trade["side"],
                "entry_px": float(entry_price), "total_c": total_contracts,
                "internal_pnl": _internal_net, "pre_bal": _batch_pre_bal,
                "ticker": ticker, "attempt": 0, "outcome": outcome
            })
            save_pending_settlements()
            _pending_bal_str = f" | bal ${_post_bal:.2f} (unconfirmed)" if _post_bal is not None else ""
            msg = f"SETTLEMENT PENDING | {trade['reason']} | {_entry_str} | {_legs_str} | est {pnl_text}" + _pending_bal_str + _verify_str
            print(msg)
            send_telegram_alert(msg)

        global _session_trades, _session_started
        import datetime as _dt
        if _session_started is None:
            _session_started = _dt.datetime.now(_dt.timezone.utc)
        _session_trades.append({"outcome": outcome, "reason": trade["reason"],
                                "side": trade["side"].upper(), "pnl": total_pnl})
        if ticker != last_traded_ticker:
            clear_live_state_file()
        settled_tickers.add(ticker)
        to_remove.append(ticker)

    for t in to_remove:
        pending_trades.pop(t, None)
    if to_remove:
        save_pending_trades()

    # ── Batch account reconciliation (Layer 2) ────────────────────────────
    # Compare sum of internal NETs to observed balance move for the batch.
    # Informational only — does not override per-trade NETs.
    if len(_batch_confirmed) > 1 and _batch_pre_bal is not None:
        _batch_internal = sum(pnl for pnl, _ in _batch_confirmed)
        _final_bal = _batch_confirmed[-1][1]
        _batch_kalshi = _final_bal - _batch_pre_bal
        _batch_disc = _batch_kalshi - _batch_internal
        if abs(_batch_disc) > 0.10:
            print(f"SETTLE BATCH | {len(_batch_confirmed)} trades | "
                  f"internal sum ${_batch_internal:+.2f} | "
                  f"kalshi delta ${_batch_kalshi:+.2f} | "
                  f"batch gap {_batch_disc:+.2f} (harvest timing)")


def break_pressure_score(strike, btc_prices):
    if len(btc_prices) < 6 or strike is None:
        return 0.0
    arr = list(btc_prices)[-6:]
    score = 0
    for i in range(1, len(arr)):
        prev_px = arr[i - 1]
        cur_px = arr[i]
        prev_signed = prev_px - strike
        cur_signed = cur_px - strike
        if cur_signed > 0 and cur_signed > prev_signed:
            score += 1
        elif cur_signed < 0 and cur_signed < prev_signed:
            score -= 1
        if prev_signed <= 0 < cur_signed:
            score += 1
        elif prev_signed >= 0 > cur_signed:
            score -= 1
        if abs(cur_px - prev_px) > 0.002 * strike:
            if abs(cur_signed) < abs(prev_signed):
                if prev_signed > 0:
                    score -= 1
                elif prev_signed < 0:
                    score += 1
    return score

def bps_fade_too_large(side, entry_bps, prev1_bps, prev2_bps, fade_threshold=2):
    if side == "yes":
        recent_peak = max(prev1_bps, prev2_bps)
        return (recent_peak - entry_bps) >= fade_threshold
    if side == "no":
        recent_trough = min(prev1_bps, prev2_bps)
        return (entry_bps - recent_trough) >= fade_threshold
    return False

def get_recent_bps_series(strike, btc_prices, checks=3):
    if strike is None or len(btc_prices) < 6:
        return []
    full = list(btc_prices)
    out = []
    for end_idx in range(6, len(full) + 1):
        window = full[end_idx - 6:end_idx]
        if len(window) == 6:
            out.append(break_pressure_score(strike, window))
    return out[-checks:]

def bps_persistent(side, strike, btc_prices, threshold=2, checks=3, need=2):
    arr = get_recent_bps_series(strike, btc_prices, checks)
    if len(arr) < checks:
        return False
    if side == "yes":
        hits = sum(1 for x in arr if x >= threshold)
        return hits >= need
    if side == "no":
        hits = sum(1 for x in arr if x <= -threshold)
        return hits >= need
    return False

def strong_abs_persistence(min_now=0.12, min_prev=0.11):
    arr = list(RECENT_ABS_PCTS)
    if len(arr) < 3:
        return False
    return arr[-1] >= min_now and arr[-2] >= min_prev and arr[-3] >= min_prev

def legacy_entry_allowed(current_abs):
    if current_abs is None:
        return False
    if current_abs < 0.12:
        return False
    if not strong_abs_persistence(0.12, 0.11):
        return False
    if abs_drop_too_large(0.095, 3):
        return False
    return True

def abs_staircase():
    arr = list(RECENT_ABS_PCTS)[-4:]
    if len(arr) < 4: return False
    non_dec = sum(1 for i in range(1, len(arr)) if arr[i] >= arr[i-1])
    net = arr[-1] - arr[0]
    max_drop = max((arr[i-1] - arr[i] for i in range(1, len(arr)) if arr[i] < arr[i-1]), default=0)
    return non_dec >= 3 and max_drop <= 0.03 and net >= 0.05

def abs_hhhl_early():
    arr = list(RECENT_ABS_PCTS)[-6:]
    if len(arr) < 6:
        return False
    drops = 0
    for i in range(1, len(arr)):
        if arr[i] < arr[i-1]:
            drops += 1
        else:
            drops = 0
        if drops >= 2:
            return False
    return arr[-1] > arr[-3] and arr[-2] > arr[-5]

def abs_consistent(min_abs, min_checks=4):
    arr = list(RECENT_ABS_PCTS)[-min_checks:]
    if len(arr) < min_checks:
        return False
    return all(v >= min_abs for v in arr) and all(arr[i] >= arr[i-1] for i in range(1, len(arr)))

def check_directional_entry(seconds_left, yes_price, no_price, strike, btc_prices, metrics, current_abs, signed_pct, paq_candles=None, current_btc=None, bcdp=0, bcdp_clean=False, ticker=""):
    # Hard floor: never enter with < 60s remaining
    if seconds_left is not None and seconds_left < 60:
        return None, None
    """
    Family 1 — Directional (BPS-led). Always checked first.
    If this family qualifies, Confirmation family does not get to compete.

    Premium Directional (180–600s, price 0.72–0.88):
      Strong BPS >= 3, abs >= 0.04%, persistent, no decay, side leads + matches strike.
      Best edge, best pricing — enter before the move gets expensive.

    Late Directional (10–179s, price 0.84–0.94):
      BPS >= 2, abs meets time-varying threshold, persistent, not fading.
      Stricter because time is short and noise is higher.
    """
    if yes_price is None or no_price is None:
        return None, None
    if metrics is None or strike is None or len(btc_prices) < 6:
        return None, None

    # shared BPS history
    full = list(btc_prices)
    bps_arr = []
    for end_idx in range(6, len(full) + 1):
        window = full[end_idx - 6:end_idx]
        if len(window) == 6:
            bps_arr.append(break_pressure_score(strike, window))
    live_bps  = bps_arr[-1] if bps_arr else break_pressure_score(strike, btc_prices)
    last3     = bps_arr[-3:] if len(bps_arr) >= 3 else bps_arr
    prev1_bps = bps_arr[-2] if len(bps_arr) >= 2 else live_bps
    prev2_bps = bps_arr[-3] if len(bps_arr) >= 3 else prev1_bps

    # ── Premium BPS (180–600s) ──────────────────────────────────────────
    # bps_premium BCDP gate: requires clean persistent BPS
    # Data: -1.89 bps_prem had BCDP_CLEAN=dirty (BPS fading: 3→2→1→0→1)
    # v188: session-gated ABS floor for bps_premium.
    # EU_MORNING: 1W/1L -$4.13 — raise ABS floor to 0.12% (double standard)
    #   to only enter on genuinely committed moves, not marginal setups.
    # NY_OPEN: 2W/1L -$5.39 — raise to 0.10% to filter weak-abs late entries.
    # EU_ACTIVE: 3W/1L +$0.88 — keep standard floor (marginal positive).
    _bps_sess = get_session_label()
    if _bps_sess == "EU_MORNING":
        _bps_sess_abs_mult = 1.5   # 50% higher floor — tighten before hard off
    elif _bps_sess == "NY_OPEN":
        _bps_sess_abs_mult = 1.25  # 25% higher floor
    else:
        _bps_sess_abs_mult = 1.0
    if 180 <= seconds_left <= 600 and bcdp_clean:
        # abs decay check — use time-specific floor via get_prem_abs_floor()
        arr = list(RECENT_ABS_PCTS)
        if not (len(arr) >= 3 and (max(arr[-3:]) - current_abs) > EARLY_ENTRY_ABS_DECAY):
            prem_abs = get_prem_abs_floor(seconds_left)

            # ── PAQ quality gate ────────────────────────────────────
            paq_yes = get_paq_score("yes", paq_candles, current_btc, live_bps, prev1_bps, current_abs, prem_abs)
            paq_no  = get_paq_score("no",  paq_candles, current_btc, live_bps, prev1_bps, current_abs, prem_abs)
            paq_y_score = paq_yes[0] if paq_yes else None
            paq_n_score = paq_no[0]  if paq_no  else None

            # bps_premium soft structure gate:
            # CTX=0 + EXP>=2 = fast momentum without candle backdrop.
            # The 00:43 bps_premium YES loss proves this profile produces the
            # same late unexitable reversal as PAQ_EARLY_AGG partial-structure entries.
            # Block when seconds_left <= 240 OR entry price >= 0.75.
            _bps_ctx_y = paq_yes[1] if paq_yes else 0
            _bps_exp_y = paq_yes[3] if paq_yes else 0
            _bps_ctx_n = paq_no[1]  if paq_no  else 0
            _bps_exp_n = paq_no[3]  if paq_no  else 0
            _bps_partial_exp_yes = (_bps_ctx_y == 0 and _bps_exp_y >= 2)
            _bps_partial_exp_no  = (_bps_ctx_n == 0 and _bps_exp_n >= 2)

            # YES
            _bps_mag_ok_y, _bps_mag_note_y = premium_bps_mag_pass(_bps_history)
            if (signed_pct is not None and signed_pct > 0
                    and current_abs >= prem_abs * _bps_sess_abs_mult
                    and EARLY_ENTRY_MIN_PRICE <= yes_price <= EARLY_ENTRY_MAX_PRICE
                    and yes_price > no_price
                    and live_bps >= EARLY_ENTRY_MIN_BPS
                    and sum(1 for b in last3 if b >= EARLY_ENTRY_PERSIST_BPS) >= 2
                    and not (last3 and (max(last3) - live_bps) >= EARLY_ENTRY_BPS_WEAKEN)
                    and (paq_y_score is None or paq_y_score >= PAQ_MODERATE)
                    and _bps_mag_ok_y):
                # Soft structure gate: block partial-structure expansion in danger zone
                if _bps_partial_exp_yes and (seconds_left <= 240 or yes_price >= Decimal("0.75")):
                    _last_entry_block = f"BPS_PREM_BLOCKED | YES | CTX=0 EXP={_bps_exp_y} partial-struct | px {float(yes_price):.4f}"
                else:
                    return "yes", "bps_premium"
            # NO
            _bps_mag_ok_n, _bps_mag_note_n = premium_bps_mag_pass(_bps_history)
            if (signed_pct is not None and signed_pct < 0
                    and current_abs >= prem_abs * _bps_sess_abs_mult
                    and EARLY_ENTRY_MIN_PRICE <= no_price <= EARLY_ENTRY_MAX_PRICE
                    and no_price > yes_price
                    and live_bps <= -EARLY_ENTRY_MIN_BPS
                    and sum(1 for b in last3 if b <= -EARLY_ENTRY_PERSIST_BPS) >= 2
                    and not (last3 and (live_bps - min(last3)) >= EARLY_ENTRY_BPS_WEAKEN)
                    and (paq_n_score is None or paq_n_score >= PAQ_MODERATE)
                    and _bps_mag_ok_n):
                # Soft structure gate: block partial-structure expansion in danger zone
                if _bps_partial_exp_no and (seconds_left <= 240 or no_price >= Decimal("0.75")):
                    _last_entry_block = f"BPS_PREM_BLOCKED | NO | CTX=0 EXP={_bps_exp_n} partial-struct | px {float(no_price):.4f}"
                else:
                    return "no", "bps_premium"

    # ── Late BPS (10–179s) ──────────────────────────────────────────────
    bps_min_abs = get_bps_min_abs(seconds_left)
    if 10 <= seconds_left <= 179 and current_abs >= bps_min_abs:
        if signed_pct is not None:
            if (signed_pct > 0
                    and Decimal("0.84") <= yes_price <= Decimal("0.94")
                    and yes_price > no_price
                    and live_bps >= BPS_MIN_SCORE
                    and bps_persistent("yes", strike, btc_prices, threshold=2, checks=3, need=2)
                    and not bps_fade_too_large("yes", live_bps, prev1_bps, prev2_bps, 2)
                    ):
                return "yes", "bps_late"
            if (signed_pct < 0
                    and Decimal("0.84") <= no_price <= Decimal("0.94")
                    and no_price > yes_price
                    and live_bps <= -BPS_MIN_SCORE
                    and bps_persistent("no", strike, btc_prices, threshold=2, checks=3, need=2)
                    and not bps_fade_too_large("no", live_bps, prev1_bps, prev2_bps, 2)
                    ):
                return "no", "bps_late"

    # Universal hard floor: never enter with <60s remaining
    # Kalshi price discovery unreliable in final minute; execution risk extreme

    return None, None


def check_confirmation_entry(seconds_left, yes_price, no_price, hist_yes, hist_no, metrics, current_abs, signed_pct, bcdp=0, bcdp_clean=False, ticker=""):
    # Universal hard floor: never enter with < 60s remaining (mirrors check_directional_entry)
    if seconds_left is not None and seconds_left < 60:
        return None, None
    """
    Family 2 — Confirmation (price/structure-led).
    Only checked when Directional family does not qualify.

    Standard Confirmation (120–360s, price 0.78–0.92):
      Strong momentum or consistent hold. abs >= 0.04%.
      Side leads market. Catches good structure when BPS is not enough.

    Late Confirmation (10–120s):
      Expensive entries only with clear continuation quality.
      Fallback/cleanup entries when structure is very strong late.
    """
    if yes_price is None or no_price is None:
        return None, None

    # ── Shared helpers for PAQ families ──────────────────────────────
    _live_bps = break_pressure_score(metrics["strike"], list(btc_prices)) if (metrics and "strike" in metrics and len(btc_prices) >= 6) else 0
    _prem_abs = get_prem_abs_floor(seconds_left)
    global _paq_pending_yes_count, _paq_pending_no_count, _paq_stop_fired, _paq_zero_streak
    global _paq_bps_soft_yes_cnt, _paq_bps_soft_no_cnt
    global _paq_agg_opp_yes_cnt, _paq_agg_opp_no_cnt
    global trail_high_water, trail_active, trail_reads_post_peak, trail_below_floor_cnt, last_entry_reads, trail_activation_reads
    global trail_mz_armed, trail_mz_armed_reads, trail_s3_zone_cnt
    global harvest_s1_done, harvest_s2_done, harvest_s3_done, harvest_s1_reads, harvest_s2_reads, harvest_s3_reads, harvest_total_sold

    # Post-stop flips are handled by the normal entry engine (bps_premium,
    # PAQ_EARLY_AGG). Data shows all 9 recorded post-stop re-entries were
    # captured at 0.59-0.87 by these strategies — above any mid-book gate.
    # The gate staying open (Case A in run_bot) is the fix. No dedicated
    # FLIP_REENTRY strategy needed.

    # ── PAQ_PENDING_ALIGN — PAQ leads, BPS lagging (2 consecutive) ────
    # YES: PAQ>=5, BPS in {-1, 0}, signed+, price 0.40-0.75
    # NO:  PAQ>=5, BPS in {0, +1}, signed-, price 0.40-0.75
    if seconds_left <= PAQ_PENDING_MAX_SECONDS and prev_paq_score is not None:
        _pending_yes_raw = (
            prev_paq_score >= PAQ_PENDING_MIN_PAQ
            and _live_bps in (-1, 0)
            and signed_pct is not None and signed_pct > 0
            and current_abs >= _prem_abs
            and yes_price >= no_price
            and PAQ_PENDING_MIN_PRICE <= yes_price <= PAQ_PENDING_MAX_PRICE
        )
        _pending_no_raw = (
            prev_paq_score >= PAQ_PENDING_MIN_PAQ
            and _live_bps in (0, 1)
            and signed_pct is not None and signed_pct < 0
            and current_abs >= _prem_abs
            and no_price >= yes_price
            and PAQ_PENDING_MIN_PRICE <= no_price <= PAQ_PENDING_MAX_PRICE
        )
        _paq_pending_yes_count = _paq_pending_yes_count + 1 if _pending_yes_raw else 0
        _paq_pending_no_count  = _paq_pending_no_count  + 1 if _pending_no_raw  else 0
        if _paq_pending_yes_count >= PAQ_PENDING_CONSEC:
            return "yes", "PAQ_PENDING_ALIGN"
        if _paq_pending_no_count >= PAQ_PENDING_CONSEC:
            return "no", "PAQ_PENDING_ALIGN"
    else:
        _paq_pending_yes_count = 0
        _paq_pending_no_count  = 0
        _paq_stop_fired = False
        _paq_zero_streak = 0
        trail_high_water = None
        trail_active = False
        trail_reads_post_peak = 0
        trail_below_floor_cnt = 0
        trail_activation_reads = 0
        trail_mz_armed = False
        trail_mz_armed_reads = 0
        trail_s3_zone_cnt = 0
        harvest_s1_done = False
        harvest_s2_done = False
        harvest_s1_reads = 0
        harvest_s2_reads = 0
        harvest_total_sold = 0
        last_entry_reads = 0
        _paq_bps_soft_yes_cnt = 0
        _paq_bps_soft_no_cnt  = 0

    # ── PAQ_EARLY_AGG (≤780s, PAQ≥4, BPS≥2/≤-2, price 0.40-0.90) ────
    # CTX/STATE entry gate: require CTX >= 1 AND STATE >= 1.
    # Every immediate flip in the dataset had CTX=0 or STATE=0 at entry.
    # This filters entries where candle backdrop or BTC position don't support
    # the direction, even if total PAQ score (>=4) and momentum look adequate.
    _agg_ctx_gate = (prev_paq_ctx is not None and prev_paq_state is not None
                     and prev_paq_ctx >= 1 and prev_paq_state >= 1)
    # Forensic gate logging: print decision-time values every time PAQ_EARLY_AGG
    # is evaluated, so we can verify displayed status vs actual gate state match.
    if seconds_left <= PAQ_EARLY_AGG_MAX_SECS and prev_paq_score is not None and prev_paq_score >= 4:
        _gate_bucket = ("STRONG" if prev_paq_score >= 5 else "MODERATE" if prev_paq_score >= 3 else "WEAK")
        # PAQ_STRUCT_GATE: structure checkpoint only (CTX+STATE).
        # READY = structure passes; BLOCKED = structure fails.
        # Price/BPS/session floors still evaluated separately after this.
        _gate_result = "READY" if _agg_ctx_gate else "BLOCKED"
        global _last_gate_result, _last_entry_block, _pending_regime_display
        _last_gate_result = _gate_result
        _last_entry_block = ""  # reset each poll

        # Entry classification:
        # TIER_A: CTX>=1, STATE>=1, EXP<=1 — early aligned structure, moderate expansion (best profile)
        # TIER_B: CTX=2, STATE=2, EXP=2   — mature full structure (late but valid)
        # TIER_C: CTX<2, STATE<2, EXP=2   — partial structure + max expansion (danger profile)
        # TIER_D: any other gate-pass combo
        _paq_ctx_v   = prev_paq_ctx   if prev_paq_ctx   is not None else 0
        _paq_state_v = prev_paq_state if prev_paq_state is not None else 0
        _paq_exp_v   = prev_paq_exp   if prev_paq_exp   is not None else 0

        if _agg_ctx_gate and _paq_exp_v <= 1:
            _entry_tier = "TIER_A"   # early structure, moderate expansion — best asymmetry
        elif _agg_ctx_gate and _paq_ctx_v == 2 and _paq_state_v == 2 and _paq_exp_v == 2:
            _entry_tier = "TIER_B"   # mature full structure — good but late
        elif _agg_ctx_gate and _paq_ctx_v < 2 and _paq_state_v < 2 and _paq_exp_v == 2:
            _entry_tier = "TIER_C"   # partial structure + max expansion — danger profile
        elif _agg_ctx_gate:
            # Split TIER_D by EXP to track whether partial-structure + max expansion
            # is a valid monetization lane or a risk pattern like TIER_C.
            _entry_tier = "TIER_D_EXP2" if _paq_exp_v == 2 else "TIER_D"
        else:
            _entry_tier = "GATE_FAIL"

        # Partial structure + EXP=2 price ceiling (TIER_C):
        # When CTX<2 AND STATE<2 AND EXP=2, cap entry below normal 0.90 ceiling.
        # These entries pay premium price for fast underpinned momentum — the
        # dataset shows they produce the cluster of unexitable late reversals.
        # Price discipline directly fixes the asymmetry problem.
        #
        # Session-aware: Asia Open (03-06 UTC / 20-22 MST) is more tolerant —
        # TIER_C entries showed 75%+ WR in that session because longer Asia trends
        # support partial-structure momentum entries. Allow up to 0.85 there.
        # All other sessions keep the 0.82 ceiling.
        if _entry_tier == "TIER_C":
            _agg_price_ceil = SESSION_ASIA_OPEN_TIER_C_CEIL if get_session_label() == "ASIA_OPEN" else Decimal("0.82")
        else:
            _agg_price_ceil = Decimal("0.90")

        # Data-driven BPS floors (3/17 session analysis):
        # - EXP=2 at >500s left: 33% stop rate vs 7% for BPS3. Require BPS>=4.
        # - NY_OPEN entries avg 2× abs at entry of EU sessions (0.200% vs 0.092%).
        #   31% stop rate. Raise minimum from 2 to 3 in NY_OPEN.
        _yes_bps_floor = 2
        if _paq_exp_v == 2 and seconds_left > 500:
            _yes_bps_floor = 4    # EXP=2 long-time: data shows 33% stop rate
        elif get_session_label() == "NY_OPEN":
            _yes_bps_floor = 3    # NY_OPEN: entering late in moves, raise bar

        if (_agg_ctx_gate
                and signed_pct is not None and signed_pct > 0
                and yes_price > no_price
                and Decimal("0.40") <= yes_price <= _agg_price_ceil
                and current_abs >= _prem_abs
                and _live_bps >= _yes_bps_floor):
            _last_entry_class = f"{_entry_tier} | CTX {_paq_ctx_v} STATE {_paq_state_v} EXP {_paq_exp_v}"
            # PAQ_EARLY_AGG BCDP gate — data: wins 4.83/5 clean, losses 2.75/5
            # BCDP_CLEAN required: no opposing sign in 5-poll window
            # Raw BCDP >= 3 still required (minimum persistence)
            # v158: floor raised 3→4 (all 13 historical wins already at >=4)
            _paq_bcdp_pass = bcdp_clean and bcdp >= 4

            # v226: Weekend BCDP reset override
            # After a violent dominant-side collapse, residue in the BCDP window
            # from the dead NO streak blocks the first valid YES continuation.
            # Proof case: 3/28 14:45 — YES@0.77, PAQ5/CTX2/STATE2, BLOCKED by 3D.
            # Old NO peaked 0.942, already at 0.24 when YES shows full quality.
            # The BCDP dirt is residue from a move that already died — override it.
            # NOTE: prev_paq_score/ctx/state are globals updated every poll —
            # they reflect the CURRENT poll's PAQ values at decision time,
            # not a prior-poll memory despite the "prev_" naming convention.
            _bcdp_reset_override = False
            if (not _paq_bcdp_pass
                    and is_weekend_window()
                    and prev_paq_score is not None and prev_paq_score >= 5
                    and prev_paq_ctx == 2 and prev_paq_state == 2):
                _h_no = list(price_history[ticker]["no"]) if ticker in price_history else []
                if _h_no:
                    _peak_no = max(_h_no)
                    _curr_no = float(no_price)
                    if _peak_no >= 0.90 and (_peak_no - _curr_no) >= 0.12:
                        _bps_list = list(_bps_history)
                        if len(_bps_list) >= 2:
                            _bps_worst = min(_bps_list[-4:]) if len(_bps_list) >= 4 else min(_bps_list)
                            _bps_improvement = _bps_list[-1] - _bps_worst
                            if _bps_improvement >= 4:
                                _bcdp_reset_override = True
                                print(f"          → BCDP_RESET_OVERRIDE | YES | "
                                      f"peak_NO {_peak_no:.2f}→{_curr_no:.2f} | "
                                      f"BPS swing {_bps_worst:+.1f}→{_bps_list[-1]:+.1f} | "
                                      f"PAQ {prev_paq_score} CTX {prev_paq_ctx} STATE {prev_paq_state}")

            _paq_bcdp_pass = _paq_bcdp_pass or _bcdp_reset_override
            _bcdp_label = f"BCDP {bcdp}{'C' if bcdp_clean else 'D'}"
            if not _paq_bcdp_pass:
                _last_entry_block = f"→ PAQ_AGG_BCDP | YES | {_bcdp_label} | BLOCK"
                return None, None
            _last_entry_block = f"→ PAQ_AGG_BCDP | YES | {_bcdp_label} | PASS"
            return "yes", "PAQ_EARLY_AGG"
        elif _agg_ctx_gate and signed_pct is not None and signed_pct > 0:
            # Structure passed but economics failed — log which gate killed it
            _block_reason = (
                "PRICE_ABOVE_CEIL" if yes_price > _agg_price_ceil else
                "PRICE_BELOW_MIN"  if yes_price < Decimal("0.40") else
                "ABS_TOO_LOW"      if current_abs < _prem_abs else
                f"BPS_TOO_LOW_{_live_bps:+.1f}_need_{_yes_bps_floor}" if _live_bps < _yes_bps_floor else
                "WRONG_DIRECTION"
            )
            _last_entry_block = f"→ {_block_reason}"
        _no_bps_floor = 2
        if _paq_exp_v == 2 and seconds_left > 500:
            _no_bps_floor = 4
        elif get_session_label() == "NY_OPEN":
            _no_bps_floor = 3

        if (_agg_ctx_gate
                and signed_pct is not None and signed_pct < 0
                and no_price > yes_price
                and Decimal("0.40") <= no_price <= _agg_price_ceil
                and current_abs >= _prem_abs
                and _live_bps <= -_no_bps_floor):
            _last_entry_class = f"{_entry_tier} | CTX {_paq_ctx_v} STATE {_paq_state_v} EXP {_paq_exp_v}"
            # PAQ_EARLY_AGG BCDP gate — data: wins 4.83/5 clean, losses 2.75/5
            _paq_bcdp_pass = bcdp_clean and bcdp >= 4

            # v226: Weekend BCDP reset override (NO side mirror of YES branch)
            # NOTE: prev_paq_score/ctx/state are globals updated every poll —
            # they reflect the CURRENT poll's PAQ values at decision time,
            # not a prior-poll memory despite the "prev_" naming convention.
            _bcdp_reset_override = False
            if (not _paq_bcdp_pass
                    and is_weekend_window()
                    and prev_paq_score is not None and prev_paq_score >= 5
                    and prev_paq_ctx == 2 and prev_paq_state == 2):
                _h_yes = list(price_history[ticker]["yes"]) if ticker in price_history else []
                if _h_yes:
                    _peak_yes = max(_h_yes)
                    _curr_yes = float(yes_price)
                    if _peak_yes >= 0.90 and (_peak_yes - _curr_yes) >= 0.12:
                        _bps_list = list(_bps_history)
                        if len(_bps_list) >= 2:
                            _bps_worst = max(_bps_list[-4:]) if len(_bps_list) >= 4 else max(_bps_list)
                            _bps_improvement = _bps_worst - _bps_list[-1]
                            if _bps_improvement >= 4:
                                _bcdp_reset_override = True
                                print(f"          → BCDP_RESET_OVERRIDE | NO | "
                                      f"peak_YES {_peak_yes:.2f}→{_curr_yes:.2f} | "
                                      f"BPS swing {_bps_worst:+.1f}→{_bps_list[-1]:+.1f} | "
                                      f"PAQ {prev_paq_score} CTX {prev_paq_ctx} STATE {prev_paq_state}")

            _paq_bcdp_pass = _paq_bcdp_pass or _bcdp_reset_override
            _bcdp_label = f"BCDP {bcdp}{'C' if bcdp_clean else 'D'}"
            if not _paq_bcdp_pass:
                _last_entry_block = f"→ PAQ_AGG_BCDP | NO | {_bcdp_label} | BLOCK"
                return None, None
            _last_entry_block = f"→ PAQ_AGG_BCDP | NO | {_bcdp_label} | PASS"
            return "no", "PAQ_EARLY_AGG"
        elif _agg_ctx_gate and signed_pct is not None and signed_pct < 0:
            _block_reason = (
                "PRICE_ABOVE_CEIL" if no_price > _agg_price_ceil else
                "PRICE_BELOW_MIN"  if no_price < Decimal("0.40") else
                "ABS_TOO_LOW"      if current_abs < _prem_abs else
                f"BPS_TOO_LOW_{_live_bps:+.1f}_need_{_no_bps_floor}" if _live_bps > -_no_bps_floor else
                "WRONG_DIRECTION"
            )
            _last_entry_block = f"→ {_block_reason}"

    # ── BCDP_FAST_COMMIT — captures the fast-commit coverage gap ───────
    # Problem: PAQ peaks at poll N, BCDP=5C, BTC commits, price jumps to
    # 0.80-0.88 before abs clears 0.08. PAQ_EARLY_AGG requires abs>=0.08
    # which arrives 2-3 polls later when price is already expensive or
    # the move is done. This family fires at the transition moment.
    #
    # Signal: BCDP has reached 5C (maximum clean persistence) AND abs is
    # crossing above a lower floor (0.040) — BTC has started committing
    # but has not yet moved the full distance. Price is still in the value
    # band. Single-read entry — the commitment signal is already confirmed
    # by BCDP=5C, waiting for a second read loses the entry price.
    #
    # Gates (all required):
    #   BCDP = 5C (full clean persistence — strongest possible signal)
    #   PAQ >= 4  (structure confirmed)
    #   CTX = 2   (full candle context — required, not optional)
    #   abs 0.040–0.079% (above noise floor, below PAQ_EARLY_AGG floor)
    #   price in 0.72–0.88 (value band — enough upside, not already priced)
    #   secs >= 300 (exit window exists)
    #   half-size ($7.50 risk) — new family, controlled probe
    #
    # Evidence: 211915-15 — NO=0.82, BCDP=5C, PAQ=4, abs=0.047, secs=481
    #   Every existing family blocked. BTC fell, settled 1.00. +$1.44 missed.
    #
    # Monitor: entry prices vs PAQ_EARLY_AGG, stop behavior, win rate.
    # Graduate to full size after 10+ clean captures with acceptable stop rate.
    global _fc_yes_cnt, _fc_no_cnt
    FC_ABS_MIN   = 0.040   # above noise, below PAQ_EARLY_AGG floor
    FC_ABS_MAX   = 0.079   # hand off to PAQ_EARLY_AGG above this
    FC_PRICE_LO  = Decimal("0.72")
    FC_PRICE_HI  = Decimal("0.88")
    FC_SECS_MIN  = 300
    FC_PAQ_MIN   = 4
    FC_CTX_REQ   = 2        # full context required — no partial structures

    if (bcdp == 5 and bcdp_clean
            and prev_paq_score is not None and prev_paq_score >= FC_PAQ_MIN
            and prev_paq_ctx == FC_CTX_REQ
            and FC_ABS_MIN <= current_abs < FC_ABS_MAX
            and seconds_left >= FC_SECS_MIN):
        if (signed_pct is not None and signed_pct > 0
                and FC_PRICE_LO <= yes_price <= FC_PRICE_HI):
            _fc_yes_cnt += 1
            _fc_no_cnt   = 0
            if _fc_yes_cnt >= 1:   # single-read — BCDP=5C is sufficient confirmation
                _fc_yes_cnt = 0
                print(f"          → BCDP_FAST_COMMIT | YES | PAQ {prev_paq_score} | abs {current_abs:.3f}% | px {float(yes_price):.2f} | {int(seconds_left)}s")
                return "yes", "BCDP_FAST_COMMIT"
        else:
            _fc_yes_cnt = 0
        if (signed_pct is not None and signed_pct < 0
                and FC_PRICE_LO <= no_price <= FC_PRICE_HI):
            _fc_no_cnt  += 1
            _fc_yes_cnt  = 0
            if _fc_no_cnt >= 1:
                _fc_no_cnt = 0
                print(f"          → BCDP_FAST_COMMIT | NO | PAQ {prev_paq_score} | abs {current_abs:.3f}% | px {float(no_price):.2f} | {int(seconds_left)}s")
                return "no", "BCDP_FAST_COMMIT"
        else:
            _fc_no_cnt = 0
    else:
        _fc_yes_cnt = 0
        _fc_no_cnt  = 0

    # ── PAQ_STRUCT_GATE — low-abs, near-fair-value, maximum upside ──────
    # Targets the highest-upside entry zone: price 0.38-0.65 when abs is low
    # but PAQ shows strong structure building.
    #
    # Data finding: BPS is only 40% accurate in low-abs (worse than coin flip).
    # PAQ is the reliable signal — 2/2 cases with PAQ>=4 + abs>=0.015% resolved
    # correctly with gains of +0.24 to +0.31.
    #
    # Requires 2 consecutive reads to filter single-poll PAQ spikes.
    # BPS used as weak directional confirmation only (>=1, not primary gate).
    # abs >= 0.015% ensures market is alive; abs < 0.08% keeps it low-abs only.
    #
    # Upside: entry at 0.45 YES → $0.55/contract × 22c = $12.10 max on $10 risk
    # vs PAQ_EARLY_AGG at 0.80 → $0.20/contract × 12c = $2.40 max on $10 risk
    global _paq_struct_yes_cnt, _paq_struct_no_cnt, _paq_struct_loss_ticker
    PAQ_STRUCT_ABS_MAX  = 0.08    # low-abs environment only
    PAQ_STRUCT_ABS_MIN  = 0.015   # market must be alive
    PAQ_STRUCT_PAQ_MIN  = 4       # strong structure required
    PAQ_STRUCT_CONSEC   = 2       # consecutive reads needed
    PAQ_STRUCT_SECS_MIN = 360     # enough time for thesis to resolve
    PAQ_STRUCT_PRICE_LO = Decimal("0.38")
    PAQ_STRUCT_PRICE_HI = Decimal("0.65")

    # v161: Session-adaptive BCDP gate — persistence floor varies by session quality.
    #
    # Evidence basis (2025-03-21 full session, 8 PAQ_STRUCT trades):
    #   Weak-session losses: all had BCDP <= 2 or dirty (2D, 2C) — no sustained flow.
    #   Active-session losses: both had BCDP=2D — dirty is the failure signal.
    #   Active-session winner: BCDP=4C, PAQ=4 — clean persistence, same PAQ floor.
    #   Conclusion: BCDP_CLEAN is the discriminator. PAQ floor does not need to rise.
    #
    # WEAK sessions (BTC_DEEP_NIGHT, ASIA_OPEN, LOW_VOLUME book):
    #   Require BCDP_CLEAN + BCDP >= 3
    #   Flat/ranging BTC produces fake structure. Must see 3 consecutive clean reads.
    #
    # ACTIVE sessions (EU_MORNING through NY_CLOSE):
    #   Require BCDP_CLEAN + BCDP >= 2 + abs >= ACTIVE_SESSION_MIN_ABS
    #   In active sessions BTC commits faster — 2C clean is a meaningful threshold.
    #   ACTIVE_SESSION_MIN_ABS = 0.020: a static floor confirming the market is
    #   genuinely moving, not micro-tick noise. This is NOT trend confirmation.
    #   PAQ floor stays at 4 (same as weak) — raising to 5 blocks real winners
    #   that had BCDP=4C, PAQ=4 with no quality failure. Data does not support it.
    #
    # What to monitor next week (M-F active sessions):
    #   - PAQ_STRUCT entries with PAQ=4, BCDP=2C in active sessions
    #   - whether those cluster as losers → tighten PAQ to 5 if pattern emerges
    #   - whether abs=0.020 floor is too loose → raise if entries fire on dead books
    ACTIVE_SESSION_MIN_ABS = 0.020
    _sess = get_session_label()
    _struct_weak_session = _sess in ("BTC_DEEP_NIGHT", "ASIA_OPEN")
    # LOW_VOLUME book env treated as weak regardless of session time
    _struct_book_weak = _book_env in ("LOW_VOLUME",)
    # v188: suppress PAQ_STRUCT_GATE in EU_MORNING entirely.
    # Data: 0W/2L, -$9.13 across 3_21 and 3_22 combined.
    # EU_MORNING has fast directional commits — price escapes the 0.38-0.65
    # fair-value window before the coiling thesis resolves. The pattern that
    # PAQ_STRUCT targets (low-abs coiling) is structurally weak here.
    if _sess == "EU_MORNING":
        _paq_struct_yes_cnt = 0
        _paq_struct_no_cnt  = 0
        return None, None
    # v219: suppress PAQ_STRUCT_GATE in ASIA_OPEN.
    # Data: 3-day audit (3/23–3/25), ASIA_OPEN 2W/3L -$9.93, EV -$1.99/trade.
    # All 3 losses were replaceable — AGG and bps_premium won those same tickers.
    # ASIA_OPEN thin liquidity means the fair-value coil rarely resolves cleanly:
    # book depth insufficient for clean exits when the thesis fails.
    # NY_PRIME (6W/0L +$29.31 EV +$4.89) and BTC_DEEP_NIGHT (3W/1L +$6.08)
    # are unaffected. This is a surgical session gate, not a family kill.
    if _sess == "ASIA_OPEN":
        _paq_struct_yes_cnt = 0
        _paq_struct_no_cnt  = 0
        return None, None
    # v244: suppress PAQ_STRUCT_GATE after 19:00 MTN within BTC_DEEP_NIGHT.
    # Data: 9-session audit (3/25–4/2), BTC_DEEP_NIGHT split by hour:
    #   17-18:xx: 4W/0L, 100% WR, +$14.98 — coil resolves cleanly, books adequate
    #   19-20:xx: 2W/2L,  50% WR,  +$1.99 — both losses from thin-book exit failures
    # The -$9.69 on 4/2 (YES@0.51, 19c, STOP UNFILLED at 20:xx) and the -$2.06
    # on 3/26 (19:xx) both show the same pattern: structure is correct but the
    # book cannot absorb the exit when the thesis fails. 17-18:xx is the clean window.
    if _sess == "BTC_DEEP_NIGHT" and get_mtn_hour() >= 19:
        _paq_struct_yes_cnt = 0
        _paq_struct_no_cnt  = 0
        return None, None
    if _struct_weak_session or _struct_book_weak:
        _struct_bcdp_ok  = _bcdp_clean and _bcdp >= 3
        _struct_paq_min  = PAQ_STRUCT_PAQ_MIN   # 4
        _struct_gate_tag = f"WEAK({_sess})"
    else:
        # Active session: BCDP floor relaxed to 2C, PAQ baseline 4.
        # BCDP_CLEAN is the discriminator — dirty BCDP (D) is the failure signal.
        # v181: lowered PAQ_MIN to 3 when BCDP>=4C in active sessions.
        # v189: REVERTED — live data shows PAQ=3 entries losing 0W/2L:
        #   March 22: PAQ_STRUCT NO@0.45 PAQ=3 EU_ACTIVE → -$4.95
        #   March 23: PAQ_STRUCT NO@0.50 PAQ=3 EU_ACTIVE → -$8.00
        #   The March 21 historical bucket was 7W/3L but included PAQ=4 entries.
        #   Live isolation of PAQ=3 specifically is 0W/2L. Revert to PAQ_MIN=4.
        _active_abs_ok   = current_abs >= ACTIVE_SESSION_MIN_ABS
        _struct_bcdp_ok  = _bcdp_clean and _bcdp >= 2 and _active_abs_ok
        _struct_paq_min  = PAQ_STRUCT_PAQ_MIN   # 4 — PAQ=3 exception removed
        _struct_gate_tag = f"ACTIVE({_sess})|PAQ_MIN={_struct_paq_min}"

    # v159: cooldown — suppress if PAQ_STRUCT lost on this ticker
    # v180: dynamic consecutive requirement — BCDP>=4C already embeds persistence
    #       confirmation that CONSEC=2 was designed to provide. Requiring both
    #       double-counts. At BCDP=2C-3C keep CONSEC=2; at BCDP>=4C reduce to 1.
    #       Evidence: 02:45 ticker had valid poll at 427s (NO=0.59, BCDP=5C, PAQ=4)
    #       blocked solely because prior poll had NO outside window, resetting counter.
    _required_consec = 1 if _bcdp >= 4 else PAQ_STRUCT_CONSEC
    # v213: WEAK sessions require higher ABS floor — 0.025 vs 0.015.
    # Data: both WEAK ASIA_OPEN losses had ABS 0.029% and 0.019% at entry.
    # The 0.015 floor allowed entries where BTC movement was near-zero.
    # Raising to 0.025 in WEAK sessions keeps fair-value coil entries while
    # blocking the near-dead-book entries that produce fragile coils.
    # ACTIVE sessions unchanged at 0.015 — NY_PRIME 7W/0L, no intervention needed.
    _psg_abs_min = 0.025 if _struct_weak_session else PAQ_STRUCT_ABS_MIN
    if (seconds_left >= PAQ_STRUCT_SECS_MIN
            and prev_paq_score is not None and prev_paq_score >= _struct_paq_min
            and _psg_abs_min <= current_abs < PAQ_STRUCT_ABS_MAX
            and _struct_bcdp_ok
            and _paq_struct_loss_ticker != ticker):
        # YES: signed_pct > 0 and BPS >= 1
        if (signed_pct is not None and signed_pct > 0
                and _live_bps > -2   # veto only on strong opposite push
                and PAQ_STRUCT_PRICE_LO <= yes_price <= PAQ_STRUCT_PRICE_HI):
            _paq_struct_yes_cnt += 1
            _paq_struct_no_cnt   = 0
            if _paq_struct_yes_cnt >= _required_consec:
                _paq_struct_yes_cnt = 0
                print(f"          → PAQ_STRUCT_GATE | YES | PAQ {prev_paq_score} | BPS {_live_bps:+.1f} | abs {current_abs:.3f}% | px {float(yes_price):.2f} | {int(seconds_left)}s | BCDP {_bcdp}C | {_struct_gate_tag}")
                return "yes", "PAQ_STRUCT_GATE"
        else:
            _paq_struct_yes_cnt = 0
        # NO: signed_pct < 0 and BPS <= -1
        if (signed_pct is not None and signed_pct < 0
                and _live_bps < 2    # veto only on strong opposite push
                and PAQ_STRUCT_PRICE_LO <= no_price <= PAQ_STRUCT_PRICE_HI):
            _paq_struct_no_cnt  += 1
            _paq_struct_yes_cnt  = 0
            if _paq_struct_no_cnt >= _required_consec:
                _paq_struct_no_cnt = 0
                print(f"          → PAQ_STRUCT_GATE | NO | PAQ {prev_paq_score} | BPS {_live_bps:+.1f} | abs {current_abs:.3f}% | px {float(no_price):.2f} | {int(seconds_left)}s | BCDP {_bcdp}C | {_struct_gate_tag}")
                return "no", "PAQ_STRUCT_GATE"
        else:
            _paq_struct_no_cnt = 0
    else:
        _paq_struct_yes_cnt = 0
        _paq_struct_no_cnt  = 0

    # ── v234: WES — Weekday Early Scout ───────────────────────────────────
    # Entry conditions (all must pass simultaneously):
    #   Session: BTC_DEEP_NIGHT 17-19:00 MTN, EU_MORNING 04:00-05:00 MTN
    #            Only windows with ≥73% S1 hit rate in 7-day 249-signal simulation.
    #   Price:   0.40–0.60 — v244: tightened from 0.65. 0.59-0.65 ran 29% stop rate.
    #   PAQ:     >= 4, ABS >= 0.035%, BPS >= 2 (abs) — direction confirmed
    #   Secs:    >= 350 — enough time for 128s avg time-to-S1 plus buffer
    #   BDI:     >= 25 — S1 exit and stop-loss must be physically executable
    #   No main position: last_entry_contracts == 0 (additive lane only)
    #   No weekends: overnight weekend book too thin for symmetric ±0.15 execution
    # Exit: mandatory 100% exit at entry+0.15 (S1) or entry-0.15 (stop). No harvest.
    # Math: symmetric ±0.15 → break-even at 50% WR. Actual: 73%. Margin: +23pp.
    _wes_sess_label = get_session_label()
    _wes_hour       = get_mtn_hour()   # v236: was dt.datetime.now().hour (system clock — wrong timezone)
    # Using system clock caused WES gate to fail silently whenever machine is not MTN.
    # get_session_label() uses get_mtn_hour() → session said BTC_DEEP_NIGHT (correct)
    # but dt.datetime.now().hour returned UTC/system hour → 17<=hour<19 always failed.
    _wes_session_ok = (
        not is_weekend_window()
        and (
            (_wes_sess_label == "BTC_DEEP_NIGHT" and 17 <= _wes_hour < 19)
            or (_wes_sess_label == "EU_MORNING"   and _wes_hour == 4)
        )
    )
    if (_wes_session_ok
            and not _wes_active
            and last_entry_contracts == 0
            and seconds_left is not None and float(seconds_left) >= 350
            and prev_paq_score is not None and prev_paq_score >= 4
            and current_abs is not None and float(current_abs) >= 0.035
            and live_bps is not None and abs(float(live_bps)) >= 2):
        # v237: added `live_bps is not None` guard.
        # live_bps is a module-level var set in run_bot(). On polls where BPS fetch
        # fails or candle data is unavailable, it can be None or undefined, causing
        # NameError / TypeError inside check_confirmation_entry → WES never signals.
        # All 7 live_bps errors on 4/1 were in the BTC_DEEP_NIGHT WES window.
        # EU_MORNING was hitting silent TypeError (abs(float(None))). Both blocked WES.
        if (float(live_bps) > 0
                and Decimal("0.40") <= yes_price <= Decimal("0.60")):
            _wes_entry_bdi = get_bdi(ticker, "yes", float(yes_price))
            if _wes_entry_bdi >= 25:
                print(f"          → WES_SIGNAL | YES@{float(yes_price):.3f} | "
                      f"PAQ:{prev_paq_score} ABS:{float(current_abs):.3f}% "
                      f"BPS:{float(live_bps):+.1f} BDI:{_wes_entry_bdi} {int(seconds_left)}s")
                return "yes", "WES_EARLY"
        elif (float(live_bps) < 0
                and Decimal("0.40") <= no_price <= Decimal("0.60")):
            _wes_entry_bdi = get_bdi(ticker, "no", float(no_price))
            if _wes_entry_bdi >= 25:
                print(f"          → WES_SIGNAL | NO@{float(no_price):.3f} | "
                      f"PAQ:{prev_paq_score} ABS:{float(current_abs):.3f}% "
                      f"BPS:{float(live_bps):+.1f} BDI:{_wes_entry_bdi} {int(seconds_left)}s")
                return "no", "WES_EARLY"

    # PAQ_EARLY_CONS DISABLED (v218)
    # Killed after full 3-day analysis (28 trades, 16W/12L):
    # - Net negative: −$5.96 despite 71% win rate
    # - EV per trade: −$0.351 (every trade costs money in expectation)
    # - Structural problem: enters AFTER BPS≥3 confirmation — price already committed,
    #   less upside remaining, same downside risk as AGG
    # - 10 of 12 losses occurred on tickers where AGG or bps_premium WON — pure damage
    # - Only 1 genuinely unique trade in 3 days (3/23 18:10, +$4.82)
    # - 13 redundant wins — those tickers were already captured by AGG/bps_premium
    # - True unique cost of killing: −$4.82 (one missed win)
    # - True benefit of killing: +$32.05 (replaceable losses eliminated)
    # - Net honest improvement: +$27.23
    # AGG fires earlier on the same signal with better timing. CONS is structurally
    # redundant. Killing it simplifies the system and removes a negative-EV lane.
    # --- PAQ_EARLY_CONS entry block removed ---

    # ── Standard Confirmation (120–360s) ──────────────────────────────
    # Tightened in v91: abs raised 0.04→0.08% (confirms genuine two-sided depth).
    # confirm_standard was net -$9.68 across sessions. The catastrophic -$9.96 loss
    # happened in a low-abs environment where CONF stop couldn't fill the exit.
    # abs >= 0.08% ensures book has real depth for both entry and emergency exit.
    # Added BPS gate: confirm-style entries need on-side BPS pressure too.
    # confirm_standard BCDP gate: requires clean persistent BPS before entering
    # Simulation: BCDP_CLEAN blocks dirty confirm entries with 0 wins blocked
    if 120 <= seconds_left <= 360 and current_abs >= 0.08 and bcdp_clean:
        if not abs_drop_too_large(0.095, 3):
            # YES — require BPS on-side
            if (yes_price > no_price
                    and (signed_pct is None or signed_pct >= 0)
                    and Decimal("0.78") <= yes_price <= Decimal("0.85")
                    and _live_bps >= 1
                    ):
                # v225: price ceiling gate — block high-price late entries
                # Both confirm_standard losses (3/23, 3/27) were px≈0.83 with 330-345s left.
                # Simulation: blocks 2L saves $9.96, blocks 1W misses $0.37 → net +$9.59.
                # Applied globally (not weekend-only): same failure mechanism on weekdays.
                if float(yes_price) > 0.80:
                    print(f"          → BLOCK | YES | CONF_STD_HIGH_PRICE_LATE | px {float(yes_price):.2f} | {int(seconds_left)}s")
                elif (strong_momentum(hist_yes)
                        or is_consistent_hold(hist_yes, 3)
                        or abs_consistent(0.08, 4)
                        or abs_hhhl_early()
                        or abs_staircase()):
                    return "yes", "confirm_standard"
            # NO — require BPS on-side
            if (no_price > yes_price
                    and (signed_pct is None or signed_pct <= 0)
                    and Decimal("0.78") <= no_price <= Decimal("0.92")
                    and _live_bps <= -1
                    ):
                # v225: price ceiling gate (same logic as YES branch above)
                if float(no_price) > 0.80:
                    print(f"          → BLOCK | NO | CONF_STD_HIGH_PRICE_LATE | px {float(no_price):.2f} | {int(seconds_left)}s")
                elif (strong_momentum(hist_no)
                        or is_consistent_hold(hist_no, 3)
                        or abs_consistent(0.08, 4)
                        or abs_hhhl_early()
                        or abs_staircase()):
                    return "no", "confirm_standard"

    # ── Late Confirmation (10–120s) ─────────────────────────────────────
    # Block at >= 0.97: upside < $0.03, full downside if wrong. This is
    # settlement cleanup, not tradeable edge. confirm_late re-entries
    # at near-settlement prices consistently produce low or zero profit.
    # Ceiling lowered 0.97 → 0.94: above 0.94 the max gain is < $0.06/contract,
    # which doesn't justify execution risk in a thin late book.
    # Data: 3/18 confirm_late @ 0.918 netted +$0.082/contract — worst profile.
    # v208: hard ceiling lowered from 0.94 to 0.87.
    # Evidence: YES@0.92 115s left → -$5.52 (March 24). Pattern: high price +
    # compressed window + LOW conviction = full loss on one-poll flip. Two
    # confirmed instances. Entries at 0.88-0.94 have worst risk/reward —
    # limited upside (already near 1.00), full downside on any reversal.
    # confirm_late DISABLED (v212)
    # Family killed after 3 large losses vs 4 small wins — net -$13.66 across all sessions.
    # Structural failure: small wins (~$0.59 avg), large losses (~$5.34 avg).
    # Ceiling fix (0.94→0.87) in v208 didn't fix it — YES@0.83 ABS=0.037% still lost $4.98.
    # Weakness is architectural: late entry + compressed time + no recovery window.
    # Burden of proof has flipped. Kill now, pilot later only with:
    #   ABS>=0.06, 0.87 ceiling, strict time window, LOW size, explicit tracking label.
    # --- confirm_late entry block removed ---

    return None, None


def decide_trade(seconds_left: float, yes_price: Decimal, no_price: Decimal, hist_yes, hist_no, strike, btc_prices, metrics, ticker: str = ""):
    global trail_harvested_ticker, trail_harvested_side, trail_harvested_time, trail_harvested_exit_px
    global _pending_regime_display, _last_entry_class, _last_entry_block
    global _bot_paused, _bot_stop_flag
    global _book_env, _book_total_depth, _book_spread, _book_asymmetry
    global _bps_history, _bcdp, _bcdp_clean, _bcdp_pending_display
    current_abs = RECENT_ABS_PCTS[-1] if RECENT_ABS_PCTS else 0.0
    signed_pct  = metrics["signed_pct"] if metrics else None

    # ── STAGE 3 HARVEST BLOCK ─────────────────────────────────────────────
    # After a TRAIL_EXIT_STAGE3, block same-ticker same-direction re-entry
    # until:  (a) price has reset meaningfully below the harvest exit price, AND
    #         (b) at least 120s have elapsed since the harvest exit.
    # Covers all entry families — prevents re-entering at terrible economics
    # after a quality harvest (same flaw observed in confirm_late re-entries).
    if (trail_harvested_ticker == ticker
            and trail_harvested_side is not None
            and trail_harvested_exit_px is not None
            and trail_harvested_time is not None):
        _secs_since_harvest = (dt.datetime.now(dt.timezone.utc) - trail_harvested_time).total_seconds()
        _harvest_side_price = yes_price if trail_harvested_side == "yes" else no_price
        _price_reset = _harvest_side_price <= (trail_harvested_exit_px - Decimal("0.10"))
        if _secs_since_harvest < 120 or not _price_reset:
            # Block same-direction only — opposite direction is fine
            if trail_harvested_side == "yes":
                yes_price = None   # temporarily null out to block YES entries
            else:
                no_price = None    # temporarily null out to block NO entries
        else:
            # Conditions met — release the harvest block
            trail_harvested_ticker  = None
            trail_harvested_side    = None
            trail_harvested_time    = None
            trail_harvested_exit_px = None

    # Fetch PAQ candles once per cycle — passed into directional for quality gate
    current_btc = metrics["btc_price"] if metrics else None
    try:
        paq_candles = get_btc_candles("3m", 3)
    except Exception:
        paq_candles = []

    # ── v251: Full entry halt during weekend window ───────────────────────
    # Friday 23:00 MTN through Monday 09:59 MTN — no new entries from any family.
    # is_weekend_window() is the single authoritative gate. All families blocked here
    # rather than individually, so no family can leak through a missing per-family guard.
    # Position management (stops, harvests, trail exits, CHOP watch) is not affected —
    # those paths run in run_bot() before decide_trade() is called.
    if is_weekend_window():
        return None, None

    # ── Kill zones — no new entries ───────────────────────────────────────
    # NY_OPEN  05:00-09:00 MTN: 4W/6L 40% WR -$18.75 (March 23). Institutional
    #          ETF sell pressure whipsaws momentum signals at 8am MTN.
    # NY_CLOSE 14:00-17:00 MTN: 0W/3L -$10.77 (March 23). Low edge environment.
    # Position management (stops, harvests, trail) continues during kill zones.
    # v227: Weekend exempt — kill zone data is weekday-only (March 23).
    #       Weekend 05:00-09:00 MTN has no ETF open, no institutional flow.
    #       Weekend 14:00-17:00 MTN has no NY close dynamics.
    #       Blocking these windows on Sat/Sun costs real trades with no data basis.
    # Note: weekend exempt clause below is now unreachable during weekend window
    # (the gate above returns first), retained for documentation clarity.
    if get_session_label() in ("NY_OPEN", "NY_CLOSE") and not is_weekend_window():
        return None, None

    # v233 BUILD 4: same-ticker same-side block
    # Problem: bot was opening second same-side entries on tickers already held,
    # creating silent risk concentration. 3/31 log showed NO-on-NO layering in
    # the 00:00 and 04:30 blocks — even when both campaigns won, attribution was
    # muddied and combined exposure was undocumented.
    # Rule: if already holding a live position on this ticker with the same side,
    # block any new same-side entry from any family until position is fully closed.
    # Opposite-side reversal entries are not blocked — this is a same-side fix only.
    if last_traded_ticker == ticker and last_entry_contracts > 0 and last_side is not None:
        _proposed_yes = yes_price is not None
        _proposed_no  = no_price is not None
        _held_yes = last_side == "yes"
        _held_no  = last_side == "no"
        if (_held_yes and _proposed_yes) or (_held_no and _proposed_no):
            print(f"          → SAME_TICKER_SAME_SIDE_BLOCK | {last_side.upper()} already held "
                  f"{last_entry_contracts}c @ {float(last_entry_price):.2f} | blocking new {last_side.upper()} entry")
            return None, None

    # ── Portfolio-level directional exposure gate (v198) ──────────────────
    # Problem: three same-direction positions open concurrently → one BTC
    # reversal wipes all three simultaneously. This is correlated risk, not
    # diversification. March 23: bps_premium + PAQ_EARLY_AGG + PAQ_EARLY_CONS
    # all long simultaneously → -$18.99 in one settlement cycle.
    #
    # Policy:
    #   0 same-side open positions → normal rules
    #   1 same-side open position  → elevated bar (PAQ_MIN+1, ABS×1.5)
    #   2+ same-side open positions → block entirely
    #
    # Uses pending_trades (keyed by ticker) to count live same-side exposure.
    # Excludes the current ticker (not yet entered). Skips settled tickers.
    _open_yes = sum(1 for tk, pt in pending_trades.items()
                    if tk != ticker and tk not in settled_tickers
                    and pt.get("side","") == "yes")
    _open_no  = sum(1 for tk, pt in pending_trades.items()
                    if tk != ticker and tk not in settled_tickers
                    and pt.get("side","") == "no")

    def _exposure_level(proposed_side):
        return _open_yes if proposed_side == "yes" else _open_no

    def _apply_exposure_elevation(side, reason, abs_val, paq, bps):
        """Returns (allow, log_reason) after applying elevation rules."""
        lvl = _exposure_level(side)
        if lvl == 0:
            return True, None
        if lvl >= 2:
            return False, f"EXPOSURE_BLOCK | {lvl} same-side open"
        # lvl == 1: one same-side position already open.
        # Previous approach raised PAQ/ABS bar — too easy to clear for strong
        # setups, which are exactly the ones carrying the most size and correlated risk.
        # Fix (v202): allow entry but force LOW conviction sizing (0.70×) regardless
        # of setup quality. Correlated risk is already open — don't pile on at full size.
        return True, f"EXPOSURE_CAPPED | 1 same-side open | forced LOW sizing"

    # Pass current PAQ score and ABS into elevation check — sourced from metrics
    _gate_paq = None
    _gate_abs = current_abs
    try:
        _gate_paq = prev_paq_score
    except Exception:
        pass

    # ── FAMILY 1: DIRECTIONAL — always checked first ─────────────────────
    dir_side, dir_reason = check_directional_entry(
        seconds_left, yes_price, no_price, strike, btc_prices, metrics, current_abs, signed_pct,
        paq_candles, current_btc, bcdp=_bcdp, bcdp_clean=_bcdp_clean, ticker=ticker
    )
    if dir_side:
        _allow, _gate_msg = _apply_exposure_elevation(dir_side, dir_reason, _gate_abs, _gate_paq, None)
        if not _allow:
            print(f"          → {_gate_msg} | blocked {dir_reason}")
            dir_side, dir_reason = None, None
        elif _gate_msg and _gate_msg.startswith("EXPOSURE_CAPPED"):
            print(f"          → {_gate_msg} | {dir_reason} allowed at reduced size")
            global _entry_exposure_capped
            _entry_exposure_capped = True  # signal to size at LOW regardless of score
    if dir_side:
        return dir_side, dir_reason

    # ── FAMILY 2: CONFIRMATION — only if Directional did not qualify ──────
    conf_side, conf_reason = check_confirmation_entry(
        seconds_left, yes_price, no_price, hist_yes, hist_no, metrics, current_abs, signed_pct,
        bcdp=_bcdp, bcdp_clean=_bcdp_clean, ticker=ticker
    )
    if conf_side:
        _allow, _gate_msg = _apply_exposure_elevation(conf_side, conf_reason, _gate_abs, _gate_paq, None)
        if not _allow:
            print(f"          → {_gate_msg} | blocked {conf_reason}")
            conf_side, conf_reason = None, None
        elif _gate_msg and _gate_msg.startswith("EXPOSURE_CAPPED"):
            print(f"          → {_gate_msg} | {conf_reason} allowed at reduced size")
            _entry_exposure_capped = True
    if conf_side:
        return conf_side, conf_reason

    return None, None


# ==================== UPDATED BPS STOP (with opposite count) ====================
def check_bps_stop_loss(ticker, strike, current_abs_pct=None):
    global last_entry_reason, last_traded_ticker, last_side, btc_prices, last_bps_opposite_count

    if last_entry_reason not in ("bps_premium", "bps_late"):
        last_bps_opposite_count = 0
        return False, None, last_bps_opposite_count

    if ticker != last_traded_ticker:
        last_bps_opposite_count = 0
        return False, None, last_bps_opposite_count

    if strike is None or len(btc_prices) < 6:
        return False, None, last_bps_opposite_count

    live_bps = break_pressure_score(strike, btc_prices)
    weak_abs = current_abs_pct is not None and current_abs_pct < 0.07

    if last_side == "yes":
        if live_bps <= -2:
            # bps_premium: require 2 consecutive reads before firing hard stop.
            # Strong lane deserves patience on a single adverse spike.
            # bps_late: fires immediately (compressed window, no time for 2 reads).
            if last_entry_reason == "bps_late":
                last_bps_opposite_count = 0
                return True, live_bps, last_bps_opposite_count
            else:
                last_bps_opposite_count += 1
                if last_bps_opposite_count < 2:
                    pass  # wait for confirmation
                else:
                    last_bps_opposite_count = 0
                    return True, live_bps, last_bps_opposite_count

        elif live_bps <= -1 and weak_abs:
            last_bps_opposite_count += 1
        else:
            last_bps_opposite_count = 0

        if last_bps_opposite_count >= 2:
            return True, live_bps, last_bps_opposite_count

    elif last_side == "no":
        if live_bps >= 2:
            # Same 2-read patience for bps_premium held NO.
            if last_entry_reason == "bps_late":
                last_bps_opposite_count = 0
                return True, live_bps, last_bps_opposite_count
            else:
                last_bps_opposite_count += 1
                if last_bps_opposite_count < 2:
                    pass  # wait for confirmation
                else:
                    last_bps_opposite_count = 0
                    return True, live_bps, last_bps_opposite_count

        elif live_bps >= 1 and weak_abs:
            last_bps_opposite_count += 1
        else:
            last_bps_opposite_count = 0

        if last_bps_opposite_count >= 2:
            return True, live_bps, last_bps_opposite_count

    return False, live_bps, last_bps_opposite_count

def update_conf_peak(yes_price, no_price):
    """Update the post-entry peak for the held Confirmation-family position."""
    global conf_entry_peak, last_side
    if last_side is None or conf_entry_peak is None:
        return
    held_px = yes_price if last_side == "yes" else no_price
    if held_px is not None and held_px > conf_entry_peak:
        conf_entry_peak = held_px


def check_non_bps_stop_loss(ticker, strike, yes_price, no_price, seconds_left, current_abs_pct=None):
    """
    Confirmation-family stop (confirm_standard / confirm_late only).

    Trigger A — CONF_REVERSAL_DAMAGE:
      BPS flips opposite by >= 1 AND at least one damage condition is true.

    Trigger B — CONF_FAST_BPS_FLIP:
      BPS flips opposite by >= 2. Immediate — no damage gate required.

    Protections (unchanged):
      Pinned: held >= 0.94 and opp <= 0.06 → block
      Late: seconds_left <= 45 and opp < 0.35 → block
    """
    global last_entry_reason, last_traded_ticker, last_side
    global last_entry_price, btc_prices, conf_entry_peak, conf_soft_reversal_count

    # Family gate — confirmation entries only
    if last_entry_reason not in ("confirm_standard", "confirm_late"):
        conf_soft_reversal_count = 0
        return False, None, None
    if ticker != last_traded_ticker:
        conf_soft_reversal_count = 0
        return False, None, None
    if last_entry_price is None or last_side is None:
        return False, None, None

    entry_px = Decimal(str(last_entry_price))
    held_px  = yes_price if last_side == "yes" else no_price
    opp_px   = no_price  if last_side == "yes" else yes_price
    if held_px is None or opp_px is None:
        return False, None, None

    update_conf_peak(yes_price, no_price)

    live_bps = 0
    if strike is not None and len(btc_prices) >= 6:
        live_bps = break_pressure_score(strike, btc_prices)

    yes_side    = (last_side == "yes")
    rev_1       = (yes_side and live_bps <= -CONF_REVERSAL_BPS)      or (not yes_side and live_bps >= CONF_REVERSAL_BPS)
    rev_fast    = (yes_side and live_bps <= -CONF_FAST_REVERSAL_BPS) or (not yes_side and live_bps >= CONF_FAST_REVERSAL_BPS)

    if not rev_1:
        conf_soft_reversal_count = 0
        return False, None, None

    # Pinned override (blocks both triggers)
    if held_px >= CONF_PINNED_HELD and opp_px <= CONF_PINNED_OPP:
        conf_soft_reversal_count = 0
        return False, None, None

    # Late-stop restriction (blocks both triggers)
    if seconds_left <= CONF_LATE_WINDOW and opp_px < CONF_LATE_OPP_MIN:
        return False, None, None

    # Trigger B: fast flip — immediate, no damage gate
    if rev_fast:
        conf_soft_reversal_count = 0
        return True, "CONF_FAST_BPS_FLIP", live_bps

    # Trigger A: reversal + damage gate
    drop_entry = entry_px - held_px
    drop_peak  = (conf_entry_peak - held_px) if conf_entry_peak is not None else Decimal("0")
    damage = (
        drop_entry >= CONF_ENTRY_DAMAGE
        or drop_peak  >= CONF_PEAK_GIVEBACK
        or held_px    <= CONF_LOSS_OF_DOM
        or opp_px     >= CONF_OPPOSITE_RISE
    )
    if not damage:
        return False, None, None

    conf_soft_reversal_count = 0
    return True, "CONF_REVERSAL_DAMAGE", live_bps


def clear_live_position_state():
    global last_side, last_entry_price, last_entry_time, last_traded_ticker
    global trail_harvested_ticker, trail_harvested_side, trail_harvested_time, trail_harvested_exit_px
    global flip_logged_ticker, last_entry_reason, last_entry_bps, last_entry_paq, last_entry_contracts
    global last_bps_opposite_count, conf_entry_peak, conf_soft_reversal_count
    global _paq_stop_fired, _paq_pending_yes_count, _paq_pending_no_count, _paq_zero_streak
    global _paq_bps_soft_yes_cnt, _paq_bps_soft_no_cnt
    global _paq_hard_flip_yes_cnt, _paq_hard_flip_no_cnt
    global _paq_agg_opp_yes_cnt, _paq_agg_opp_no_cnt
    global _paq_struct_yes_cnt, _paq_struct_no_cnt
    global _chop_watch_active, _chop_watch_polls, _chop_watch_paq_low
    global _chop_dip_price, _chop_watch_bps_start
    global _any_stop_fired
    global _bdi0_hold_count, _bdi0_hold_px  # v245: BDI=0 single-hold-max
    global _bdi0_exit_pending                # v247: forced next-poll exit flag
    global _tail_risk_mode, _tail_risk_entry_px
    global trail_high_water, trail_active, trail_reads_post_peak, trail_below_floor_cnt, last_entry_reads, trail_activation_reads
    global trail_mz_armed, trail_mz_armed_reads, trail_s3_zone_cnt
    global harvest_s1_done, harvest_s2_done, harvest_s3_done, harvest_s1_reads, harvest_s2_reads, harvest_s3_reads, harvest_total_sold
    global harvest_miss_streak, harvest_miss_anchor, harvest_miss_bdi_last
    global _weekend_struct_entry
    last_side = None
    last_entry_price = None
    last_entry_time = None
    last_traded_ticker = None
    flip_logged_ticker = None
    last_entry_reason = None
    last_entry_bps = None
    last_entry_paq = None
    last_entry_contracts = 0
    _weekend_struct_entry = False
    _wsl_entry_secs = 900
    _paq_stop_fired = False
    _any_stop_fired = False
    _bdi0_hold_count   = 0     # v245: reset hold counter on position clear
    _bdi0_hold_px      = None  # v245: reset hold price reference
    _bdi0_exit_pending = False  # v247: reset forced-exit flag on position clear
    _tail_risk_mode = False
    _tail_risk_entry_px = None
    _paq_zero_streak = 0
    _paq_bps_soft_yes_cnt = 0
    _paq_bps_soft_no_cnt  = 0
    _paq_agg_opp_yes_cnt  = 0
    _paq_agg_opp_no_cnt   = 0
    _fc_yes_cnt           = 0
    _fc_no_cnt            = 0
    _paq_struct_yes_cnt   = 0
    _paq_struct_no_cnt    = 0
    _chop_watch_active    = False
    _chop_watch_polls     = 0
    _chop_watch_paq_low   = 0
    _chop_dip_price       = None
    _chop_watch_bps_start = 0.0
    _paq_hard_flip_yes_cnt = 0
    _paq_hard_flip_no_cnt  = 0
    trail_high_water = None
    trail_active = False
    trail_reads_post_peak = 0
    trail_below_floor_cnt = 0
    trail_activation_reads = 0
    trail_mz_armed = False
    trail_mz_armed_reads = 0
    trail_s3_zone_cnt = 0
    last_entry_reads = 0
    last_entry_abs = 0.0
    last_bps_opposite_count = 0
    conf_entry_peak = None
    conf_soft_reversal_count = 0
    harvest_s1_done = False
    harvest_s1_count = 0       # v231: re-trigger counter reset on new position
    harvest_s1_fire_px = None  # v231: zone reference reset
    harvest_s1_zone_left = False  # v231: zone-exit flag reset
    # v234: WES state reset
    global _wes_active, _wes_entry_px, _wes_contracts, _wes_s1_target, _wes_stop_target, _wes_side
    global _wes_entry_secs, _wes_promoted, _wes_parent_family, _wes_parent_entry_px, _wes_parent_contracts, _wes_combined_avg_px
    _wes_active = False; _wes_entry_px = None; _wes_contracts = 0
    _wes_s1_target = None; _wes_stop_target = None; _wes_side = None; _wes_entry_secs = None
    _wes_promoted = False; _wes_parent_family = None; _wes_parent_entry_px = None
    _wes_parent_contracts = 0; _wes_combined_avg_px = None
    harvest_s2_done = False
    harvest_s3_done = False
    harvest_s1_reads = 0
    harvest_s2_reads = 0
    harvest_s3_reads = 0
    harvest_total_sold = 0
    harvest_miss_streak = 0
    harvest_miss_anchor = None
    harvest_miss_bdi_last = 0
    _harvest_diag_fired.clear()
    # Harvest-block state: cleared on position reset so stale Stage 3 locks
    # don't persist across unrelated future entries on the same ticker.
    trail_harvested_ticker  = None
    trail_harvested_side    = None
    trail_harvested_time    = None
    trail_harvested_exit_px = None

# NEW HELPER: side/strike compatibility gate
def side_matches_contract(side: str, btc_price: float | None, strike: float | None) -> bool:
    if btc_price is None or strike is None:
        return False
    if side == "yes":
        return btc_price >= strike
    if side == "no":
        return btc_price < strike
    return False

def run_bot():
    global _bcdp, _bcdp_clean, _bps_history  # must be declared so assignments update module-level globals
    global last_entry_abs, _paq_struct_derisked
    global last_traded_ticker, last_side, last_entry_price, last_entry_time, flip_logged_ticker, last_seen_ticker, last_logged_event_key
    global prev_paq_score, prev_paq_bucket, prev_paq_ctx, prev_paq_state, prev_paq_exp
    global last_entry_reason, last_entry_bps, last_entry_paq, last_entry_contracts, last_bps_opposite_count, conf_entry_peak, conf_soft_reversal_count
    global _paq_stop_fired, _paq_zero_streak, _paq_pending_yes_count, _paq_pending_no_count
    global _paq_bps_soft_yes_cnt, _paq_bps_soft_no_cnt
    global _paq_agg_opp_yes_cnt, _paq_agg_opp_no_cnt
    global _paq_hard_flip_yes_cnt, _paq_hard_flip_no_cnt
    global _any_stop_fired
    global _bdi0_hold_count, _bdi0_hold_px  # v245: BDI=0 single-hold-max
    global _bdi0_exit_pending                # v247: forced next-poll exit flag
    global _tail_risk_mode, _tail_risk_entry_px
    global trail_high_water, trail_active, trail_reads_post_peak, trail_below_floor_cnt, last_entry_reads, trail_activation_reads
    global trail_mz_armed, trail_mz_armed_reads, trail_s3_zone_cnt
    global harvest_s1_done, harvest_s2_done, harvest_s3_done, harvest_s1_reads, harvest_s2_reads, harvest_s3_reads, harvest_total_sold
    global last_exit_side, last_exit_time, last_exit_price
    global trail_harvested_ticker, trail_harvested_side, trail_harvested_time, trail_harvested_exit_px
    global _pending_regime_display, _last_entry_class, _last_entry_block
    # v234: WES globals — declared here so Python treats them as module-level throughout
    # run_bot(). Without this, _wes_active = True inside the WES flat-sizing path causes
    # Python to classify all _wes_* references as locals → UnboundLocalError every poll.
    global _wes_active, _wes_entry_px, _wes_contracts, _wes_s1_target, _wes_stop_target, _wes_side
    # v238: WES promotion globals — must also be in run_bot() global declaration
    global _wes_entry_secs, _wes_promoted, _wes_parent_family, _wes_parent_entry_px, _wes_parent_contracts, _wes_combined_avg_px
    # v252: live_bps declared global so all helper functions that reference it as a
    # module-level variable always find a valid value. Prior builds only assigned it
    # as a local at line ~5149, so any early-return or exception before that point
    # left helpers with a stale or missing module-level live_bps → NameError.
    global live_bps
    live_bps = 0.0  # safe default; overwritten at the BPS computation step each poll

    check_telegram_commands()
    if _bot_stop_flag:
        send_telegram_alert("AetherBot stopped cleanly")
        print("TELEGRAM CMD | clean stop")
        raise SystemExit(0)
    check_settlements()
    check_pending_settlements()
    market = get_open_kalshi_market()
    if not market:
        print("No open market.")
        return SLOW_POLL

    ticker = market["ticker"]
    if ticker != last_seen_ticker:
        RECENT_ABS_PCTS.clear()
        clean_ticker_reads.clear()
        fallback_strike_cache.clear()
        last_seen_ticker = ticker
        # Attempt to restore live state from disk (handles mid-run restarts)
        if last_entry_contracts == 0:
            print(f"LIVE STATE CHECK | ticker={ticker} | file_exists={os.path.exists(LIVE_STATE_FILE)}")
            _restored = load_live_state(ticker)
            if _restored:
                pass  # state loaded — bot will resume management next poll
            elif os.path.exists(LIVE_STATE_FILE):
                # File exists but didn't restore — log and reconcile if settled
                try:
                    import json as _j
                    with open(LIVE_STATE_FILE) as _f:
                        _s = _j.load(_f)
                    _saved_at_str = _s.get('saved_at', '')
                    _saved_age = 9999
                    if _saved_at_str:
                        try:
                            _saved_age = (dt.datetime.now(dt.timezone.utc) -
                                          dt.datetime.fromisoformat(_saved_at_str)).total_seconds()
                        except Exception:
                            pass
                    print(f"LIVE STATE SKIP | saved_ticker={_s.get('ticker')} | "
                          f"side={_s.get('side')} | entry={_s.get('entry_price')} | "
                          f"saved_at={_s.get('saved_at','?')}")

                    # ── Restart-settlement reconciliation engine (v190) ───────
                    # Triggered only when: saved ticker matches current ticker AND
                    # get_live_position_contracts returned 0 (position already gone).
                    # Uses strict matching: only sell-side fills for the saved side,
                    # capped at saved contract count. Settlement value applied only
                    # to remaining unmatched contracts after fills are accounted for.
                    _skip_ticker  = _s.get('ticker')
                    _skip_side    = _s.get('side')
                    _skip_entry   = float(_s.get('entry_price', 0) or 0)
                    _skip_contr   = int(_s.get('contracts', 0) or 0)
                    _skip_reason  = _s.get('entry_reason', 'UNKNOWN')
                    # Only reconcile when saved ticker matches current ticker
                    # (different ticker means the position settled in a prior session —
                    # handled by auto-clear below, not reconciliation)
                    if (_skip_ticker == ticker and _skip_side and
                            _skip_entry > 0 and _skip_contr > 0):
                        try:
                            # Step 1: confirm market is actually settled
                            _r_market = get_market_details(_skip_ticker)
                            _r_status = str(_r_market.get("status","")).lower() if _r_market else ""
                            _r_settled = _r_status in ("settled","closed","resolved","finalized")
                            _r_settle_side = get_settlement_side(_r_market) if _r_market else None

                            if _r_settled:
                                # Step 2: fetch fills — strictly filter to sell orders
                                # on the saved side only, ordered by time
                                _r_resp = signed_request("GET", "/portfolio/orders",
                                                         params={"ticker": _skip_ticker,
                                                                 "limit": 50})
                                _r_exit_fills = []  # (contracts, price)
                                if _r_resp.status_code == 200:
                                    _r_orders = _r_resp.json().get("orders", [])
                                    for _ro in _r_orders:
                                        # Must be: sell action, same side as our position,
                                        # actually filled
                                        if _ro.get("action") != "sell": continue
                                        if _ro.get("side","").lower() != _skip_side.lower(): continue
                                        _rfc = int(Decimal(str(_ro.get("fill_count_fp", 0))))
                                        if _rfc <= 0: continue
                                        _rfp = float(_ro.get("avg_fill_price_dollars") or
                                                     _ro.get(f"{_skip_side}_price_dollars") or 0)
                                        if _rfp <= 0: continue
                                        _r_exit_fills.append((_rfc, _rfp))

                                # Step 3: account for exits, cap at saved contract count
                                _r_total_exited = min(_skip_contr,
                                                      sum(c for c,_ in _r_exit_fills))
                                _r_settled_c    = max(0, _skip_contr - _r_total_exited)
                                _cost_basis     = _skip_entry * _skip_contr

                                # Step 4: compute exit proceeds from fills
                                _r_exit_proceeds = sum(c * p for c,p in _r_exit_fills)
                                _r_exit_summary  = [f"exit {c}c@{p:.2f}"
                                                    for c,p in _r_exit_fills]

                                # Step 5: add settlement value for remaining contracts
                                if _r_settled_c > 0 and _r_settle_side:
                                    _r_won = (_r_settle_side == _skip_side)
                                    _r_settle_val = _r_settled_c * (1.0 if _r_won else 0.0)
                                    _r_exit_proceeds += _r_settle_val
                                    _r_exit_summary.append(
                                        f"settled {_r_settled_c}c {'WIN' if _r_won else 'LOSS'}")

                                _r_pnl     = _r_exit_proceeds - _cost_basis
                                _r_outcome = "WIN" if _r_pnl > 0 else "LOSS"
                                _r_summary = " | ".join(_r_exit_summary) if _r_exit_summary else "no fills found"
                                print(f"LIVE STATE SETTLED | {_r_outcome} | "
                                      f"{_skip_side.upper()} @ {_skip_entry:.2f} ({_skip_contr}c) | "
                                      f"{_r_summary} | NET {_r_pnl:+.2f}")

                                # Step 6: record in pnl log, remove pending trade,
                                # clear state file immediately
                                if _skip_ticker not in _ticker_pnl_log:
                                    _ticker_pnl_log[_skip_ticker] = []
                                _ticker_pnl_log[_skip_ticker].append((_skip_reason, _r_pnl))
                                if _skip_ticker in pending_trades:
                                    del pending_trades[_skip_ticker]
                                    save_pending_trades()
                                clear_live_state_file()
                            else:
                                # Market not yet settled — leave state for next poll
                                print(f"LIVE STATE PENDING | market status {_r_status!r} — will retry")
                        except Exception as _re:
                            print(f"LIVE STATE RECONCILE ERROR | {_re}")

                    # Auto-clear stale state for different-ticker or old files
                    elif _skip_ticker != ticker and _saved_age > 1200:
                        clear_live_state_file()
                        print(f"LIVE STATE CLEARED | stale age {_saved_age:.0f}s")
                except Exception as _e:
                    print(f"LIVE STATE READ ERROR: {_e}")
        # Reset PAQ state so stale scores from the previous ticker don't
        # carry forward into the first entry checks of a new ticker.
        # This was the root cause of PAQ_EARLY_AGG firing with PAQ=1 when
        # prev_paq_score held a high value from the prior session.
        prev_paq_score  = None
        prev_paq_bucket = ""
        prev_paq_ctx    = None
        prev_paq_state  = None
        prev_paq_exp    = None
        for _ck, _tl in list(_ticker_pnl_log.items()):
            if _ck != ticker:
                _tk_net = sum(p for _,p in _tl)
                _tk_parts = " | ".join(f"{r} {p:+.2f}" for r,p in _tl)
                _lbl = "NET WIN" if _tk_net >= 0 else "NET LOSS"
                # Extract readable HH:MM from ticker ID e.g. KXBTC15M-26MAR211930-30 → 19:30
                _ck_time = re.search(r'(\d{4})-\d{2}$', _ck)
                if _ck_time:
                    # Kalshi ticker IDs encode Eastern Time (ET).
                    # MTN = ET - 2 always (EDT=UTC-4, MDT=UTC-6; EST=UTC-5, MST=UTC-7)
                    _ck_et_h = int(_ck_time.group(1)[:2])
                    _ck_mtn_h = (_ck_et_h - 2) % 24
                    _ck_label = f"{_ck_mtn_h:02d}:{_ck_time.group(1)[2:]}"
                else:
                    _ck_label = _ck[-5:]
                _trade_word = "trade" if len(_tl) == 1 else "trades"
                _close_msg = f"TICKER CLOSE | {_ck_label} MTN | {len(_tl)} {_trade_word} | {_lbl} {_tk_net:+.2f} | {_tk_parts}"
                print(_close_msg)
                send_telegram_alert(_close_msg)
                del _ticker_pnl_log[_ck]
        print(f"{dt.datetime.now():%H:%M:%S} | NEW TICKER | {ticker}")
        # Reset regime rolling window — keep last classification as seed
        # so first polls of new ticker use realistic prior rather than UNKNOWN
        global _regime_poll_count, _regime_abs_samples, _regime_bps_samples, _regime_spread_samples
        _regime_poll_count = 0
        _regime_abs_samples.clear()
        _regime_bps_samples.clear()
        _regime_spread_samples.clear()
        # _regime intentionally NOT reset — seeded from previous ticker
        # BCDP history reset: new ticker = fresh order flow slate
        _bps_history.clear()
        _bcdp = 0
        _bcdp_clean = False
        # v159: clear PAQ_STRUCT loss cooldown when a genuinely new ticker starts
        global _paq_struct_loss_ticker
        if _paq_struct_loss_ticker and _paq_struct_loss_ticker != ticker:
            _paq_struct_loss_ticker = None

    close_time = dt.datetime.fromisoformat(market["close_time"].replace("Z", "+00:00"))
    seconds_left = (close_time - dt.datetime.now(dt.timezone.utc)).total_seconds()

    yes_price, no_price = get_prices(market)
    strike = None   # Step 2 replacement

    if yes_price is None or no_price is None:
        print(f"{dt.datetime.now():%H:%M:%S} | Missing prices | {int(seconds_left)}s left")
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    btc_snapshot = get_btc_snapshot()
    btc_available = btc_snapshot["available"]
    current_btc = btc_snapshot["current_price"]
    recent_move_pct = btc_snapshot["recent_move_pct"]

    # Step 2: new strike parsing after BTC snapshot
    # First try the strike from the open-markets list object
    strike = get_market_strike(market, current_btc)

    # If rollover list data is missing or incomplete, retry from the full market-details endpoint
    if strike is None:
        detail_market = get_market_details(ticker)
        if detail_market:
            detail_strike = get_market_strike(detail_market, current_btc)
            if detail_strike is not None:
                strike = detail_strike
                print(
                    f"{dt.datetime.now():%H:%M:%S} | STRIKE RECOVERED FROM DETAILS | "
                    f"ticker {ticker} | strike {strike:.2f}"
                )

    if strike is None:
        if ticker in fallback_strike_cache:
            strike = fallback_strike_cache[ticker]
        elif current_btc is not None and current_btc > 0:
            strike = current_btc
            fallback_strike_cache[ticker] = strike
            print(f"{dt.datetime.now():%H:%M:%S} | STRIKE LOCKED TO BTC SPOT | {strike:.2f}")
        else:
            print(f"{dt.datetime.now():%H:%M:%S} | Missing/plausibility-failed strike | skipping")
            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    metrics = compute_btc_strike_metrics(current_btc, strike)

    if metrics is None:
        print(f"{dt.datetime.now():%H:%M:%S} | Invalid BTC/strike metrics | skipping")
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # Step 3: hard outlier blocker
    if metrics["abs_pct"] > 5.0:
        print(
            f"{dt.datetime.now():%H:%M:%S} | ABS PCT OUTLIER | "
            f"ticker {ticker} | BTC {metrics['btc_price']:.2f} | "
            f"strike {metrics['strike']:.2f} | abs {metrics['abs_pct']:.3f}% | skipping"
        )
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # NEW TICKER STABILIZER (forces 2 clean reads on rollover)
    clean_ticker_reads[ticker] += 1
    if clean_ticker_reads[ticker] < 2:
        _stab_bal = ""
        try:
            _br = signed_request("GET", "/portfolio/balance")
            if _br.status_code == 200:
                _bd = _br.json()
                _bv = float(_bd.get("balance", _bd.get("available_balance", _bd.get("cash_balance", 0)))) / 100
                _stab_bal = f" | bal ${_bv:.2f}"
        except Exception:
            pass
        print(
            f"{dt.datetime.now():%H:%M:%S} | NEW TICKER STABILIZING | "
            f"{ticker} | read {clean_ticker_reads[ticker]}/2 | "
            f"BTC {metrics['btc_price']:.2f} | strike {metrics['strike']:.2f} | "
            f"abs {metrics['abs_pct']:.3f}%" + _stab_bal
        )
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    abs_pct_for_risk = metrics["abs_pct"] if metrics else None
    abs_text = f"{metrics['abs_pct']:.3f}%" if metrics else "N/A"
    # FIX 1: guard against outlier abs_pct values (e.g. 49.83% from a
    # mis-parsed strike) poisoning the RECENT_ABS_PCTS deque.
    ABS_PCT_SANE_MAX = 5.0
    if abs_pct_for_risk is not None and float(abs_pct_for_risk) <= ABS_PCT_SANE_MAX:
        clean_vals = [v for v in RECENT_ABS_PCTS if v <= ABS_PCT_SANE_MAX]
        if len(clean_vals) != len(RECENT_ABS_PCTS):
            print(
                f"{dt.datetime.now():%H:%M:%S} | ABS DEQUE PURGE | "
                f"removed {len(RECENT_ABS_PCTS) - len(clean_vals)} outlier(s)"
            )
            RECENT_ABS_PCTS.clear()
            for v in clean_vals:
                RECENT_ABS_PCTS.append(v)
        RECENT_ABS_PCTS.append(float(abs_pct_for_risk))
    elif abs_pct_for_risk is not None:
        print(
            f"{dt.datetime.now():%H:%M:%S} | ABS PCT DEQUE SKIP | "
            f"value {float(abs_pct_for_risk):.3f}% exceeds sane max {ABS_PCT_SANE_MAX}% | not appended"
        )

    if btc_available and current_btc is not None:
        btc_prices.append(current_btc)

    live_bps = break_pressure_score(strike, btc_prices) if strike is not None else 0.0

    # Update confirmation-family post-entry peak every cycle
    if last_entry_reason in ("confirm_standard", "confirm_late"):
        update_conf_peak(yes_price, no_price)

    update_history(ticker, yes_price, no_price)

    now_str = f"{dt.datetime.now():%H:%M:%S}"

    # Update PAQ every cycle for display — uses same candles already fetched for decide_trade
    # We compute for YES side by convention; bucket reflects current BTC/candle structure
    try:
        _disp_candles = get_btc_candles("3m", 3)
        _disp_btc = btc_prices[-1] if btc_prices else None
        _disp_bps = live_bps
        # Compute prev BPS properly using a 6-price window ending one step back
        _btc_list = list(btc_prices)
        _disp_prev_bps = (break_pressure_score(strike, _btc_list[:-1])
                          if strike is not None and len(_btc_list) >= 7
                          else live_bps)
        _disp_abs = float(RECENT_ABS_PCTS[-1]) if RECENT_ABS_PCTS else 0.0
        _disp_prem = get_prem_abs_floor(seconds_left)
        if _disp_btc is not None:
            _paq_result = get_paq_score("yes", _disp_candles, _disp_btc, _disp_bps, _disp_prev_bps, _disp_abs, _disp_prem)
            # Immediately store into prev_paq_* so status line and gate check
            # use the SAME values from the SAME candle fetch this poll cycle.
            # Previously _paq_result was computed but never stored, causing
            # status line (old prev_paq) and gate check (fresh compute) to diverge.
            if _paq_result:
                prev_paq_score  = _paq_result[0]
                prev_paq_ctx    = _paq_result[1]
                prev_paq_state  = _paq_result[2]
                prev_paq_exp    = _paq_result[3]
                prev_paq_bucket = _paq_result[4]
    except Exception:
        pass

    if prev_paq_score is not None and prev_paq_ctx is not None:
        paq_text = f" | PAQ {prev_paq_score} | CTX {prev_paq_ctx} STATE {prev_paq_state} EXP {prev_paq_exp}"
    elif prev_paq_score is not None:
        paq_text = f" | PAQ {prev_paq_score}"
    else:
        paq_text = " | PAQ --"
    # Build compact status suffix: gate state + block reason if applicable
    global _last_gate_result, _last_entry_block
    _gate_suffix = f" | {_last_gate_result}" if _last_gate_result else ""
    _block_suffix = f" | {_last_entry_block}" if _last_entry_block else ""
    _last_gate_result = ""
    _last_entry_block = ""
    _regime_suffix = f" | {_pending_regime_display}" if _pending_regime_display else ""
    # Note: _gate_suffix and _block_suffix moved AFTER BCDP in the print below
    # Update market regime classifier each poll
    _abs_for_regime = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
    # Real-time book classification — reuse the entry orderbook if already fetched,
    # otherwise fetch once here. No extra API call when entering a position.
    _poll_ob = get_orderbook(ticker)
    _book_env = classify_book_environment(_poll_ob, _abs_for_regime)
    update_market_regime(_abs_for_regime, live_bps, yes_price, no_price)
    # BCDP: compute BEFORE status print so this poll's value is shown immediately
    _bps_history.append(live_bps)
    _bcdp = compute_bcdp(_bps_history)
    _bcdp_clean = compute_bcdp_clean(_bps_history)
    _bcdp_display_now = f"BCDP {_bcdp}{'C' if _bcdp_clean else ''}"
    if _bcdp == 0:
        _bcdp_display_now = "BCDP 0"

    _bcdp_suffix = f" | {_bcdp_display_now}"
    # PHI suffix: show post-entry health score when a position is open
    _phi_suffix = ""
    if last_entry_contracts > 0 and last_traded_ticker == ticker and last_entry_price:
        _phi_held  = float(yes_price if last_side == "yes" else no_price)
        _phi_quick = get_post_entry_phi(
            paq_now=prev_paq_score or 0, paq_entry=last_entry_paq or (prev_paq_score or 0),
            live_bps=live_bps or 0.0, entry_bps=last_entry_bps or 0.0,
            held_px=_phi_held, entry_px=float(last_entry_price),
            bdi=get_bdi(ticker, last_side or "yes", _phi_held), side=last_side or "yes"
        )
        _phi_suffix = f" | PHI {_phi_quick}"
    # Order: BPS | PAQ | REGIME | BCDP | PHI (when open) | READY/BLOCK alerts at end
    print(format_main_status_line(now_str, yes_price, no_price, seconds_left, metrics) + f" | BPS {live_bps:+.1f}{paq_text}{_regime_suffix}{_bcdp_suffix}{_phi_suffix}{_gate_suffix}{_block_suffix}")
    _pending_regime_display = ""

    # Pause gate — skip all position management and entries when paused
    if _bot_paused:
        print(f"          → PAUSED | monitoring only, no entries or exits")
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # Persist live position state every poll so a restart can resume management
    if last_entry_contracts > 0 and last_traded_ticker == ticker:
        save_live_state()

    if last_entry_reason not in ("bps_premium", "bps_late"):
        check_flip_event(ticker, yes_price, no_price)

    # If contract has expired but we still have an open unfilled position,
    # the market has settled — clear state immediately rather than waiting 20 min.
    # This happens after stop ladders fail entirely (book dead) and the contract
    # expires with no fill. Carrying stale state blocks entries on subsequent tickers.
    if seconds_left <= 0 and last_entry_contracts > 0 and ticker == last_traded_ticker:
        # State cleared — settlement confirms outcome
        # Do NOT pop pending_trades — leave it for check_settlements() to process
        # so the SETTLED WIN/LOSS print fires correctly with P&L and balance.
        # Only clear live position state so the next ticker starts clean.
        clear_live_state_file()
        clear_live_position_state()

    # HARD GATE: never attempt any stop after contract expiry or when no position
    if seconds_left > 0 and last_entry_contracts > 0 and ticker == last_traded_ticker:
        last_entry_reads += 1  # track poll cycles for trail stabilization

        # ── v254: TIME_BDI_LOW pre-emptive exit ──────────────────────────────
        # When >67% through the 15-min window (>10 min elapsed) AND BDI < 50
        # AND position is losing, exit proactively while liquidity remains.
        # Evidence: 4/9 data shows 4/5 BDI=0 forced exits in final minutes of
        # window. By then the book is empty and fills are catastrophic
        # (-$0.19 to -$0.29/contract slippage). This fires BEFORE BDI reaches 0.
        # Uses staged exit (50% sell, wait 1 poll, sell remaining 50%) to avoid
        # dumping the entire position into a thinning book at once.
        if (last_side and last_entry_contracts > 0
                and not _bdi0_exit_pending
                and seconds_left is not None and float(seconds_left) > 0):
            _tbl_window_duration = 900  # 15-min = 900s
            _tbl_elapsed = _tbl_window_duration - float(seconds_left)
            _tbl_threshold = _tbl_window_duration * 0.67  # ~10 min
            if _tbl_elapsed > _tbl_threshold:
                _tbl_held_px = float(yes_price if last_side == "yes" else no_price)
                _tbl_entry_px = float(last_entry_price) if last_entry_price else _tbl_held_px
                _tbl_losing = _tbl_held_px < _tbl_entry_px
                _tbl_ob = get_orderbook(ticker)
                _tbl_ob_key = "yes_dollars" if last_side == "yes" else "no_dollars"
                _tbl_ob_levels = (_tbl_ob.get(_tbl_ob_key) or _tbl_ob.get(_tbl_ob_key.replace("_dollars", "")) or []) if _tbl_ob else []
                _tbl_bdi = 0
                for _lvl in _tbl_ob_levels:
                    try:
                        _lpx = float(_lvl[0])
                        _lqty = float(_lvl[1])
                        if _lpx > 1.0: _lpx /= 100
                        if _lqty > 100: _lqty /= 100
                        if _tbl_held_px - 0.10 <= _lpx <= _tbl_held_px + 0.10:
                            _tbl_bdi += int(_lqty)
                    except Exception:
                        pass
                if _tbl_bdi < 50 and _tbl_losing:
                    print(
                        f"          -> TIME_BDI_LOW | {last_side.upper()} | {last_entry_contracts}c | "
                        f"BDI {_tbl_bdi} | {int(seconds_left)}s left | "
                        f"entry {_tbl_entry_px:.4f} -> now {_tbl_held_px:.4f} | staged exit"
                    )
                    _tbl_half = max(1, last_entry_contracts // 2)
                    _tbl_result1 = execute_rapid_stop_loss_exit(
                        ticker=ticker, side=last_side,
                        yes_price=yes_price, no_price=no_price,
                        reason_label="TIME_BDI_LOW_STAGE1",
                        max_contracts=_tbl_half,
                        metrics=metrics, market=market, ob_snapshot=_tbl_ob,
                    )
                    _tbl_filled1 = int(_tbl_result1.get("filled_qty", 0))
                    if _tbl_filled1 > 0 and _tbl_result1.get("avg_exit_price"):
                        _tbl_pnl1 = (float(_tbl_result1["avg_exit_price"]) - _tbl_entry_px) * _tbl_filled1
                        print(f"          -> TIME_BDI_LOW_STAGE1_FILLED | {_tbl_filled1}c | pnl {_tbl_pnl1:+.2f}")
                        update_pending_trade_exits(ticker, "stop", _tbl_filled1, float(_tbl_result1["avg_exit_price"]))
                    last_entry_contracts = max(0, last_entry_contracts - _tbl_filled1)
                    if last_entry_contracts > 0:
                        time.sleep(17)  # wait one poll interval for book to refresh
                        _tbl_ob2 = get_orderbook(ticker)
                        _tbl_result2 = execute_rapid_stop_loss_exit(
                            ticker=ticker, side=last_side,
                            yes_price=yes_price, no_price=no_price,
                            reason_label="TIME_BDI_LOW_STAGE2",
                            metrics=metrics, market=market, ob_snapshot=_tbl_ob2,
                        )
                        _tbl_filled2 = int(_tbl_result2.get("filled_qty", 0))
                        if _tbl_filled2 > 0 and _tbl_result2.get("avg_exit_price"):
                            _tbl_pnl2 = (float(_tbl_result2["avg_exit_price"]) - _tbl_entry_px) * _tbl_filled2
                            print(f"          -> TIME_BDI_LOW_STAGE2_FILLED | {_tbl_filled2}c | pnl {_tbl_pnl2:+.2f}")
                            update_pending_trade_exits(ticker, "stop", _tbl_filled2, float(_tbl_result2["avg_exit_price"]))
                        last_entry_contracts = max(0, last_entry_contracts - _tbl_filled2)
                    if last_entry_contracts <= 0:
                        print_full_exit_settlement(ticker)
                        pending_trades.pop(ticker, None)
                        save_pending_trades()
                        clear_live_state_file()
                        clear_live_position_state()
                        return FAST_POLL

        # ── v247/v254: Forced exit after BDI=0 HOLD1 ────────────────────────
        # v254 upgrade: uses staged exit (50%/50%) instead of full dump.
        # After a HOLD1 deferred the exit, stop conditions may not re-qualify
        # on subsequent polls: _paq_stop_fired is latched, BPS thresholds may
        # not be met, trail conditions may not trigger. Without this block,
        # the position drifts silently to settlement with no exit attempted.
        # Simulation (4/4-4/5 logs): +$11.34 net improvement across 3 events.
        if _bdi0_exit_pending and last_side and last_entry_contracts > 0:
            _f_held_now  = float(yes_price if last_side == "yes" else no_price)
            _f_entry_px  = float(last_entry_price) if last_entry_price else _f_held_now
            # Profitability at mark: held-side price > entry price for both YES and NO.
            # YES@0.53 profitable when YES>0.53. NO@0.53 profitable when NO>0.53.
            # Prior version had (_f_held_now < _f_entry_px) for NO — incorrect.
            _f_profitable = _f_held_now > _f_entry_px
            # Near-settlement suppression guard:
            # Suppress ONLY when all three hold: (1) < 30s left, (2) held price >= 0.90
            # (already deep in-the-money), AND (3) position is net profitable at mark.
            # This protects a late winner (e.g. trail at 10s, YES=0.89 on YES@0.74 entry)
            # without giving a free pass to late losers (YES=0.10 at 25s is not suppressed
            # because _f_profitable is False).
            _f_suppress = (
                seconds_left is not None and float(seconds_left) < 30
                and _f_held_now >= 0.90
                and _f_profitable
            )
            if _f_suppress:
                print(
                    f"          → FORCED_EXIT_SUPPRESSED_NEAR_SETTLEMENT | {last_side.upper()} | "
                    f"held {_f_held_now:.4f} | profitable={_f_profitable} | {int(seconds_left)}s left"
                )
                _bdi0_exit_pending = False
            else:
                _f_hold_ref = _bdi0_hold_px or _f_held_now
                _f_delta    = round(_f_held_now - _f_hold_ref, 4)
                print(
                    f"          -> STAGED_EXIT_AFTER_HOLD1 | {last_side.upper()} | {last_entry_contracts}c | "
                    f"hold_px {_f_hold_ref:.4f} -> now {_f_held_now:.4f} ({_f_delta:+.4f}) | {int(seconds_left)}s"
                )
                # v254: staged exit — sell 50%, wait 1 poll, sell remaining 50%
                # Replaces full dump into empty book which caused catastrophic slippage.
                _f_ob = get_orderbook(ticker)
                _f_half = max(1, last_entry_contracts // 2)
                # Stage 1: sell first half
                _f_result = execute_rapid_stop_loss_exit(
                    ticker=ticker,
                    side=last_side,
                    yes_price=yes_price,
                    no_price=no_price,
                    reason_label="STAGED_EXIT_HOLD1_S1",
                    max_contracts=_f_half,
                    metrics=metrics,
                    market=market,
                    ob_snapshot=_f_ob,
                )
                _bdi0_exit_pending = False  # always clear after first attempt
                _f_total_filled = 0
                if _f_result["status"] in ("full_exit", "partial_exit"):
                    _f_filled   = int(_f_result["filled_qty"])
                    _f_avg_px   = _f_result["avg_exit_price"]
                    _f_total_filled += _f_filled
                    if _f_filled > 0 and _f_avg_px is not None:
                        _f_exit_px = float(_f_avg_px)
                        _f_pnl = (_f_exit_px - _f_entry_px) * _f_filled
                        _f_pnl_txt = f"+${_f_pnl:.2f}" if _f_pnl >= 0 else f"-${abs(_f_pnl):.2f}"
                        print(f"          -> STAGED_EXIT_S1_FILLED | {last_side.upper()} | {_f_filled}c @ {_f_exit_px:.4f} | {_f_pnl_txt}")
                        update_pending_trade_exits(ticker, "stop", _f_filled, _f_exit_px)
                    last_entry_contracts = max(0, last_entry_contracts - _f_filled)
                # Stage 2: wait one poll, sell remainder
                if last_entry_contracts > 0:
                    time.sleep(17)  # one poll interval — let book refresh
                    # v254: BDI recovery detection — if book came back, cancel exit
                    _f_ob2 = get_orderbook(ticker)
                    _f_ob2_key = "yes_dollars" if last_side == "yes" else "no_dollars"
                    _f_ob2_levels = (_f_ob2.get(_f_ob2_key) or _f_ob2.get(_f_ob2_key.replace("_dollars", "")) or []) if _f_ob2 else []
                    _f_recovery_bdi = 0
                    for _lvl in _f_ob2_levels:
                        try:
                            _lpx = float(_lvl[0])
                            _lqty = float(_lvl[1])
                            if _lpx > 1.0: _lpx /= 100
                            if _lqty > 100: _lqty /= 100
                            if _f_held_now - 0.10 <= _lpx <= _f_held_now + 0.10:
                                _f_recovery_bdi += int(_lqty)
                        except Exception:
                            pass
                    if _f_recovery_bdi > 50 and _f_profitable:
                        # Book recovered AND position is profitable — cancel staged exit
                        print(
                            f"          -> BDI_RECOVERY | {last_side.upper()} | BDI {_f_recovery_bdi} | "
                            f"profitable={_f_profitable} | cancelling staged exit, resume normal"
                        )
                        _any_stop_fired = False  # allow normal stop evaluation
                        _bdi0_hold_count = 0
                    else:
                        _f_result2 = execute_rapid_stop_loss_exit(
                            ticker=ticker,
                            side=last_side,
                            yes_price=yes_price,
                            no_price=no_price,
                            reason_label="STAGED_EXIT_HOLD1_S2",
                            metrics=metrics,
                            market=market,
                            ob_snapshot=_f_ob2,
                        )
                        if _f_result2["status"] in ("full_exit", "partial_exit"):
                            _f_filled2 = int(_f_result2["filled_qty"])
                            _f_avg_px2 = _f_result2["avg_exit_price"]
                            _f_total_filled += _f_filled2
                            if _f_filled2 > 0 and _f_avg_px2 is not None:
                                _f_exit_px2 = float(_f_avg_px2)
                                _f_pnl2 = (_f_exit_px2 - _f_entry_px) * _f_filled2
                                _f_pnl_txt2 = f"+${_f_pnl2:.2f}" if _f_pnl2 >= 0 else f"-${abs(_f_pnl2):.2f}"
                                print(f"          -> STAGED_EXIT_S2_FILLED | {last_side.upper()} | {_f_filled2}c @ {_f_exit_px2:.4f} | {_f_pnl_txt2}")
                                update_pending_trade_exits(ticker, "stop", _f_filled2, _f_exit_px2)
                            last_entry_contracts = max(0, last_entry_contracts - _f_filled2)
                if last_entry_contracts <= 0:
                    print_full_exit_settlement(ticker)
                    pending_trades.pop(ticker, None)
                    save_pending_trades()
                    clear_live_state_file()
                    clear_live_position_state()
                    return FAST_POLL
                elif _f_result.get("note") == "BDI_ZERO" and _f_total_filled == 0:
                    # Still no book, nothing filled — escalation next call
                    _any_stop_fired = False

        # ── Post-entry PHI health score (v214) ───────────────────────────────
        # Single unified signal: is the thesis still intact?
        # Computed every poll. Used to: (1) log health, (2) drive harvest aggression.
        # Does NOT gate entries — purely post-entry.
        _held_px_f  = float(yes_price if last_side == "yes" else no_price)
        _entry_px_f = float(last_entry_price) if last_entry_price else _held_px_f
        _phi_bdi    = get_bdi(ticker, last_side or "yes", _held_px_f)
        _phi = get_post_entry_phi(
            paq_now   = prev_paq_score or 0,
            paq_entry = last_entry_paq or (prev_paq_score or 0),
            live_bps  = live_bps or 0.0,
            entry_bps = last_entry_bps or 0.0,
            held_px   = _held_px_f,
            entry_px  = _entry_px_f,
            bdi       = _phi_bdi,
            side      = last_side or "yes"
        )
        # PHI drives harvest tranche size: low health → more aggressive harvesting
        # High PHI (≥70): let it run, standard harvest tranches
        # Mid PHI (40-69): slightly elevated harvest aggression
        # Low PHI (<40): thesis degrading, harvest maximum tranche now
        _phi_harvest_boost = False
        if _phi < 40 and not harvest_s1_done and last_entry_contracts > 1:
            _phi_harvest_boost = True  # passed to harvest functions via flag below

        # v229: Post-partial tail-risk recovery exit
        # After CONTRACT_VELOCITY_PARTIAL fills, the tail enters a dead zone:
        # PAQ stop blocked (_paq_stop_fired), trail blocked (_any_stop_fired),
        # CHOP only arms if BPS goes adverse, harvest waits for full S1 threshold.
        # Proof case: 0015-15 NO@0.58 9c tail — recovered to NO=0.75 at 22:12:38
        # but had no dedicated exit logic. Settled YES=1.00 → full tail loss.
        # Fix: if tail recovers to ≥90% of entry price, force a recovery exit now.
        if (_tail_risk_mode
                and last_side
                and last_entry_contracts > 0
                and _tail_risk_entry_px is not None
                and seconds_left is not None and seconds_left > 30):
            _tail_held_px = float(yes_price if last_side == "yes" else no_price)
            _tail_recovery_threshold = _tail_risk_entry_px * 0.90
            if _tail_held_px >= _tail_recovery_threshold:
                print(f"          → TAIL_RISK_RECOVERY | {last_side.upper()} | "
                      f"held {_tail_held_px:.4f} ≥ threshold {_tail_recovery_threshold:.4f} "
                      f"(90% of entry {_tail_risk_entry_px:.4f}) | {last_entry_contracts}c | {int(seconds_left)}s")
                _tail_ob = get_orderbook(ticker)
                _tail_result = execute_rapid_stop_loss_exit(
                    ticker=ticker,
                    side=last_side,
                    yes_price=yes_price,
                    no_price=no_price,
                    reason_label="TAIL_RISK_RECOVERY",
                    metrics=metrics,
                    market=market,
                    ob_snapshot=_tail_ob,
                )
                if _tail_result["status"] in ("full_exit", "partial_exit"):
                    _tail_filled = int(_tail_result["filled_qty"])
                    _tail_avg_px = _tail_result["avg_exit_price"]
                    _tail_remaining = int(_tail_result["remaining_qty"])
                    if _tail_filled > 0 and _tail_avg_px is not None:
                        _tail_pnl = (float(_tail_avg_px) - _tail_risk_entry_px) * _tail_filled
                        _pnl_txt = f"+${_tail_pnl:.2f}" if _tail_pnl >= 0 else f"-${abs(_tail_pnl):.2f}"
                        print(f"          → TAIL_RISK_FILL | {_tail_filled}c @ {float(_tail_avg_px):.4f} | {_pnl_txt}")
                        update_pending_trade_exits(ticker, "stop", _tail_filled, float(_tail_avg_px))
                    last_entry_contracts = _tail_remaining
                    if _tail_remaining <= 0:
                        _tail_risk_mode = False
                        _tail_risk_entry_px = None
                        print_full_exit_settlement(ticker)
                        pending_trades.pop(ticker, None)
                        save_pending_trades()
                        clear_live_state_file()
                        clear_live_position_state()
                        return FAST_POLL
                    else:
                        # Partial fill — disarm tail mode, remainder handled normally
                        _tail_risk_mode = False
                        _tail_risk_entry_px = None
                else:
                    if _tail_result.get("note") == "BDI_ZERO":
                        # v246: hold — reset so all stop mechanisms re-evaluate next poll
                        _any_stop_fired = False
                    else:
                        print(f"          → TAIL_RISK_UNFILLED | {last_side.upper()} | book thin")

        # ── v234: WES exit management ─────────────────────────────────────
        # WES uses a symmetric ±0.15 exit. No harvest system. No trail. No PHI.
        # S1 target (entry+0.15) → full exit. Stop target (entry-0.15) → full exit.
        # Both exits use execute_rapid_stop_loss_exit for immediate full fill.
        if (_wes_active
                and not _wes_promoted          # v238: promoted WES exits via parent family logic
                and _wes_entry_px is not None
                and last_side is not None
                and last_entry_contracts > 0
                and ticker == last_traded_ticker):
            _wes_held = float(yes_price if last_side == "yes" else no_price)
            _wes_exit_reason = None
            if _wes_held >= _wes_s1_target:
                _wes_exit_reason = f"WES_S1_EXIT | {last_side.upper()} | held {_wes_held:.4f} >= target {_wes_s1_target:.4f}"
            elif _wes_held <= _wes_stop_target:
                _wes_exit_reason = f"WES_STOP | {last_side.upper()} | held {_wes_held:.4f} <= stop {_wes_stop_target:.4f}"

            if _wes_exit_reason:
                print(f"          → {_wes_exit_reason} | {last_entry_contracts}c | entry {_wes_entry_px:.4f}")
                _wes_ob = get_orderbook(ticker)
                _wes_result = execute_rapid_stop_loss_exit(
                    ticker=ticker, side=last_side,
                    yes_price=yes_price, no_price=no_price,
                    reason_label=_wes_exit_reason.split('|')[0].strip(),
                    metrics=metrics, market=market, ob_snapshot=_wes_ob,
                )
                if _wes_result["status"] in ("full_exit", "partial_exit"):
                    _wes_filled = int(_wes_result["filled_qty"])
                    _wes_avg_px = _wes_result["avg_exit_price"]
                    if _wes_filled > 0 and _wes_avg_px is not None:
                        _wes_pnl = (float(_wes_avg_px) - _wes_entry_px) * _wes_filled
                        if last_side == "no":
                            _wes_pnl = (_wes_entry_px - float(_wes_avg_px)) * _wes_filled
                        _pnl_txt = f"+${_wes_pnl:.2f}" if _wes_pnl >= 0 else f"-${abs(_wes_pnl):.2f}"
                        print(f"          → WES_FILL | {_wes_filled}c @ {float(_wes_avg_px):.4f} | {_pnl_txt}")
                        update_pending_trade_exits(ticker, "stop", _wes_filled, float(_wes_avg_px))
                    last_entry_contracts = max(0, last_entry_contracts - int(_wes_result["filled_qty"]))
                    if last_entry_contracts <= 0:
                        _wes_active = False
                        _wes_entry_px = _wes_s1_target = _wes_stop_target = _wes_side = None
                        _wes_contracts = 0
                        print_full_exit_settlement(ticker)
                        pending_trades.pop(ticker, None)
                        save_pending_trades()
                        clear_live_state_file()
                        clear_live_position_state()
                        return FAST_POLL
                elif _wes_result.get("note") == "BDI_ZERO":
                    # v246: hold — reset so all stop mechanisms re-evaluate next poll
                    _any_stop_fired = False
        # Data: WEAK session losses telegraph failure by poll 2 via BPS collapse.
        # Winners: BPS stays positive (+1.50 avg at poll+2).
        # Losers: BPS decays to near-zero or flips negative by poll+2.
        # In WEAK sessions (ASIA_OPEN, BTC_DEEP_NIGHT), if by poll 2:
        #   - BPS has collapsed to 0 or flipped against the trade, AND
        #   - ABS has not improved from entry (no BTC follow-through)
        # → cut 33% of position immediately. Don't wait for poll 4.
        # ACTIVE sessions untouched — NY_PRIME 7W/0L, no intervention needed.
        _early_derisk_sess = get_session_label() in ("ASIA_OPEN", "BTC_DEEP_NIGHT")
        if (last_entry_reason == "PAQ_STRUCT_GATE"
                and not _paq_struct_derisked
                and not harvest_s1_done
                and last_entry_contracts > 0
                and last_entry_reads == 2
                and _early_derisk_sess):
            _live_bps_now = live_bps if live_bps is not None else 0.0
            _live_abs_now2 = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
            # BPS has flipped against or collapsed to zero
            _bps_collapsed = (last_side == "yes" and _live_bps_now <= 0) or \
                             (last_side == "no"  and _live_bps_now >= 0)
            # ABS hasn't improved from entry
            _abs_flat = _live_abs_now2 <= last_entry_abs * 1.2  # less than 20% improvement
            if _bps_collapsed and _abs_flat:
                _early_qty = max(1, round(last_entry_contracts * 0.33))
                print(f"          → PAQ_STRUCT_EARLY_DERISK | WEAK sess poll-2 | BPS{_live_bps_now:+.1f} collapsed | ABS{_live_abs_now2:.3f} flat | exiting {_early_qty}/{last_entry_contracts}c")
                _derisk_ob2 = get_orderbook(ticker)
                _derisk_res2 = execute_rapid_stop_loss_exit(
                    ticker=ticker, side=last_side,
                    yes_price=yes_price, no_price=no_price,
                    reason_label="PAQ_STRUCT_EARLY_DERISK",
                    ob_snapshot=_derisk_ob2,
                    max_contracts=_early_qty,
                    ladder_override=[Decimal("0.00"), Decimal("0.01"), Decimal("0.02"), Decimal("0.03")]
                )
                if _derisk_res2["status"] in ("full_exit", "partial_exit"):
                    _eq = int(_derisk_res2["filled_qty"])
                    _epx = float(_derisk_res2["avg_exit_price"] or 0)
                    _epnl = (_epx - float(last_entry_price)) * _eq if last_entry_price else 0
                    print(f"          → PAQ_STRUCT_EARLY_DERISKED | {_eq}c @ {_epx:.4f} | est {_epnl:+.2f} | {last_entry_contracts - _eq}c remaining")
                elif _derisk_res2["status"] == "unfilled":
                    if _derisk_res2.get("note") == "BDI_ZERO":
                        _any_stop_fired = False  # v246: hold — allow re-evaluation next poll
                    else:
                        print(f"          → PAQ_STRUCT_EARLY_DERISK UNFILLED | book thin")
                # Note: don't set _paq_struct_derisked=True — still allow poll-4 derisk on remainder

            # ── Poll-2 scale-in: mirror of early derisk (v214) ───────────────
            # When thesis CONFIRMS at poll 2 (BPS still aligned, ABS improving),
            # add 25% more contracts. Asymmetric payoff: cut when bad, add when good.
            # Data: winning PAQ_STRUCT trades had BPS +1.50 avg at poll+2 vs +0.20 for losers.
            # Entry at 0.45-0.65 with confirmed momentum → upside $0.35-0.55/contract.
            # Gate: BPS still directional AND ABS improved ≥30% from entry.
            # Cap: add-on limited by BDI and risk — max 25% extra, never exceeds
            # 1.5× original conviction-sized risk. WEAK sessions only (same scope as derisk).
            # Not a new entry — uses existing position state, same ticker.
            elif not _bps_collapsed:
                _bps_confirming = (last_side == "yes" and _live_bps_now >= 1) or \
                                  (last_side == "no"  and _live_bps_now <= -1)
                _abs_improving  = _live_abs_now2 >= last_entry_abs * 1.30  # ≥30% improvement
                if (_bps_confirming and _abs_improving
                        and last_entry_price is not None):
                    _addon_qty = max(1, round(last_entry_contracts * 0.25))
                    _addon_price = yes_price if last_side == "yes" else no_price
                    _addon_risk  = float(_addon_price) * _addon_qty
                    # Hard cap: addon risk ≤ 40% of original risk
                    _orig_risk = float(last_entry_price) * last_entry_contracts
                    if _addon_risk <= _orig_risk * 0.40:
                        _addon_bdi = get_bdi(ticker, last_side, float(_addon_price))
                        if _addon_bdi >= _addon_qty:
                            print(f"          → PAQ_STRUCT_SCALE_IN | poll-2 confirmed | BPS{_live_bps_now:+.1f} ABS{_live_abs_now2:.3f}(+{(_live_abs_now2/max(last_entry_abs,0.001)-1)*100:.0f}%) | adding {_addon_qty}c @ {float(_addon_price):.4f}")
                            _si_resp = place_limit_order(ticker, last_side, _addon_price, _addon_qty, "PAQ_STRUCT_SCALE_IN", seconds_left, _live_abs_now2)
                            if _si_resp and _si_resp.status_code in (200, 201):
                                last_entry_contracts += _addon_qty
                                print(f"          → PAQ_STRUCT_SCALE_IN FILLED | position now {last_entry_contracts}c")

        if (last_entry_reason == "PAQ_STRUCT_GATE"
                and not _paq_struct_derisked
                and not harvest_s1_done
                and last_entry_contracts > 0
                and last_entry_reads >= 4):  # v159: restore explicit 4-poll minimum before de-risk eligible
            _live_abs_now = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
            _should_derisk, _derisk_note = paq_struct_continuity_check(last_entry_abs, _live_abs_now)
            if _should_derisk:
                _paq_struct_derisked = True
                _derisk_qty = max(1, round(last_entry_contracts * 0.50))
                _current_held_px = yes_price if last_side == "yes" else no_price
                print(f"          → PAQ_STRUCT_DERISK | {_derisk_note} | exiting {_derisk_qty}/{last_entry_contracts}c")
                _derisk_ob = get_orderbook(ticker)
                _derisk_result = execute_rapid_stop_loss_exit(
                    ticker=ticker, side=last_side,
                    yes_price=yes_price, no_price=no_price,
                    reason_label="PAQ_STRUCT_DERISK",
                    ob_snapshot=_derisk_ob,
                    max_contracts=_derisk_qty,
                    ladder_override=[Decimal("0.00"), Decimal("0.01"), Decimal("0.02"), Decimal("0.03")]
                )
                if _derisk_result["status"] in ("full_exit", "partial_exit"):
                    _d_qty = int(_derisk_result["filled_qty"])
                    _d_px  = float(_derisk_result["avg_exit_price"] or 0)
                    _d_pnl = (_d_px - float(last_entry_price)) * _d_qty if last_entry_price else 0
                    print(f"          → PAQ_STRUCT_DERISKED | {_d_qty}c @ {_d_px:.4f} | est {_d_pnl:+.2f} | {last_entry_contracts - _d_qty}c remaining")
                elif _derisk_result["status"] == "unfilled":
                    if _derisk_result.get("note") == "BDI_ZERO":
                        _any_stop_fired = False  # v246: hold — allow re-evaluation next poll
                        _paq_struct_derisked = False  # allow retry next poll
                    else:
                        print(f"          → PAQ_STRUCT_DERISK UNFILLED | book thin — holding full position")
                        _paq_struct_derisked = False  # allow retry next poll

        # ── PAQ_STRUCT early BPS-collapse derisk (v213, WEAK sessions only) ──────
        # Data: WEAK-session losers telegraph themselves by poll 2.
        # Winners keep directional BPS alive (avg +1.50 through poll+4).
        # Losers collapse toward zero by poll+1 (avg +0.20) and flip by poll+5.
        # By poll 2, the thesis has either confirmed or is fading.
        # This fires a 33% partial exit earlier than the 4-poll continuity check
        # when BPS collapses AND ABS hasn't grown from entry — coil didn't commit.
        # Only WEAK sessions: ACTIVE (NY_PRIME) 7W/0L — no intervention warranted.
        if (last_entry_reason == "PAQ_STRUCT_GATE"
                and not _paq_struct_derisked
                and not harvest_s1_done
                and last_entry_contracts > 0
                and last_entry_reads == 2           # exactly poll 2
                and get_session_label() in ("BTC_DEEP_NIGHT", "ASIA_OPEN")):
            _bps_collapsed = (
                (last_side == "yes" and live_bps <= 0) or
                (last_side == "no"  and live_bps >= 0)
            )
            _abs_stagnant = (abs_pct_for_risk is not None
                             and float(abs_pct_for_risk) <= (last_entry_abs * 1.3))
            if _bps_collapsed and _abs_stagnant:
                _early_qty = max(1, round(last_entry_contracts * 0.33))
                print(f"          → PAQ_STRUCT_EARLY_DERISK | WEAK session BPS collapsed at poll 2 | "
                      f"BPS {live_bps:+.1f} ABS {float(abs_pct_for_risk):.3f}% | exiting {_early_qty}/{last_entry_contracts}c")
                _early_ob = get_orderbook(ticker)
                _early_result = execute_rapid_stop_loss_exit(
                    ticker=ticker, side=last_side,
                    yes_price=yes_price, no_price=no_price,
                    reason_label="PAQ_STRUCT_EARLY_DERISK",
                    ob_snapshot=_early_ob,
                    max_contracts=_early_qty,
                    ladder_override=[Decimal("0.00"), Decimal("0.01"), Decimal("0.02"), Decimal("0.03")]
                )
                if _early_result["status"] in ("full_exit", "partial_exit"):
                    _ed_qty = int(_early_result["filled_qty"])
                    _ed_px  = float(_early_result["avg_exit_price"] or 0)
                    _ed_pnl = (_ed_px - float(last_entry_price)) * _ed_qty if last_entry_price else 0
                    print(f"          → PAQ_STRUCT_EARLY_DERISKED | {_ed_qty}c @ {_ed_px:.4f} | est {_ed_pnl:+.2f} | {last_entry_contracts - _ed_qty}c remaining")
                    _paq_struct_derisked = True  # prevent double-derisk on poll 4
                elif _early_result["status"] == "unfilled":
                    if _early_result.get("note") == "BDI_ZERO":
                        _any_stop_fired = False  # v246: hold — allow re-evaluation next poll
                    else:
                        print(f"          → PAQ_STRUCT_EARLY_DERISK UNFILLED | book thin")

        # ── PAQ_EARLY_CONS 250s hard exit (v217) ─────────────────────────────
        # v216: initial build at 200s. v217: raised to 250s based on full dataset.
        # Simulation across 28 trades (3/23–3/25):
        #   250s exit alone:              delta +$5.88 vs hold
        #   200s exit alone:              delta +$4.03 vs hold
        #   250s exit + 450s entry min:   delta +$14.59 vs hold (best combo)
        # 250s captures more of the loss-prevention window while still preserving
        # winning trades that are already at 0.97+ at 250s (exit at a profit).
        # Standard 4-rung ladder — mid-book fills at 250s are viable.
        if (last_entry_reason == "PAQ_EARLY_CONS"
                and last_entry_contracts > 0
                and not _any_stop_fired
                and 235 <= seconds_left <= 265):
            _held_px_cons = float(yes_price if last_side == "yes" else no_price)
            _entry_px_cons = float(last_entry_price) if last_entry_price else _held_px_cons
            _cons_pnl_est = (_held_px_cons - _entry_px_cons) * last_entry_contracts
            print(f"          → CONS_250S_EXIT | {int(seconds_left)}s | held {_held_px_cons:.4f} | entry {_entry_px_cons:.4f} | est {_cons_pnl_est:+.2f} | exiting {last_entry_contracts}c")
            _cons_ob = get_orderbook(ticker)
            _cons_result = execute_rapid_stop_loss_exit(
                ticker=ticker, side=last_side,
                yes_price=yes_price, no_price=no_price,
                reason_label="CONS_250S_EXIT",
                ob_snapshot=_cons_ob,
                max_contracts=last_entry_contracts,
                ladder_override=[Decimal("0.00"), Decimal("0.01"), Decimal("0.02"), Decimal("0.03")]
            )
            if _cons_result["status"] in ("full_exit", "partial_exit"):
                _cq  = int(_cons_result["filled_qty"])
                _cpx = float(_cons_result["avg_exit_price"] or 0)
                _cpnl = (_cpx - _entry_px_cons) * _cq
                print(f"          → CONS_250S_EXITED | {_cq}c @ {_cpx:.4f} | est {_cpnl:+.2f}")
                _any_stop_fired = True
            elif _cons_result["status"] == "unfilled":
                if _cons_result.get("note") == "BDI_ZERO":
                    _any_stop_fired = False  # v246: hold — allow re-evaluation next poll
                else:
                    print(f"          → CONS_250S_EXIT UNFILLED | book thin at {_held_px_cons:.4f} — holding, normal stops continue")

        # ── TWO-STAGE CHOP-WATCH GATE ────────────────────────────────────────────
        # Stage 1 (admission filter): adverse BPS + abs >= chop floor starts the window.
        # Stage 2 (persistence decision): PAQ trend over next 2-3 polls decides outcome.
        #
        # CHOP_RECOVERY      → hold confidently, dip is noise
        # REVERSAL_PERSISTENT → let normal stop logic proceed to exit
        #
        # Low-abs adverse BPS never enters the review pathway at all — it's noise.
        global _chop_watch_active, _chop_watch_polls, _chop_watch_paq_low
        global _chop_dip_price, _chop_watch_bps_start

        CHOP_ABS_FLOOR      = 0.04   # below this: noise, ignore adverse BPS entirely
        CHOP_RECOVERY_PAQ   = 3      # PAQ must reach this to confirm chop recovery
        REVERSAL_PAQ_POLLS  = 3      # PAQ must stay <= 1 this many polls to confirm reversal

        _live_abs  = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
        _live_paq  = prev_paq_score if prev_paq_score is not None else 0
        _curr_held = yes_price if last_side == "yes" else no_price

        # Check if adverse BPS is present
        _adverse_bps = (last_side == "yes" and live_bps <= -1) or                        (last_side == "no"  and live_bps >=  1)

        if _chop_watch_active:
            # ── Stage 2: PAQ persistence decision ────────────────────────────
            _chop_watch_polls += 1

            if _live_paq >= CHOP_RECOVERY_PAQ:
                # CHOP_RECOVERY requires both PAQ recovered AND BPS easing.
                _bps_easing = (last_side == "yes" and live_bps > _chop_watch_bps_start) or                               (last_side == "no"  and live_bps < _chop_watch_bps_start)
                if not _bps_easing:
                    _last_entry_block = f"→ CHOP {last_side.upper()} watch {_chop_watch_polls}"
                else:
                    _chop_watch_active  = False
                    _chop_watch_polls   = 0
                    _chop_watch_paq_low = 0
                    _chop_dip_price     = None

            elif _live_paq <= 1:
                _chop_watch_paq_low += 1
                _last_entry_block = f"→ CHOP {last_side.upper()} LOW {_chop_watch_paq_low}/{REVERSAL_PAQ_POLLS}"
                if _chop_watch_paq_low >= REVERSAL_PAQ_POLLS:
                    print(f"          → REVERSAL_PERSISTENT | {last_side.upper()} | proceeding to exit")
                    _chop_watch_active  = False
                    _chop_watch_polls   = 0
                    _chop_watch_paq_low = 0
                    _chop_dip_price     = None
            else:
                _last_entry_block = f"→ CHOP {last_side.upper()} watch {_chop_watch_polls}"

            # ── v249: CHOP_TIMEOUT_UNDERWATER — third escape path ─────────────
            # The two existing exit conditions (PAQ recovery or PAQ collapse)
            # fail when a genuine high-conviction reversal arrives: adverse BPS
            # stays elevated, PAQ stays mid-range (2-4), and CHOP simply runs
            # until expiry. Confirmed failure: 4/5 bps_premium NO @ 0.72 ran
            # 15 watches from 314s to settlement with no exit path found.
            #
            # Fire when ALL THREE hold:
            #   1. CHOP has persisted >= 8 polls (enough time for recovery/reversal)
            #   2. Position is underwater at mark (held-side px < entry price)
            #   3. Adverse BPS is STILL present (market still leaning against position)
            # Condition 3 prevents the timeout from killing positions where price
            # is temporarily underwater but BPS has already eased — those are
            # genuine chop situations where the watch is still doing its job.
            # Data: simulation across 9 sessions — 6 long-CHOP events, all 3
            # underwater-at-poll8 losers had adverse BPS throughout.
            #
            # Resolution: disarm CHOP watch and fall through to normal stop engine.
            # Not a bespoke exit — uses the existing PAQ/BPS/trail/velocity logic.
            # This ensures the correct stop family handles the exit, not a one-off path.
            if _chop_watch_active and _chop_watch_polls >= 8:
                _chop_held_now = float(yes_price if last_side == "yes" else no_price)
                _chop_entry_px = float(last_entry_price) if last_entry_price else _chop_held_now
                _chop_underwater = _chop_held_now < _chop_entry_px
                _chop_still_adverse = _adverse_bps  # BPS still opposing the position
                if _chop_underwater and _chop_still_adverse:
                    _chop_pnl_at_mark = (_chop_held_now - _chop_entry_px) * last_entry_contracts
                    print(
                        f"          → CHOP_TIMEOUT_UNDERWATER | {last_side.upper()} | "
                        f"polls {_chop_watch_polls} | held {_chop_held_now:.4f} < entry {_chop_entry_px:.4f} | "
                        f"est {_chop_pnl_at_mark:+.2f} | BPS {live_bps:+.1f} still adverse | "
                        f"disarming CHOP → handing to stop engine"
                    )
                    _chop_watch_active  = False
                    _chop_watch_polls   = 0
                    _chop_watch_paq_low = 0
                    _chop_dip_price     = None
                    # Fall through — do NOT return early; stop engine evaluates this poll

        elif _adverse_bps and not _paq_stop_fired:
            # ── Stage 1: admission filter ─────────────────────────────────────
            # v175: Compound conviction gate — skip chop watch when:
            #   A) BPS >= 3 opposing (high-PAQ reversal like 212230-30)
            #   B) BPS >= 2 opposing AND PAQ <= 2 (degraded structure like 212115-15)
            # Either condition = real reversal, not noise. Let stops run.
            # Chop watch only opens when BPS=1 adverse, or BPS=2 with PAQ>=3.
            #
            # Evidence:
            #   212230-30: BPS+3 to +6, PAQ 4-6 → gate A fires at first BPS>=3 poll
            #   212115-15: BPS=-2, PAQ=1 at 19:08:18 → gate B fires, saves $6.24
            _bps_magnitude = abs(live_bps)
            _gate_a = _bps_magnitude >= 3                        # high BPS regardless of PAQ
            _gate_b = _bps_magnitude >= 2 and _live_paq <= 2    # moderate BPS + degraded PAQ
            _skip_chop = _gate_a or _gate_b
            if _live_abs < CHOP_ABS_FLOOR:
                pass  # below noise floor — ignore
            elif _skip_chop:
                # Conviction reversal — skip chop watch, normal stops run
                _gate_label = "A" if _gate_a else "B"
                _last_entry_block = f"→ REVERSAL_STRONG [{_gate_label}] BPS {live_bps:+.1f} PAQ {_live_paq}"
                pass  # fall through to stop engine
            else:
                # Weak signal (BPS 1-2 with PAQ>=3) — genuine ambiguity, watch it
                _chop_watch_active    = True
                _chop_watch_polls     = 0
                _chop_watch_paq_low   = 0
                _chop_dip_price       = _curr_held
                _chop_watch_bps_start = live_bps
                _last_entry_block = f"→ CHOP {last_side.upper()} OPEN"

        # If chop-watch is still active (not yet resolved), skip normal stop logic
        # to avoid racing between the watch window and the stop engine.
        # v211: PAQ_STRUCT_DERISK is exempt from this gate — CHOP and DERISK serve
        # different jobs. CHOP watches for reversal persistence. DERISK checks whether
        # the coiling thesis ever committed. On a PAQ_STRUCT_GATE trade that moves
        # adversely early, CHOP fires first and was suppressing DERISK entirely.
        # March 25 Loss 1 (YES@0.53 -$7.95): CHOP OPEN fired at poll 2, DERISK
        # never evaluated at poll 4, 15c held to zero settlement.
        # Fix: DERISK runs on schedule regardless of CHOP state. CHOP still gates
        # the velocity/flip/trail stop engine — that interaction is unchanged.
        if _chop_watch_active:
            # PAQ_STRUCT_DERISK: allow evaluation even during chop-watch
            if (last_entry_reason == "PAQ_STRUCT_GATE"
                    and not _paq_struct_derisked
                    and not harvest_s1_done
                    and last_entry_contracts > 0
                    and last_entry_reads >= 4):
                _live_abs_chop = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
                _should_derisk_chop, _derisk_note_chop = paq_struct_continuity_check(last_entry_abs, _live_abs_chop)
                if _should_derisk_chop:
                    _paq_struct_derisked = True
                    _derisk_qty_chop = max(1, round(last_entry_contracts * 0.50))
                    print(f"          → PAQ_STRUCT_DERISK | {_derisk_note_chop} | exiting {_derisk_qty_chop}/{last_entry_contracts}c [during CHOP]")
                    _derisk_ob_chop = get_orderbook(ticker)
                    _derisk_res_chop = execute_rapid_stop_loss_exit(
                        ticker=ticker, side=last_side,
                        yes_price=yes_price, no_price=no_price,
                        reason_label="PAQ_STRUCT_DERISK",
                        ob_snapshot=_derisk_ob_chop,
                        max_contracts=_derisk_qty_chop,
                        ladder_override=[Decimal("0.00"), Decimal("0.01"), Decimal("0.02"), Decimal("0.03")]
                    )
                    if _derisk_res_chop["status"] in ("full_exit", "partial_exit"):
                        _d_qty_c = int(_derisk_res_chop["filled_qty"])
                        _d_px_c  = float(_derisk_res_chop["avg_exit_price"] or 0)
                        _d_pnl_c = (_d_px_c - float(last_entry_price)) * _d_qty_c if last_entry_price else 0
                        print(f"          → PAQ_STRUCT_DERISKED | {_d_qty_c}c @ {_d_px_c:.4f} | est {_d_pnl_c:+.2f} | {last_entry_contracts - _d_qty_c}c remaining")
                    elif _derisk_res_chop["status"] == "unfilled":
                        if _derisk_res_chop.get("note") == "BDI_ZERO":
                            _any_stop_fired = False  # v246: hold — allow re-evaluation next poll
                            _paq_struct_derisked = False  # allow retry
                        else:
                            print(f"          → PAQ_STRUCT_DERISK UNFILLED | book thin — holding full position")
                            _paq_struct_derisked = False  # allow retry next poll
            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

        # ── CONTRACT PRICE VELOCITY — parallel reversal trigger ────────────
        # Near strike, BTC abs can be tiny while the contract reprices violently.
        # In that regime, the contract IS the leading signal — not BTC.
        # This trigger fires independently of abs% when price velocity confirms
        # a genuine structural flip regardless of what BTC is doing.
        #
        # Evidence: 03:56:31 YES +0.16 in 1 poll (abs=0.044%), 03:57:05 YES +0.22
        # (abs=0.014%) — every abs-gated stop suppressed while NO collapsed.
        #
        # Gate: held-side drops >= 0.15 in 1 poll (or >= 0.20 across 2 polls)
        #       AND opposite-side structure rising (PAQ>=4 or CTX/STATE 2/2)
        #       AND position still mid-book (held >= 0.15 — not already at book edge)
        _price_vel_stop = False
        _vel_label      = ""
        _vel_predrop_px = None
        _vel_partial    = False   # default: full exit unless intact-structure fires
        _vel_intact     = False
        _vel_harvest_ratio = 0.0
        _vel_partial_contracts = None
        if last_side and last_entry_contracts > 0 and not _paq_stop_fired:
            _held_px_now = yes_price if last_side == "yes" else no_price
            _opp_px_now  = no_price  if last_side == "yes" else yes_price
            _hist_held   = list(price_history[ticker]["yes" if last_side == "yes" else "no"])
            _opp_strong  = (prev_paq_score is not None and prev_paq_score >= 4) or                            (prev_paq_ctx == 2 and prev_paq_state == 2)
            if _held_px_now is not None and float(_held_px_now) >= 0.12:
                if len(_hist_held) >= 2:
                    _vel_1poll = float(_hist_held[-2]) - float(_held_px_now)
                    # Extreme tier: >= 0.35 single-poll drop = binary contract resolution
                    # No structure confirmation needed — a 0.49 drop IS the confirmation.
                    # Data: 04:28:44 YES=0.80 → 04:28:56 YES=0.31 (drop=0.49), opp_strong=False
                    # suppressed by opp_strong gate. That is too strict for extreme moves.
                    _extreme_vel = _vel_1poll >= 0.35 and float(abs_pct_for_risk or 0) >= 0.01
                    # Moderate tier: >= 0.15 still needs structure confirmation (chop filter)
                    _moderate_vel = _vel_1poll >= 0.15 and _opp_strong
                    if _extreme_vel:
                        _price_vel_stop = True
                        _vel_label = f"PRICE_VEL_EXTREME | drop {_vel_1poll:.3f} in 1 poll"
                    elif _moderate_vel:
                        _price_vel_stop = True
                        _vel_label = f"PRICE_VEL_1P | drop {_vel_1poll:.3f} in 1 poll"
                # Two-poll velocity: held dropped >= 0.20 across 2 polls (still needs structure)
                if not _price_vel_stop and len(_hist_held) >= 3:
                    _vel_2poll = float(_hist_held[-3]) - float(_held_px_now)
                    if _vel_2poll >= 0.20 and _opp_strong:
                        _price_vel_stop = True
                        _vel_label = f"PRICE_VEL_2P | drop {_vel_2poll:.3f} in 2 polls"
            if _price_vel_stop:
                _drop_amt = _vel_1poll if "PRICE_VEL_1P" in _vel_label or "PRICE_VEL_EXTREME" in _vel_label else \
                            _vel_2poll if "PRICE_VEL_2P" in _vel_label else 0.0
                _vel_predrop_px = Decimal(str(round(float(_held_px_now) + _drop_amt, 2)))
                print(
                    f"          → CONTRACT VELOCITY | "
                    f"{last_side.upper()} | {_vel_label} | "
                    f"held {float(_held_px_now):.4f} | pre-drop {float(_vel_predrop_px):.4f} | PAQ {prev_paq_score} | {int(seconds_left)}s"
                )

        # ── PAQ stop: PAQ==0 / PAQ1_BPS_LOST / PAQ_AGG_OPP_BPS / FLIP_EMERGENCY
        _trade_age = (dt.datetime.now(dt.timezone.utc) - last_entry_time).total_seconds() if last_entry_time else 0

        # C: PAQ_EARLY_AGG opposite-BPS stop (trade_age>=180s OR time_left<=360s)
        # PAQ_AGG_OPP_BPS: split by PAQ quality + persistence requirement
        #
        # PAQ <= 3 (weak): BPS threshold ±1, fires immediately (1 read)
        #   Structure is soft — one credible opposite read is enough.
        # PAQ >= 4 (moderate/strong): BPS threshold ±2, requires 2 consecutive reads
        #   Structure still intact — force market to PROVE the reversal before stopping.
        #   One shove in the wrong direction is not proof. Two is.
        _paq_agg_bps_stop = False
        # Age gate: 180s minimum prevents noise exits immediately after entry.
        # Exception: HIGH_ABS (>= 0.08%) bypasses the age gate entirely.
        # A genuine BTC reversal at 60s into a trade is real signal — not noise —
        # and should be detected while the contract is still mid-book and IOC
        # fills are viable. The age gate was noise protection; abs already provides that.
        # PAQ_HARD_BPS_FLIP (stronger BPS threshold) already has no age gate.
        _agg_abs_early = metrics.get("abs_pct", 0.0) if metrics else 0.0
        _high_abs_early = _agg_abs_early >= 0.08
        if (last_entry_reason == "PAQ_EARLY_AGG"
                and not _paq_stop_fired
                and (_trade_age >= 180 or seconds_left <= 360 or _high_abs_early)):
            _paq_agg_paq = prev_paq_score if prev_paq_score is not None else 0
            _paq_agg_strong = (_paq_agg_paq >= 4)
            _paq_agg_bps_thresh    = -2 if _paq_agg_strong else -1
            _paq_agg_bps_thresh_no =  2 if _paq_agg_strong else  1
            # Moderate-abs zone (0.04-0.08%): always require 2 reads regardless of PAQ
            # Single BPS tick against position in moderate abs is not proof of reversal
            # HIGH_ABS (>=0.08%): use PAQ-quality-based reads (strong=2, weak=1)
            # abs gate value — must be defined before _reads_needed uses it
            _agg_abs = metrics.get("abs_pct", 0.0) if metrics else 0.0
            _reads_needed = 2 if (_paq_agg_strong or _agg_abs < 0.08) else 1

            # YES side — abs gate: require genuine BTC movement before counting opposition
            if last_side == "yes" and yes_price < Decimal("0.97"):
                if live_bps <= _paq_agg_bps_thresh and _agg_abs >= 0.04:
                    _paq_agg_opp_yes_cnt += 1
                    if _paq_agg_opp_yes_cnt >= _reads_needed:
                        _paq_agg_bps_stop = True
                else:
                    _paq_agg_opp_yes_cnt = 0  # streak reset (no abs or BPS improved)
            else:
                _paq_agg_opp_yes_cnt = 0

            # NO side — abs gate: require genuine BTC movement before counting opposition
            if last_side == "no" and no_price < Decimal("0.97"):
                if live_bps >= _paq_agg_bps_thresh_no and _agg_abs >= 0.04:
                    _paq_agg_opp_no_cnt += 1
                    if _paq_agg_opp_no_cnt >= _reads_needed:
                        _paq_agg_bps_stop = True
                else:
                    _paq_agg_opp_no_cnt = 0  # streak reset
            else:
                _paq_agg_opp_no_cnt = 0

        # D: late flip emergency stop
        # Suppressed when secs_left < 120: at near-settlement the losing-side
        # book has no buyers. Both FLIP_EMERGENCY attempts at <120s in 3/17
        # exhausted all 5 ladder steps without a single fill.
        # Also suppressed when abs < 0.02%: live evidence (21:57 unfilled stop)
        # showed FLIP_EMERGENCY firing at abs=0.004% converted a recoverable
        # position into a near-full loss on pure noise. Require genuine BTC movement
        # before treating a market price reversal as a real invalidation signal.
        _current_abs = metrics.get("abs_pct", 0.0) if metrics else 0.0
        _flip_structural = (flip_logged_ticker == ticker
                            and 120 <= seconds_left <= 300
                            and last_entry_contracts > 0
                            and not _paq_stop_fired)
        # abs gate: require genuine BTC movement before treating contract flip as real
        # Live evidence (21:57 unfilled stop, abs=0.004%): low-abs FLIP_EMERGENCY
        # converted recoverable position into near-full loss on noise.
        _flip_emergency = _flip_structural and _current_abs >= 0.02
        if _flip_structural and not _flip_emergency:
            # Log suppression so we can count post-session whether these were real reversals
            print(f"          → FLIP SUPPRESSED | abs {_current_abs:.3f}% < 0.02% | {int(seconds_left)}s")

        # Primary PAQ stop
        _signed_pct = metrics.get("signed_pct") if metrics else None
        _paq_stop, _paq_label = check_paq_stop_loss(live_bps, yes_price, no_price, _signed_pct, seconds_left, metrics=metrics)

        if _paq_agg_bps_stop: _paq_stop, _paq_label = True, "PAQ_AGG_OPP_BPS"
        if _flip_emergency:    _paq_stop, _paq_label = True, "FLIP_EMERGENCY"
        if _price_vel_stop:
            _paq_stop  = True
            _paq_label = "CONTRACT_VELOCITY"
            # Environment-aware velocity scope:
            # In LOW_VOLUME or thin-book conditions, a one-poll shock is more likely
            # a vacuum flush than genuine reversal — especially when BCDP is still
            # strongly persistent and BPS has not flipped.
            # In that case: partial exit (33%) instead of full liquidation.
            # Full exit still fires when BCDP < 4 (persistence degraded)
            # or BPS has already flipped against the held side.
            _vel_bps_onside = (
                (last_side == "yes" and live_bps >= 0) or
                (last_side == "no"  and live_bps <= 0)
            )
            _vel_harvest_ratio = (
                harvest_total_sold / last_entry_contracts
                if last_entry_contracts > 0 else 0.0
            )
            _vel_derisked = _vel_harvest_ratio >= 0.40
            # v158: intact-structure partial — no longer requires LOW_VOLUME env
            # Vacuum flushes occur in any regime. The signal is structure, not env.
            _vel_intact = (
                _vel_harvest_ratio == 0.0
                and _vel_bps_onside
                and _bcdp_clean
                and _bcdp >= 3
                and not _vel_derisked
            )
            # Legacy env-aware partial still active for thin-book de-risked cases
            _vel_env_thin = (_regime in ("LOW_VOLUME",) or _book_env in ("LOW_VOLUME",))
            _vel_env_partial = _vel_env_thin and _bcdp >= 4 and _vel_bps_onside and not _vel_derisked
            _vel_partial = _vel_intact or _vel_env_partial
            if _vel_partial:
                _paq_label = "CONTRACT_VELOCITY_PARTIAL"

        if _paq_stop and not _paq_stop_fired:
            _paq_stop_fired = True   # E: latch — no repeated restarts this position
            # Pre-classify by abs% at trigger (proxy — resolved to 4-way label after fill)
            _abs_at_stop = metrics.get("abs_pct", 0) if metrics else 0
            _high_abs    = _abs_at_stop >= 0.08   # likely genuine reversal vs chop
            _vel_ratio_note = f" | harvested {_vel_harvest_ratio:.0%}" if _paq_label in ("CONTRACT_VELOCITY","CONTRACT_VELOCITY_PARTIAL") else ""
            print(f"          → STOP TRIGGER | {_paq_label} | {last_side.upper()} | PAQ {prev_paq_score} | BPS {live_bps:+.1f} | abs {_abs_at_stop:.3f}% | {int(seconds_left)}s{_vel_ratio_note}")
            _stop_ob_snap = get_orderbook(ticker)
            _vel_anchor = _vel_predrop_px if _paq_label in ("CONTRACT_VELOCITY", "CONTRACT_VELOCITY_PARTIAL") else None
            # Partial velocity: cap exit at 33% of position (round up to min 1c)
            _vel_partial_contracts = max(1, round(get_live_position_contracts(ticker) * 0.33)) if _vel_partial else None
            _vel_ladder = None  # full ladder unless partial
            if _vel_partial:
                # Tighter ladder for partial — we want to fill, not chase
                _vel_ladder = [Decimal("0.00"), Decimal("0.02"), Decimal("0.04"), Decimal("0.07")]
                _vel_partial_tag = "INTACT" if _vel_intact else f"ENV {_regime}/{_book_env}"
                print(f"          → STOP PARTIAL_VEL | {_vel_partial_tag} | BCDP {_bcdp} | BPS {live_bps:+.1f} | harvested {_vel_harvest_ratio:.0%} | cap {_vel_partial_contracts}c")
            result = execute_rapid_stop_loss_exit(
                ticker=ticker,
                side=last_side,
                yes_price=yes_price,
                no_price=no_price,
                reason_label=_paq_label,
                ladder_override=_vel_ladder,
                metrics=metrics,
                market=market,
                ob_snapshot=_stop_ob_snap,
                pre_drop_anchor=_vel_anchor,
                max_contracts=_vel_partial_contracts
            )
            if result["status"] in ("full_exit", "partial_exit"):
                filled_qty = int(result["filled_qty"])
                avg_exit_price = result["avg_exit_price"]
                remaining_qty  = int(result["remaining_qty"])
                if filled_qty > 0 and avg_exit_price is not None:
                    exit_px  = float(avg_exit_price)
                    entry_px = float(last_entry_price)
                    est_pnl  = (exit_px - entry_px) * filled_qty
                    pnl_text = f"+${est_pnl:.2f}" if est_pnl >= 0 else f"-${abs(est_pnl):.2f}"
                    print(f"          → STOP FILLED | {last_side.upper()} | {_paq_label} | {filled_qty}c @ {exit_px:.4f} | {pnl_text}")
                    _paq_stop_remaining = max(0, int(result.get("remaining_qty", 0)))
                    send_telegram_alert(
                        f"STOPLOSS | {last_side.upper()} | "
                        f"{filled_qty}x @ {avg_exit_price:.2f} | "
                        f"entry {float(last_entry_price):.2f} | "
                        f"{_paq_stop_remaining}x remaining"
                    )
                if filled_qty > 0 and avg_exit_price is not None:
                    update_pending_trade_exits(ticker, "stop", filled_qty, float(avg_exit_price))
                last_entry_contracts = remaining_qty if result["status"] == "partial_exit" else 0
                last_entry_reason    = None if remaining_qty <= 0 else last_entry_reason
                # v229: Arm tail-risk mode when partial velocity stop fills with remainder
                if result["status"] == "partial_exit" and remaining_qty > 0:
                    _tail_risk_mode     = True
                    _tail_risk_entry_px = float(last_entry_price) if last_entry_price else None
                if remaining_qty <= 0:
                    print_full_exit_settlement(ticker)  # WIN/LOSS SETTLED + TICKER CLOSE feed
                    pending_trades.pop(ticker, None)
                    save_pending_trades()
                    clear_live_state_file()
                    clear_live_position_state()
                return FAST_POLL
            elif result.get("note") == "NO_POSITION":
                # Control-plane failure: stop fired but position not found
                # (already logged by execute_rapid_stop_loss_exit as STOP BLOCKED)
                print(f"          → STOP ERROR | {_paq_label} | state mismatch")
                # state mismatch logged to console only
            elif result.get("note") != "BDI_ZERO":
                # BDI_ZERO already logged as STOP HOLD — don't double-print
                print(f"          → STOP UNFILLED | {last_side.upper()} | {_paq_label} | book thin")
                send_telegram_alert(f"STOPLOSS | {last_side.upper()} | Failed to fill")
            else:
                # v245: BDI_ZERO hold — position still open, clear _any_stop_fired so
                # all stop mechanisms can re-evaluate on next poll (trail, BPS, non-BPS).
                # Without this reset, _any_stop_fired=True (set inside execute) permanently
                # blocks trail/BPS/non-BPS stops after any PAQ stop hold, leaving the
                # position unmonitored until settlement.
                _any_stop_fired = False

        # ── DIRECTIONAL-family stop ───────────────────────────────────────
        bps_stop, stop_bps, bps_opp_count = check_bps_stop_loss(ticker, strike, abs_pct_for_risk)
        if bps_stop and not _any_stop_fired:
            _stop_ob_snap = get_orderbook(ticker)
            result = execute_rapid_stop_loss_exit(
                ticker=ticker,
                side=last_side,
                yes_price=yes_price,
                no_price=no_price,
                reason_label=f"BPS_{stop_bps:+.1f}",
                metrics=metrics,
                market=market,
                ob_snapshot=_stop_ob_snap
            )
            if result["status"] in ("full_exit", "partial_exit"):
                filled_qty = int(result["filled_qty"])
                avg_exit_price = result["avg_exit_price"]
                remaining_qty = int(result["remaining_qty"])
                exit_note = result["note"]
                if filled_qty > 0 and avg_exit_price is not None:
                    exit_px = float(avg_exit_price)
                    entry_px = float(last_entry_price)
                    est_pnl = (exit_px - entry_px) * filled_qty
                    pnl_text = f"+${est_pnl:.2f}" if est_pnl >= 0 else f"-${abs(est_pnl):.2f}"
                    print(f"          → STOP FILLED | {last_side.upper()} | BPS {stop_bps:+.1f} | {filled_qty}c @ {exit_px:.4f} | {pnl_text}")
                    _dir_stop_remaining = max(0, int(remaining_qty))
                    send_telegram_alert(
                        f"STOPLOSS | {last_side.upper()} | "
                        f"{filled_qty}x @ {exit_px:.2f} | "
                        f"entry {float(last_entry_price):.2f} | "
                        f"{_dir_stop_remaining}x remaining"
                    )
                    if filled_qty > 0:
                        update_pending_trade_exits(ticker, "stop", filled_qty, exit_px)
                    last_entry_contracts = remaining_qty
                    if remaining_qty <= 0:
                        last_exit_side  = last_side
                        last_exit_time  = dt.datetime.now(dt.timezone.utc)
                        last_exit_price = Decimal(str(exit_px))
                        print_full_exit_settlement(ticker)  # WIN/LOSS SETTLED + TICKER CLOSE feed
                        pending_trades.pop(ticker, None)
                        save_pending_trades()
                        clear_live_state_file()
                        clear_live_position_state()
                    return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL
            else:
                # v245: BDI_ZERO hold — reset _any_stop_fired so trail/non-BPS stops
                # can re-evaluate next poll.
                if result.get("note") == "BDI_ZERO":
                    _any_stop_fired = False
                else:
                    print(f"          → STOP UNFILLED | {last_side.upper()} | BPS {stop_bps:+.1f} | book thin")
                    send_telegram_alert(f"STOPLOSS | {last_side.upper()} | Failed to fill")

        # ── PROFIT-PROTECTION (trail stop — after hard invalidation) ────────
        _trail_fire, _trail_label, _trail_trigger_px = check_profit_protection(
            yes_price, no_price, seconds_left, live_bps, last_entry_reads, last_entry_time,
            trade_age_secs=_trade_age
        )

        # ── Partial profit harvest ─────────────────────────────────────
        # Proactive inventory reduction while book is still liquid.
        # Runs before trail exit logic — if we harvest some contracts,
        # the remaining position is smaller and easier to manage.
        # v214/v215: PHI boost — when thesis health < 40, force larger
        # harvest tranche immediately rather than waiting for standard trigger.
        if not _trail_fire and last_entry_contracts > 1:
            _harv_fire, _harv_stage, _harv_count = check_partial_harvest(
                yes_price, no_price, seconds_left, live_bps,
                last_entry_price, last_entry_contracts,
                trade_age_secs=_trade_age
            )
            # PHI boost: override tranche upward when health is degrading
            if _phi_harvest_boost and not _harv_fire:
                _held_px_phi = float(yes_price if last_side == "yes" else no_price)
                # Only fire if price has moved enough to not be underwater
                if (last_side == "yes" and float(yes_price) > float(last_entry_price) * 0.92) or \
                   (last_side == "no"  and float(no_price)  > float(last_entry_price) * 0.92):
                    _harv_fire  = True
                    _harv_stage = "PHI_DECAY"
                    _harv_count = max(1, round(last_entry_contracts * 0.40))
                    print(f"          → PHI HARVEST BOOST | PHI{_phi} | {last_side.upper()} | boosted tranche {_harv_count}c")
            if _harv_fire and _harv_count > 0:
                _held_for_harv = yes_price if last_side == "yes" else no_price
                _h_filled, _h_px = execute_partial_harvest(
                    ticker, last_side, yes_price, no_price,
                    _harv_stage, _harv_count, _held_for_harv,
                    seconds_left=seconds_left, market=market
                )
                if _h_filled > 0:
                    last_entry_contracts = max(0, last_entry_contracts - _h_filled)
        if _trail_fire and not _any_stop_fired:
            held_px_now = float(yes_price if last_side == "yes" else no_price)
            print(f"          → TRAIL STOP | {_trail_label} | {last_side.upper()} | held {held_px_now:.4f} | entry {float(last_entry_price):.4f}")
            # Strategy 3 uses aggressive ladder offsets — prioritise fill over price
            _ladder_override = TRAIL_S3_LADDER_OFFSETS if _trail_label == "TIME_DECAY_EXIT" else None
            _stop_ob_snap = get_orderbook(ticker)
            result = execute_rapid_stop_loss_exit(
                ticker=ticker,
                side=last_side,
                yes_price=yes_price,
                no_price=no_price,
                reason_label=_trail_label,
                ladder_override=_ladder_override,
                metrics=metrics,
                market=market,
                ob_snapshot=_stop_ob_snap
            )

            if result["status"] in ("full_exit", "partial_exit"):
                filled_qty = int(result["filled_qty"])
                avg_exit_price = result["avg_exit_price"]
                remaining_qty  = int(result["remaining_qty"])
                if filled_qty > 0 and avg_exit_price is not None:
                    exit_px   = float(avg_exit_price)
                    entry_px  = float(last_entry_price)
                    est_pnl   = (exit_px - entry_px) * filled_qty
                    pnl_text  = f"+${est_pnl:.2f}" if est_pnl >= 0 else f"-${abs(est_pnl):.2f}"
                    price_delta = round(exit_px - _trail_trigger_px, 4)
                    print(
                        f"TRAIL EXIT | {last_side.upper()} | {_trail_label} | filled {filled_qty} | "
                        f"trigger {_trail_trigger_px:.4f} | avg_exit {exit_px:.4f} | "
                        f"delta {price_delta:+.4f} | est {pnl_text} | {result['note']}"
                    )
                    send_telegram_alert(
                        f"STOPLOSS | {last_side.upper()} | "
                        f"{filled_qty}x @ {exit_px:.2f} | "
                        f"entry {float(last_entry_price):.2f} | "
                        f"{int(result['remaining_qty'])}x remaining"
                    )
                    # Stage 3 harvest: set block state to prevent same-direction re-entry
                    if _trail_label == "TRAIL_EXIT_STAGE3":
                        trail_harvested_ticker  = ticker
                        trail_harvested_side    = last_side
                        trail_harvested_time    = dt.datetime.now(dt.timezone.utc)
                        trail_harvested_exit_px = Decimal(str(exit_px))
                        print(
                            f"{dt.datetime.now():%H:%M:%S} | STAGE3 HARVEST LOCK | "
                            f"{ticker} | {last_side.upper()} | exit {exit_px:.4f} | "
                            f"same-dir re-entry blocked until price resets"
                        )
                if filled_qty > 0 and avg_exit_price is not None:
                    update_pending_trade_exits(ticker, "stop", filled_qty, float(avg_exit_price))
                last_entry_contracts = remaining_qty if result["status"] == "partial_exit" else 0
                if remaining_qty <= 0:
                    last_exit_side  = last_side
                    last_exit_time  = dt.datetime.now(dt.timezone.utc)
                    last_exit_price = Decimal(str(exit_px)) if 'exit_px' in dir() and exit_px else None
                    print_full_exit_settlement(ticker)  # WIN/LOSS SETTLED + TICKER CLOSE feed
                    pending_trades.pop(ticker, None)
                    save_pending_trades()
                    clear_live_state_file()
                    clear_live_position_state()
                return FAST_POLL
            elif result.get("note") == "BDI_ZERO":
                # v245: trail hold — reset _any_stop_fired so PAQ/BPS/non-BPS stops
                # can re-evaluate next poll instead of being permanently locked out.
                _any_stop_fired = False

        # ── CONFIRMATION-family stop (only if directional did not exit) ───
        if last_entry_reason not in ("bps_premium", "bps_late", "PAQ_PENDING_ALIGN", "PAQ_EARLY_AGG", "PAQ_EARLY_CONS"):
            non_bps_stop, stop_reason, stop_bps = check_non_bps_stop_loss(
                ticker, strike, yes_price, no_price, seconds_left, abs_pct_for_risk
            )
            if non_bps_stop and not _any_stop_fired:
                _stop_ob_snap = get_orderbook(ticker)
                result = execute_rapid_stop_loss_exit(
                    ticker=ticker,
                    side=last_side,
                    yes_price=yes_price,
                    no_price=no_price,
                    reason_label=stop_reason,
                    metrics=metrics,
                    market=market,
                    ob_snapshot=_stop_ob_snap
                )
                if result["status"] in ("full_exit", "partial_exit"):
                    filled_qty = int(result["filled_qty"])
                    avg_exit_price = result["avg_exit_price"]
                    remaining_qty = int(result["remaining_qty"])
                    exit_note = result["note"]
                    if filled_qty > 0 and avg_exit_price is not None:
                        exit_px = float(avg_exit_price)
                        entry_px = float(last_entry_price)
                        est_pnl = (exit_px - entry_px) * filled_qty
                        pnl_text = f"+${est_pnl:.2f}" if est_pnl >= 0 else f"-${abs(est_pnl):.2f}"
                        print(
                            f"CONF STOP-LOSS EXIT | {last_side.upper()} | filled {filled_qty} | "
                            f"remaining {remaining_qty} | avg_exit {exit_px:.4f} | "
                            f"reason {stop_reason} | est {pnl_text} | {exit_note}"
                        )
                        send_telegram_alert(
                            f"STOPLOSS | {last_side.upper()} | "
                            f"{filled_qty}x @ {exit_px:.2f} | "
                            f"entry {float(last_entry_price):.2f} | "
                            f"{int(remaining_qty)}x remaining"
                        )
                        if filled_qty > 0:
                            update_pending_trade_exits(ticker, "stop", filled_qty, exit_px)
                        last_entry_contracts = remaining_qty
                        if remaining_qty <= 0:
                            last_exit_side  = last_side
                            last_exit_time  = dt.datetime.now(dt.timezone.utc)
                            last_exit_price = Decimal(str(exit_px))
                            pending_trades.pop(ticker, None)
                            save_pending_trades()
                            clear_live_state_file()
                            clear_live_position_state()
                        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL
                else:
                    # v245: BDI_ZERO hold — reset _any_stop_fired so all mechanisms
                    # can re-evaluate next poll.
                    if result.get("note") == "BDI_ZERO":
                        _any_stop_fired = False
                    else:
                        print(f"          → CONF STOP FAILED | {result['note']}")
                        send_telegram_alert(f"STOPLOSS | {last_side.upper()} | Failed to fill")

    # ── Re-entry gate ────────────────────────────────────────────────────────
    # Three cases after a position closes on this ticker:
    #
    #   A. Opposite-direction signal: passes gate immediately
    #      (abs >= 0.08%, opposite price 0.35-0.70, BPS confirming, >= 180s left)
    #      → allow immediately. The flip is the whole point of detecting the stop.
    #      Checking this BEFORE same-direction cooldown so the gate is explicitly
    #      flip-aware, not relying on a price threshold heuristic.
    #
    #   B. Same-direction: blocked for 90s AND until price resets >= 0.08
    #      → prevents re-entering a failing thesis before the market clears.
    #      Exception: LATE_REENTRY_BLOCK also applies at <= 120s + price >= 0.90.
    #
    #   C. Position still open (last_exit_side is None): hard block.

    if seconds_left < MIN_SECONDS_LEFT_TO_TRADE or seconds_left > MAX_SECONDS_LEFT_TO_TRADE:
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    _can_reenter = True
    if ticker == last_traded_ticker and last_exit_side is not None and last_exit_time is not None:
        _secs_since_exit = (dt.datetime.now(dt.timezone.utc) - last_exit_time).total_seconds()
        _curr_price = yes_price if last_exit_side == "yes" else no_price
        _price_reset = (last_exit_price is not None
                        and abs(float(_curr_price) - float(last_exit_price)) >= 0.08)

        # Gate: decides whether re-entry is allowed. decide_trade decides what to enter.
        # Opposite-direction signals pass immediately — the normal engine (bps_premium,
        # PAQ_EARLY_AGG) catches every post-stop flip. Data: all 9 recorded post-stop
        # re-entries were at 0.59-0.87, captured by these strategies without a
        # dedicated flip pathway. No separate FLIP_REENTRY strategy needed.
        _opposite_signal = (
            (last_exit_side == "yes" and signed_pct is not None and signed_pct < 0) or
            (last_exit_side == "no"  and signed_pct is not None and signed_pct > 0)
        )
        _late_high_price = seconds_left <= 120 and float(_curr_price) >= 0.90
        if _late_high_price and _secs_since_exit < 300 and not _opposite_signal:
            _can_reenter = False
            print(
                f"LATE_REENTRY_BLOCK | same-side {last_exit_side.upper()} | "
                f"{int(seconds_left)}s left | price {float(_curr_price):.4f} >= 0.90 | "
                f"exit {_secs_since_exit:.0f}s ago"
            )
        elif _secs_since_exit < 90 and not _price_reset and not _late_high_price and not _opposite_signal:
            _can_reenter = False
            print(
                f"COOLDOWN BLOCK | same-side {last_exit_side.upper()} | "
                f"{_secs_since_exit:.0f}s since exit | "
                f"delta {abs(float(_curr_price) - float(last_exit_price)):.3f} (need 0.08)"
            )

    elif ticker == last_traded_ticker and last_exit_side is None:
        _can_reenter = False  # position still being managed

    if not _can_reenter:
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    side, reason = decide_trade(seconds_left, yes_price, no_price, price_history[ticker]["yes"], price_history[ticker]["no"], strike, btc_prices, metrics, ticker)
    if not side:
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    price = yes_price if side == "yes" else no_price

    # NEW: side/strike compatibility gate (Step 4 - kept exactly)
    if not side_matches_contract(side, current_btc, strike):
        log_rejection_once(ticker, seconds_left, side, "side_strike_mismatch")
        print(
            f"{dt.datetime.now():%H:%M:%S} | BLOCKED SIDE/STRIKE MISMATCH | "
            f"side {side.upper()} | BTC {current_btc:.2f} | strike {strike:.2f}"
        )
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # legacy guards removed — hh_hl_early, staircase, tier95_auto folded into confirmation family

    if reason in (
        "bps_premium",
        "bps_late",
        "confirm_standard",
        "confirm_late",
        "PAQ_PENDING_ALIGN",
        "PAQ_EARLY_AGG",
        "PAQ_EARLY_CONS",
        "PAQ_STRUCT_GATE",
        "BCDP_FAST_COMMIT",
    ):
        if abs_drop_too_large(0.095, 3):
            log_rejection_once(ticker, seconds_left, side, f"{reason}_abs_decay_0095")
            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # ── v238: WES Promotion gate ────────────────────────────────────────────
    # When WES is active and a whitelisted main family signals same direction,
    # promote: WES stays in, parent adds contracts up to its normal target,
    # parent family owns exit. Harvest + stop triggers use parent entry price —
    # same thresholds as if standalone main family. WES earns from its cheap
    # entry to wherever the parent exits. No extra gross exposure beyond
    # parent's normal size.
    #
    # Whitelist: bps_premium, PAQ_STRUCT_GATE only.
    # AGG excluded (highest stop-hold rate). BCDP/confirm excluded (not ready).
    #
    # Gate (all must pass):
    #   _wes_active, not already promoted, same side, same ticker
    #   WES entry <= 0.58 (promotable ceiling — data shows losses cluster above)
    #   WES not already S1'd or stopped (targets still set)
    #   parent independently qualifies (reason returned from decide_trade)
    #   seconds_left >= 240
    #   promotion within 300s of WES entry (wes_entry_secs - seconds_left <= 300)
    #   BDI at parent entry >= 50
    #   WES not underwater (held price > wes_entry_px)
    #
    # Rollback: if add-on order fails, restore all WES standalone state.
    _WES_PROMOTE_WHITELIST = ("bps_premium", "PAQ_STRUCT_GATE")
    if (_wes_active
            and not _wes_promoted
            and reason in _WES_PROMOTE_WHITELIST
            and _wes_side is not None and side == _wes_side
            and last_traded_ticker == ticker
            and _wes_entry_px is not None and _wes_entry_px <= 0.58
            and _wes_s1_target is not None and _wes_stop_target is not None
            and seconds_left is not None and float(seconds_left) >= 240
            and _wes_entry_secs is not None
            and (_wes_entry_secs - float(seconds_left)) <= 300):
        # BDI and underwater checks
        _promo_held = float(yes_price if side == "yes" else no_price)
        _promo_bdi  = get_bdi(ticker, side, _promo_held)
        _wes_not_underwater = _promo_held > _wes_entry_px
        _promo_bucket = "<=0.58" if _wes_entry_px <= 0.58 else "0.59-0.65"

        if _promo_bdi >= 50 and _wes_not_underwater:
            # Compute add-on contracts: parent target minus WES already held
            # Use parent's normal conviction sizing to get target count
            _promo_risk = get_risk_dollars(price, reason, float(seconds_left), float(current_abs) if current_abs else None, side)
            _promo_target_c = calc_count(_promo_risk, reason, float(seconds_left), float(current_abs) if current_abs else None, side)
            _promo_addon_c  = max(0, _promo_target_c - _wes_contracts)

            print(f"          → WES_PROMOTE | {side.upper()} | scout@{_wes_entry_px:.4f} "
                  f"parent@{float(price):.4f} | {_wes_contracts}c WES + {_promo_addon_c}c {reason} "
                  f"| bucket:{_promo_bucket} | BDI:{_promo_bdi} | {int(seconds_left)}s")

            if _promo_addon_c > 0:
                _promo_resp = place_limit_order(ticker, side, price, _promo_addon_c, reason, seconds_left, abs_pct_for_risk)
                if _promo_resp.status_code in (200, 201):
                    # v239: verify actual filled quantity — don't assume full fill.
                    # Kalshi order response contains fill_count_fp (actual contracts filled).
                    # If partial fill, promoted state uses real count, not intended target.
                    _promo_filled_c = _promo_addon_c  # default: assume full fill
                    try:
                        _promo_body = _promo_resp.json()
                        _promo_order = _promo_body.get("order", _promo_body)
                        _fill_fp = _promo_order.get("fill_count_fp", None)
                        if _fill_fp is not None:
                            _promo_filled_c = min(int(Decimal(str(_fill_fp))), _promo_addon_c)
                    except Exception:
                        pass  # if parse fails, keep default full-fill assumption

                    if _promo_filled_c == 0:
                        # Order accepted but zero fills — treat as failure, rollback
                        _wes_s1_target   = round(_wes_entry_px + 0.15, 4)
                        _wes_stop_target = round(_wes_entry_px - 0.15, 4)
                        send_telegram_alert(f"WES PROMOTE FAILED | zero fills | standalone WES restored | S1:{_wes_s1_target}")
                        print(f"          → WES_PROMOTION_FAILED | zero fills on accepted order "
                              f"| rollback to standalone WES | S1:{_wes_s1_target} stop:{_wes_stop_target}")
                        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

                    # Promotion succeeded with _promo_filled_c actual contracts
                    # Record add-on at parent price first, then promote_pending_trade
                    # overwrites entry_price to combined_avg_px for correct P&L accounting.
                    record_pending_trade(ticker, reason, side, price, _promo_filled_c, float(_promo_risk), abs_pct_for_risk)

                    _wes_combined_avg_px = round(
                        (_wes_contracts * _wes_entry_px + _promo_filled_c * float(price))
                        / (_wes_contracts + _promo_filled_c), 4)

                    # v239: promote_pending_trade sets entry_price = combined_avg_px
                    # so check_settlements() uses correct weighted average for P&L.
                    # last_entry_price (live var) stays at parent price for triggers.
                    promote_pending_trade(
                        ticker       = ticker,
                        wes_entry_px = _wes_entry_px,
                        wes_contracts= _wes_contracts,
                        parent_entry_px  = float(price),
                        parent_contracts = _promo_filled_c,
                        combined_avg_px  = _wes_combined_avg_px,
                        parent_family    = reason,
                    )

                    _wes_promoted         = True
                    _wes_parent_family    = reason
                    _wes_parent_entry_px  = float(price)
                    _wes_parent_contracts = _promo_filled_c
                    # Disable WES standalone exits — parent now owns exit management
                    _wes_s1_target   = None
                    _wes_stop_target = None
                    # Hand off to parent: last_entry_* uses PARENT price so harvest/stop
                    # triggers fire at parent-family thresholds (same as standalone).
                    # WES contracts ride to the same exit price, earning more from cheaper entry.
                    # pending_trades["entry_price"] = combined_avg_px (set by promote_pending_trade)
                    # so settlement P&L is correct. Two prices, two roles — by design.
                    last_side              = side
                    last_entry_price       = price          # parent's price → harvest/stop triggers
                    last_entry_time        = dt.datetime.now(dt.timezone.utc)
                    last_traded_ticker     = ticker
                    last_entry_reason      = reason
                    last_entry_bps         = live_bps
                    last_entry_paq         = prev_paq_score if prev_paq_score is not None else 0
                    last_entry_contracts   = _wes_contracts + _promo_filled_c
                    last_entry_abs         = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
                    _paq_struct_derisked   = False
                    last_bps_opposite_count= 0
                    _weekend_struct_entry  = (reason == "PAQ_STRUCT_GATE" and is_weekend_window())
                    conf_entry_peak        = price
                    conf_soft_reversal_count = 0
                    last_exit_side = last_exit_time = last_exit_price = None
                    send_telegram_alert(
                        f"WES PROMOTE {side.upper()} | {_wes_contracts}c@{_wes_entry_px:.3f} "
                        f"+ {_promo_filled_c}c@{float(price):.3f} | {reason} | blended {_wes_combined_avg_px:.3f}")
                    print(f"          → WES_PROMOTED | blended_px:{_wes_combined_avg_px:.4f} | "
                          f"wes:{_wes_contracts}c@{_wes_entry_px:.4f} parent:{_promo_filled_c}c@{float(price):.4f} | "
                          f"total:{last_entry_contracts}c | exit owned by {reason}")
                else:
                    # Order failed — rollback to standalone WES
                    _wes_s1_target   = round(_wes_entry_px + 0.15, 4)
                    _wes_stop_target = round(_wes_entry_px - 0.15, 4)
                    send_telegram_alert(f"WES PROMOTE FAILED | order rejected {_promo_resp.status_code} | standalone WES restored")
                    print(f"          → WES_PROMOTION_FAILED | rollback to standalone WES "
                          f"| S1:{_wes_s1_target} stop:{_wes_stop_target}")
            else:
                # No add-on contracts needed (WES already at or above target size)
                # Still promote: flip exit ownership, WES rides under parent management
                _wes_promoted         = True
                _wes_parent_family    = reason
                _wes_parent_entry_px  = float(price)
                _wes_parent_contracts = 0
                _wes_combined_avg_px  = round(_wes_entry_px, 4)  # no add-on → blended = WES px
                _wes_s1_target   = None
                _wes_stop_target = None
                # v240: fully initialize parent-family state — identical to standalone parent fill.
                # Prior version only set 3 fields, leaving trade_age, entry context, and
                # post-entry management state reflecting the scout rather than a fresh parent entry.
                last_side              = side
                last_entry_price       = price          # parent price → harvest/stop triggers
                last_entry_time        = dt.datetime.now(dt.timezone.utc)
                last_traded_ticker     = ticker
                last_entry_reason      = reason
                last_entry_bps         = live_bps
                last_entry_paq         = prev_paq_score if prev_paq_score is not None else 0
                last_entry_contracts   = _wes_contracts
                last_entry_abs         = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
                _paq_struct_derisked   = False
                last_bps_opposite_count= 0
                _weekend_struct_entry  = (reason == "PAQ_STRUCT_GATE" and is_weekend_window())
                conf_entry_peak        = price
                conf_soft_reversal_count = 0
                _paq_pending_yes_count = _paq_pending_no_count = 0
                last_exit_side = last_exit_time = last_exit_price = None
                # Update pending_trades entry_price to combined_avg_px for correct P&L accounting
                promote_pending_trade(
                    ticker           = ticker,
                    wes_entry_px     = _wes_entry_px,
                    wes_contracts    = _wes_contracts,
                    parent_entry_px  = float(price),
                    parent_contracts = 0,
                    combined_avg_px  = _wes_combined_avg_px,
                    parent_family    = reason,
                )
                send_telegram_alert(
                    f"WES PROMOTE {side.upper()} | {_wes_contracts}c@{_wes_entry_px:.3f} "
                    f"ZERO_ADDON | {reason}@{float(price):.3f} takes ownership")
                print(f"          → WES_PROMOTED_ZERO_ADDON | WES {_wes_contracts}c rides under {reason} | "
                      f"parent px:{float(price):.4f} → harvest/stop triggers at parent thresholds")

            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL
        else:
            # Promotion gate failed — log reason, continue as standalone WES
            _fail_reason = f"BDI:{_promo_bdi}<50" if _promo_bdi < 50 else "WES_underwater"
            print(f"          → WES_PROMOTE_BLOCKED | {_fail_reason} | WES continues standalone")

    # ── v234: WES flat sizing — bypass conviction system entirely ────────
    # WES uses fixed $4 risk, max 4 contracts. No conviction score. No multiplier.
    # Symmetric exit means sizing volatility is irrelevant — max loss is always $0.60/c.
    if reason == "WES_EARLY":
        _wes_risk_flat = Decimal("4.00")
        _wes_c = min(4, max(1, int((_wes_risk_flat / price).to_integral_value(rounding=ROUND_DOWN))))
        _conv_tier = "WES_FLAT"
        _conv_score = 0.0
        contracts = _wes_c
        risk_dollars = _wes_risk_flat
        _entry_bdi = get_bdi(ticker, side, float(price))
        _pre_bdi_contracts = contracts
        print_buy_snapshot(side, price, reason, seconds_left, contracts, recent_move_pct, metrics, live_bps)
        print(f"             Conv:      WES_FLAT | $4.00 risk | {contracts}c | S1:{float(price)+0.15:.3f} stop:{float(price)-0.15:.3f}")
        resp = place_limit_order(ticker, side, price, contracts, reason, seconds_left, abs_pct_for_risk)
        if resp.status_code in (200, 201):
            record_pending_trade(ticker, reason, side, price, contracts, float(risk_dollars), abs_pct_for_risk)
            send_telegram_alert(f"WES {side.upper()} | {contracts}x @ {float(price):.2f}")
            last_side = side; last_entry_price = Decimal(str(price))
            last_entry_time = dt.datetime.now(dt.timezone.utc)
            last_traded_ticker = ticker; flip_logged_ticker = None
            last_exit_side = last_exit_time = last_exit_price = None
            last_entry_reason = reason; last_entry_bps = live_bps
            last_entry_paq = prev_paq_score if prev_paq_score is not None else 0
            last_entry_contracts = contracts; last_entry_abs = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
            _paq_struct_derisked = False; last_bps_opposite_count = 0
            _weekend_struct_entry = False; conf_entry_peak = price
            conf_soft_reversal_count = 0; _paq_pending_yes_count = _paq_pending_no_count = 0
            _wes_active = True; _wes_entry_px = float(price)
            _wes_contracts = contracts; _wes_side = side
            _wes_entry_secs = float(seconds_left) if seconds_left is not None else 0.0
            _wes_s1_target = round(float(price) + 0.15, 4)
            _wes_stop_target = round(float(price) - 0.15, 4)
            print(f"          → WES_ARMED | {side.upper()}@{float(price):.4f} | "
                  f"S1:{_wes_s1_target:.4f} stop:{_wes_stop_target:.4f} | {contracts}c")
        else:
            print("WES order failed:", resp.status_code, resp.text)
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # ── Conviction-based risk sizing (v199) ──────────────────────────────
    # Score built from signals already computed: PAQ, BCDP, ABS, time, family.
    # One function, three tiers, no new gates.
    # Data basis: March 23 67-trade sample — HIGH 85% WR +$1.11/trade,
    # LOW 62% WR -$0.80/trade. Multipliers: LOW 0.70×, MID 1.00×, HIGH 1.40×.
    _conv_score = conviction_score(
        reason=reason,
        paq=int(prev_paq_score) if prev_paq_score is not None else 0,
        bcdp_n=_bcdp,
        bcdp_clean=_bcdp_clean,
        abs_pct=float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0,
        seconds_left=float(seconds_left) if seconds_left is not None else 0.0,
        entry_price=float(price),
    )
    _conv_mult, _conv_tier = conviction_multiplier(_conv_score)

    # v228: Weekend PAQ_EARLY_AGG HIGH → MID sizing cap
    # Proof case: 3/28 YES@0.71 15c (HIGH 1.40×) — book died mid-trade,
    # stop unfilled, full -$10.65. Thin weekend books can't support amplified
    # sizing when reversals happen and exits fail. bps_premium unaffected.
    # Data basis: March 23 HIGH conviction data is weekday-only.
    if (reason == "PAQ_EARLY_AGG"
            and is_weekend_window()
            and _conv_tier == "HIGH"):
        _conv_mult, _conv_tier = Decimal("1.00"), "MID(WKND_CAP)"

    # v233 BUILD 2: CTX floor on conviction
    # CTX=0 means market structure is unconfirmed — no directional commitment.
    # High PAQ or ABS can be momentum-only. CTX is structural confirmation.
    # Sizing at MID/HIGH with CTX=0 amplifies losses on unconfirmed moves.
    # Data basis: 3/31 Trades 07,09,13,19 — CTX=0 entries oversized into
    # moves that either failed or required luck to survive.
    # Rule: CTX=0 → cap at LOW. CTX=1 → cap at MID. CTX=2 → HIGH allowed.
    # Applied to PAQ_EARLY_AGG, bps_premium, BCDP_FAST_COMMIT.
    # Rationale: PAQ_STRUCT_GATE and confirm_standard have own gates — exempt.
    _ctx_at_entry = prev_paq_ctx if prev_paq_ctx is not None else 0
    if reason in ("PAQ_EARLY_AGG", "bps_premium", "BCDP_FAST_COMMIT"):
        if _ctx_at_entry == 0 and _conv_tier not in ("LOW", "LOW(CAPPED)"):
            _conv_mult, _conv_tier = Decimal("0.70"), "LOW(CTX0_CAP)"
        elif _ctx_at_entry == 1 and _conv_tier == "HIGH":
            _conv_mult, _conv_tier = Decimal("1.00"), "MID(CTX1_CAP)"
        # CTX=2 → no cap, HIGH allowed normally

    # v233 BUILD 3: ASIA_OPEN + BTC_DEEP_NIGHT + VOLATILE AGG overnight cap
    # Data basis: 3/31 YES@0.56 (14c) -$7.84 and YES@0.61 (9c) -$4.95 both
    # ASIA_OPEN. Single overnight AGG failures erasing multiple Premium wins.
    # Rule: PAQ_EARLY_AGG in ASIA_OPEN or BTC_DEEP_NIGHT → cap risk $5, HIGH→MID.
    # Also applies when regime is VOLATILE (book too thin for oversized AGG).
    # Weekday version of the correct weekend business decision (v228).
    _v233_sess = get_session_label()
    _v233_overnight = _v233_sess in ("ASIA_OPEN", "BTC_DEEP_NIGHT")
    if (reason == "PAQ_EARLY_AGG"
            and ((_v233_overnight and not is_weekend_window())
                 or _regime == "VOLATILE")):
        # Override risk base: will be applied before conviction mult below
        # Flag for get_risk_dollars override — handled via inline cap after sizing
        if _conv_tier in ("HIGH", "MID(WKND_CAP)"):
            _conv_mult, _conv_tier = Decimal("1.00"), "MID(OVERNIGHT_CAP)"

    # Exposure cap: second same-side entry forced to LOW regardless of setup quality
    global _entry_exposure_capped
    if _entry_exposure_capped:
        _conv_mult, _conv_tier = Decimal("0.70"), "LOW(CAPPED)"
        _entry_exposure_capped = False  # reset after applying

    risk_dollars = get_risk_dollars(price, reason, seconds_left, abs_pct_for_risk, side)
    risk_dollars = (risk_dollars * _conv_mult).quantize(Decimal("0.01"))
    # v233 BUILD 3: hard cap $5 for AGG in overnight sessions or VOLATILE
    if (reason == "PAQ_EARLY_AGG"
            and ((_v233_overnight and not is_weekend_window()) or _regime == "VOLATILE")):
        _overnight_cap = Decimal("5.00")
        if risk_dollars > _overnight_cap:
            risk_dollars = _overnight_cap
    contracts = max(1, int((risk_dollars / price).to_integral_value(rounding=ROUND_DOWN)))
    # v169: PAQ_EARLY_AGG late-entry size reduction
    # secs_left < 200: exit window compressed — single BTC tick in final 10s can override signal.
    # 50% size preserves upside capture while halving settlement-variance exposure.
    # Scoped to fresh PAQ_EARLY_AGG entries only. No other families affected.
    if (reason == "PAQ_EARLY_AGG"
            and seconds_left is not None and seconds_left < 200
            and last_entry_contracts == 0):  # fresh entry only
        contracts = max(1, contracts // 2)

    # v253: Single-snapshot BDI — fetch once, use everywhere.
    # Root cause of 4/7 10:15 -$18.88 loss: v252 made two separate get_bdi() calls —
    # one for the size clamp (line ~6713) and one for the final confirmation (~6827).
    # Between those two API calls the book state could differ, allowing a thin-book
    # entry to pass the clamp (BDI appeared ≥50) then log BDI=36 at confirmation
    # (where 36 < 32 is False so contracts stayed at 32). The same BDI=36 should have
    # triggered BDI_CLAMP5 → 5 contracts → loss would have been ~-$2.95 not -$18.88.
    # Fix: one get_bdi() call here, frozen into _entry_bdi, used for:
    #   (1) size clamp (PAQ_EARLY_AGG / BCDP_FAST_COMMIT / high-price bps_premium)
    #   (2) bps_premium thin-book gate
    #   (3) ASIA_OPEN counter gate
    #   (4) final confirmation / backstop
    #   (5) BUY SNAPSHOT logging
    # No thresholds changed. No new policy. Atomicity only.
    _entry_bdi = get_bdi(ticker, side, float(price))

    # v233 BUILD 1: BDI entry-side size clamp
    # BDI < 25 → position physically cannot support a stop exit at reasonable prices.
    # 3/31 Trade 06: BDI 9, 11c, FLIP_EMERGENCY filled at attempt 6 at $0.06 — near-total loss.
    # Trade 02: BDI 8, 9c bps_premium — stop and harvest both failed.
    # This is not a signal quality gate; it is a physical exit viability gate.
    # Signal can be strong (PAQ 6, high ABS) but thin book makes losses unrecoverable.
    # Applied to PAQ_EARLY_AGG, BCDP_FAST_COMMIT, bps_premium above 0.82.
    # Data basis: 3/31 log — BDI<25 entries produced worst fills in the session.
    if reason in ("PAQ_EARLY_AGG", "BCDP_FAST_COMMIT") or \
       (reason == "bps_premium" and float(price) > 0.82):
        if _entry_bdi < 25:
            contracts = min(contracts, 3)
            if _conv_tier not in ("LOW", "LOW(CTX0_CAP)", "LOW(CAPPED)"):
                _conv_tier = f"{_conv_tier}+BDI_CLAMP3"
        elif _entry_bdi < 50:
            contracts = min(contracts, 5)
            if _conv_tier == "HIGH":
                _conv_mult, _conv_tier = Decimal("0.70"), "LOW(BDI_CLAMP5)"
            elif _conv_tier == "MID":
                _conv_tier = "MID+BDI_CLAMP5"

    if price < MIN_EXECUTABLE_PRICE or price >= MAX_EXECUTABLE_PRICE:
        log_rejection_once(ticker, seconds_left, side, "executable_price_guard")
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    vetoed = check_divergence_veto(seconds_left, side, recent_move_pct)
    if vetoed:
        log_rejection_once(ticker, seconds_left, side, "divergence_veto")
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # ── bps_premium thin-book gate (v207) ────────────────────────────────
    # bps_premium in STABLE or MODERATE with BDI < 15 = deceptive entry.
    # Book appears normal but has no real exit depth on reversal.
    # March 24: BDI=1 bps_premium loss -$3.08 in exactly this profile.
    # VOLATILE thin-book bps_premium left open — may still be legitimate.
    # v253: uses frozen _entry_bdi — no second get_bdi() call.
    if (reason == "bps_premium"
            and _regime in ("STABLE", "MODERATE")
            and _entry_bdi < 15):
        log_rejection_once(ticker, seconds_left, side, "bps_premium_thin_book")
        return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # ── ASIA_OPEN COUNTER + thin-book gate (v220) ─────────────────────────
    # Simulation across 3/26-3/27 (2 days, 10 COUNTER+BDI<100 entries in
    # ASIA_OPEN): blocking BDI<50 saves $15.88 in losses, blocks $0 in wins.
    # Pattern: in ASIA_OPEN, COUNTER entries (BPS opposes session-preferred
    # direction) with BDI<50 at entry have no viable exit book on reversal.
    # Two failure modes found: (1) immediate reversal - no harvest window;
    # (2) delayed reversal - partial harvest possible but still nets negative.
    # Blocking is cleaner than harvesting on thin books.
    #
    # COUNTER definition for ASIA_OPEN:
    #   YES entries: COUNTER when live_bps <= 0 (BPS not pushing YES)
    #   NO entries:  COUNTER when live_bps >= 0 (BPS not pushing NO)
    #
    # BDI<50 chosen over BDI<100: BDI<50 blocked 0 wins, saved 3 losses
    # (+$15.88). BDI<100 blocked 6 wins, saved 4 losses (+$14.36 - worse).
    # Does NOT apply to NY_PRIME or BTC_DEEP_NIGHT - those sessions produce
    # real fills even on thin books. Session-specific by design.
    # Revisit after 5+ additional sessions confirm pattern holds.
    # v253: uses frozen _entry_bdi — no second get_bdi() call.
    _ao_sess = get_session_label()
    if _ao_sess == "ASIA_OPEN":
        _ao_counter = (
            (side == "yes" and (live_bps is None or live_bps <= 0)) or
            (side == "no"  and (live_bps is None or live_bps >= 0))
        )
        if _ao_counter and _entry_bdi < 50:
            log_rejection_once(ticker, seconds_left, side, "ASIA_OPEN_COUNTER_BDI_THIN")
            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # ── WEEKEND GATES (v221/v222) ──────────────────────────────────────────
    # Data: 3/21 Sat + 3/22 Sun (2 weekend days).
    # v221: STRUCT gated entirely on weekends (-$14.77 → +$11.17 swing).
    # v222: STRUCT re-enabled on weekends with ladder exit + delayed stop.
    #   Ladder: 25% @0.65 | 25% @0.72 | full close @0.80.
    #   Stop: entry minus 0.10, only activates after 300s elapsed.
    #   Entry gate: BPS must be non-zero and aligned at entry (not 0.0).
    #   Data: simulation on 3/21+3/22 shows LOST $19.28 actual →
    #   WON $11.25 with ladder+stop. Net improvement: $30.53.
    #   Risk levels simulated: $3 (WON $3.98/2-days), $5 (WON $6.53),
    #   $7 (WON $9.21). Start at $3, scale after validation.
    #   AGG, bps_premium, BCDP: zero changes, untouched.
    _is_weekend = is_weekend_window()

    # Weekend STRUCT BPS alignment gate (replaces hard block from v221)
    # BPS must be non-zero and directionally aligned — zero BPS = no conviction
    if _is_weekend and reason == "PAQ_STRUCT_GATE":
        _wknd_struct_bps = live_bps if live_bps is not None else 0
        _bps_aligned = (side == "yes" and _wknd_struct_bps > 0) or \
                       (side == "no"  and _wknd_struct_bps < 0)
        if not _bps_aligned:
            log_rejection_once(ticker, seconds_left, side, "WEEKEND_STRUCT_BPS_ZERO")
            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL
        # Entry allowed — _weekend_struct_entry flag set at order placement below

    # Gate 2: BPS stability gate on weekends — require 6+ consecutive polls
    #   of consistent BPS direction before entry.
    #   Data: 3-5 polls after BPS flip = 67% WR -$20.12 (weekend).
    #         6+ polls stable = 92% WR +$31.88 (weekend).
    #   Grok raw-log confirmation: 4 blocked entries, 3 were losses, 1 missed win.
    #   Net: saves $15.97 losses, costs $2.60 missed win = +$13.37.
    #   Uses _bps_history deque (maxlen=8 after v221 expansion).
    #   Consistent = all non-zero BPS values same sign as current side.
    if _is_weekend and len(_bps_history) > 0:
        _bps_hist_list = list(_bps_history)
        _nonzero_bps = [b for b in _bps_hist_list if b != 0]
        if _nonzero_bps:
            _target_positive = (side == "yes")  # YES entry needs positive BPS
            _stable_polls = 0
            for _b in reversed(_nonzero_bps):
                if (_b > 0) == _target_positive:
                    _stable_polls += 1
                else:
                    break
            if _stable_polls < 6:
                log_rejection_once(ticker, seconds_left, side,
                    f"WEEKEND_BPS_UNSTABLE_{_stable_polls}of6")
                return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

    # BDI entry confirmation: real depth must exist at entry price.
    # Prevents entering a ghost market where quoted price has no actual bids.
    # Required: BDI >= contracts (full position supportable by book).
    # PAQ_STRUCT_GATE specifically — catching ghost quotes at fair value.
    # v253: uses frozen _entry_bdi from single snapshot above — no second get_bdi() call.
    _pre_bdi_contracts = contracts  # save for logging
    if _entry_bdi < contracts:
        if _entry_bdi == 0:
            _last_entry_block = f"→ BLOCK | {side.upper()} | BDI_EMPTY"
            return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL
        # Partial depth: reduce contracts to what book supports, proceed
        contracts = _entry_bdi

    resp = place_limit_order(ticker, side, price, contracts, reason, seconds_left, abs_pct_for_risk)
    if resp.status_code in (200, 201):
        rank = get_strategy_rank(reason)

        record_pending_trade(ticker, reason, side, price, contracts, float(risk_dollars), abs_pct_for_risk)
        print_buy_snapshot(side, price, reason, seconds_left, contracts, recent_move_pct, metrics, live_bps)
        print(f"             Conv:      {_conv_score:.1f} ({_conv_tier}) → {float(_conv_mult):.2f}× risk ${float(risk_dollars):.2f} ({_regime}) | BDI {_entry_bdi} | sized {_pre_bdi_contracts}→{contracts}c")
        send_telegram_alert(f"TRADED {side.upper()} | {reason} | {contracts}x @ {float(price):.2f} | ${float(price)*contracts:.2f}")
        last_side = side
        last_entry_price = Decimal(str(price))
        last_entry_time = dt.datetime.now(dt.timezone.utc)
        last_traded_ticker = ticker
        flip_logged_ticker = None
        # Reset exit tracking so the active-position gate fires on next poll.
        # Without this, last_exit_side retains the PREVIOUS position's exit value,
        # which causes the cooldown gate to treat a stale exit as current and
        # allow unlimited same-direction stacking since old cooldown has expired.
        last_exit_side  = None
        last_exit_time  = None
        last_exit_price = None

        last_entry_reason = reason
        last_entry_bps = live_bps
        last_entry_paq = prev_paq_score if prev_paq_score is not None else 0
        last_entry_contracts = contracts
        last_entry_abs = float(abs_pct_for_risk) if abs_pct_for_risk is not None else 0.0
        _paq_struct_derisked = False  # reset for new position
        last_bps_opposite_count = 0
        # v222: flag weekend STRUCT entries for ladder exit mode
        _weekend_struct_entry = (reason == "PAQ_STRUCT_GATE" and is_weekend_window())
        _wsl_entry_secs = float(seconds_left) if seconds_left is not None else 900.0
        # initialise confirmation-family peak tracking
        conf_entry_peak = price
        conf_soft_reversal_count = 0
        _paq_pending_yes_count = 0
        _paq_pending_no_count  = 0

        # v234: WES arming previously duplicated here — removed v240 (dead code).
        # WES flat-sizing block (above) returns before reaching this path.
        # WES state is set there. This block was unreachable.

        outcome_text = f"TRADED ({contracts} contracts)"
    else:
        print("Order failed:", resp.status_code, resp.text)
        send_telegram_alert(f"ORDER FAILED | {side.upper()} | {reason} | status {resp.status_code}")
        outcome_text = f"ORDER FAILED ({resp.status_code})"

    log_trigger_record(ticker, seconds_left, side, reason, yes_price, no_price, btc_available, vetoed, outcome_text, contracts, float(risk_dollars), metrics)

    return FAST_POLL if seconds_left <= FAST_POLL_WINDOW else SLOW_POLL

def get_strategy_rank(reason: str) -> int:
    ranks = {
        "bps_premium":       1,
        "bps_late":          2,
        "BCDP_FAST_COMMIT":  2,  # half-size probe — same harvest tier as PAQ_STRUCT_GATE
        "PAQ_STRUCT_GATE":   2,  # low-abs max-upside — same tier as PAQ_PENDING_ALIGN
        "PAQ_PENDING_ALIGN": 2,
        "PAQ_EARLY_CONS":    3,
        "PAQ_EARLY_AGG":     4,
        "confirm_standard":  5,
        "confirm_late":      6,
    }
    return ranks.get(reason, 99)

if __name__ == "__main__":
    print("AetherBot v254")
    load_pending_trades()
    load_pending_settlements()
    drain_telegram_queue()  # discard stale commands from previous session
    send_telegram_alert("AetherBot Telegram alerts are now live")
    while True:
        try:
            sleep_for = run_bot()
        except KeyboardInterrupt:
            raise
        except Exception as e:
            print("Loop error:", type(e).__name__, str(e))
            sleep_for = SLOW_POLL
        time.sleep(sleep_for)
