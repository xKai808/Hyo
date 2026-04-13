#!/usr/bin/env python3
"""
Kai Dashboard Generator
Reads all data sources and generates a single HTML dashboard.
Runs on Mac Mini via cron at 17:35 MTN (after analysis + fact-check + API check).
Also runs on-demand: python3 generate_dashboard.py

Output: ~/Documents/Projects/Kai/dashboard.html
Open in browser: file:///Users/kai/Documents/Projects/Kai/dashboard.html
"""

import os
import re
import glob
from datetime import datetime, timedelta
from pathlib import Path

# Paths
KAI_DIR = os.path.expanduser("~/Documents/Projects/Kai")
AETHERBOT_DIR = os.path.expanduser("~/Documents/Projects/AetherBot")
LOG_DIR = os.path.join(AETHERBOT_DIR, "Logs")
ANALYSIS_DIR = os.path.join(AETHERBOT_DIR, "Kai analysis")
MEMORY_DIR = os.path.join(KAI_DIR, "memory")
OUTPUT = os.path.join(KAI_DIR, "dashboard.html")


def read_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except:
        return ""


def parse_heartbeat():
    hb = read_file(os.path.join(MEMORY_DIR, "heartbeat.md"))
    if not hb:
        return {"status": "NO DATA", "last_active": "unknown", "bot": "unknown", "log": "unknown", "disk": "unknown", "alerts": "No heartbeat file found"}

    result = {}
    for line in hb.split("\n"):
        if "Last active:" in line:
            result["last_active"] = line.split("Last active:")[1].strip()
        if "AetherBot process" in line and "|" in line:
            parts = [p.strip() for p in line.split("|")]
            result["bot"] = parts[2] if len(parts) > 2 else "unknown"
        if "Log activity" in line and "|" in line:
            parts = [p.strip() for p in line.split("|")]
            result["log"] = parts[2] if len(parts) > 2 else "unknown"
        if "Disk space" in line and "|" in line:
            parts = [p.strip() for p in line.split("|")]
            result["disk"] = parts[2] if len(parts) > 2 else "unknown"

    # Alerts
    alerts = []
    in_alerts = False
    for line in hb.split("\n"):
        if "## Alerts" in line:
            in_alerts = True
            continue
        if in_alerts and line.startswith("- "):
            alerts.append(line[2:].strip())
        elif in_alerts and line.startswith("None"):
            break
        elif in_alerts and line.startswith("---"):
            break

    result["alerts"] = "<br>".join(alerts) if alerts else "None"
    result["status"] = "OK" if not alerts else "ALERT"
    return result


def parse_api_usage():
    """Parse the structured api_usage.md report."""
    usage = read_file(os.path.join(MEMORY_DIR, "api_usage.md"))
    if not usage:
        return {
            "last_checked": "Not yet run",
            "kalshi_balance": "—", "kalshi_portfolio": "—",
            "openai_credits": "—", "openai_used": "—", "openai_granted": "—",
            "openai_usage_month": "—", "openai_limit": "—", "openai_resets": "—",
            "anthropic_cost_today": "—", "anthropic_cost_month": "—", "anthropic_tokens": "—",
            "alerts": "Not yet run"
        }

    result = {"last_checked": "unknown", "alerts": "None"}

    # Generic table row parser: "| Label | Value |" → extract value
    def extract_table_value(section_header, row_label):
        in_section = False
        for line in usage.split("\n"):
            if section_header in line:
                in_section = True
            elif line.startswith("## ") and in_section:
                in_section = False
            if in_section and row_label in line and "|" in line:
                parts = [p.strip() for p in line.split("|")]
                return parts[2] if len(parts) > 2 else "—"
        return "—"

    # Timestamp
    for line in usage.split("\n"):
        if "Last checked:" in line:
            result["last_checked"] = line.split("Last checked:")[1].strip()

    # Alerts
    in_alerts = False
    alert_lines = []
    for line in usage.split("\n"):
        if "## Alerts" in line:
            in_alerts = True
            continue
        elif line.startswith("## ") and in_alerts:
            break
        if in_alerts and line.strip().startswith("- "):
            alert_lines.append(line.strip()[2:])
        elif in_alerts and line.strip() == "None":
            break
    result["alerts"] = "<br>".join(alert_lines) if alert_lines else "None"

    # Kalshi
    result["kalshi_balance"] = extract_table_value("## Kalshi", "Cash balance")
    result["kalshi_portfolio"] = extract_table_value("## Kalshi", "Portfolio value")

    # OpenAI
    result["openai_credits"] = extract_table_value("## OpenAI", "Credits remaining")
    result["openai_used"] = extract_table_value("## OpenAI", "Credits used")
    result["openai_granted"] = extract_table_value("## OpenAI", "Credits granted")
    result["openai_usage_month"] = extract_table_value("## OpenAI", "Usage this month")
    result["openai_limit"] = extract_table_value("## OpenAI", "Spending limit")
    result["openai_resets"] = extract_table_value("## OpenAI", "Resets")

    # Anthropic
    result["anthropic_cost_today"] = extract_table_value("## Anthropic", "API cost today")
    result["anthropic_cost_month"] = extract_table_value("## Anthropic", "API cost this month")
    result["anthropic_tokens"] = extract_table_value("## Anthropic", "Tokens today")

    return result


def parse_balance_ledger():
    """Parse balance data from initialization doc and daily notes."""
    # Known balance data
    balances = [
        ("2026-03-25", None),  # placeholder for chart start
        ("2026-03-28", 89.87),
        ("2026-03-29", 101.25),
        ("2026-03-30", 90.18),
        ("2026-03-31", 110.32),
        ("2026-04-01", 119.02),
        ("2026-04-02", 121.02),
        ("2026-04-03", 111.55),
        ("2026-04-04", 107.30),
        ("2026-04-05", 76.18),
        ("2026-04-06", 93.04),
        ("2026-04-07", 104.02),
        ("2026-04-08", 92.28),
    ]

    # Try to read newer balances from daily notes
    daily_dir = os.path.join(MEMORY_DIR, "daily")
    if os.path.isdir(daily_dir):
        for fname in sorted(os.listdir(daily_dir)):
            if not fname.endswith(".md"):
                continue
            date_str = fname.replace(".md", "")
            content = read_file(os.path.join(daily_dir, fname))
            # Look for "Balance end: $X" or "balance end" patterns
            match = re.search(r'Balance end:\s*\$?([\d.]+)', content)
            if match:
                bal = float(match.group(1))
                # Update if date exists, else append
                found = False
                for i, (d, b) in enumerate(balances):
                    if d == date_str:
                        balances[i] = (d, bal)
                        found = True
                        break
                if not found:
                    balances.append((date_str, bal))

    # Remove None entries and sort
    balances = [(d, b) for d, b in balances if b is not None]
    balances.sort(key=lambda x: x[0])
    return balances


def parse_session_brief():
    """Parse key info from session brief."""
    brief = read_file(os.path.join(MEMORY_DIR, "session_brief.md"))
    if not brief:
        return {"open_issues": [], "priorities": [], "automation": []}

    result = {"open_issues": [], "priorities": [], "automation": []}

    section = None
    for line in brief.split("\n"):
        if "## Open Issues" in line:
            section = "issues"
        elif "## Priority Stack" in line:
            section = "priorities"
        elif "## Automation Status" in line:
            section = "automation"
        elif line.startswith("## "):
            section = None
        elif section == "issues" and line.strip().startswith(("1.", "2.", "3.", "4.", "5.")):
            result["open_issues"].append(line.strip())
        elif section == "priorities" and line.strip().startswith(("1.", "2.", "3.", "4.", "5.")):
            result["priorities"].append(line.strip())

    return result


def get_daily_pnl(balances):
    """Calculate daily P&L from balance changes."""
    pnl = []
    for i in range(1, len(balances)):
        date = balances[i][0]
        change = balances[i][1] - balances[i-1][1]
        pnl.append((date, change))
    return pnl


def calculate_financials(balances):
    """Calculate expense tracking and net position."""
    if not balances:
        return {}

    start_bal = 101.38  # initial deposit
    current_bal = balances[-1][1]
    trading_pnl = current_bal - start_bal

    # Monthly expenses
    claude_monthly = 200.00
    gpt_monthly = 20.00
    # Approximate daily cost (API calls only, not subscription)
    gpt_api_daily = 0.01  # fact-check
    api_monitor_daily = 0.001

    # Days since start (3/28)
    days_active = 12  # 3/28 to 4/8
    trading_days = 9  # excluding weekends

    total_api_cost = (gpt_api_daily + api_monitor_daily) * trading_days
    monthly_fixed = claude_monthly + gpt_monthly

    return {
        "start_balance": start_bal,
        "current_balance": current_bal,
        "trading_pnl": trading_pnl,
        "monthly_fixed": monthly_fixed,
        "daily_api_cost": gpt_api_daily + api_monitor_daily,
        "total_api_cost": total_api_cost,
        "days_active": days_active,
        "trading_days": trading_days,
        "daily_avg_pnl": trading_pnl / trading_days if trading_days > 0 else 0,
        "break_even_daily": monthly_fixed / 22,  # 22 trading days/month
        "peak": max(b for _, b in balances),
        "trough": min(b for _, b in balances),
    }


def generate_html(heartbeat, api_usage, balances, brief, financials):
    now = datetime.now().strftime("%Y-%m-%d %H:%M MTN")
    daily_pnl = get_daily_pnl(balances)

    # Chart data
    balance_labels = [f"'{d[5:]}'" for d, _ in balances]
    balance_values = [str(b) for _, b in balances]
    pnl_labels = [f"'{d[5:]}'" for d, _ in daily_pnl]
    pnl_values = [f"{v:.2f}" for _, v in daily_pnl]
    pnl_colors = [("'#10b981'" if v >= 0 else "'#ef4444'") for _, v in daily_pnl]

    # Use Kalshi live balance if available, otherwise fall back to ledger
    kalshi_bal = api_usage.get("kalshi_balance", "—")
    if kalshi_bal != "—":
        try:
            live_bal = float(kalshi_bal.replace("$", ""))
            financials["current_balance"] = live_bal
            financials["trading_pnl"] = live_bal - financials.get("start_balance", 101.38)
        except:
            pass

    # Status colors
    bot_color = "#10b981" if heartbeat.get("bot", "").startswith("RUNNING") else "#ef4444"
    hb_status_color = "#10b981" if heartbeat.get("status") == "OK" else "#f59e0b"

    # Financial health
    pnl_color = "#10b981" if financials.get("trading_pnl", 0) >= 0 else "#ef4444"
    daily_avg = financials.get("daily_avg_pnl", 0)
    daily_avg_color = "#10b981" if daily_avg >= 0 else "#ef4444"
    be_daily = financials.get("break_even_daily", 10)

    # Open issues HTML
    issues_html = ""
    for issue in brief.get("open_issues", []):
        issues_html += f'<div class="issue-item">{issue}</div>'
    if not issues_html:
        issues_html = '<div class="issue-item">No open issues loaded</div>'

    # Priorities HTML
    priorities_html = ""
    for p in brief.get("priorities", []):
        priorities_html += f'<div class="priority-item">{p}</div>'
    if not priorities_html:
        priorities_html = '<div class="priority-item">No priorities loaded</div>'

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Kai Dashboard</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', sans-serif;
    background: #0a0a0f;
    color: #e4e4e7;
    min-height: 100vh;
    padding: 20px;
}}
.header {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
    padding-bottom: 16px;
    border-bottom: 1px solid #27272a;
}}
.header h1 {{
    font-size: 28px;
    font-weight: 700;
    background: linear-gradient(135deg, #8b5cf6, #6366f1);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}}
.header .timestamp {{
    color: #71717a;
    font-size: 13px;
}}
.grid {{
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
    margin-bottom: 24px;
}}
.card {{
    background: #18181b;
    border: 1px solid #27272a;
    border-radius: 12px;
    padding: 20px;
}}
.card-label {{
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: #71717a;
    margin-bottom: 8px;
}}
.card-value {{
    font-size: 28px;
    font-weight: 700;
}}
.card-sub {{
    font-size: 12px;
    color: #71717a;
    margin-top: 4px;
}}
.grid-2 {{
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 16px;
    margin-bottom: 24px;
}}
.grid-3 {{
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 16px;
    margin-bottom: 24px;
}}
.chart-card {{
    background: #18181b;
    border: 1px solid #27272a;
    border-radius: 12px;
    padding: 20px;
}}
.chart-card h3 {{
    font-size: 14px;
    font-weight: 600;
    margin-bottom: 16px;
    color: #a1a1aa;
}}
.status-card {{
    background: #18181b;
    border: 1px solid #27272a;
    border-radius: 12px;
    padding: 20px;
}}
.status-card h3 {{
    font-size: 14px;
    font-weight: 600;
    margin-bottom: 16px;
    color: #a1a1aa;
}}
.status-row {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 0;
    border-bottom: 1px solid #27272a;
}}
.status-row:last-child {{ border-bottom: none; }}
.status-dot {{
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
    margin-right: 8px;
}}
.status-label {{ font-size: 13px; color: #a1a1aa; }}
.status-value {{ font-size: 13px; font-weight: 500; }}
.expense-table {{
    width: 100%;
    border-collapse: collapse;
    margin-top: 8px;
}}
.expense-table th {{
    text-align: left;
    font-size: 11px;
    text-transform: uppercase;
    color: #71717a;
    padding: 8px 0;
    border-bottom: 1px solid #27272a;
}}
.expense-table td {{
    font-size: 13px;
    padding: 8px 0;
    border-bottom: 1px solid #1e1e23;
}}
.expense-table .amount {{ text-align: right; font-weight: 600; }}
.expense-table .total td {{
    border-top: 2px solid #27272a;
    font-weight: 700;
    padding-top: 12px;
}}
.issue-item, .priority-item {{
    font-size: 13px;
    padding: 8px 0;
    border-bottom: 1px solid #1e1e23;
    line-height: 1.5;
}}
.issue-item:last-child, .priority-item:last-child {{ border-bottom: none; }}
.green {{ color: #10b981; }}
.red {{ color: #ef4444; }}
.yellow {{ color: #f59e0b; }}
.section-title {{
    font-size: 16px;
    font-weight: 600;
    margin-bottom: 16px;
    color: #e4e4e7;
}}
.alert-banner {{
    background: #451a03;
    border: 1px solid #92400e;
    border-radius: 8px;
    padding: 12px 16px;
    margin-bottom: 16px;
    font-size: 13px;
    color: #fbbf24;
    display: {'block' if heartbeat.get('status') != 'OK' else 'none'};
}}
.footer {{
    text-align: center;
    color: #3f3f46;
    font-size: 11px;
    margin-top: 32px;
    padding-top: 16px;
    border-top: 1px solid #1e1e23;
}}
</style>
</head>
<body>

<div class="header">
    <h1>Kai Dashboard</h1>
    <div class="timestamp">Last updated: {now}<br>Refresh: run generate_dashboard.py or wait for 17:35 cron</div>
</div>

<div class="alert-banner">
    {heartbeat.get('alerts', 'None')}
</div>

<!-- Top metrics -->
<div class="grid">
    <div class="card">
        <div class="card-label">AetherBot Balance (Kalshi Live)</div>
        <div class="card-value" style="color: {pnl_color}">${financials.get('current_balance', 0):.2f}</div>
        <div class="card-sub">Portfolio: {api_usage.get('kalshi_portfolio', '—')} | Start: ${financials.get('start_balance', 0):.2f} | Peak: ${financials.get('peak', 0):.2f}</div>
    </div>
    <div class="card">
        <div class="card-label">Trading P&L (All Time)</div>
        <div class="card-value" style="color: {pnl_color}">{'+' if financials.get('trading_pnl', 0) >= 0 else ''}{financials.get('trading_pnl', 0):.2f}</div>
        <div class="card-sub">{financials.get('trading_days', 0)} trading days | Avg: ${daily_avg:.2f}/day</div>
    </div>
    <div class="card">
        <div class="card-label">Break-Even Target</div>
        <div class="card-value" style="color: #f59e0b">${be_daily:.2f}/day</div>
        <div class="card-sub">${financials.get('monthly_fixed', 0):.0f}/mo fixed ÷ 22 trading days</div>
    </div>
    <div class="card">
        <div class="card-label">Bot Status</div>
        <div class="card-value" style="color: {bot_color}">{heartbeat.get('bot', 'Unknown').split('|')[0].strip()}</div>
        <div class="card-sub">Heartbeat: {heartbeat.get('last_active', 'unknown')}</div>
    </div>
</div>

<!-- Charts -->
<div class="grid-2">
    <div class="chart-card">
        <h3>BALANCE HISTORY</h3>
        <canvas id="balanceChart" height="120"></canvas>
    </div>
    <div class="chart-card">
        <h3>DAILY P&L</h3>
        <canvas id="pnlChart" height="120"></canvas>
    </div>
</div>

<!-- Financials + System + Issues -->
<div class="grid-3">
    <div class="status-card">
        <h3>EXPENSES & REVENUE</h3>
        <table class="expense-table">
            <thead>
                <tr><th>Item</th><th class="amount">Monthly</th></tr>
            </thead>
            <tbody>
                <tr><td>Claude Max subscription</td><td class="amount red">-$200.00</td></tr>
                <tr><td>GPT-4o subscription</td><td class="amount red">-$20.00</td></tr>
                <tr><td>GPT API (fact-check)</td><td class="amount red">-$0.22</td></tr>
                <tr><td>Domain (hyo.world)</td><td class="amount red">~-$1.00</td></tr>
                <tr class="total"><td>Monthly Burn</td><td class="amount red">-$221.22</td></tr>
                <tr><td>AetherBot (projected)</td><td class="amount {'green' if daily_avg >= 0 else 'red'}">{'+' if daily_avg >= 0 else ''}${daily_avg * 22:.2f}</td></tr>
                <tr class="total"><td>Net Monthly</td><td class="amount {'green' if (daily_avg * 22 - 221.22) >= 0 else 'red'}">{'+' if (daily_avg * 22 - 221.22) >= 0 else ''}${daily_avg * 22 - 221.22:.2f}</td></tr>
            </tbody>
        </table>
    </div>

    <div class="status-card">
        <h3>SYSTEM STATUS</h3>
        <div class="status-row">
            <span class="status-label"><span class="status-dot" style="background: {bot_color}"></span>AetherBot</span>
            <span class="status-value">{heartbeat.get('bot', 'Unknown')}</span>
        </div>
        <div class="status-row">
            <span class="status-label"><span class="status-dot" style="background: {'#10b981' if 'ACTIVE' in heartbeat.get('log', '') else '#f59e0b'}"></span>Log Activity</span>
            <span class="status-value">{heartbeat.get('log', 'Unknown')}</span>
        </div>
        <div class="status-row">
            <span class="status-label"><span class="status-dot" style="background: #10b981"></span>Disk</span>
            <span class="status-value">{heartbeat.get('disk', 'Unknown')}</span>
        </div>

        <h3 style="margin-top: 16px; margin-bottom: 12px;">OPENAI / GPT-4o</h3>
        <div class="status-row">
            <span class="status-label">Credits remaining</span>
            <span class="status-value" style="color: #10b981">{api_usage.get('openai_credits', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">Used / Granted</span>
            <span class="status-value">{api_usage.get('openai_used', '—')} / {api_usage.get('openai_granted', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">This month</span>
            <span class="status-value">{api_usage.get('openai_usage_month', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">Limit</span>
            <span class="status-value">{api_usage.get('openai_limit', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">Resets</span>
            <span class="status-value">{api_usage.get('openai_resets', '—')}</span>
        </div>

        <h3 style="margin-top: 16px; margin-bottom: 12px;">CLAUDE / ANTHROPIC</h3>
        <div class="status-row">
            <span class="status-label">API cost today</span>
            <span class="status-value">{api_usage.get('anthropic_cost_today', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">API cost this month</span>
            <span class="status-value">{api_usage.get('anthropic_cost_month', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">Tokens today</span>
            <span class="status-value">{api_usage.get('anthropic_tokens', '—')}</span>
        </div>
        <div class="status-row">
            <span class="status-label">Subscription</span>
            <span class="status-value">Max $200/mo</span>
        </div>
        <div class="status-row">
            <span class="status-label">Usage resets</span>
            <span class="status-value">Every 5 hours</span>
        </div>

        <div style="margin-top: 12px; font-size: 11px; color: #52525b;">Last check: {api_usage.get('last_checked', '—')}</div>
    </div>

    <div class="status-card">
        <h3>OPEN ISSUES</h3>
        {issues_html}
        <h3 style="margin-top: 20px;">PRIORITIES</h3>
        {priorities_html}
    </div>
</div>

<div class="footer">
    Kai — CEO of Hyo | Operator of AetherBot | Dashboard auto-generates at 17:35 MTN weekdays
</div>

<script>
// Balance chart
new Chart(document.getElementById('balanceChart'), {{
    type: 'line',
    data: {{
        labels: [{','.join(balance_labels)}],
        datasets: [{{
            label: 'Balance ($)',
            data: [{','.join(balance_values)}],
            borderColor: '#8b5cf6',
            backgroundColor: 'rgba(139, 92, 246, 0.1)',
            fill: true,
            tension: 0.3,
            pointRadius: 4,
            pointBackgroundColor: '#8b5cf6'
        }}, {{
            label: 'Start ($101.38)',
            data: Array({len(balances)}).fill(101.38),
            borderColor: '#3f3f46',
            borderDash: [5, 5],
            pointRadius: 0,
            fill: false
        }}]
    }},
    options: {{
        responsive: true,
        plugins: {{
            legend: {{ display: true, labels: {{ color: '#71717a', font: {{ size: 11 }} }} }}
        }},
        scales: {{
            x: {{ ticks: {{ color: '#52525b', font: {{ size: 10 }} }}, grid: {{ color: '#1e1e23' }} }},
            y: {{ ticks: {{ color: '#52525b', callback: v => '$' + v }}, grid: {{ color: '#1e1e23' }} }}
        }}
    }}
}});

// P&L chart
new Chart(document.getElementById('pnlChart'), {{
    type: 'bar',
    data: {{
        labels: [{','.join(pnl_labels)}],
        datasets: [{{
            label: 'Daily P&L ($)',
            data: [{','.join(pnl_values)}],
            backgroundColor: [{','.join(pnl_colors)}],
            borderRadius: 4
        }}]
    }},
    options: {{
        responsive: true,
        plugins: {{
            legend: {{ display: false }}
        }},
        scales: {{
            x: {{ ticks: {{ color: '#52525b', font: {{ size: 10 }} }}, grid: {{ color: '#1e1e23' }} }},
            y: {{ ticks: {{ color: '#52525b', callback: v => '$' + v }}, grid: {{ color: '#1e1e23' }} }}
        }}
    }}
}});
</script>

</body>
</html>"""

    with open(OUTPUT, "w") as f:
        f.write(html)


if __name__ == "__main__":
    heartbeat = parse_heartbeat()
    api_usage = parse_api_usage()
    balances = parse_balance_ledger()
    brief = parse_session_brief()
    financials = calculate_financials(balances)

    generate_html(heartbeat, api_usage, balances, brief, financials)
    print(f"Dashboard generated: {OUTPUT}")
    print(f"Open: file://{OUTPUT}")
