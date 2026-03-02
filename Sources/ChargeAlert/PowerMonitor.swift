import Foundation
import IOKit
import IOKit.ps

final class PowerMonitor {
    private var runLoopSource: CFRunLoopSource?
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    static func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any] else {
            return true // safe default
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSACPowerValue {
                    return true
                }
            }
        }

        return sources.isEmpty ? true : false
    }

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            let onAC = PowerMonitor.isOnACPower()
            Log.info("Power source changed: \(onAC ? "AC" : "Battery")")
            monitor.onChange(onAC)
        }, context) else {
            Log.error("Failed to create power notification run loop source")
            return
        }

        runLoopSource = source.takeRetainedValue()
        CFRunLoopAddSource(RunLoop.main.getCFRunLoop(), runLoopSource, .defaultMode)
        Log.info("Power monitor started")
    }

    func stop() {
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(RunLoop.main.getCFRunLoop(), source, .defaultMode)
        runLoopSource = nil
        Log.info("Power monitor stopped")
    }
}
