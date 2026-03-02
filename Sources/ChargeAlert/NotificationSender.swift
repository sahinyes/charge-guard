import Foundation
import CoreLocation

enum NotificationSender {
    static func send(config: Config, location: CLLocation?) async {
        let urlString = "\(config.ntfyServer)/\(config.ntfyTopic)"
        guard let url = URL(string: urlString) else {
            Log.error("Invalid ntfy URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("🔌 Charger Disconnected!", forHTTPHeaderField: "Title")
        request.setValue("urgent", forHTTPHeaderField: "Priority")
        request.setValue("electric_plug,warning", forHTTPHeaderField: "Tags")

        let body: String
        let findMyAction = "view, Find My, findmy://"
        request.setValue(findMyAction, forHTTPHeaderField: "Actions")

        if let location = location {
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            body = "Location: \(lat), \(lon)"
        } else {
            body = "Location unavailable - check Location Services"
        }

        request.httpBody = body.data(using: .utf8)

        for attempt in 1...2 {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    Log.info("Notification sent successfully (attempt \(attempt))")
                    return
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    Log.error("Notification failed with status \(code) (attempt \(attempt))")
                }
            } catch {
                Log.error("Notification error: \(error.localizedDescription) (attempt \(attempt))")
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
