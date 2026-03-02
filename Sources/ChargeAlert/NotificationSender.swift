import Foundation

enum NotificationSender {
    enum Event {
        case disconnected
        case connected
    }

    static func send(config: Config, event: Event) async {
        // ntfy (primary)
        await sendNtfy(config: config, event: event)

        // Discord (optional)
        if config.discordEnabled {
            await sendDiscord(config: config, event: event)
        }
    }

    // MARK: - ntfy

    private static func sendNtfy(config: Config, event: Event) async {
        let urlString = "\(config.ntfyServer)/\(config.ntfyTopic)"
        guard let url = URL(string: urlString) else {
            Log.error("Invalid ntfy URL: \(urlString)")
            return
        }

        let (title, body, tags, priority): (String, String, String, String) = switch event {
        case .disconnected:
            ("\u{1F50C} Charger Disconnected!", "Your MacBook charger was unplugged.", "electric_plug,warning", "urgent")
        case .connected:
            ("\u{1F50B} Charger Connected", "Your MacBook charger was plugged back in.", "battery,white_check_mark", "default")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        request.setValue(priority, forHTTPHeaderField: "Priority")
        request.setValue(tags, forHTTPHeaderField: "Tags")
        request.httpBody = body.data(using: .utf8)

        await sendHTTP(request: request, label: "ntfy")
    }

    // MARK: - Discord

    private static func sendDiscord(config: Config, event: Event) async {
        guard !config.discordWebhookURL.isEmpty else { return }
        guard let url = URL(string: config.discordWebhookURL) else {
            Log.error("Invalid Discord webhook URL")
            return
        }

        let (title, description, color): (String, String, Int) = switch event {
        case .disconnected:
            ("\u{1F50C} Charger Disconnected!", "Your MacBook charger was unplugged.", 16_007_990)
        case .connected:
            ("\u{1F50B} Charger Connected", "Your MacBook charger was plugged back in.", 4_437_377)
        }

        let embed: [String: Any] = [
            "title": title,
            "description": description,
            "color": color,
            "footer": ["text": "charge-alert"],
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        let payload: [String: Any] = [
            "username": "charge-alert",
            "embeds": [embed],
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            Log.error("Failed to serialize Discord payload")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        await sendHTTP(request: request, label: "Discord")
    }

    // MARK: - HTTP Helper

    private static func sendHTTP(request: URLRequest, label: String) async {
        for attempt in 1...2 {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    Log.info("\(label) notification sent (attempt \(attempt))")
                    return
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    Log.error("\(label) failed with status \(code) (attempt \(attempt))")
                }
            } catch {
                Log.error("\(label) error: \(error.localizedDescription) (attempt \(attempt))")
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
