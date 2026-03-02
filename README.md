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
# Send a test notification
charge-alert test-alert

# Check logs
tail -f /tmp/charge-alert.err.log
```

## CLI Commands

```bash
charge-alert test-alert   # Send a test notification to verify setup
charge-alert trust        # Add current WiFi to trusted networks
charge-alert untrust      # Remove current WiFi from trusted networks
charge-alert trust-list   # Show trusted networks and current connection
charge-alert trust-pick   # Pick from known WiFi networks to trust
```

> **Note:** The running daemon reads config at startup. After `trust`/`untrust`, restart the daemon: `./scripts/install.sh`

## Configuration

Config lives at `~/.config/charge-alert/config.json`:

```json
{
    "cooldownSeconds": 30,
    "discordEnabled": false,
    "discordWebhookURL": "",
    "locationTimeout": 10,
    "ntfyServer": "https://ntfy.sh",
    "ntfyTopic": "charge-alert-a1b2c3d4",
    "serverPort": 8090,
    "tailscaleIP": "100.x.x.x",
    "trustedWiFiNetworks": ["HomeWiFi", "OfficeWiFi-5G"]
}
```

| Key | Description | Default |
|---|---|---|
| `ntfyTopic` | Unique topic for notifications (auto-generated) | UUID-based |
| `ntfyServer` | ntfy server URL | `https://ntfy.sh` |
| `discordWebhookURL` | Discord webhook URL for notifications | `""` |
| `discordEnabled` | Enable Discord notifications | `false` |
| `tailscaleIP` | Your MacBook's Tailscale IP | `""` (set via install or manually) |
| `serverPort` | Map server port | `8090` |
| `locationTimeout` | Location request timeout (seconds) | `10` |
| `cooldownSeconds` | Min seconds between alerts | `30` |
| `trustedWiFiNetworks` | WiFi networks where alerts are suppressed | `[]` (none) |

## Uninstall

```bash
./scripts/uninstall.sh
```

Config is preserved. To fully remove: `rm -rf ~/.config/charge-alert`

## Edge Cases

- **Trusted WiFi**: Alerts suppressed when connected to a whitelisted network (WiFi off or SSID unreadable = alert fires, fail-safe)
- **Charger removed during sleep**: Detected on wake via `NSWorkspace.didWakeNotification`
- **Location Services off**: Notification sent without coordinates, logs show instructions
- **ntfy.sh down**: 1 retry after 3s, then logs error (best-effort)
- **Rapid plug/unplug**: 30s cooldown prevents duplicate alerts
- **Port conflict**: Map server fails gracefully, notifications still work

## License

MIT
