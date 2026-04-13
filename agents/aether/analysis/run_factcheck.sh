#!/bin/zsh
# AetherBot GPT Fact-Check — runs weekdays at 17:15 MTN
# Two modes:
#   1. Analysis fact-check (default): critique today's analysis
#   2. Daily log review (--log): independent review of raw trading log
#
# Cron: 15 17 * * 1-5  (analysis)
#        0 22 * * 1-5  (daily log review — after full day of trading)
#
# Post-migration: all paths under ~/Documents/Projects/Hyo/agents/aether/

source ~/.zshrc

export HYO_ROOT="$HOME/Documents/Projects/Hyo"
AETHER_DIR="$HYO_ROOT/agents/aether"
ANALYSIS_DIR="$AETHER_DIR/analysis"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
LOG_FILE="$AETHER_DIR/logs/factcheck_log.txt"

echo "$(date): Fact-check triggered (mode: ${1:---analysis})" >> "$LOG_FILE"

if [[ "${1:-}" == "--log" ]]; then
    # Daily log review mode — send raw log to GPT
    TARGET_DATE="${2:-$TODAY}"
    LOG_PATH="$AETHER_DIR/logs/AetherBot_${TARGET_DATE}.txt"
    LEGACY_LOG="$HOME/Documents/Projects/AetherBot/Logs/AetherBot_${TARGET_DATE}.txt"
    CROSSCHECK="$ANALYSIS_DIR/GPT_CrossCheck_${TARGET_DATE}.txt"

    # Check if already reviewed (and not a PENDING stub)
    if [[ -f "$CROSSCHECK" ]] && ! grep -q "PENDING" "$CROSSCHECK" 2>/dev/null; then
        echo "$(date): GPT log review already exists for $TARGET_DATE. Skipping." >> "$LOG_FILE"
        exit 0
    fi

    # Find the log file
    if [[ ! -f "$LOG_PATH" ]]; then
        if [[ -f "$LEGACY_LOG" ]]; then
            LOG_PATH="$LEGACY_LOG"
        else
            echo "$(date): No AetherBot log found for $TARGET_DATE. Skipping." >> "$LOG_FILE"
            exit 1
        fi
    fi

    echo "$(date): Running GPT daily log review on $LOG_PATH" >> "$LOG_FILE"
    /opt/homebrew/bin/python3 "$ANALYSIS_DIR/gpt_factcheck.py" --log "$TARGET_DATE" >> "$LOG_FILE" 2>&1
    echo "$(date): Daily log review complete" >> "$LOG_FILE"
else
    # Analysis fact-check mode (original)
    ANALYSIS_FILE=""
    for prefix in Final_Analysis Deep_Analysis Analysis; do
        candidate="$ANALYSIS_DIR/${prefix}_${TODAY}.txt"
        if [[ -f "$candidate" ]]; then
            ANALYSIS_FILE="$candidate"
            break
        fi
    done

    if [[ -z "$ANALYSIS_FILE" ]]; then
        # Wait up to 20 minutes for the analysis file to appear
        WAITED=0
        while [[ $WAITED -lt 1200 ]]; do
            for prefix in Final_Analysis Deep_Analysis Analysis; do
                candidate="$ANALYSIS_DIR/${prefix}_${TODAY}.txt"
                if [[ -f "$candidate" ]]; then
                    ANALYSIS_FILE="$candidate"
                    break 2
                fi
            done
            sleep 30
            WAITED=$((WAITED + 30))
        done
    fi

    if [[ -z "$ANALYSIS_FILE" ]]; then
        echo "$(date): No analysis file found after 20 min wait. Skipping." >> "$LOG_FILE"
        exit 1
    fi

    # Check if GPT fact-check already appended
    if grep -q "GPT-4o FACT-CHECK" "$ANALYSIS_FILE" 2>/dev/null; then
        echo "$(date): Fact-check already present. Skipping." >> "$LOG_FILE"
        exit 0
    fi

    echo "$(date): Running GPT fact-check on $ANALYSIS_FILE" >> "$LOG_FILE"
    /opt/homebrew/bin/python3 "$ANALYSIS_DIR/gpt_factcheck.py" >> "$LOG_FILE" 2>&1
    echo "$(date): Fact-check complete" >> "$LOG_FILE"
fi
