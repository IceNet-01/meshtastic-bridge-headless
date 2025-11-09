#!/bin/bash
# Script to list available Meshtastic devices

echo "==================================="
echo "Meshtastic Device Detection"
echo "==================================="
echo ""

echo "USB Serial Devices:"
echo "-------------------"
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | awk '{print $NF}' || echo "No devices found"

echo ""
echo "Recent USB Device Messages (dmesg):"
echo "------------------------------------"
dmesg | grep -i "tty\|usb" | tail -10

echo ""
echo "Meshtastic Python Detection:"
echo "----------------------------"
if command -v meshtastic &> /dev/null; then
    meshtastic --list 2>/dev/null || echo "Meshtastic CLI found but no devices detected"
else
    echo "Meshtastic CLI not available (install with: pip install meshtastic)"
fi

echo ""
echo "==================================="
