#!/usr/bin/env python3
"""
Kai API Usage & Balance Monitor
Checks:
  1. Kalshi account balance (live from API)
  2. OpenAI credits: remaining / used / granted + billing cycle
  3. Anthropic API costs (requires admin key)

Runs on Mac Mini via cron at 17:30 MTN.
Output: ~/Documents/Projects/Kai/memory/api_usage.md (for dashboard)

Requirements in ~/Documents/Projects/Kai/.env:
  OPENAI_API_KEY=sk-proj-...
  ANTHROPIC_ADMIN_KEY=sk-ant-admin-... (optional, for Claude API cost tracking)
  KALSHI_API_KEY=<your-kalshi-api-key-id>
  KALSHI_PRIVATE_KEY_PATH=<path-to-private-key.pem>
"""

import os
import sys
import json
import time
import base64
import hashlib
import urllib.request
import urllib.error
from datetime import datetime, timedelta

ENV_FILE = os.path.expanduser("~/Documents/Projects/Kai/.env")
USAGE_FILE = os.path.expanduser("~/Documents/Projects/Kai/memory/api_usage.md")
ANALYSIS_DIR = os.path.expanduser("~/Documents/Projects/AetherBot/Kai analysis")

KALSHI_BASE = "https://api.elections.kalshi.com/trade-api/v2"


def load_env():
    """Load config from .env file."""
    keys = {}
    try:
        with open(ENV_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, val = line.split("=", 1)
                    keys[key.strip()] = val.strip()
    except FileNotFoundError:
        pass
    return keys


# ─── KALSHI ───────────────────────────────────────────────

def kalshi_sign(method, path, timestamp_ms, private_key_path):
    """Generate RSA-PSS signature for Kalshi API auth."""
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
    except ImportError:
        return None, "cryptography package not installed. Run: pip3 install cryptography"

    try:
        with open(private_key_path, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)
    except FileNotFoundError:
        return None, f"Private key not found: {private_key_path}"
    except Exception as e:
        return None, f"Key load error: {e}"

    message = f"{timestamp_ms}{method}{path}".encode()
    try:
        signature = private_key.sign(
            message,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        return base64.b64encode(signature).decode(), None
    except Exception as e:
        return None, f"Signing error: {e}"


def check_kalshi_balance(api_key_id, private_key_path):
    """Get live Kalshi account balance."""
    result = {"balance": "—", "portfolio_value": "—", "error": None}

    if not api_key_id or not private_key_path:
        result["error"] = "Missing KALSHI_API_KEY or KALSHI_PRIVATE_KEY_PATH in .env"
        return result

    path = "/trade-api/v2/portfolio/balance"
    timestamp_ms = str(int(time.time() * 1000))

    sig, err = kalshi_sign("GET", path, timestamp_ms, private_key_path)
    if err:
        result["error"] = err
        return result

    try:
        req = urllib.request.Request(
            f"{KALSHI_BASE}/portfolio/balance",
            headers={
                "KALSHI-ACCESS-KEY": api_key_id,
                "KALSHI-ACCESS-TIMESTAMP": timestamp_ms,
                "KALSHI-ACCESS-SIGNATURE": sig,
                "Content-Type": "application/json"
            }
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            # Balance and portfolio_value are in cents
            balance_cents = data.get("balance", 0)
            portfolio_cents = data.get("portfolio_value", 0)
            result["balance"] = f"${balance_cents / 100:.2f}"
            result["portfolio_value"] = f"${portfolio_cents / 100:.2f}"
            result["balance_raw"] = balance_cents / 100
            result["portfolio_raw"] = portfolio_cents / 100
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        result["error"] = f"HTTP {e.code}: {body[:200]}"
    except Exception as e:
        result["error"] = str(e)

    return result


# ─── OPENAI ───────────────────────────────────────────────

def check_openai(api_key):
    """Check OpenAI usage via organization API + legacy billing endpoints.

    sk-proj- keys may not have billing access (403). In that case we fall
    back to the organization completions usage endpoint and track spend
    from a known starting credit balance.
    """
    result = {
        "credits_remaining": "—",
        "credits_used": "—",
        "credits_granted": "$20.00",  # Known: operator loaded $20 on 4/8
        "usage_this_period": "—",
        "hard_limit": "—",
        "billing_cycle": "End of month",
        "error": None,
        "errors": []
    }

    if not api_key:
        result["error"] = "No OPENAI_API_KEY in .env"
        return result

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    # Track usage from local fact-check log instead of API (sk-proj- keys lack billing access)
    # Each GPT-4o fact-check call costs ~$0.01
    # Count how many fact-checks have run this month from the log
    factcheck_log = os.path.join(
        os.path.expanduser("~/Documents/Projects/AetherBot/Kai analysis"),
        "factcheck_log.txt"
    )
    credits_granted = 20.00  # Loaded 4/8
    calls_this_month = 0
    try:
        now = datetime.now()
        month_prefix = now.strftime("%Y-%m")
        with open(factcheck_log, "r") as f:
            for line in f:
                if month_prefix in line and ("Starting" in line or "Done" in line):
                    calls_this_month += 1
        calls_this_month = calls_this_month // 2  # Start+Done = 1 call
    except:
        pass

    estimated_cost = calls_this_month * 0.01
    remaining = credits_granted - estimated_cost

    result["credits_remaining"] = f"${remaining:.2f}"
    result["credits_remaining_raw"] = remaining
    result["credits_used"] = f"${estimated_cost:.2f}"
    result["usage_this_period"] = f"${estimated_cost:.2f} ({calls_this_month} fact-checks)"
    result["hard_limit"] = "$20.00 prepaid"
    result["billing_cycle"] = "Prepaid (no auto-renew)"

    # Verify the key actually works with a lightweight check
    try:
        # Tiny models list call — costs nothing, confirms key is valid
        req = urllib.request.Request(
            "https://api.openai.com/v1/models",
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            result["key_status"] = "Valid"
    except urllib.error.HTTPError as e:
        if e.code == 401:
            result["key_status"] = "INVALID"
            result["errors"].append("Key rejected (401)")
        else:
            result["key_status"] = "Valid (billing restricted)"
    except Exception as e:
        result["errors"].append(f"key_check: {e}")

    if result["errors"]:
        result["error"] = " | ".join(result["errors"])

    return result


# ─── ANTHROPIC ────────────────────────────────────────────

def check_anthropic(admin_key=None, regular_key=None):
    """Check Anthropic API usage and costs.

    Admin key (sk-ant-admin-*) needed for billing endpoints.
    Regular key (sk-ant-api*) can only verify it works, no billing access.
    """
    result = {
        "cost_today": "~$0 (Max sub)",
        "cost_this_month": "~$0 (Max sub)",
        "tokens_today": "—",
        "key_status": "—",
        "error": None,
        "errors": []
    }

    # If we only have a regular key, verify it works but skip billing
    if not admin_key and regular_key:
        if regular_key.startswith("sk-ant-api"):
            result["key_status"] = "Valid (regular key)"
            result["error"] = "Regular API key — billing needs admin key (sk-ant-admin-*) from console.anthropic.com"
            # We primarily use Claude Max subscription, not API calls
            # So cost tracking is informational, not critical
            return result

    if not admin_key:
        result["key_status"] = "No admin key"
        result["error"] = "Billing needs admin key — but costs are ~$0 since we use Max subscription"
        return result

    headers = {
        "anthropic-version": "2023-06-01",
        "x-api-key": admin_key,
        "Content-Type": "application/json"
    }

    now = datetime.now()
    today_start = now.strftime("%Y-%m-%dT00:00:00Z")
    tomorrow = (now + timedelta(days=1)).strftime("%Y-%m-%dT00:00:00Z")
    month_start = now.replace(day=1).strftime("%Y-%m-%dT00:00:00Z")

    # 1. Today's costs
    try:
        url = f"https://api.anthropic.com/v1/organizations/cost_report?starting_at={today_start}&ending_at={tomorrow}&bucket_width=1d"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            total = 0
            for bucket in data.get("data", []):
                for item in bucket.get("items", []):
                    total += float(item.get("cost_usd", 0))
            result["cost_today"] = f"${total:.4f}"
    except Exception as e:
        result["errors"].append(f"cost_today: {e}")

    # 2. Month-to-date costs
    try:
        url = f"https://api.anthropic.com/v1/organizations/cost_report?starting_at={month_start}&ending_at={tomorrow}&bucket_width=1d"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            total = 0
            for bucket in data.get("data", []):
                for item in bucket.get("items", []):
                    total += float(item.get("cost_usd", 0))
            result["cost_this_month"] = f"${total:.4f}"
    except Exception as e:
        result["errors"].append(f"cost_month: {e}")

    # 3. Today's token usage
    try:
        url = f"https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at={today_start}&ending_at={tomorrow}&bucket_width=1d"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            total_tokens = 0
            for bucket in data.get("data", []):
                for item in bucket.get("items", []):
                    total_tokens += item.get("output_tokens", 0)
                    total_tokens += item.get("uncached_input_tokens", 0)
                    total_tokens += item.get("cached_input_tokens", 0)
            if total_tokens > 1000000:
                result["tokens_today"] = f"{total_tokens/1000000:.1f}M"
            elif total_tokens > 1000:
                result["tokens_today"] = f"{total_tokens/1000:.1f}K"
            else:
                result["tokens_today"] = str(total_tokens)
    except Exception as e:
        result["errors"].append(f"tokens: {e}")

    if result["errors"]:
        result["error"] = " | ".join(result["errors"])

    return result


# ─── REPORT ───────────────────────────────────────────────

def write_report(kalshi, openai_r, anthropic_r):
    """Write structured usage report for dashboard consumption."""
    now = datetime.now()
    timestamp = now.strftime("%Y-%m-%d %H:%M MTN")

    # Determine alert level
    alerts = []
    credits_raw = openai_r.get("credits_remaining_raw", None)
    if credits_raw is not None and credits_raw < 5:
        alerts.append(f"OpenAI credits low: {openai_r['credits_remaining']}")
    if kalshi.get("error"):
        alerts.append(f"Kalshi: {kalshi['error']}")

    alert_str = "\n".join(f"- **{a}**" for a in alerts) if alerts else "None"

    report = f"""# API & Balance Report
Last checked: {timestamp}

## Alerts
{alert_str}

## Kalshi (AetherBot)
| Metric | Value |
|--------|-------|
| Cash balance | {kalshi.get('balance', '—')} |
| Portfolio value | {kalshi.get('portfolio_value', '—')} |
{f"| Error | {kalshi['error']} |" if kalshi.get('error') else ""}

## OpenAI / GPT-4o
| Metric | Value |
|--------|-------|
| Credits remaining | {openai_r.get('credits_remaining', '—')} |
| Credits used | {openai_r.get('credits_used', '—')} |
| Credits granted | {openai_r.get('credits_granted', '—')} |
| Usage this month | {openai_r.get('usage_this_period', '—')} |
| Spending limit | {openai_r.get('hard_limit', '—')} |
| Resets | {openai_r.get('billing_cycle', 'End of calendar month')} |
{f"| Error | {openai_r['error']} |" if openai_r.get('error') else ""}

## Anthropic / Claude API
| Metric | Value |
|--------|-------|
| API cost today | {anthropic_r.get('cost_today', '—')} |
| API cost this month | {anthropic_r.get('cost_this_month', '—')} |
| Tokens today | {anthropic_r.get('tokens_today', '—')} |
| Subscription | Claude Max $200/mo (resets every 5 hours) |
{f"| Error | {anthropic_r['error']} |" if anthropic_r.get('error') else ""}

## Monthly Expense Tracking
| Item | Cost | Type |
|------|------|------|
| Claude Max subscription | $200.00/mo | Fixed |
| GPT-4o subscription | $20.00/mo | Fixed |
| GPT API calls (~22/mo) | ~$0.22/mo | Variable |
| Domain (hyo.world) | ~$1.00/mo | Fixed |
| **Total burn** | **~$221.22/mo** | |
| Break-even daily target | **$10.06/day** | 22 trading days |

---
*Updated daily at 17:30 MTN by api_usage_check.py*
"""

    os.makedirs(os.path.dirname(USAGE_FILE), exist_ok=True)
    with open(USAGE_FILE, "w") as f:
        f.write(report)

    # Also update balance in session brief if Kalshi returned real data
    if kalshi.get("balance_raw") is not None:
        brief_file = os.path.expanduser("~/Documents/Projects/Kai/memory/session_brief.md")
        try:
            with open(brief_file, "r") as f:
                content = f.read()
            # Update the balance line
            import re
            new_bal = f"| AetherBot balance | ${kalshi['balance_raw']:.2f}"
            content = re.sub(
                r'\| AetherBot balance \| \$[\d.]+',
                new_bal,
                content
            )
            with open(brief_file, "w") as f:
                f.write(content)
        except Exception:
            pass

    return report


if __name__ == "__main__":
    env = load_env()

    # Kalshi
    kalshi_key = env.get("KALSHI_API_KEY", "")
    kalshi_pem = env.get("KALSHI_PRIVATE_KEY_PATH", "")
    kalshi_result = check_kalshi_balance(kalshi_key, kalshi_pem)

    # OpenAI
    openai_key = env.get("OPENAI_API_KEY", "")
    openai_result = check_openai(openai_key) if openai_key else {"error": "No OPENAI_API_KEY in .env"}

    # Anthropic
    anthropic_admin = env.get("ANTHROPIC_ADMIN_KEY", "")
    anthropic_regular = env.get("ANTHROPIC_API_KEY", "")
    anthropic_result = check_anthropic(admin_key=anthropic_admin, regular_key=anthropic_regular)

    report = write_report(kalshi_result, openai_result, anthropic_result)

    print(f"Report written to {USAGE_FILE}")
    if kalshi_result.get("balance_raw") is not None:
        print(f"  Kalshi balance: {kalshi_result['balance']}")
    if kalshi_result.get("error"):
        print(f"  Kalshi: {kalshi_result['error']}")
    if openai_result.get("error"):
        print(f"  OpenAI: {openai_result['error']}")
    if anthropic_result.get("error"):
        print(f"  Anthropic: {anthropic_result['error']}")
