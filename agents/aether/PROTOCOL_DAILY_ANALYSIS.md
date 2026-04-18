# PROTOCOL: Aether Daily Analysis
**Version:** 1.0  
**Created:** 2026-04-18  
**Owner:** Aether  
**Reviewed by:** Kai  

> **Cold-start guarantee:** A 3rd-party agent with zero context can read this file and produce the correct output. Every path, command, API call, format, and verification step is specified exactly. No assumptions. No "you should know this."

---

## WHAT THIS PRODUCES

One analysis file and one HQ feed entry published every night at 23:00 MT.

**Output 1:** `~/Documents/Projects/Hyo/agents/aether/analysis/Analysis_YYYY-MM-DD.txt`  
**Output 2:** Entry in `~/Documents/Projects/Hyo/agents/sam/website/data/feed.json` with `"id": "aether-analysis-YYYY-MM-DD"`

Both must exist for the pipeline to be considered complete. Missing either = failure.

---

## TRIGGER

**When:** Daily at 23:00 MT via launchd  
**Plist:** `~/Documents/Projects/Hyo/agents/aether/analysis/com.hyo.aether-analysis.plist`  
**Manual trigger:** `bash ~/Documents/Projects/Hyo/agents/aether/analysis/run_analysis.sh`  
**Can also trigger via queue:** `kai exec "bash agents/aether/analysis/run_analysis.sh"`

---

## ENVIRONMENT REQUIREMENTS

**Required files:**
```
~/security/hyo.env              ← primary (preferred)
~/Documents/Projects/Hyo/agents/nel/security/.env  ← fallback
```

**Required environment variables:**
```
ANTHROPIC_API_KEY=sk-ant-...    ← Claude Sonnet 4.6 (primary analyst)
OPENAI_API_KEY=sk-...           ← GPT-4 (adversarial cross-check)
TELEGRAM_BOT_TOKEN=...          ← optional, for Telegram delivery
TELEGRAM_CHAT_ID=...            ← optional, for Telegram delivery
```

**Required Python packages:**
```
anthropic      ← pip install anthropic
openai         ← pip install openai
```

**Models used (never change without updating KNOWLEDGE.md):**
```
Claude: claude-sonnet-4-6       ← primary analysis
GPT:    gpt-4-turbo-preview     ← adversarial cross-check
```

---

## INPUT DATA

### Primary Input: AetherBot Log

**Location:** `~/Documents/Projects/AetherBot/Logs/AetherBot_YYYY-MM-DD.txt`  
**Format:** Plain text, one line per event. 2000–5000 lines for a full trading day.  
**Selection rule:** Use the log for the most recent COMPLETED trading day.

**SPARSE LOG GATE (mandatory):**
```
If line_count(today_log) < 100:
    Check yesterday_log line_count
    If yesterday_log > today_log:
        Use yesterday_log instead
        Label analysis as yesterday's date
    Else:
        Warn "both logs sparse" — analysis may be incomplete
        Proceed with whatever exists
```

Why: AetherBot creates next day's file at midnight. At 23:00 MT analysis time, today's file may have only 1 line (a tick stub). The previous day's full log has the actual trading data.

### Secondary Input: Balance Ledger

**Location:** `~/Documents/Projects/Hyo/kai/memory/KNOWLEDGE.md` → section `## BALANCE LEDGER`  
**Purpose:** Inject into Claude system prompt as context for P&L verification  
**Format:** One line per day: `4/13 $86.44 | 4/14 $108.91 | ...`

### Tertiary Input: Open Issues

**Location:** `~/Documents/Projects/Hyo/kai/memory/KNOWLEDGE.md` → section `## Open AetherBot issues`  
**Purpose:** Inject into Claude system prompt so analyst knows what to watch for  
**Current issues (as of 2026-04-18):**
```
ISSUE 1 (P0): Harvest miss — Mode A (thin anchor depth, gate ±0.02) vs Mode B (deep book, ABSENT bids, stale orderbook). v254 will instrument place_exit_order().
ISSUE 2 (P1): BDI=0 stop hold fires when seconds_left <= 120 → position expires. Fix: skip hold at <120s. 4 confirmed expiry losses Apr 13-16.
ISSUE 3 (P1): POS WARNING | API 0 local N — fires during exit sequences. May indicate phantom entries. Fix: when API 0 and seconds_left <= 30, treat as settled, clear state.
ISSUE 4 (P2): EU_MORNING post-04:15 losses clustering. 3 sessions confirm, need 2-3 more.
ISSUE 5 (P3): Weekend risk profile (target $5 flat, PAQ_MIN=4, disable confirm_late/standard). Not built.
```

### Version Context

**Current deployed version:** v253  
**Next planned build:** v254  
**Source:** `~/Documents/Projects/Hyo/kai/memory/KNOWLEDGE.md` → `## AETHERBOT — ANALYSIS STANDARDS` section  
**Rule:** Never assume version numbers. Read KNOWLEDGE.md. They change.

---

## PIPELINE STEPS

### Step 1: Run the Analysis Script

```bash
cd ~/Documents/Projects/Hyo
bash agents/aether/analysis/run_analysis.sh
```

This script:
1. Loads env from `~/security/hyo.env`
2. Finds the latest AetherBot log (with sparse log gate)
3. Runs `agents/aether/analysis/kai_analysis.py`
4. Copies output to `agents/aether/analysis/Analysis_YYYY-MM-DD.txt`
5. Publishes to HQ via `bin/aether-publish-analysis.sh`

**If the script fails at any step:** check `agents/aether/logs/aether-YYYY-MM-DD.md` for error output.

---

### Step 2: Claude Analysis (what kai_analysis.py does)

**Script:** `~/Documents/Projects/Hyo/agents/aether/analysis/kai_analysis.py`

**Claude system prompt includes:**
- Role: primary analyst for AetherBot (Kalshi prediction markets, KXBTC15M contracts)
- Balance ledger (current)
- Open issues (current)
- Analysis rules (see below)
- Current version + next version

**Claude is asked to produce (exact requirements):**

```
1. Full trade-by-trade ledger grouped by strategy family
   - Every trade: strategy, side (YES/NO), entry price, contracts, exit type, net P&L
   - Each family: subtotal of wins/losses, win rate, net P&L
   
2. Stop and harvest event log
   - Every STOP, HARVEST, FORCED_EXIT, HOLD event with timestamp and P&L

3. Session window P&L breakdown
   - Windows: EU_MORNING (00:00-09:30 MT) | NY_OPEN | NY_PRIME | NY_CLOSE | EVENING | OVERNIGHT
   - Net P&L per window
   
4. EOD balance update
   - Opening balance (from ledger)
   - Session net
   - Closing balance (verified from last balance line in log)
   - Flag if claimed settlement P&L ≠ actual balance change

5. One recommendation (exactly one of three formats):
   RECOMMENDATION: BUILD v[XXX]
   RECOMMENDATION: COLLECT MORE DATA
   RECOMMENDATION: MONITOR AND HOLD
```

**Claude analysis rules (hardcoded in system prompt):**
- Come with a position — not a report  
- Never kill strategies from single-session data  
- Mechanism level required: not "losses in EVENING" but "all 4 EVENING losses are bps_premium NO positions entered 19:45–21:15 MT when BTC moved directionally"  
- All times in Mountain Time (never UTC)  
- Every recommendation requires specific log evidence with timestamps and dollar amounts  
- Current version v253. Next build v254.

---

### Step 3: GPT Cross-Check (adversarial)

**Script:** `~/Documents/Projects/Hyo/agents/aether/analysis/gpt_crosscheck.py`

GPT receives Claude's analysis and is asked to produce **adversarial intelligence** — not arithmetic.

**GPT cross-check must identify (not duplicate Claude's work):**
- Strategy drift: Is performance degrading across sessions (not just today)?
- Risk concentration: Are too many positions correlated?
- Entry quality degradation: Are entry prices drifting unfavorable?
- Harvest efficiency trends: Is the harvest rate improving or declining over time?
- Timing optimization gaps: Are there session windows with consistent underperformance?
- Cross-session regression: Did a recent code change degrade anything?

**If GPT output is just arithmetic (balance X, day net Y):** the prompt is broken. GPT should produce insights Claude didn't have. Each GPT API dollar must produce a non-duplicate finding.

---

### Step 4: Claude Final Synthesis

Claude receives GPT's adversarial critique and produces a final synthesis that:
1. Addresses GPT's specific challenges
2. Confirms or revises the initial recommendation
3. States what the recommendation means in concrete terms (exact code changes if BUILD, exact metrics thresholds if COLLECT)

---

### Step 5: Publish to HQ

**Script:** `~/Documents/Projects/Hyo/bin/aether-publish-analysis.sh`  
**Arguments:** `[DATE] [ANALYSIS_FILE_PATH]`

This script:
1. Reads the analysis file
2. Adds an entry to `agents/sam/website/data/feed.json`:
   ```json
   {
     "id": "aether-analysis-YYYY-MM-DD",
     "type": "aether-analysis",
     "date": "YYYY-MM-DD",
     "title": "AetherBot Analysis — YYYY-MM-DD",
     "preview": "[first 2 sentences of recommendation]",
     "readLink": "/daily/aether-analysis-YYYY-MM-DD"
   }
   ```
3. Creates `agents/sam/website/daily/aether-analysis-YYYY-MM-DD.html` (rendered HTML version)
4. DUAL-PATH: Also copies to `website/data/feed.json` and `website/daily/`
5. Commits and pushes to git

**DUAL-PATH GATE:** Any commit that touches `agents/sam/website/` must ALSO touch `website/`. A pre-commit hook enforces this. If the hook blocks the commit, run:
```bash
git add website/data/feed.json website/daily/aether-analysis-YYYY-MM-DD.html
```

---

## OUTPUT FORMAT

The analysis file must follow this exact structure (no exceptions):

```
================================================================================
AETHERBOT SESSION ANALYSIS | [DATE RANGE]
Prepared by Kai, orchestrator — hyo.world
================================================================================


================================================================================
PART 1: BALANCE LEDGER UPDATE
================================================================================

Prior confirmed EOD ([YESTERDAY]):  $XXX.XX
[DATE] Open: $XXX.XX   EOD: $XXX.XX   Net: [+/-]$XX.XX

Period net [START DATE → END DATE]: [+/-]$XX.XX


================================================================================
PART 2: TRADE-BY-TRADE LEDGER BY FAMILY
================================================================================

--- [DATE] ---

[STRATEGY_NAME]
  HH:MM  [YES/NO] @ [PRICE]  [CONTRACTS]c  [WIN/LOSS]  [+/-]$X.XX  ([EXIT_TYPE])
  [STRATEGY_NAME] net:  [+/-]$X.XX  ([N] trades, [W]W/[L]L, [PCT]% WR)

[REPEAT FOR ALL STRATEGIES AND ALL DATES]


================================================================================
PART 3: STOP / HARVEST EVENT LOG
================================================================================

[TIMESTAMP] [EVENT_TYPE] — [STRATEGY] [SIDE] [CONTRACTS]c [DETAILS] [P&L_IMPACT]

[REPEAT FOR ALL STOP/HARVEST/FORCED_EXIT/HOLD EVENTS]


================================================================================
PART 4: SESSION WINDOW P&L
================================================================================

Session       Start    End      Net P&L   Trades   Notes
-----------   ------   ------   -------   ------   -----
EU_MORNING    00:00    09:30    $X.XX     N        [any pattern]
NY_OPEN       09:30    10:30    $X.XX     N
NY_PRIME      10:30    15:00    $X.XX     N
NY_CLOSE      15:00    16:30    $X.XX     N
EVENING       16:30    22:00    $X.XX     N
OVERNIGHT     22:00    00:00    $X.XX     N
-----------   ------   ------   -------   ------   -----
TOTAL                           $X.XX     N


================================================================================
PART 5: OPEN ISSUE STATUS
================================================================================

ISSUE 1 (P0): [current status — confirmed / active / no new data]
ISSUE 2 (P1): [current status]
ISSUE 3 (P1): [current status]
ISSUE 4 (P2): [current status]
ISSUE 5 (P3): [current status]


================================================================================
PART 6: GPT ADVERSARIAL CROSS-CHECK
================================================================================

[GPT's 3-5 specific challenges or findings that are NOT in Claude's analysis]

[Claude's response to each challenge]


================================================================================
PART 7: FINAL RECOMMENDATION
================================================================================

RECOMMENDATION: [BUILD v[XXX] | COLLECT MORE DATA | MONITOR AND HOLD]

[If BUILD:]
What changes: [exact code changes required, file names, line descriptions]
Why now: [specific log evidence with timestamps and dollar amounts]
Risk if we wait: [what we lose by collecting more data first]

[If COLLECT MORE DATA:]
What we need: [specific events or session types required]
How many sessions: [minimum count before revisiting]
What to watch for: [exact log patterns that trigger a build decision]

[If MONITOR AND HOLD:]
What's stable: [what's working, should not be touched]
What's uncertain: [what needs more data]
Next trigger: [the specific event that moves this to BUILD or COLLECT]


================================================================================
PART 8: BALANCE LEDGER (UPDATED)
================================================================================

[Full updated ledger through today — copy from KNOWLEDGE.md and add today's row]
```

**Footer (required on every analysis):**
```
Prepared by Kai, orchestrator — hyo.world
Analysis date: [YYYY-MM-DD]
AetherBot version: v[XXX] deployed
```

---

## VERIFICATION CRITERIA

The pipeline is NOT done until ALL of the following are true:

**[ ] 1. Analysis file exists on disk**
```bash
ls -la ~/Documents/Projects/Hyo/agents/aether/analysis/Analysis_YYYY-MM-DD.txt
# Expected: file exists, size > 5000 bytes
```

**[ ] 2. Analysis file contains a recommendation**
```bash
grep "RECOMMENDATION:" ~/Documents/Projects/Hyo/agents/aether/analysis/Analysis_YYYY-MM-DD.txt
# Expected: exactly one RECOMMENDATION line
```

**[ ] 3. HQ feed entry exists**
```bash
python3 -c "
import json
with open('/Users/[username]/Documents/Projects/Hyo/agents/sam/website/data/feed.json') as f:
    d = json.load(f)
ids = [r['id'] for r in d.get('reports', [])]
print('FOUND' if 'aether-analysis-YYYY-MM-DD' in ids else 'MISSING')
"
# Expected: FOUND
```

**[ ] 4. HTML page renders on Vercel (live check)**
```bash
curl -s -o /dev/null -w "%{http_code}" https://hyo.world/daily/aether-analysis-YYYY-MM-DD
# Expected: 200
```

**[ ] 5. Both paths committed**
```bash
git -C ~/Documents/Projects/Hyo diff --name-only HEAD | grep -E "website/data/feed.json|agents/sam/website/data/feed.json"
# Expected: both paths changed OR neither (meaning commit already pushed)
```

**[ ] 6. Balance ledger in KNOWLEDGE.md updated**
```bash
grep "YYYY-MM-DD" ~/Documents/Projects/Hyo/kai/memory/KNOWLEDGE.md
# Expected: today's balance entry present
```

If any check fails → the pipeline is not done → fix and re-verify before closing the session.

---

## ERROR RECOVERY

### "Analysis file missing after run"
```bash
# Check what kai_analysis.py actually wrote
ls -la ~/Documents/Projects/AetherBot/"Kai analysis"/
# If file is there, copy it manually:
cp ~/Documents/Projects/AetherBot/"Kai analysis"/Analysis_YYYY-MM-DD.txt \
   ~/Documents/Projects/Hyo/agents/aether/analysis/
```

### "Feed entry missing after publish"
```bash
# Re-run just the publish step
bash ~/Documents/Projects/Hyo/bin/aether-publish-analysis.sh YYYY-MM-DD \
     ~/Documents/Projects/Hyo/agents/aether/analysis/Analysis_YYYY-MM-DD.txt
```

### "Vercel returns 404 for /daily/aether-analysis-YYYY-MM-DD"
```bash
# Check if HTML file exists with correct prefix
ls ~/Documents/Projects/Hyo/agents/sam/website/daily/aether-analysis-YYYY-MM-DD.html
# If missing, the publish script failed — re-run publish step above
# If present, check Vercel deployment: may need git push + Vercel redeploy
```

### "Dual-path gate blocks commit"
```bash
# Always add both paths before committing
git add agents/sam/website/data/feed.json website/data/feed.json
git add agents/sam/website/daily/aether-analysis-YYYY-MM-DD.html
git add website/daily/aether-analysis-YYYY-MM-DD.html 2>/dev/null || true
git commit -m "aether: publish analysis YYYY-MM-DD"
git push origin main
```

### "AetherBot log has < 100 lines"
Activate sparse log gate (already in run_analysis.sh):  
Check `~/Documents/Projects/AetherBot/Logs/AetherBot_YESTERDAY.txt` — use that log, label analysis as YESTERDAY's date.

### "GPT cross-check produces only arithmetic"
The GPT prompt in `gpt_crosscheck.py` needs to be updated. GPT's role is adversarial intelligence — finding what Claude missed. If GPT is just summarizing numbers:
1. Add explicit instruction: "Do NOT summarize balance or P&L — Claude already did this"
2. Add 5 specific adversarial questions GPT must answer about risk concentration, drift, timing

---

## KNOWN FAILURE MODES (from session errors log)

| Error | Root Cause | Prevention Gate |
|-------|-----------|-----------------|
| Analysis labeled "limited data" | Sparse log gate not active | Gate: `if line_count < 100 → use yesterday` |
| Recommendation says "BUILD" without log evidence | Analysis skipped mechanism-level check | Gate: `grep "RECOMMENDATION:" output — verify timestamp/dollar evidence in same section` |
| Feed entry missing but file exists | Publish script not called or failed silently | Gate: verify feed.json after every run |
| 404 on Vercel for aether-analysis | Bare filename (not prefixed) | Gate: filename must start with `aether-analysis-` |
| Balance ledger not updated | Session ended without writing to KNOWLEDGE.md | Gate: end-of-session checklist item 1 |

---

## SCHEDULE INTEGRATION

This protocol is part of the nightly reporting cadence:

```
22:45 MT — aether-daily-DATE published (basic daily report)
23:00 MT — aether-analysis-DATE published (this protocol — full analysis with GPT)
23:30 MT — kai-daily-DATE published
```

Both reports (`aether-daily` and `aether-analysis`) must appear in HQ feed by 23:59 MT.  
Morning completeness check at 07:00 MT will flag any missing entries as P1.

---

## REFERENCE EXAMPLE

A correctly-executed analysis is saved at:  
`~/Documents/Projects/Hyo/kai/memory/feedback/AetherBot_Analysis_Apr13-16_reference.txt`

Read it before evaluating whether a new analysis meets the bar. The bar is:
- Every loss traced to its mechanism (not just "loss in EVENING")
- Every strategy family assessed by edge-per-contract (not just win rate)
- One specific recommendation with specific code changes or specific data requirements
- No hedged language ("we may want to consider") — a position, not a report
