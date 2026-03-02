import CoreLocation

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var hasResumed = false
    private(set) var cachedLocation: CLLocation?
    private var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Start passive monitoring to keep cachedLocation fresh.
    /// Calls onUpdate whenever a new location arrives (for map server updates).
    func startMonitoring(onUpdate: @escaping (CLLocation) -> Void) {
        self.onLocationUpdate = onUpdate

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        if status == .denied || status == .restricted {
            Log.warn("Location monitoring: denied/restricted. Enable in System Settings > Privacy > Location Services")
            return
        }

        // Safe to call before authorization — CoreLocation will deliver
        // updates once the user grants permission
        manager.startMonitoringSignificantLocationChanges()
        Log.info("Location monitoring started (significant changes)")
    }

    func requestLocation(timeout: Int = 10) async -> CLLocation? {
        let status = manager.authorizationStatus

        if status == .denied || status == .restricted {
            Log.warn("Location services denied/restricted. Enable in System Settings > Privacy > Location Services")
            return cachedLocation
        }

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let enabled = CLLocationManager.locationServicesEnabled()
        if !enabled {
            Log.warn("Location services disabled system-wide. Enable in System Settings > Privacy > Location Services")
            return cachedLocation
        }

        hasResumed = false
        let timeoutSeconds = timeout

        let location: CLLocation? = await withCheckedContinuation { cont in
            self.continuation = cont

            self.manager.requestLocation()

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                guard !self.hasResumed else { return }
                self.hasResumed = true
                self.continuation = nil
                Log.warn("Location request timed out after \(timeoutSeconds)s")
                cont.resume(returning: self.cachedLocation)
            }
        }

        return location
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.first else { return }
            cachedLocation = location
            onLocationUpdate?(location)

            guard !hasResumed else { return }
            hasResumed = true
            Log.info("Got location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            Log.error("Location error: \(error.localizedDescription)")
            guard !hasResumed else { return }
            hasResumed = true
            continuation?.resume(returning: cachedLocation)
            continuation = nil
        }
    }
}
