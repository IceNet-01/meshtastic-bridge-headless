#!/bin/bash
# Fully Automated Installation Script for Meshtastic Bridge Headless Server
# Run with: curl -sSL https://raw.githubusercontent.com/IceNet-01/meshtastic-bridge/main/install-auto.sh | bash

set -e  # Exit on error

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "\n${CYAN}▶${NC} ${YELLOW}$1${NC}"; }

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    error_exit "Do not run this script as root! Run as your regular user."
fi

# Header
clear
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Meshtastic Bridge - Auto Installer${NC}         ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Headless Server Edition                   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
log_info "Fully automated installation - no prompts needed!"
echo ""

# Detect system
log_step "Step 1/8: Detecting system"
OS_TYPE=$(uname -s)
ARCH=$(uname -m)
if [ -f /proc/device-tree/model ]; then
    PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "Unknown")
    if [[ "$PI_MODEL" == *"Raspberry Pi"* ]]; then
        log_success "Detected: Raspberry Pi ($PI_MODEL)"
        IS_RASPBERRY_PI=true
    else
        log_success "Detected: $OS_TYPE ($ARCH)"
        IS_RASPBERRY_PI=false
    fi
else
    log_success "Detected: $OS_TYPE ($ARCH)"
    IS_RASPBERRY_PI=false
fi

# Get installation directory
if [ -d "$PWD/.git" ] && [ -f "$PWD/bridge.py" ]; then
    # Already in the project directory
    INSTALL_DIR="$PWD"
    log_info "Using current directory: $INSTALL_DIR"
else
    # Need to clone the repository
    INSTALL_DIR="$HOME/meshtastic-bridge"
    log_step "Step 2/8: Downloading Meshtastic Bridge"

    if [ -d "$INSTALL_DIR" ]; then
        log_warning "Directory $INSTALL_DIR already exists"
        log_info "Updating existing installation..."
        cd "$INSTALL_DIR"
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || log_warning "Could not update repository"
    else
        log_info "Cloning repository to $INSTALL_DIR..."
        git clone https://github.com/IceNet-01/meshtastic-bridge.git "$INSTALL_DIR" || \
            error_exit "Failed to clone repository. Check your internet connection."
        cd "$INSTALL_DIR"
    fi
    log_success "Repository ready"
fi

cd "$INSTALL_DIR"

# Configure user permissions
log_step "Step 3/8: Configuring permissions"
if groups "$USER" | grep -q '\bdialout\b'; then
    log_success "User $USER already in dialout group"
    NEED_RELOGIN=false
else
    log_info "Adding user $USER to dialout group..."
    sudo usermod -a -G dialout "$USER" || error_exit "Failed to add user to dialout group"
    log_success "Added to dialout group"
    NEED_RELOGIN=true
fi

# Install system dependencies
log_step "Step 4/8: Installing system dependencies"
log_info "This may take a minute..."

# Check if dependencies are already installed
DEPS_NEEDED=false
if ! command -v python3 &> /dev/null; then
    DEPS_NEEDED=true
fi
if ! dpkg -l | grep -q python3-venv 2>/dev/null; then
    DEPS_NEEDED=true
fi

if [ "$DEPS_NEEDED" = true ]; then
    log_info "Installing python3-venv and python3-pip..."
    sudo apt update -qq || log_warning "apt update failed, continuing..."
    sudo apt install -y python3-venv python3-pip >/dev/null 2>&1 || \
        error_exit "Failed to install system dependencies"
    log_success "System dependencies installed"
else
    log_success "System dependencies already installed"
fi

# Set up virtual environment
log_step "Step 5/8: Setting up Python environment"
if [ ! -d "$INSTALL_DIR/venv" ]; then
    log_info "Creating virtual environment..."
    python3 -m venv venv || error_exit "Failed to create virtual environment"
    source venv/bin/activate
    pip install --upgrade pip -q
    log_info "Installing Python packages..."
    pip install -r requirements.txt -q || error_exit "Failed to install Python packages"
    log_success "Virtual environment created"
else
    log_info "Virtual environment exists, updating packages..."
    source venv/bin/activate
    pip install --upgrade pip -q
    pip install --upgrade -r requirements.txt -q || log_warning "Some packages may need manual update"
    log_success "Packages updated"
fi

# Make scripts executable
log_step "Step 6/8: Setting permissions"
chmod +x "$INSTALL_DIR"/*.py 2>/dev/null || true
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
log_success "Scripts are executable"

# Install systemd service
log_step "Step 7/8: Installing systemd service"

# Create temporary service file with correct paths
TEMP_SERVICE="/tmp/meshtastic-bridge-$$.service"
sed "s|/home/mesh/meshtastic-bridge|$INSTALL_DIR|g" "$INSTALL_DIR/meshtastic-bridge.service" > "$TEMP_SERVICE"
sed -i "s|User=mesh|User=$USER|g" "$TEMP_SERVICE"
sed -i "s|Group=mesh|Group=$USER|g" "$TEMP_SERVICE"

# Install service
sudo cp "$TEMP_SERVICE" /etc/systemd/system/meshtastic-bridge.service || \
    error_exit "Failed to install systemd service"
rm "$TEMP_SERVICE"

sudo systemctl daemon-reload || error_exit "Failed to reload systemd"
sudo systemctl enable meshtastic-bridge.service >/dev/null 2>&1 || \
    error_exit "Failed to enable service"
log_success "Systemd service installed and enabled"

# Pre-flight checks
log_step "Step 8/8: Running pre-flight checks"

# Check for USB devices
USB_COUNT=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | wc -l)
if [ "$USB_COUNT" -ge 2 ]; then
    log_success "Found $USB_COUNT USB serial devices"
    RADIOS_CONNECTED=true
else
    log_warning "Found only $USB_COUNT USB serial device(s)"
    log_warning "Make sure both Meshtastic radios are connected!"
    RADIOS_CONNECTED=false
fi

# Check Python version
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
log_success "Python version: $PYTHON_VERSION"

# Installation complete
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Installation Complete!${NC}                     ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

log_success "Meshtastic Bridge is installed and configured!"
echo ""
echo -e "${YELLOW}Auto-start on boot:${NC} ✓ Enabled"
echo -e "${YELLOW}Auto-restart on crash:${NC} ✓ Enabled"
echo -e "${YELLOW}Installation directory:${NC} $INSTALL_DIR"
echo ""

# Start the service automatically
if [ "$RADIOS_CONNECTED" = true ]; then
    log_info "Starting service now..."
    sudo systemctl start meshtastic-bridge.service || log_warning "Service failed to start"
    sleep 2

    if sudo systemctl is-active --quiet meshtastic-bridge.service; then
        log_success "Service is running!"
        echo ""
        echo -e "${GREEN}🎉 Your Meshtastic Bridge is now live!${NC}"
        echo ""
        echo "View live logs:"
        echo -e "  ${CYAN}sudo journalctl -u meshtastic-bridge -f${NC}"
        echo ""
        echo "Check status:"
        echo -e "  ${CYAN}sudo systemctl status meshtastic-bridge${NC}"
    else
        log_warning "Service started but may have issues"
        echo ""
        echo "Check logs:"
        echo -e "  ${CYAN}sudo journalctl -u meshtastic-bridge -n 50${NC}"
    fi
else
    log_warning "Service not started - connect both radios first"
    echo ""
    echo "After connecting radios, start with:"
    echo -e "  ${CYAN}sudo systemctl start meshtastic-bridge${NC}"
fi

echo ""

# Show next steps
if [ "$NEED_RELOGIN" = true ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠  IMPORTANT: You must log out and back in  ║${NC}"
    echo -e "${YELLOW}║     for USB permissions to take effect!       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════╝${NC}"
    echo ""
fi

echo -e "${CYAN}Useful commands:${NC}"
echo ""
echo "  View logs:       sudo journalctl -u meshtastic-bridge -f"
echo "  Check status:    sudo systemctl status meshtastic-bridge"
echo "  Restart:         sudo systemctl restart meshtastic-bridge"
echo "  Stop:            sudo systemctl stop meshtastic-bridge"
echo ""
echo -e "${CYAN}Documentation:${NC}"
echo "  README-HEADLESS.md - Full documentation"
echo "  QUICKSTART-HEADLESS.md - Quick reference"
echo ""
echo -e "${GREEN}Installation finished successfully!${NC}"
echo ""
