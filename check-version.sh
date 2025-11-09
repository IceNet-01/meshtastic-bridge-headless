#!/bin/bash
# Check for updates without installing them
# Usage: ./check-version.sh

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Determine installation directory
if [ -f "$PWD/bridge.py" ] && [ -f "$PWD/VERSION" ]; then
    INSTALL_DIR="$PWD"
else
    INSTALL_DIR="$HOME/meshtastic-bridge-headless"
fi

cd "$INSTALL_DIR" 2>/dev/null || {
    echo "Error: Installation not found at $INSTALL_DIR"
    exit 1
}

# Get current version
if [ -f "VERSION" ]; then
    CURRENT_VERSION=$(cat VERSION)
else
    CURRENT_VERSION="unknown"
fi

echo -e "${BLUE}Meshtastic Bridge - Version Check${NC}"
echo ""
echo -e "Current version: ${GREEN}$CURRENT_VERSION${NC}"

# Check if git repository
if [ ! -d ".git" ]; then
    echo ""
    echo "Not a git repository - cannot check for updates"
    exit 0
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
echo -e "Current branch:  ${CYAN}$CURRENT_BRANCH${NC}"

# Fetch latest (silently)
echo ""
echo "Checking for updates..."
git fetch origin --quiet 2>/dev/null || {
    echo "Failed to check for updates (network issue?)"
    exit 1
}

# Compare versions
LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/$CURRENT_BRANCH 2>/dev/null || echo "$LOCAL_COMMIT")

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    echo -e "${GREEN}✓ You are running the latest version${NC}"
    echo ""
    exit 0
fi

# Updates available
echo -e "${YELLOW}⚠ Updates available!${NC}"
echo ""

# Show new commits
COMMIT_COUNT=$(git rev-list HEAD..origin/$CURRENT_BRANCH --count 2>/dev/null || echo "0")
echo -e "New commits: ${YELLOW}$COMMIT_COUNT${NC}"
echo ""

echo -e "${BLUE}Recent changes:${NC}"
git log --oneline --pretty=format:"  %C(yellow)%h%Creset - %s" HEAD..origin/$CURRENT_BRANCH | head -10
echo ""
echo ""

# Check if there's a newer VERSION file
git show origin/$CURRENT_BRANCH:VERSION 2>/dev/null > /tmp/remote_version_$$ || true
if [ -f "/tmp/remote_version_$$" ]; then
    REMOTE_VERSION=$(cat /tmp/remote_version_$$)
    rm /tmp/remote_version_$$

    if [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
        echo -e "Latest version: ${GREEN}$REMOTE_VERSION${NC}"
        echo ""
    fi
fi

echo -e "${CYAN}To update, run:${NC}"
echo -e "  ./update.sh"
echo ""
