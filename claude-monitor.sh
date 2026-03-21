#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Missing .env file."
    echo "Create it by copying the example:"
    echo "  cp $SCRIPT_DIR/.env.example $SCRIPT_DIR/.env"
    echo "Then fill in your values."
    exit 1
fi

source "$ENV_FILE"

for var in CLAUDE_MONITOR_FROM CLAUDE_MONITOR_GMAIL_APP_PASSWORD CLAUDE_MONITOR_TO; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is not set in $ENV_FILE"
        exit 1
    fi
done

THRESHOLD_KB=8000000   # 8 GB
CHECK_INTERVAL=30      # seconds
ALERT_SENT=0

echo "Claude Code memory monitor started (threshold: 8GB, checking every ${CHECK_INTERVAL}s)"
echo "Alerts will be sent to: $CLAUDE_MONITOR_TO"

while true; do
    # Check if Claude is running
    CLAUDE_PID=$(pgrep -f "claude" | head -1)

    if [ -z "$CLAUDE_PID" ]; then
        # Claude not running — reset alert flag so next session gets a fresh alert
        if [ "$ALERT_SENT" -eq 1 ]; then
            echo "[$(date '+%H:%M:%S')] Claude no longer running. Alert flag reset."
            ALERT_SENT=0
        fi
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Sum memory (RSS in KB) of all claude processes
    MEM_KB=$(pgrep -f "claude" | xargs -I{} ps -o rss= -p {} 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    MEM_GB=$(awk "BEGIN {printf \"%.2f\", $MEM_KB/1024/1024}")

    if [ "$MEM_KB" -gt "$THRESHOLD_KB" ] && [ "$ALERT_SENT" -eq 0 ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        HOSTNAME=$(hostname)

        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║  ⚠️  WARNING: Claude Code High Memory Usage!      ║"
        echo "║  Current usage: ${MEM_GB} GB                         ║"
        echo "║  Consider running /clear in Claude Code          ║"
        echo "╚══════════════════════════════════════════════════╝"
        echo ""

        EMAIL_BODY="Claude Code High Memory Warning

Hostname:  $HOSTNAME
Time:      $TIMESTAMP
Memory:    ${MEM_GB} GB (threshold: 8 GB)

Recommended action: run /clear inside Claude Code to free up memory.
This will clear the conversation context and reduce memory usage.

-- Claude Monitor"

        echo -e "Subject: ⚠️ Claude Code High Memory Warning on Pi\n\n$EMAIL_BODY" \
            | msmtp "$CLAUDE_MONITOR_TO" \
            && echo "[$(date '+%H:%M:%S')] Alert email sent to $CLAUDE_MONITOR_TO" \
            || echo "[$(date '+%H:%M:%S')] WARNING: Failed to send alert email"

        ALERT_SENT=1
    else
        echo "[$(date '+%H:%M:%S')] Claude running — memory: ${MEM_GB} GB"
    fi

    sleep "$CHECK_INTERVAL"
done
