import Foundation
import IOKit
import IOKit.pwr_mgt

final class SleepAssertion {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var held = false

    func acquire() {
        guard !held else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "charge-alert: sending theft notification" as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            held = true
            Log.info("Sleep assertion acquired (id: \(assertionID))")
        } else {
            Log.error("Failed to acquire sleep assertion: \(result)")
        }
    }

    func release() {
        guard held else { return }

        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            Log.info("Sleep assertion released (id: \(assertionID))")
        } else {
            Log.error("Failed to release sleep assertion: \(result)")
        }

        held = false
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }
}
