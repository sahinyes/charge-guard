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

# Auto-detect Tailscale IP and write to config
CONFIG_FILE="$HOME/.config/charge-alert/config.json"
if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$TS_IP" ] && [ -f "$CONFIG_FILE" ]; then
        CURRENT_IP=$(grep '"tailscaleIP"' "$CONFIG_FILE" | tr -d ' ",' | cut -d: -f2)
        if [ -z "$CURRENT_IP" ] || [ "$CURRENT_IP" != "$TS_IP" ]; then
            # Use osascript for reliable JSON editing via inline JXA
            osascript -l JavaScript -e "
                var fm = $.NSFileManager.defaultManager;
                var path = '$CONFIG_FILE';
                var data = $.NSData.alloc.initWithContentsOfFile(path);
                var str = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
                var obj = JSON.parse(str);
                obj.tailscaleIP = '$TS_IP';
                var out = JSON.stringify(obj, Object.keys(obj).sort(), 4);
                $(out).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
            " 2>/dev/null && echo "==> Tailscale IP set to $TS_IP in config" || echo "WARN: Could not write Tailscale IP to config. Set it manually in $CONFIG_FILE"
        fi
    fi
else
    echo ""
    echo "WARN: Tailscale not found. Install Tailscale and set 'tailscaleIP' manually in $CONFIG_FILE"
fi

echo ""
echo "==> charge-alert installed and running!"
echo ""
echo "Next steps:"
echo "  1. Install 'ntfy' app on your iPhone from the App Store"
echo "  2. Run: cat ~/.config/charge-alert/config.json"
echo "  3. Copy the 'ntfyTopic' value"
echo "  4. In ntfy app: tap '+' → paste the topic → Subscribe"
echo "  5. Test: charge-alert test-alert"
echo ""
echo "Logs: tail -f /tmp/charge-alert.err.log"
PORT=$(grep '"serverPort"' "$CONFIG_FILE" 2>/dev/null | tr -d ' ",' | cut -d: -f2)
IP=$(grep '"tailscaleIP"' "$CONFIG_FILE" 2>/dev/null | tr -d ' ",' | cut -d: -f2)
if [ -n "$IP" ] && [ -n "$PORT" ]; then
    echo "Map:  http://${IP}:${PORT}/map"
fi
