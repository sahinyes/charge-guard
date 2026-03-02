import Foundation
import CoreLocation
import AppKit

@MainActor
final class App {
    private let config: Config
    private var powerMonitor: PowerMonitor!
    private let locationProvider: LocationProvider
    private let mapServer: MapServer
    private let sleepAssertion: SleepAssertion

    private var wasOnAC: Bool
    private var lastAlertTime: Date = .distantPast
    private var wakeObserver: NSObjectProtocol?

    init() {
        config = Config.load()
        locationProvider = LocationProvider()
        mapServer = MapServer()
        sleepAssertion = SleepAssertion()
        wasOnAC = PowerMonitor.isOnACPower()

        powerMonitor = PowerMonitor { [unowned self] isOnAC in
            Task { @MainActor in
                self.handlePowerChange(isOnAC: isOnAC)
            }
        }
    }

    func start() {
        Log.info("charge-alert starting...")
        Log.info("Config: webhook=\(config.discordWebhookURL.isEmpty ? "(not set)" : "configured"), port=\(config.serverPort)")
        Log.info("Current power: \(wasOnAC ? "AC" : "Battery")")

        mapServer.start(port: config.serverPort)
        powerMonitor.start()
        registerWakeNotification()

        // Start passive location monitoring to keep cache fresh
        locationProvider.startMonitoring { [weak self] location in
            self?.mapServer.updateLocation(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy
            )
        }

        Log.info("charge-alert running. Monitoring power source changes...")
    }

    func stop() {
        powerMonitor.stop()
        mapServer.stop()
        sleepAssertion.release()

        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

        Log.info("charge-alert stopped")
    }

    // MARK: - Power Change Handling

    private func handlePowerChange(isOnAC: Bool) {
        let disconnected = wasOnAC && !isOnAC
        let connected = !wasOnAC && isOnAC
        wasOnAC = isOnAC

        if disconnected {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastAlertTime)
            guard elapsed >= Double(config.cooldownSeconds) else {
                Log.info("Cooldown active (\(Int(elapsed))s / \(config.cooldownSeconds)s). Skipping alert.")
                return
            }
            lastAlertTime = now
            Log.info("*** CHARGER DISCONNECTED — triggering alert ***")
            triggerAlert(event: .disconnected)
        } else if connected {
            lastAlertTime = .distantPast  // Reset cooldown — next unplug is a fresh event
            Log.info("*** CHARGER CONNECTED ***")
            triggerAlert(event: .connected)
        }
    }

    private func triggerAlert(event: NotificationSender.Event) {
        sleepAssertion.acquire()

        Task { @MainActor in
            await NotificationSender.send(config: config, event: event)
            sleepAssertion.release()
        }
    }

    // MARK: - Wake from Sleep

    private func registerWakeNotification() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleWake()
            }
        }
        Log.info("Wake notification observer registered")
    }

    private func handleWake() {
        let isOnAC = PowerMonitor.isOnACPower()
        Log.info("Woke from sleep. Power: \(isOnAC ? "AC" : "Battery"), was: \(wasOnAC ? "AC" : "Battery")")

        if wasOnAC && !isOnAC {
            // Charger was removed during sleep
            wasOnAC = isOnAC

            let now = Date()
            let elapsed = now.timeIntervalSince(lastAlertTime)
            guard elapsed >= Double(config.cooldownSeconds) else {
                Log.info("Cooldown active after wake. Skipping.")
                return
            }

            lastAlertTime = now
            Log.info("*** CHARGER REMOVED DURING SLEEP — triggering alert ***")
            triggerAlert(event: .disconnected)
        } else {
            wasOnAC = isOnAC
        }
    }
}
