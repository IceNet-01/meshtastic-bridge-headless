#!/bin/bash
# Health Check Script for Meshtastic Bridge
# Can be used with monitoring systems like Nagios, Icinga, or run via cron
# Exit codes: 0=OK, 1=WARNING, 2=CRITICAL

set -e

STATUS_FILE="/tmp/meshtastic-bridge-status.json"
MAX_AGE_SECONDS=120  # Status file must be updated within 2 minutes

# Check if status file exists
if [ ! -f "$STATUS_FILE" ]; then
    echo "CRITICAL: Status file $STATUS_FILE not found - bridge may not be running"
    exit 2
fi

# Check if jq is available (optional, for better JSON parsing)
if command -v jq &> /dev/null; then
    USE_JQ=true
else
    USE_JQ=false
fi

# Get current timestamp
NOW=$(date +%s)

if [ "$USE_JQ" = true ]; then
    # Parse with jq for accurate parsing
    LAST_UPDATE=$(jq -r '.timestamp // 0' "$STATUS_FILE" 2>/dev/null || echo "0")
    RUNNING=$(jq -r '.running // false' "$STATUS_FILE" 2>/dev/null || echo "false")
    RADIOS_CONNECTED=$(jq -r '.radios_connected // false' "$STATUS_FILE" 2>/dev/null || echo "false")
    UPTIME=$(jq -r '.uptime_seconds // 0' "$STATUS_FILE" 2>/dev/null || echo "0")

    # Get error counts
    RADIO1_ERRORS=$(jq -r '.stats.radio1.errors // 0' "$STATUS_FILE" 2>/dev/null || echo "0")
    RADIO2_ERRORS=$(jq -r '.stats.radio2.errors // 0' "$STATUS_FILE" 2>/dev/null || echo "0")
else
    # Simple grep-based parsing (less accurate but works without jq)
    LAST_UPDATE=$(grep -oP '"timestamp":\s*\K[0-9.]+' "$STATUS_FILE" 2>/dev/null | head -1 || echo "0")
    RUNNING=$(grep -oP '"running":\s*\K(true|false)' "$STATUS_FILE" 2>/dev/null | head -1 || echo "false")
    RADIOS_CONNECTED=$(grep -oP '"radios_connected":\s*\K(true|false)' "$STATUS_FILE" 2>/dev/null | head -1 || echo "false")
    UPTIME=$(grep -oP '"uptime_seconds":\s*\K[0-9.]+' "$STATUS_FILE" 2>/dev/null | head -1 || echo "0")
    RADIO1_ERRORS=0
    RADIO2_ERRORS=0
fi

# Calculate age of status file
LAST_UPDATE_INT=${LAST_UPDATE%.*}  # Remove decimal part
AGE=$((NOW - LAST_UPDATE_INT))

# Check if status is stale
if [ $AGE -gt $MAX_AGE_SECONDS ]; then
    echo "CRITICAL: Status file is stale (${AGE}s old, max ${MAX_AGE_SECONDS}s)"
    exit 2
fi

# Check if bridge is running
if [ "$RUNNING" != "true" ]; then
    echo "CRITICAL: Bridge is not running"
    exit 2
fi

# Check if radios are connected
if [ "$RADIOS_CONNECTED" != "true" ]; then
    echo "CRITICAL: Radios not connected"
    exit 2
fi

# Convert uptime to hours for display
UPTIME_INT=${UPTIME%.*}
UPTIME_HOURS=$((UPTIME_INT / 3600))
UPTIME_MINS=$(((UPTIME_INT % 3600) / 60))

# All checks passed
echo "OK: Bridge healthy - Uptime: ${UPTIME_HOURS}h ${UPTIME_MINS}m - Errors: R1=$RADIO1_ERRORS R2=$RADIO2_ERRORS"
exit 0
