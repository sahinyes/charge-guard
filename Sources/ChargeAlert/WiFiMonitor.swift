import CoreWLAN
import Foundation

enum WiFiMonitor {
    static func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    static func isOnTrustedNetwork(_ trustedNetworks: [String]) -> Bool {
        guard !trustedNetworks.isEmpty else { return false }
        guard let ssid = currentSSID() else { return false }
        return trustedNetworks.contains(ssid)
    }

    static func preferredNetworks() -> [String] {
        guard let name = CWWiFiClient.shared().interface()?.interfaceName else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listpreferredwirelessnetworks", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
