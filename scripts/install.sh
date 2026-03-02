#!/bin/bash
set -euo pipefail

BINARY_NAME="charge-alert"
INSTALL_DIR="/usr/local/bin"
PLIST_NAME="dev.sahiny.charge-alert.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Building charge-alert (release)..."
cd "$PROJECT_DIR"
swift build -c release --disable-sandbox 2>&1

BUILD_PATH=".build/release/$BINARY_NAME"
if [ ! -f "$BUILD_PATH" ]; then
    echo "ERROR: Build failed. Binary not found at $BUILD_PATH"
    exit 1
fi

echo "==> Installing binary to $INSTALL_DIR/$BINARY_NAME..."
sudo cp "$BUILD_PATH" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod 755 "$INSTALL_DIR/$BINARY_NAME"

echo "==> Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$PROJECT_DIR/$PLIST_NAME" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

DOMAIN="gui/$(id -u)"
SERVICE_LABEL="dev.sahiny.charge-alert"

# Unload if already running
launchctl bootout "$DOMAIN/$SERVICE_LABEL" 2>/dev/null || true
sleep 1

echo "==> Loading LaunchAgent..."
launchctl bootstrap "$DOMAIN" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo "==> charge-alert installed and running!"
echo ""
echo "Next steps:"
echo "  1. Install 'ntfy' app on your iPhone from the App Store"
echo "  2. Run: cat ~/.config/charge-alert/config.json"
echo "  3. Copy the 'ntfyTopic' value"
echo "  4. In ntfy app: tap '+' → paste the topic → Subscribe"
echo ""
echo "Logs: tail -f /tmp/charge-alert.err.log"
echo "Map:  http://$(grep tailscaleIP ~/.config/charge-alert/config.json 2>/dev/null | tr -d ' ",' | cut -d: -f2):$(grep serverPort ~/.config/charge-alert/config.json 2>/dev/null | tr -d ' ",' | cut -d: -f2)/map"
