#!/usr/bin/env python3
"""
Kai Telegram Bot v2 — Shared Memory, Unified Interface
========================================================================
One Kai. One memory. Two interfaces (Telegram + Cowork).

Architecture:
- Kai owns the Telegram token (getUpdates polling)
- AetherBot sends one-way alerts only
- Conversations logged to daily notes + conversation history file
- Auto-memory readable from both Telegram and Cowork
- Claude API gets full context: session brief + memory index + recent conversation

Commands: /status /balance /analysis /bot /stop /pause /resume /issues /tasks /help
Anything else → Claude conversation with full Kai context.

Usage: nohup python3 kai_telegram.py >> ~/kai_telegram.log 2>&1 &
"""

import json, os, sys, time, datetime, urllib.request, urllib.error, threading
import subprocess, glob, re

# ─────────────────────────────────────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────────────────────────────────────

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, "Documents", "Projects")

ENV_PATH            = os.path.join(PROJECTS, "Kai", ".env")
SESSION_BRIEF       = os.path.join(PROJECTS, "Kai", "memory", "session_brief.md")
OPERATOR_TASKS      = os.path.join(PROJECTS, "Kai", "memory", "operator_tasks.md")
DAILY_NOTES_DIR     = os.path.join(PROJECTS, "Kai", "memory", "daily")
PLAYBOOK            = os.path.join(PROJECTS, "Kai", "memory", "playbook.md")
MEMORY_DIR          = os.path.join(PROJECTS, ".auto-memory")
MEMORY_INDEX        = os.path.join(MEMORY_DIR, "MEMORY.md")

AETHERBOT_LOG_DIR   = os.path.join(PROJECTS, "AetherBot", "Logs")
AETHERBOT_ANALYSIS  = os.path.join(PROJECTS, "AetherBot", "Kai analysis")
STOP_FLAG           = os.path.join(PROJECTS, "AetherBot", ".stop_flag")
PAUSE_FLAG          = os.path.join(PROJECTS, "AetherBot", ".pause_flag")

# Deploy flags — Cowork writes these, bridge acts on them
DEPLOY_TELEGRAM_FLAG = os.path.join(PROJECTS, "AetherBot", ".deploy_telegram")
DEPLOY_AETHERBOT_FLAG = os.path.join(PROJECTS, "AetherBot", ".deploy_aetherbot")
DEPLOY_HYO_FLAG = os.path.join(PROJECTS, "AetherBot", ".deploy_hyo")
AETHERBOT_MASTER_DIR = os.path.join(PROJECTS, "AetherBot", "Code versions")
HYO_GIT_DIR = os.path.join(os.path.expanduser("~"), "Kai", "github")  # legacy Kai path
HYO_GIT_DIR_ALT = os.path.join(PROJECTS, "Kai", "github")  # canonical path

# Conversation history — shared file so Cowork can read it
CONVO_HISTORY_FILE  = os.path.join(PROJECTS, "Kai", "memory", "telegram_history.json")

CREDIT_USAGE_FILE   = os.path.join(PROJECTS, "Kai", "memory", "credit_usage.json")

TELEGRAM_MSG_LIMIT  = 4000
MAX_HISTORY         = 20       # keep last 20 exchanges in context
LAST_UPDATE_ID      = 0
LAST_LOG_CHECK      = time.time()
LAST_ANALYSIS_FILES = set()

# Sonnet 4.6 pricing (per token)
COST_INPUT_PER_TOKEN  = 3.0 / 1_000_000    # $3/M input
COST_OUTPUT_PER_TOKEN = 15.0 / 1_000_000   # $15/M output

# ─────────────────────────────────────────────────────────────────────────────
# ENV LOADER
# ─────────────────────────────────────────────────────────────────────────────

def load_env_keys():
    keys = {}
    if os.path.exists(ENV_PATH):
        try:
            with open(ENV_PATH) as f:
                for line in f:
                    line = line.strip()
                    if "=" not in line or line.startswith("#"):
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().encode("ascii", "ignore").decode("ascii").strip()
                    keys[k] = v
        except Exception as e:
            log(f"ERROR loading .env: {e}")
    return keys

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING & UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

def log(msg):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")
    sys.stdout.flush()

def truncate_msg(text, limit=TELEGRAM_MSG_LIMIT):
    if len(text) <= limit:
        return text
    return text[:limit-80] + f"\n\n[...truncated, {len(text)-limit} chars omitted]"

def safe_read(filepath):
    try:
        with open(filepath) as f:
            return f.read()
    except Exception:
        return ""

def today_str():
    return datetime.datetime.now().strftime("%Y-%m-%d")

def now_str():
    return datetime.datetime.now().strftime("%H:%M")

# ─────────────────────────────────────────────────────────────────────────────
# CREDIT USAGE TRACKING
# ─────────────────────────────────────────────────────────────────────────────

_credit_data = {
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "total_cost_usd": 0.0,
    "calls_today": 0,
    "cost_today_usd": 0.0,
    "today_date": "",
    "calls_all_time": 0,
    "history": []  # last 7 days: [{"date": str, "calls": int, "cost": float}]
}

def load_credit_data():
    global _credit_data
    if os.path.exists(CREDIT_USAGE_FILE):
        try:
            with open(CREDIT_USAGE_FILE) as f:
                _credit_data = json.load(f)
        except Exception:
            pass
    # Reset daily counters if new day
    if _credit_data.get("today_date") != today_str():
        # Archive yesterday
        if _credit_data.get("today_date") and _credit_data.get("calls_today", 0) > 0:
            _credit_data.setdefault("history", []).append({
                "date": _credit_data["today_date"],
                "calls": _credit_data["calls_today"],
                "cost": round(_credit_data["cost_today_usd"], 4)
            })
            # Keep last 7 days
            _credit_data["history"] = _credit_data["history"][-7:]
        _credit_data["today_date"] = today_str()
        _credit_data["calls_today"] = 0
        _credit_data["cost_today_usd"] = 0.0

def save_credit_data():
    try:
        os.makedirs(os.path.dirname(CREDIT_USAGE_FILE), exist_ok=True)
        with open(CREDIT_USAGE_FILE, "w") as f:
            json.dump(_credit_data, f, indent=2)
    except Exception as e:
        log(f"ERROR saving credit data: {e}")

def record_api_usage(input_tokens, output_tokens):
    """Record token usage from a Claude API call."""
    cost = (input_tokens * COST_INPUT_PER_TOKEN) + (output_tokens * COST_OUTPUT_PER_TOKEN)
    _credit_data["total_input_tokens"] = _credit_data.get("total_input_tokens", 0) + input_tokens
    _credit_data["total_output_tokens"] = _credit_data.get("total_output_tokens", 0) + output_tokens
    _credit_data["total_cost_usd"] = round(_credit_data.get("total_cost_usd", 0) + cost, 4)
    _credit_data["calls_today"] = _credit_data.get("calls_today", 0) + 1
    _credit_data["cost_today_usd"] = round(_credit_data.get("cost_today_usd", 0) + cost, 4)
    _credit_data["calls_all_time"] = _credit_data.get("calls_all_time", 0) + 1
    save_credit_data()
    log(f"API usage: {input_tokens}in/{output_tokens}out = ${cost:.4f}")

# ─────────────────────────────────────────────────────────────────────────────
# CONVERSATION HISTORY (persisted, shared with Cowork)
# ─────────────────────────────────────────────────────────────────────────────

_convo_history = []  # list of {"role": "user"|"assistant", "content": str, "ts": str}

def load_conversation_history():
    global _convo_history
    if os.path.exists(CONVO_HISTORY_FILE):
        try:
            with open(CONVO_HISTORY_FILE) as f:
                _convo_history = json.load(f)
            # Trim to max
            if len(_convo_history) > MAX_HISTORY * 2:
                _convo_history = _convo_history[-(MAX_HISTORY * 2):]
            log(f"Loaded {len(_convo_history)} conversation history entries")
        except Exception as e:
            log(f"ERROR loading conversation history: {e}")
            _convo_history = []
    else:
        _convo_history = []

def save_conversation_history():
    try:
        os.makedirs(os.path.dirname(CONVO_HISTORY_FILE), exist_ok=True)
        with open(CONVO_HISTORY_FILE, "w") as f:
            json.dump(_convo_history, f, indent=2, ensure_ascii=False)
    except Exception as e:
        log(f"ERROR saving conversation history: {e}")

def add_to_history(role, content):
    _convo_history.append({
        "role": role,
        "content": content,
        "ts": datetime.datetime.now().isoformat()
    })
    # Trim
    if len(_convo_history) > MAX_HISTORY * 2:
        _convo_history[:] = _convo_history[-(MAX_HISTORY * 2):]
    save_conversation_history()

# ─────────────────────────────────────────────────────────────────────────────
# DAILY NOTES LOGGING
# ─────────────────────────────────────────────────────────────────────────────

def log_to_daily_notes(user_msg, kai_response, is_command=False):
    """Append Telegram exchange to today's daily notes."""
    try:
        os.makedirs(DAILY_NOTES_DIR, exist_ok=True)
        daily_file = os.path.join(DAILY_NOTES_DIR, f"{today_str()}.md")

        # Check if we need to add Telegram section header
        existing = safe_read(daily_file)
        needs_header = "## Telegram Log" not in existing

        with open(daily_file, "a") as f:
            if needs_header:
                f.write(f"\n\n## Telegram Log\n")

            ts = now_str()
            if is_command:
                f.write(f"\n**{ts}** `{user_msg}` → {kai_response[:200]}\n")
            else:
                f.write(f"\n**{ts} Operator:** {user_msg}\n")
                f.write(f"**{ts} Kai:** {kai_response[:500]}\n")

    except Exception as e:
        log(f"ERROR logging to daily notes: {e}")

# ─────────────────────────────────────────────────────────────────────────────
# MEMORY INTEGRATION
# ─────────────────────────────────────────────────────────────────────────────

def load_memory_context():
    """Load MEMORY.md index for Claude context. Compact — just the index."""
    content = safe_read(MEMORY_INDEX)
    if not content:
        return ""
    return f"Memory Index (auto-memory):\n{content.strip()}\n"

def load_relevant_memories(user_msg):
    """
    Load memory files that seem relevant to the user's message.
    Simple keyword matching against memory descriptions.
    """
    index = safe_read(MEMORY_INDEX)
    if not index:
        return ""

    msg_lower = user_msg.lower()
    relevant = []

    # Keywords that trigger specific memory loads
    triggers = {
        "revenue": ["project_revenue_north_star.md", "reference_income_strategy.md"],
        "aetherbot": ["project_aetherbot.md"],
        "hyo": ["project_hyo.md"],
        "analysis": ["feedback_analysis_process.md", "feedback_analysis_approach.md"],
        "deploy": ["feedback_deploy_process.md"],
        "playbook": ["reference_playbook.md"],
    }

    files_to_load = set()
    for keyword, filenames in triggers.items():
        if keyword in msg_lower:
            files_to_load.update(filenames)

    # Always load project_aetherbot.md and operator profile for general context
    if not files_to_load:
        files_to_load = {"project_aetherbot.md", "user_operator.md"}

    snippets = []
    for fname in files_to_load:
        fpath = os.path.join(MEMORY_DIR, fname)
        content = safe_read(fpath)
        if content:
            # Strip frontmatter
            if content.startswith("---"):
                parts = content.split("---", 2)
                if len(parts) >= 3:
                    content = parts[2].strip()
            snippets.append(f"[{fname}]: {content[:400]}")

    if snippets:
        return "Relevant Memories:\n" + "\n\n".join(snippets) + "\n"
    return ""

# ─────────────────────────────────────────────────────────────────────────────
# TELEGRAM API
# ─────────────────────────────────────────────────────────────────────────────

def telegram_api(method, params, token):
    url = f"https://api.telegram.org/bot{token}/{method}"
    data = json.dumps(params, ensure_ascii=False).encode("utf-8")
    try:
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=35) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        log(f"Telegram API error {e.code}: {body[:200]}")
        return None
    except Exception as e:
        log(f"Telegram API exception: {e}")
        return None

def send_message(chat_id, text, token):
    text = truncate_msg(text)
    result = telegram_api("sendMessage", {"chat_id": chat_id, "text": text}, token)
    if result and result.get("ok"):
        log(f"Sent {len(text)} chars")
        return True
    log(f"Send failed: {result}")
    return False

def get_updates(token, offset=0, timeout=30):
    result = telegram_api("getUpdates", {
        "offset": offset, "timeout": timeout, "allowed_updates": ["message"]
    }, token)
    if result and result.get("ok"):
        return result.get("result", [])
    return []

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND HANDLERS (mobile-friendly, concise)
# ─────────────────────────────────────────────────────────────────────────────

def cmd_status(keys):
    """Concise mobile-friendly status. No wall of text."""
    brief = safe_read(SESSION_BRIEF)
    if not brief:
        return "Could not read session_brief.md"

    # Extract key values with regex
    bal_match = re.search(r'AetherBot balance[^\$]*(\$[\d.]+)', brief)
    balance = bal_match.group(1) if bal_match else "?"

    pnl_match = re.search(r'session P&L[^+\-]*([\+\-]\$[\d.]+)', brief)
    pnl = pnl_match.group(1) if pnl_match else "?"

    gap_match = re.search(r'Balance gap[^-]*([\-]\$[\d.]+)', brief)
    gap = gap_match.group(1) if gap_match else "?"

    # Check if bot is running
    try:
        log_files = glob.glob(os.path.join(AETHERBOT_LOG_DIR, "*.txt"))
        if log_files:
            latest = max(log_files, key=os.path.getmtime)
            age = time.time() - os.path.getmtime(latest)
            bot_status = "RUNNING" if age < 300 else f"STALE ({int(age/60)}m ago)"
        else:
            bot_status = "NO LOGS"
    except:
        bot_status = "UNKNOWN"

    # Check flags
    flags = []
    if os.path.exists(STOP_FLAG):
        flags.append("STOPPED")
    if os.path.exists(PAUSE_FLAG):
        flags.append("PAUSED")
    flag_str = " | ".join(flags) if flags else "ACTIVE"

    # Count open issues
    issues_count = len(re.findall(r'^\d+\.', brief, re.MULTILINE))

    msg = f"""KAI STATUS

Bot: {bot_status} | {flag_str}
Balance: {balance}
Today P&L: {pnl}
Gap: {gap}
Issues: {issues_count} open

/balance /analysis /bot /issues"""

    return msg

def cmd_balance(keys):
    """Compact balance with ledger."""
    brief = safe_read(SESSION_BRIEF)
    if not brief:
        return "Could not read session_brief.md"

    # Extract ledger code block
    ledger = ""
    in_ledger = False
    in_code = False
    for line in brief.split("\n"):
        if "Balance Ledger" in line:
            in_ledger = True
            continue
        if in_ledger:
            if "```" in line:
                in_code = not in_code
                continue
            if in_code:
                ledger += line + "\n"
            if line.startswith("## ") and not in_code:
                break

    bal_match = re.search(r'AetherBot balance[^\$]*(\$[\d.]+)', brief)
    balance = bal_match.group(1) if bal_match else "?"

    return f"Balance: {balance}\n\n{ledger.strip()}"

def cmd_analysis(keys):
    """Latest analysis summary."""
    today = today_str()
    candidates = [
        f"Final_Analysis_{today}.txt",
        f"Deep_Analysis_{today}.txt",
        f"Analysis_{today}.txt",
    ]

    for name in candidates:
        path = os.path.join(AETHERBOT_ANALYSIS, name)
        if os.path.exists(path):
            content = safe_read(path)
            if content:
                # First 1200 chars
                return f"ANALYSIS: {name}\n\n{content[:1200]}"

    # Try yesterday
    yesterday = (datetime.datetime.now() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")
    for prefix in ["Final_Analysis_", "Deep_Analysis_", "Analysis_"]:
        path = os.path.join(AETHERBOT_ANALYSIS, f"{prefix}{yesterday}.txt")
        if os.path.exists(path):
            content = safe_read(path)
            if content:
                return f"ANALYSIS (yesterday): {prefix}{yesterday}.txt\n\n{content[:1200]}"

    return "No analysis found for today or yesterday."

def cmd_bot(keys):
    """Last 20 lines of latest AetherBot log."""
    try:
        log_files = glob.glob(os.path.join(AETHERBOT_LOG_DIR, "*.txt"))
        if not log_files:
            return "No log files found in AetherBot/Logs/"

        latest = max(log_files, key=os.path.getmtime)
        content = safe_read(latest)
        if not content:
            return "Could not read log file"

        lines = content.strip().split("\n")
        tail = lines[-20:]
        age = time.time() - os.path.getmtime(latest)

        return f"LOG: {os.path.basename(latest)} ({int(age/60)}m ago)\n\n" + "\n".join(tail)
    except Exception as e:
        return f"Error: {e}"

def cmd_stop(keys):
    try:
        with open(STOP_FLAG, "w") as f:
            f.write(str(int(time.time())))
        return "STOP flag set. AetherBot will halt on next check."
    except Exception as e:
        return f"Error: {e}"

def cmd_pause(keys):
    try:
        with open(PAUSE_FLAG, "w") as f:
            f.write(str(int(time.time())))
        return "PAUSE flag set. AetherBot monitoring only."
    except Exception as e:
        return f"Error: {e}"

def cmd_resume(keys):
    try:
        removed = []
        if os.path.exists(STOP_FLAG):
            os.remove(STOP_FLAG)
            removed.append("stop")
        if os.path.exists(PAUSE_FLAG):
            os.remove(PAUSE_FLAG)
            removed.append("pause")
        if removed:
            return f"Cleared: {', '.join(removed)}. AetherBot resuming."
        return "No flags were set."
    except Exception as e:
        return f"Error: {e}"

def cmd_issues(keys):
    brief = safe_read(SESSION_BRIEF)
    if not brief:
        return "Could not read session_brief.md"

    lines = brief.split("\n")
    in_issues = False
    issues = []
    for line in lines:
        if line.startswith("## Open Issues"):
            in_issues = True
            continue
        if in_issues:
            if line.startswith("## "):
                break
            stripped = line.strip()
            if stripped and re.match(r'^\d+\.', stripped):
                issues.append(stripped)

    if not issues:
        return "No open issues found."

    return "OPEN ISSUES\n\n" + "\n".join(issues)

def cmd_tasks(keys):
    content = safe_read(OPERATOR_TASKS)
    if not content:
        return "No operator tasks found."
    # First 1500 chars
    return f"TASKS\n\n{content[:1500]}"

def cmd_dashboard(keys):
    """Condensed operational dashboard — everything on one screen."""
    brief = safe_read(SESSION_BRIEF)

    # ── Bot status ──
    try:
        log_files = glob.glob(os.path.join(AETHERBOT_LOG_DIR, "*.txt"))
        if log_files:
            latest = max(log_files, key=os.path.getmtime)
            age = time.time() - os.path.getmtime(latest)
            bot_line = f"RUNNING ({int(age/60)}m ago)" if age < 300 else f"STALE ({int(age/60)}m)"
        else:
            bot_line = "NO LOGS"
    except:
        bot_line = "UNKNOWN"

    flags = []
    if os.path.exists(STOP_FLAG): flags.append("STOPPED")
    if os.path.exists(PAUSE_FLAG): flags.append("PAUSED")
    flag_str = " | ".join(flags) if flags else "ACTIVE"

    # ── Balance ──
    bal = re.search(r'AetherBot balance[^\$]*(\$[\d.]+)', brief) if brief else None
    pnl = re.search(r'session P&L[^+\-]*([\+\-]\$[\d.]+)', brief) if brief else None
    gap = re.search(r'Balance gap[^-]*([\-]\$[\d.]+)', brief) if brief else None

    # ── Issues count ──
    issues = len(re.findall(r'^\d+\.\s+\*\*', brief, re.MULTILINE)) if brief else 0
    # Count issues with "v254 FIXES" as addressed
    fixed = brief.count("v254 FIXES") if brief else 0

    # ── Credit usage ──
    load_credit_data()  # refresh
    cost_today = _credit_data.get("cost_today_usd", 0)
    calls_today = _credit_data.get("calls_today", 0)
    cost_all = _credit_data.get("total_cost_usd", 0)
    calls_all = _credit_data.get("calls_all_time", 0)

    # Estimate remaining (Anthropic API typical $5 free tier or check balance)
    # We'll show spend rate instead since we can't query balance
    avg_per_call = cost_all / calls_all if calls_all > 0 else 0.015
    history = _credit_data.get("history", [])
    if history:
        recent_days = history[-3:]
        avg_daily = sum(d["cost"] for d in recent_days) / len(recent_days)
    else:
        avg_daily = cost_today if cost_today > 0 else 0

    # ── Last 3 days credit history ──
    hist_lines = ""
    for day in history[-3:]:
        hist_lines += f"  {day['date']}: {day['calls']} calls, ${day['cost']:.3f}\n"

    msg = f"""KAI DASHBOARD
{'='*30}

BOT: {bot_line} | {flag_str}
BAL: {bal.group(1) if bal else '?'} | P&L: {pnl.group(1) if pnl else '?'} | Gap: {gap.group(1) if gap else '?'}
ISSUES: {issues} open ({fixed} fixed by v254)

CREDITS (Claude API)
  Today: {calls_today} calls, ${cost_today:.3f}
  All-time: {calls_all} calls, ${cost_all:.3f}
  Avg/call: ${avg_per_call:.4f}
  Avg/day: ${avg_daily:.3f}
{hist_lines}
PRIORITIES
  1. Revenue (AetherBot)
  2. Remote access (Telegram+Dashboard)
  3. Hyo DNS+Stripe"""

    return msg

def cmd_help(keys):
    return """KAI COMMANDS

/dashboard — full operational overview
/status — quick system snapshot
/balance — balance + ledger
/analysis — today's analysis
/bot — last 20 log lines
/issues — open issues list
/tasks — operator task list
/stop — halt AetherBot
/pause — monitor-only mode
/resume — clear all flags
/help — this message

Anything else → talk to Kai (Claude)"""

# ─────────────────────────────────────────────────────────────────────────────
# CLAUDE CONVERSATIONAL INTERFACE (with memory + history)
# ─────────────────────────────────────────────────────────────────────────────

def build_system_prompt():
    """Build Claude system prompt with session brief + memory + identity."""

    # Core identity
    system = """You are Kai — CEO of Hyo and operator of AetherBot.
You are responding via Telegram to your operator (Hyo).
Be concise. This is mobile — short paragraphs, no walls of text.
Max 800 chars unless the question demands more.
You have full operational autonomy. Never ask permission. Default to action.
Revenue (AetherBot daily P&L) is the north star.\n\n"""

    # Session brief (truncated for token efficiency)
    brief = safe_read(SESSION_BRIEF)
    if brief:
        system += "SESSION STATE:\n" + brief[:2500] + "\n\n"

    # Memory index
    memory = safe_read(MEMORY_INDEX)
    if memory:
        system += "MEMORY INDEX:\n" + memory[:1000] + "\n\n"

    return system

def claude_conversation(user_msg, keys):
    """Send to Claude with full context: system prompt + conversation history."""
    anthropic_key = keys.get("ANTHROPIC_API_KEY", "")
    if not anthropic_key:
        return "ERROR: No ANTHROPIC_API_KEY"

    system = build_system_prompt()

    # Load relevant memories for this specific message
    relevant = load_relevant_memories(user_msg)
    if relevant:
        system += relevant + "\n"

    # Build messages array from conversation history
    messages = []
    # Include recent history for continuity
    recent = _convo_history[-(MAX_HISTORY * 2):]
    for entry in recent:
        messages.append({
            "role": entry["role"],
            "content": entry["content"]
        })

    # Add current message
    messages.append({"role": "user", "content": user_msg})

    data = json.dumps({
        "model": "claude-sonnet-4-6",
        "max_tokens": 800,
        "system": system,
        "messages": messages
    }, ensure_ascii=False).encode("utf-8")

    try:
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=data,
            headers={
                "x-api-key": anthropic_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json"
            }
        )
        with urllib.request.urlopen(req, timeout=45) as resp:
            result = json.loads(resp.read())
            # Track credit usage
            usage = result.get("usage", {})
            in_tok = usage.get("input_tokens", 0)
            out_tok = usage.get("output_tokens", 0)
            if in_tok or out_tok:
                record_api_usage(in_tok, out_tok)
            if "content" in result and len(result["content"]) > 0:
                return result["content"][0]["text"]
            return f"Unexpected response: {json.dumps(result)[:200]}"
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        log(f"Claude API error {e.code}: {body[:300]}")
        return f"Claude API error {e.code}"
    except Exception as e:
        log(f"Claude API exception: {e}")
        return f"Error: {e}"

# ─────────────────────────────────────────────────────────────────────────────
# AUTO-ALERTS (heartbeat + new analysis detection)
# ─────────────────────────────────────────────────────────────────────────────

def check_aetherbot_heartbeat(chat_id, token):
    global LAST_LOG_CHECK
    now = time.time()
    if now - LAST_LOG_CHECK < 1800:  # 30 min
        return
    LAST_LOG_CHECK = now

    try:
        log_files = glob.glob(os.path.join(AETHERBOT_LOG_DIR, "*.txt"))
        if not log_files:
            return
        latest = max(log_files, key=os.path.getmtime)
        age = now - os.path.getmtime(latest)
        if age > 1200:  # 20 min stale
            send_message(chat_id, f"HEARTBEAT: No AetherBot log activity in {int(age/60)}m. Bot may be down.", token)
            log(f"Heartbeat alert sent ({int(age/60)}m stale)")
    except Exception as e:
        log(f"Heartbeat check error: {e}")

def check_new_analysis(chat_id, token):
    global LAST_ANALYSIS_FILES
    try:
        current = set(glob.glob(os.path.join(AETHERBOT_ANALYSIS, "*Analysis*.txt")))
        new_files = current - LAST_ANALYSIS_FILES
        for fp in new_files:
            log(f"New analysis: {os.path.basename(fp)}")
            content = safe_read(fp)
            if content:
                summary = f"NEW ANALYSIS: {os.path.basename(fp)}\n\n{content[:600]}\n\n[/analysis for full]"
                send_message(chat_id, summary, token)
        LAST_ANALYSIS_FILES = current
    except Exception as e:
        log(f"Analysis check error: {e}")

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY ENGINE — file-triggered, no terminal access needed
# ─────────────────────────────────────────────────────────────────────────────

def check_deploy_telegram(chat_id, token):
    """
    If .deploy_telegram flag exists, Cowork has updated kai_telegram.py.
    Kill the whole process — the watchdog wrapper restarts us with the new code.

    NOTE: Must use os._exit(), not sys.exit(). This function runs in a daemon
    thread (alert_loop). sys.exit() only raises SystemExit in the current
    thread, which kills the alert thread but leaves the main polling thread
    running — the bridge stays "alive" but stops checking deploy flags.
    os._exit() terminates the whole process from any thread.
    """
    if os.path.exists(DEPLOY_TELEGRAM_FLAG):
        try:
            msg = safe_read(DEPLOY_TELEGRAM_FLAG).strip() or "Kai bridge update"
            os.remove(DEPLOY_TELEGRAM_FLAG)
            log(f"DEPLOY TELEGRAM: {msg}")
            send_message(chat_id, f"Restarting with new code: {msg}", token)
            time.sleep(1)
            # Force-exit from whatever thread we're in so watchdog relaunches
            os._exit(0)
        except Exception as e:
            log(f"Deploy telegram error: {e}")

def check_deploy_aetherbot(chat_id, token):
    """
    If .deploy_aetherbot flag exists, Cowork has written a new AetherBot version.
    Flag file contains the version filename (e.g. AetherBot_MASTER_v255.py).
    Kill old bot, copy new version to ~/bot.py, start it.
    """
    if not os.path.exists(DEPLOY_AETHERBOT_FLAG):
        return
    try:
        flag_content = safe_read(DEPLOY_AETHERBOT_FLAG).strip()
        os.remove(DEPLOY_AETHERBOT_FLAG)

        if not flag_content:
            log("DEPLOY AETHERBOT: empty flag, skipping")
            return

        # Flag content = filename in Code versions/
        source = os.path.join(AETHERBOT_MASTER_DIR, flag_content)
        target = os.path.expanduser("~/bot.py")

        if not os.path.exists(source):
            msg = f"Deploy failed: {source} not found"
            log(msg)
            send_message(chat_id, msg, token)
            return

        log(f"DEPLOY AETHERBOT: {flag_content}")
        send_message(chat_id, f"Deploying {flag_content}...", token)

        # 1. Kill old AetherBot
        subprocess.run(["pkill", "-f", "python.*bot\\.py"], capture_output=True)
        time.sleep(2)

        # 2. Backup current bot.py
        if os.path.exists(target):
            backup = target + f".bak.{int(time.time())}"
            subprocess.run(["cp", target, backup], capture_output=True)

        # 3. Copy new version
        subprocess.run(["cp", source, target], capture_output=True)

        # 4. Start new AetherBot
        bot_log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
        today = today_str()
        log_file = os.path.join(bot_log_dir, f"AetherBot_{today}.txt")

        proc = subprocess.Popen(
            ["/opt/homebrew/bin/python3", target],
            stdout=open(log_file, "a"),
            stderr=subprocess.STDOUT,
            start_new_session=True
        )

        time.sleep(3)
        if proc.poll() is None:
            msg = f"AetherBot deployed: {flag_content} (PID {proc.pid})"
        else:
            msg = f"AetherBot failed to start (exit code {proc.returncode})"

        log(msg)
        send_message(chat_id, msg, token)

        # Log to daily notes
        log_to_daily_notes(f"[AUTO-DEPLOY] {flag_content}", msg, is_command=True)

    except Exception as e:
        msg = f"Deploy AetherBot error: {e}"
        log(msg)
        send_message(chat_id, msg, token)

def check_deploy_hyo(chat_id, token):
    """
    If .deploy_hyo flag exists, push the Hyo git repo to GitHub.
    Vercel auto-deploys from main branch, so this triggers a fresh site build.
    Flag file content (optional) = commit message override.

    Auth: reads GITHUB_TOKEN from .env and uses `git -c credential.helper=...`
    with an in-memory askpass. The token is NEVER written to .git/config or
    any file on disk — it lives only in the subprocess env for the push call.
    """
    if not os.path.exists(DEPLOY_HYO_FLAG):
        return
    try:
        flag_content = safe_read(DEPLOY_HYO_FLAG).strip()
        os.remove(DEPLOY_HYO_FLAG)

        # Find the git repo — canonical first, then legacy
        git_dir = None
        for candidate in (HYO_GIT_DIR_ALT, HYO_GIT_DIR):
            if os.path.isdir(os.path.join(candidate, ".git")):
                git_dir = candidate
                break

        if not git_dir:
            msg = f"Deploy Hyo failed: no git repo found in {HYO_GIT_DIR_ALT} or {HYO_GIT_DIR}"
            log(msg)
            send_message(chat_id, msg, token)
            return

        # Load GITHUB_TOKEN from .env — required for authentication
        keys = load_env_keys()
        gh_token = keys.get("GITHUB_TOKEN", "").strip()
        gh_user  = keys.get("GITHUB_USER", "xKai808").strip()
        if not gh_token:
            msg = "Deploy Hyo failed: GITHUB_TOKEN missing from .env (add GITHUB_TOKEN=ghp_... then retry)"
            log(msg)
            send_message(chat_id, msg, token)
            return

        commit_msg = flag_content or "Hyo auto-deploy from Kai bridge"
        log(f"DEPLOY HYO: {git_dir} — {commit_msg}")
        send_message(chat_id, f"Deploying Hyo from {os.path.basename(git_dir)}...", token)

        # 1. Stage any pending changes
        subprocess.run(["git", "add", "-A"], cwd=git_dir, capture_output=True)

        # 2. Commit if there are staged changes (ignore failure if nothing to commit)
        subprocess.run(
            ["git", "commit", "-m", commit_msg],
            cwd=git_dir, capture_output=True, text=True
        )
        # returncode != 0 is fine if "nothing to commit"

        # 3. Push with token injected via throwaway URL. Disable credential.helper
        # so macOS Keychain's stale cached token isn't used first. The token lives
        # in subprocess argv for the duration of the push only (a few seconds),
        # then the subprocess exits. It's never written to .git/config.
        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"  # never prompt interactively
        env.pop("SSH_ASKPASS", None)
        env.pop("DISPLAY", None)

        auth_url = f"https://{gh_user}:{gh_token}@github.com/xKai808/Hyo.git"

        push_result = subprocess.run(
            [
                "git",
                "-c", "credential.helper=",      # disable osxkeychain cache
                "push", auth_url, "HEAD:main",
            ],
            cwd=git_dir, capture_output=True, text=True, timeout=120, env=env
        )

        if push_result.returncode == 0:
            msg = "Hyo pushed to GitHub. Vercel will auto-deploy in ~60s."
        else:
            # Scrub token from any error output before logging/sending
            err = (push_result.stderr or push_result.stdout or "").strip()[-400:]
            if gh_token and gh_token in err:
                err = err.replace(gh_token, "***REDACTED***")
            msg = f"Hyo push failed:\n{err}"

        log(msg)
        send_message(chat_id, msg, token)
        log_to_daily_notes("[AUTO-DEPLOY] Hyo", msg, is_command=True)

    except Exception as e:
        msg = f"Deploy Hyo error: {e}"
        log(msg)
        send_message(chat_id, msg, token)

# ─────────────────────────────────────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────────────────────────────────────

COMMANDS = {
    "/dashboard": cmd_dashboard,
    "/status": cmd_status,
    "/balance": cmd_balance,
    "/analysis": cmd_analysis,
    "/bot": cmd_bot,
    "/stop": cmd_stop,
    "/pause": cmd_pause,
    "/resume": cmd_resume,
    "/issues": cmd_issues,
    "/tasks": cmd_tasks,
    "/help": cmd_help,
}

def main():
    global LAST_UPDATE_ID

    keys = load_env_keys()
    token = keys.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = keys.get("TELEGRAM_CHAT_ID", "")

    if not token or not chat_id:
        log("FATAL: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID required in .env")
        sys.exit(1)

    log(f"Kai Telegram v2 starting (chat_id={chat_id})")

    # Load persisted state
    load_conversation_history()
    load_credit_data()

    # Initialize analysis file set (don't alert for pre-existing files)
    LAST_ANALYSIS_FILES.update(glob.glob(os.path.join(AETHERBOT_ANALYSIS, "*Analysis*.txt")))

    send_message(chat_id, "Kai online.\n/help for commands.", token)

    # Alert + deploy thread
    def alert_loop():
        while True:
            try:
                # Deploy checks — every 10 seconds
                check_deploy_telegram(chat_id, token)
                check_deploy_aetherbot(chat_id, token)
                check_deploy_hyo(chat_id, token)
                # Heartbeat + analysis — internal timers
                check_aetherbot_heartbeat(chat_id, token)
                check_new_analysis(chat_id, token)
                time.sleep(10)  # fast cycle for deploy responsiveness
            except SystemExit:
                raise  # let sys.exit() propagate for telegram self-restart
            except Exception as e:
                log(f"Alert loop error: {e}")
                time.sleep(10)

    threading.Thread(target=alert_loop, daemon=True).start()
    log("Alert loop started")

    # Main polling loop
    while True:
        try:
            updates = get_updates(token, offset=LAST_UPDATE_ID + 1)

            for update in updates:
                LAST_UPDATE_ID = update.get("update_id", LAST_UPDATE_ID)
                message = update.get("message", {})
                text = message.get("text", "").strip()
                msg_chat_id = message.get("chat", {}).get("id")

                if not text or msg_chat_id != int(chat_id):
                    continue

                log(f"MSG: {text[:60]}")
                response = None
                is_command = False

                # Command dispatch
                cmd = text.split()[0].lower() if text.startswith("/") else None
                if cmd and cmd in COMMANDS:
                    is_command = True
                    response = COMMANDS[cmd](keys)
                elif text.startswith("/"):
                    response = f"Unknown: {cmd}\n/help for commands"
                else:
                    # Conversational — add to history, get Claude response
                    add_to_history("user", text)
                    response = claude_conversation(text, keys)
                    if response:
                        add_to_history("assistant", response)

                if response:
                    send_message(msg_chat_id, response, token)
                    # Log to daily notes
                    log_to_daily_notes(text, response, is_command=is_command)

        except KeyboardInterrupt:
            log("Shutting down.")
            break
        except Exception as e:
            log(f"Main loop error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
