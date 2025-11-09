#!/bin/bash
# Easy Update Script for Meshtastic Bridge Headless Server
# Safely updates to the latest version with backup and rollback support

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
echo -e "${BLUE}║${NC}  ${GREEN}Meshtastic Bridge - Update Script${NC}          ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Safely update to the latest version          ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Determine installation directory
if [ -f "$PWD/bridge.py" ] && [ -f "$PWD/VERSION" ]; then
    INSTALL_DIR="$PWD"
else
    INSTALL_DIR="$HOME/meshtastic-bridge-headless"
    if [ ! -d "$INSTALL_DIR" ]; then
        error_exit "Installation not found. Expected at: $INSTALL_DIR"
    fi
fi

cd "$INSTALL_DIR"
log_info "Installation directory: $INSTALL_DIR"
echo ""

# Get current version
if [ -f "VERSION" ]; then
    CURRENT_VERSION=$(cat VERSION)
    log_info "Current version: ${GREEN}$CURRENT_VERSION${NC}"
else
    CURRENT_VERSION="unknown"
    log_warning "Current version: unknown (VERSION file not found)"
fi

# Step 1: Check if git repository
log_step "Step 1/7: Checking repository status"
if [ ! -d ".git" ]; then
    error_exit "Not a git repository. Cannot update automatically."
fi

# Check if there are uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    log_warning "You have uncommitted local changes"
    echo ""
    git status --short
    echo ""
    read -p "Continue update? Local changes will be stashed. (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled by user"
        exit 0
    fi

    log_info "Stashing local changes..."
    git stash save "Pre-update stash $(date '+%Y-%m-%d %H:%M:%S')"
fi

log_success "Repository is ready"

# Step 2: Create backup
log_step "Step 2/7: Creating backup"
BACKUP_DIR="$HOME/.meshtastic-bridge-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/backup_${CURRENT_VERSION}_${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"
log_info "Backing up to: $BACKUP_PATH"

# Copy current installation
cp -r "$INSTALL_DIR" "$BACKUP_PATH"
log_success "Backup created"

echo ""
log_info "Rollback command (if needed):"
echo -e "  ${CYAN}$BACKUP_PATH/rollback.sh${NC}"

# Create rollback script
cat > "$BACKUP_PATH/rollback.sh" <<EOF
#!/bin/bash
# Rollback script - restore from backup
set -e
echo "Rolling back to version $CURRENT_VERSION..."
sudo systemctl stop meshtastic-bridge 2>/dev/null || true
rm -rf "$INSTALL_DIR"
cp -r "$BACKUP_PATH" "$INSTALL_DIR"
cd "$INSTALL_DIR"
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl start meshtastic-bridge
echo "Rollback complete!"
sudo systemctl status meshtastic-bridge
EOF
chmod +x "$BACKUP_PATH/rollback.sh"

# Step 3: Fetch latest changes
log_step "Step 3/7: Fetching latest version"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
log_info "Current branch: $CURRENT_BRANCH"

git fetch origin 2>&1 | grep -v "^From" || true
log_success "Latest changes fetched"

# Check if updates are available
LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/$CURRENT_BRANCH 2>/dev/null || echo "$LOCAL_COMMIT")

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    log_success "Already up to date!"
    echo ""
    log_info "Current version: $CURRENT_VERSION"
    echo ""
    echo "No updates available."
    exit 0
fi

# Show what will be updated
echo ""
log_info "Changes in the update:"
git log --oneline HEAD..origin/$CURRENT_BRANCH | head -10
echo ""

# Step 4: Stop the service
log_step "Step 4/7: Stopping service"
if systemctl is-active --quiet meshtastic-bridge 2>/dev/null; then
    log_info "Stopping meshtastic-bridge service..."
    sudo systemctl stop meshtastic-bridge
    log_success "Service stopped"
else
    log_info "Service is not running"
fi

# Step 5: Pull updates
log_step "Step 5/7: Installing updates"
log_info "Pulling latest changes..."
git pull origin $CURRENT_BRANCH

# Get new version
if [ -f "VERSION" ]; then
    NEW_VERSION=$(cat VERSION)
    log_success "Updated to version: ${GREEN}$NEW_VERSION${NC}"
else
    NEW_VERSION="unknown"
    log_success "Update complete"
fi

# Step 6: Update dependencies
log_step "Step 6/7: Updating dependencies"
if [ -d "venv" ]; then
    log_info "Activating virtual environment..."
    source venv/bin/activate

    log_info "Updating pip..."
    pip install --upgrade pip -q

    log_info "Updating Python packages..."
    pip install --upgrade -r requirements.txt -q

    log_success "Dependencies updated"
else
    log_warning "Virtual environment not found - skipping dependency update"
fi

# Update service file if needed
if [ -f "meshtastic-bridge.service" ]; then
    SERVICE_FILE="/etc/systemd/system/meshtastic-bridge.service"
    if [ -f "$SERVICE_FILE" ]; then
        log_info "Checking if service file needs updating..."

        # Update paths in service file
        TEMP_SERVICE="/tmp/meshtastic-bridge-update-$$.service"
        sed "s|/home/mesh/meshtastic-bridge|$INSTALL_DIR|g" "$INSTALL_DIR/meshtastic-bridge.service" > "$TEMP_SERVICE"
        sed -i "s|User=mesh|User=$USER|g" "$TEMP_SERVICE"
        sed -i "s|Group=mesh|Group=$USER|g" "$TEMP_SERVICE"

        # Check if different
        if ! cmp -s "$TEMP_SERVICE" "$SERVICE_FILE"; then
            log_info "Service file has changes, updating..."
            sudo cp "$TEMP_SERVICE" "$SERVICE_FILE"
            sudo systemctl daemon-reload
            log_success "Service file updated"
        else
            log_info "Service file is up to date"
        fi
        rm "$TEMP_SERVICE"
    fi
fi

# Step 7: Start the service
log_step "Step 7/7: Starting service"
log_info "Starting meshtastic-bridge service..."
sudo systemctl start meshtastic-bridge

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet meshtastic-bridge; then
    log_success "Service started successfully"
else
    log_error "Service failed to start!"
    echo ""
    log_info "Check logs with:"
    echo -e "  ${CYAN}sudo journalctl -u meshtastic-bridge -n 50${NC}"
    echo ""
    log_info "To rollback:"
    echo -e "  ${CYAN}$BACKUP_PATH/rollback.sh${NC}"
    exit 1
fi

# Show final status
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Update Complete!${NC}                           ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

log_success "Successfully updated from $CURRENT_VERSION → $NEW_VERSION"
echo ""
echo -e "${YELLOW}What's New:${NC}"
git log --pretty=format:"%h - %s" HEAD~5..HEAD
echo ""
echo ""

log_info "Verify service status:"
echo -e "  ${CYAN}sudo systemctl status meshtastic-bridge${NC}"
echo ""

log_info "View live logs:"
echo -e "  ${CYAN}sudo journalctl -u meshtastic-bridge -f${NC}"
echo ""

log_info "Check version:"
echo -e "  ${CYAN}python3 bridge.py --version${NC}"
echo ""

if [ -f "$BACKUP_PATH/rollback.sh" ]; then
    log_info "If you encounter issues, rollback with:"
    echo -e "  ${CYAN}$BACKUP_PATH/rollback.sh${NC}"
    echo ""
fi

log_success "Update finished successfully!"
echo ""
