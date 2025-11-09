#!/bin/bash
# Failure Notification Script for Meshtastic Bridge
# Called by systemd when service fails
# Customize this script to send notifications via your preferred method

SERVICE_NAME="$1"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log to syslog
logger -t meshtastic-bridge-alert "Service $SERVICE_NAME failed on $HOSTNAME at $TIMESTAMP"

# Example notification methods (uncomment and configure as needed):

# 1. EMAIL NOTIFICATION (requires mail/mailx)
# if command -v mail &> /dev/null; then
#     echo "Service $SERVICE_NAME failed on $HOSTNAME at $TIMESTAMP" | \
#         mail -s "ALERT: Meshtastic Bridge Failed on $HOSTNAME" admin@example.com
# fi

# 2. SLACK WEBHOOK
# if [ -n "$SLACK_WEBHOOK_URL" ]; then
#     curl -X POST -H 'Content-type: application/json' \
#         --data "{\"text\":\"🚨 ALERT: Meshtastic Bridge failed on $HOSTNAME at $TIMESTAMP\"}" \
#         "$SLACK_WEBHOOK_URL"
# fi

# 3. DISCORD WEBHOOK
# if [ -n "$DISCORD_WEBHOOK_URL" ]; then
#     curl -X POST -H 'Content-type: application/json' \
#         --data "{\"content\":\"🚨 ALERT: Meshtastic Bridge failed on $HOSTNAME at $TIMESTAMP\"}" \
#         "$DISCORD_WEBHOOK_URL"
# fi

# 4. TELEGRAM BOT
# if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
#     MESSAGE="🚨 ALERT: Meshtastic Bridge failed on $HOSTNAME at $TIMESTAMP"
#     curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
#         -d chat_id="$TELEGRAM_CHAT_ID" \
#         -d text="$MESSAGE"
# fi

# 5. PUSHOVER
# if [ -n "$PUSHOVER_TOKEN" ] && [ -n "$PUSHOVER_USER" ]; then
#     curl -s \
#         --form-string "token=$PUSHOVER_TOKEN" \
#         --form-string "user=$PUSHOVER_USER" \
#         --form-string "title=Meshtastic Bridge Alert" \
#         --form-string "message=Service failed on $HOSTNAME at $TIMESTAMP" \
#         https://api.pushover.net/1/messages.json
# fi

# 6. NTFY.SH (simple HTTP notifications)
# NTFY_TOPIC="meshtastic-alerts"
# curl -X POST "https://ntfy.sh/$NTFY_TOPIC" \
#     -H "Title: Meshtastic Bridge Alert" \
#     -H "Priority: urgent" \
#     -d "Service failed on $HOSTNAME at $TIMESTAMP"

# 7. CUSTOM WEBHOOK
# if [ -n "$CUSTOM_WEBHOOK_URL" ]; then
#     curl -X POST -H 'Content-type: application/json' \
#         --data "{\"service\":\"$SERVICE_NAME\",\"host\":\"$HOSTNAME\",\"timestamp\":\"$TIMESTAMP\",\"status\":\"failed\"}" \
#         "$CUSTOM_WEBHOOK_URL"
# fi

# Get recent log lines for context
RECENT_LOGS=$(journalctl -u meshtastic-bridge -n 20 --no-pager 2>/dev/null || echo "Unable to fetch logs")

# Write alert to local file for debugging
ALERT_LOG="/var/log/meshtastic-bridge-alerts.log"
if [ -w "$(dirname "$ALERT_LOG")" ] || [ -w "$ALERT_LOG" ]; then
    cat >> "$ALERT_LOG" <<EOF
========================================
ALERT: Service Failure
Timestamp: $TIMESTAMP
Hostname: $HOSTNAME
Service: $SERVICE_NAME
Recent Logs:
$RECENT_LOGS
========================================

EOF
fi

echo "Alert logged for service $SERVICE_NAME failure at $TIMESTAMP"
