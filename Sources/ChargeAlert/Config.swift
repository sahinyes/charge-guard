import Foundation

struct Config: Codable {
    var ntfyTopic: String
    var ntfyServer: String
    var tailscaleIP: String
    var serverPort: UInt16
    var locationTimeout: Int
    var cooldownSeconds: Int

    static let defaultConfig = Config(
        ntfyTopic: "charge-alert-\(UUID().uuidString.prefix(8).lowercased())",
        ntfyServer: "https://ntfy.sh",
        tailscaleIP: "",
        serverPort: 8080,
        locationTimeout: 10,
        cooldownSeconds: 30
    )

    static let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/charge-alert")
    }()

    static let configFile: URL = {
        configDir.appendingPathComponent("config.json")
    }()

    static func load() -> Config {
        let fm = FileManager.default

        if fm.fileExists(atPath: configFile.path) {
            do {
                let data = try Data(contentsOf: configFile)
                let decoder = JSONDecoder()
                let config = try decoder.decode(Config.self, from: data)
                Log.info("Config loaded from \(configFile.path)")
                return config
            } catch {
                Log.error("Failed to parse config: \(error). Using defaults.")
                return defaultConfig
            }
        }

        // First run — create default config
        let config = defaultConfig
        do {
            try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configFile, options: .atomic)
            Log.info("Created default config at \(configFile.path)")
            Log.info("ntfy topic: \(config.ntfyTopic)")
            Log.info("Subscribe on iPhone: open ntfy app → add topic '\(config.ntfyTopic)'")
        } catch {
            Log.error("Failed to write default config: \(error)")
        }

        return config
    }
}
