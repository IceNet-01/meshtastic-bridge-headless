#!/bin/bash
# Headless Server Installation Script for Meshtastic Bridge
# This script automates the complete installation of the headless bridge service
#
# Usage:
#   ./install-headless.sh           # Interactive mode (asks questions)
#   ./install-headless.sh --auto    # Fully automated (no prompts)

set -e  # Exit on error

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check for auto mode
AUTO_MODE=false
if [[ "$1" == "--auto" ]] || [[ "$1" == "-y" ]] || [[ "$1" == "--yes" ]]; then
    AUTO_MODE=true
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Meshtastic Bridge - Headless Server${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

if [ "$AUTO_MODE" = true ]; then
    log_info "Running in automatic mode (no prompts)"
    echo ""
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Do not run this script as root!"
    echo "Run as your regular user. The script will use sudo when needed."
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "Installation directory: $SCRIPT_DIR"
echo ""

# Step 1: Add user to dialout group for serial port access
echo -e "${YELLOW}[1/5] Configuring user permissions...${NC}"
NEED_RELOGIN=false
if groups $USER | grep -q '\bdialout\b'; then
    log_success "User $USER is already in dialout group"
else
    log_info "Adding user $USER to dialout group..."
    sudo usermod -a -G dialout $USER
    log_success "Added to dialout group"
    NEED_RELOGIN=true
    log_warning "NOTE: You will need to log out and log back in for group changes to take effect!"
fi
echo ""

# Step 2: Install system dependencies
echo -e "${YELLOW}[2/5] Installing system dependencies...${NC}"
if ! dpkg -l | grep -q python3-venv; then
    echo "Installing python3-venv and python3-pip..."
    sudo apt update
    sudo apt install -y python3-venv python3-pip
else
    echo "✓ System dependencies already installed"
fi
echo ""

# Step 3: Set up virtual environment
echo -e "${YELLOW}[3/5] Setting up Python virtual environment...${NC}"
cd "$SCRIPT_DIR"
if [ ! -d "$SCRIPT_DIR/venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    echo "Installing Python packages (headless-only)..."
    pip install -r requirements.txt
    echo "✓ Virtual environment created"
else
    echo "Virtual environment exists, upgrading packages..."
    source venv/bin/activate
    pip install --upgrade -r requirements.txt
    echo "✓ Packages upgraded"
fi
echo ""

# Step 4: Make scripts executable
echo -e "${YELLOW}[4/5] Setting script permissions...${NC}"
chmod +x "$SCRIPT_DIR/bridge.py"
chmod +x "$SCRIPT_DIR/list-devices.sh"
chmod +x "$SCRIPT_DIR/device_manager.py"
chmod +x "$SCRIPT_DIR/install-headless.sh"
echo "✓ Scripts are now executable"
echo ""

# Step 5: Install and enable systemd service (automatic for headless)
echo -e "${YELLOW}[5/5] Installing systemd service...${NC}"

# Update the service file with current installation path
SERVICE_FILE="$SCRIPT_DIR/meshtastic-bridge.service"
TEMP_SERVICE="/tmp/meshtastic-bridge-temp.service"

# Replace placeholder paths with actual installation directory
sed "s|/home/mesh/meshtastic-bridge|$SCRIPT_DIR|g" "$SERVICE_FILE" > "$TEMP_SERVICE"
sed -i "s|User=mesh|User=$USER|g" "$TEMP_SERVICE"
sed -i "s|Group=mesh|Group=$USER|g" "$TEMP_SERVICE"

echo "Installing systemd service to /etc/systemd/system/..."
sudo cp "$TEMP_SERVICE" /etc/systemd/system/meshtastic-bridge.service
rm "$TEMP_SERVICE"

echo "Enabling service for auto-start on boot..."
sudo systemctl daemon-reload
sudo systemctl enable meshtastic-bridge.service

echo "✓ Service installed and enabled!"
echo ""

# Installation complete
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "${GREEN}The Meshtastic Bridge headless server is now installed!${NC}"
echo ""
echo "Features enabled:"
echo "  ✓ Auto-start on system boot"
echo "  ✓ Auto-restart on crash"
echo "  ✓ Crash protection (max 5 restarts in 60 seconds)"
echo "  ✓ System resource management"
echo "  ✓ Enhanced logging to systemd journal"
echo ""
echo "Service management commands:"
echo "  ${BLUE}Start service:${NC}   sudo systemctl start meshtastic-bridge"
echo "  ${BLUE}Stop service:${NC}    sudo systemctl stop meshtastic-bridge"
echo "  ${BLUE}Restart:${NC}         sudo systemctl restart meshtastic-bridge"
echo "  ${BLUE}Check status:${NC}    sudo systemctl status meshtastic-bridge"
echo "  ${BLUE}View logs:${NC}       sudo journalctl -u meshtastic-bridge -f"
echo "  ${BLUE}Disable auto-start:${NC} sudo systemctl disable meshtastic-bridge"
echo ""
echo "Manual operation (without service):"
echo "  ${BLUE}Run once:${NC}        cd $SCRIPT_DIR && source venv/bin/activate && python3 bridge.py"
echo ""

# Offer to start the service now
if [ "$AUTO_MODE" = true ]; then
    START_NOW="Y"
else
    read -p "Do you want to start the service now? [Y/n]: " START_NOW
    START_NOW=${START_NOW:-Y}
fi

if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    log_info "Starting meshtastic-bridge service..."
    sudo systemctl start meshtastic-bridge
    sleep 2

    if sudo systemctl is-active --quiet meshtastic-bridge; then
        log_success "Service is running!"
        echo ""
        log_info "Checking service status..."
        sudo systemctl status meshtastic-bridge --no-pager
        echo ""
        echo -e "${YELLOW}View live logs with:${NC} sudo journalctl -u meshtastic-bridge -f"
    else
        log_warning "Service started but may have issues"
        echo "Check logs: sudo journalctl -u meshtastic-bridge -n 50"
    fi
else
    echo ""
    log_info "Service not started. Start it later with:"
    echo "  sudo systemctl start meshtastic-bridge"
fi

echo ""
if [ "$NEED_RELOGIN" = true ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠  IMPORTANT: You must log out and back in  ║${NC}"
    echo -e "${YELLOW}║     for USB permissions to take effect!       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════╝${NC}"
    echo ""
fi

echo -e "${GREEN}Installation complete! Your headless Meshtastic Bridge is ready.${NC}"
echo ""
