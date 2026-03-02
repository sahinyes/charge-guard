# charge-alert

MacBook anti-theft alert system. Sends a push notification to your iPhone when the charger is disconnected, with a live location map accessible over Tailscale.

No Apple Developer Account required. Zero external dependencies.

## How It Works

```
MacBook (Swift daemon)                        iPhone
┌─────────────────────┐                       ┌──────────────┐
│ IOKit: power monitor │──ntfy.sh POST───────→ │ ntfy app     │
│ CoreLocation: GPS    │                       │ (App Store)  │
│ NWListener: map srv  │←──Tailscale HTTP────── │ Safari       │
└─────────────────────┘                       └──────────────┘
```

1. Charger disconnected → daemon detects via IOKit
2. Gets current location via CoreLocation (WiFi-based)
3. Sends push notification via [ntfy.sh](https://ntfy.sh) (free, open source)
4. iPhone receives notification with "Open Map" button
5. Map opens over Tailscale showing live location with Leaflet.js

## Requirements

- macOS 14+ (Sonoma or later)
- Xcode Command Line Tools (`xcode-select --install`)
- [Tailscale](https://tailscale.com) installed on both MacBook and iPhone
- [ntfy](https://apps.apple.com/app/ntfy/id1625396347) app on iPhone

## Install

```bash
git clone https://github.com/sahiny/charge-alert.git
cd charge-alert
chmod +x scripts/install.sh
./scripts/install.sh
```

The install script will:
1. Build the release binary
2. Copy it to `/usr/local/bin/charge-alert`
3. Install and load the LaunchAgent (auto-starts at login)

## Setup

### 1. Grant Location Services

On first run, macOS will prompt for Location Services access. Grant it in:

**System Settings → Privacy & Security → Location Services → charge-alert → Allow**

### 2. Subscribe on iPhone

```bash
# Get your unique topic
cat ~/.config/charge-alert/config.json | grep ntfyTopic
```

1. Open the **ntfy** app on iPhone
2. Tap **+** (add subscription)
3. Paste your `ntfyTopic` value
4. Tap **Subscribe**

### 3. Configure Tailscale IP

Edit `~/.config/charge-alert/config.json` and set `tailscaleIP` to your MacBook's Tailscale IP:

```bash
# Find your Tailscale IP
tailscale ip -4
```

### 4. Verify

```bash
# Check it's running
tail -f /tmp/charge-alert.err.log

# Test: unplug your charger
# You should receive a notification within 5-10 seconds
```

## Configuration

Config lives at `~/.config/charge-alert/config.json`:

```json
{
    "ntfyTopic": "charge-alert-a1b2c3d4",
    "ntfyServer": "https://ntfy.sh",
    "tailscaleIP": "100.x.x.x",
    "serverPort": 8080,
    "locationTimeout": 10,
    "cooldownSeconds": 30
}
```

| Key | Description | Default |
|---|---|---|
| `ntfyTopic` | Unique topic for notifications (auto-generated) | UUID-based |
| `ntfyServer` | ntfy server URL | `https://ntfy.sh` |
| `tailscaleIP` | Your MacBook's Tailscale IP | `` |
| `serverPort` | Map server port | `8080` |
| `locationTimeout` | Location request timeout (seconds) | `10` |
| `cooldownSeconds` | Min seconds between alerts | `30` |

## Uninstall

```bash
./scripts/uninstall.sh
```

Config is preserved. To fully remove: `rm -rf ~/.config/charge-alert`

## Edge Cases

- **Charger removed during sleep**: Detected on wake via `NSWorkspace.didWakeNotification`
- **Location Services off**: Notification sent without coordinates, logs show instructions
- **ntfy.sh down**: 1 retry after 3s, then logs error (best-effort)
- **Rapid plug/unplug**: 30s cooldown prevents duplicate alerts
- **Port conflict**: Map server fails gracefully, notifications still work

## License

MIT
