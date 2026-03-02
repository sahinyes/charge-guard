import Foundation
import Network
import os

final class MapServer {

    // MARK: - Location State

    struct LocationState {
        var lat: Double = 0
        var lon: Double = 0
        var accuracy: Double = 0
        var timestamp: Date = Date()
    }

    private let state = OSAllocatedUnfairLock(initialState: LocationState())
    private var listener: NWListener?

    // MARK: - Public API

    func updateLocation(lat: Double, lon: Double, accuracy: Double) {
        state.withLock { s in
            s.lat = lat
            s.lon = lon
            s.accuracy = accuracy
            s.timestamp = Date()
        }
    }

    func start(port: UInt16) {
        let params = NWParameters.tcp
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                Log.error("Invalid port: \(port)")
                return
            }
            let l = try NWListener(using: params, on: nwPort)
            l.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Log.info("MapServer listening on port \(port)")
                case .failed(let error):
                    Log.error("MapServer listener failed: \(error)")
                default:
                    break
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            Log.error("Failed to create MapServer listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        Log.info("MapServer stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                // Silence timeout/reset noise from port scanners and preconnects
                if case .posix(let code) = error, code == .ETIMEDOUT || code == .ECONNRESET {
                    break
                }
                Log.error("MapServer connection failed: \(error)")
            default:
                break
            }
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                // Silence timeout/reset noise
                if case .posix(let code) = error, code == .ETIMEDOUT || code == .ECONNRESET {
                    connection.cancel()
                    return
                }
                Log.error("MapServer receive error: \(error)")
                connection.cancel()
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.handleRequest(request, connection: connection)
        }
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        let path = parts.count >= 2 ? String(parts[1]) : "/"

        switch path {
        case "/":
            sendRedirect(connection, location: "/map")
        case "/map":
            sendResponse(connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Self.mapHTML)
        case "/api/location":
            let snapshot = state.withLock { s in s }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let ts = formatter.string(from: snapshot.timestamp)
            let json = """
            {"lat":\(snapshot.lat),"lon":\(snapshot.lon),"accuracy":\(snapshot.accuracy),"timestamp":"\(ts)"}
            """
            sendResponse(connection, status: "200 OK", contentType: "application/json", body: json)
        default:
            sendResponse(connection, status: "404 Not Found", contentType: "text/plain", body: "Not Found")
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(_ connection: NWConnection, status: String, contentType: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendRedirect(_ connection: NWConnection, location: String) {
        let response = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Embedded HTML

    static let mapHTML: String = #"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>charge-alert | Live Location</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { background: #1a1a2e; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            #map { width: 100vw; height: 100vh; }

            .info-panel {
                position: fixed;
                bottom: 20px;
                left: 20px;
                right: 20px;
                max-width: 400px;
                background: rgba(255, 255, 255, 0.08);
                backdrop-filter: blur(16px) saturate(1.2);
                -webkit-backdrop-filter: blur(16px) saturate(1.2);
                border: 1px solid rgba(255, 255, 255, 0.12);
                border-radius: 16px;
                padding: 20px;
                color: #e0e0e0;
                z-index: 1000;
                font-size: 14px;
            }
            .info-panel h2 {
                font-size: 16px;
                font-weight: 600;
                margin-bottom: 12px;
                color: #ff4757;
                display: flex;
                align-items: center;
                gap: 8px;
            }
            .info-row {
                display: flex;
                justify-content: space-between;
                padding: 4px 0;
                border-bottom: 1px solid rgba(255, 255, 255, 0.06);
            }
            .info-row:last-child { border-bottom: none; }
            .info-label { color: #888; }
            .info-value { font-family: ui-monospace, monospace; color: #fff; }
            .status-dot {
                width: 8px; height: 8px;
                background: #ff4757;
                border-radius: 50%;
                display: inline-block;
                animation: pulse-dot 2s infinite;
            }

            .pulse-marker {
                width: 20px; height: 20px;
                background: #ff4757;
                border-radius: 50%;
                border: 3px solid #fff;
                box-shadow: 0 0 0 0 rgba(255, 71, 87, 0.7);
                animation: pulse-ring 2s infinite;
            }
            @keyframes pulse-ring {
                0% { box-shadow: 0 0 0 0 rgba(255, 71, 87, 0.7); }
                70% { box-shadow: 0 0 0 20px rgba(255, 71, 87, 0); }
                100% { box-shadow: 0 0 0 0 rgba(255, 71, 87, 0); }
            }
            @keyframes pulse-dot {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.4; }
            }

            .accuracy-circle {
                background: rgba(255, 71, 87, 0.1);
                border: 1px solid rgba(255, 71, 87, 0.3);
                border-radius: 50%;
            }
        </style>
    </head>
    <body>
        <div id="map"></div>
        <div class="info-panel">
            <h2><span class="status-dot"></span> charge-alert Tracking</h2>
            <div class="info-row">
                <span class="info-label">Latitude</span>
                <span class="info-value" id="lat">--</span>
            </div>
            <div class="info-row">
                <span class="info-label">Longitude</span>
                <span class="info-value" id="lon">--</span>
            </div>
            <div class="info-row">
                <span class="info-label">Accuracy</span>
                <span class="info-value" id="acc">--</span>
            </div>
            <div class="info-row">
                <span class="info-label">Last Update</span>
                <span class="info-value" id="time">--</span>
            </div>
        </div>

        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <script>
            const map = L.map('map', { zoomControl: false }).setView([0, 0], 2);
            L.control.zoom({ position: 'topright' }).addTo(map);

            L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
                attribution: '&copy; OpenStreetMap &copy; CARTO',
                maxZoom: 19
            }).addTo(map);

            const pulseIcon = L.divIcon({
                className: '',
                html: '<div class="pulse-marker"></div>',
                iconSize: [20, 20],
                iconAnchor: [10, 10]
            });

            let marker = null;
            let accuracyCircle = null;
            let firstUpdate = true;

            async function updateLocation() {
                try {
                    const res = await fetch('/api/location');
                    const data = await res.json();
                    if (!data.lat && !data.lon) return;

                    const latlng = [data.lat, data.lon];

                    if (marker) {
                        marker.setLatLng(latlng);
                    } else {
                        marker = L.marker(latlng, { icon: pulseIcon }).addTo(map);
                    }

                    if (accuracyCircle) {
                        accuracyCircle.setLatLng(latlng);
                        accuracyCircle.setRadius(data.accuracy || 100);
                    } else {
                        accuracyCircle = L.circle(latlng, {
                            radius: data.accuracy || 100,
                            className: 'accuracy-circle',
                            fillOpacity: 0.1,
                            stroke: true,
                            weight: 1
                        }).addTo(map);
                    }

                    if (firstUpdate) {
                        map.setView(latlng, 16);
                        firstUpdate = false;
                    }

                    document.getElementById('lat').textContent = data.lat.toFixed(6);
                    document.getElementById('lon').textContent = data.lon.toFixed(6);
                    document.getElementById('acc').textContent = (data.accuracy || 0).toFixed(0) + 'm';
                    document.getElementById('time').textContent = data.timestamp || '--';
                } catch (e) {
                    console.error('Failed to fetch location:', e);
                }
            }

            updateLocation();
            setInterval(updateLocation, 30000);
        </script>
    </body>
    </html>
    """#
}
