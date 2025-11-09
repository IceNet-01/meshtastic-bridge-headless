#!/bin/bash
# Smart USB Device Waiting Script
# Waits for Meshtastic USB devices to be available before starting service
# Usage: wait-for-usb-devices.sh [max_wait_seconds] [required_count]

set -e

# Configuration
MAX_WAIT=${1:-30}           # Maximum wait time in seconds (default: 30)
REQUIRED_COUNT=${2:-2}      # Number of USB devices required (default: 2)
CHECK_INTERVAL=1            # Check every second

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to count USB serial devices
count_usb_devices() {
    local count=0

    # Count ttyUSB* devices
    if ls /dev/ttyUSB* >/dev/null 2>&1; then
        count=$((count + $(ls /dev/ttyUSB* 2>/dev/null | wc -l)))
    fi

    # Count ttyACM* devices
    if ls /dev/ttyACM* >/dev/null 2>&1; then
        count=$((count + $(ls /dev/ttyACM* 2>/dev/null | wc -l)))
    fi

    echo "$count"
}

# Main waiting loop
log_info "Waiting for $REQUIRED_COUNT USB serial device(s) (max ${MAX_WAIT}s)..."

elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
    USB_COUNT=$(count_usb_devices)

    if [ "$USB_COUNT" -ge "$REQUIRED_COUNT" ]; then
        log_info "Found $USB_COUNT USB serial device(s) - ready to proceed"

        # List the devices for logging
        if ls /dev/ttyUSB* >/dev/null 2>&1; then
            log_info "ttyUSB devices: $(ls /dev/ttyUSB* 2>/dev/null | tr '\n' ' ')"
        fi
        if ls /dev/ttyACM* >/dev/null 2>&1; then
            log_info "ttyACM devices: $(ls /dev/ttyACM* 2>/dev/null | tr '\n' ' ')"
        fi

        exit 0
    fi

    # Log progress every 5 seconds
    if [ $((elapsed % 5)) -eq 0 ] && [ $elapsed -gt 0 ]; then
        log_info "Still waiting... Found $USB_COUNT/$REQUIRED_COUNT device(s) (${elapsed}s elapsed)"
    fi

    sleep $CHECK_INTERVAL
    elapsed=$((elapsed + CHECK_INTERVAL))
done

# Timeout reached
log_error "Timeout after ${MAX_WAIT}s - found only $USB_COUNT/$REQUIRED_COUNT USB device(s)"
log_warn "Please check that Meshtastic radios are connected via USB"

# List available serial devices for debugging
log_info "Available serial devices:"
ls -la /dev/tty{USB,ACM}* 2>/dev/null || log_warn "No /dev/ttyUSB* or /dev/ttyACM* devices found"

exit 1
