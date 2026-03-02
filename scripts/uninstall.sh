#!/bin/bash
set -euo pipefail

BINARY_NAME="charge-alert"
INSTALL_DIR="/usr/local/bin"
PLIST_NAME="dev.sahiny.charge-alert.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "==> Stopping charge-alert..."
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

echo "==> Removing LaunchAgent..."
rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo "==> Removing binary..."
sudo rm -f "$INSTALL_DIR/$BINARY_NAME"

echo ""
echo "==> charge-alert uninstalled."
echo ""
echo "Config preserved at: ~/.config/charge-alert/config.json"
echo "To remove config: rm -rf ~/.config/charge-alert"
echo "To remove logs:   rm -f /tmp/charge-alert.*.log"
