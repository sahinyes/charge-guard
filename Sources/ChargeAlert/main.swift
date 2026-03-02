import Foundation

// MARK: - CLI Commands

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : nil

if let command {
    switch command {
    case "trust":
        handleTrust()
    case "untrust":
        handleUntrust()
    case "trust-list":
        handleTrustList()
    case "trust-pick":
        handleTrustPick()
    case "test-alert":
        handleTestAlert()
    case "help", "--help", "-h":
        handleHelp()
    default:
        fputs("Error: Unknown command '\(command)'\n\n", stderr)
        printUsage()
        exit(1)
    }
}

// MARK: - CLI Handlers

func handleTrust() -> Never {
    guard let ssid = WiFiMonitor.currentSSID() else {
        fputs("Error: Not connected to WiFi. Connect to a network first.\n", stderr)
        exit(1)
    }

    var config = Config.load()
    var networks = config.trustedWiFiNetworks ?? []

    if networks.contains(ssid) {
        print("'\(ssid)' is already trusted.")
        exit(0)
    }

    networks.append(ssid)
    config.trustedWiFiNetworks = networks

    do {
        try config.save()
        print("Added '\(ssid)' to trusted networks.")
    } catch {
        fputs("Error: Failed to save config: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

func handleUntrust() -> Never {
    guard let ssid = WiFiMonitor.currentSSID() else {
        fputs("Error: Not connected to WiFi. Connect to a network first.\n", stderr)
        exit(1)
    }

    var config = Config.load()
    var networks = config.trustedWiFiNetworks ?? []

    guard let index = networks.firstIndex(of: ssid) else {
        print("'\(ssid)' is not in the trusted list.")
        exit(0)
    }

    networks.remove(at: index)
    config.trustedWiFiNetworks = networks

    do {
        try config.save()
        print("Removed '\(ssid)' from trusted networks.")
    } catch {
        fputs("Error: Failed to save config: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

func handleTrustList() -> Never {
    let config = Config.load()
    let networks = config.trustedWiFiNetworks ?? []
    let currentSSID = WiFiMonitor.currentSSID()

    if networks.isEmpty {
        print("No trusted networks configured.")
    } else {
        print("Trusted networks:")
        for network in networks {
            let marker = (network == currentSSID) ? " (current)" : ""
            print("  - \(network)\(marker)")
        }
    }

    print("")
    if let ssid = currentSSID {
        let status = networks.contains(ssid) ? "trusted" : "not trusted"
        print("Current network: \(ssid) (\(status))")
    } else {
        print("Current network: not connected")
    }
    exit(0)
}

func handleTrustPick() -> Never {
    let knownNetworks = WiFiMonitor.preferredNetworks()
    guard !knownNetworks.isEmpty else {
        fputs("No known WiFi networks found.\n", stderr)
        exit(1)
    }

    var config = Config.load()
    let trusted = config.trustedWiFiNetworks ?? []

    let available = knownNetworks.filter { !trusted.contains($0) }

    if !trusted.isEmpty {
        let alreadyTrusted = knownNetworks.filter { trusted.contains($0) }
        if !alreadyTrusted.isEmpty {
            print("Already trusted: \(alreadyTrusted.joined(separator: ", "))")
            print("")
        }
    }

    guard !available.isEmpty else {
        print("All known networks are already trusted.")
        exit(0)
    }

    print("Known WiFi networks:")
    for (i, network) in available.enumerated() {
        print("  \(i + 1). \(network)")
    }
    print("")

    print("Enter numbers to trust (comma-separated, e.g. 1,3): ", terminator: "")
    guard let input = readLine(), !input.trimmingCharacters(in: .whitespaces).isEmpty else {
        print("No selection made.")
        exit(0)
    }

    let selections = input
        .components(separatedBy: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        .filter { $0 >= 1 && $0 <= available.count }
        .map { available[$0 - 1] }

    guard !selections.isEmpty else {
        fputs("No valid selections.\n", stderr)
        exit(1)
    }

    var networks = trusted
    for network in selections {
        if !networks.contains(network) {
            networks.append(network)
            print("Added '\(network)' to trusted networks.")
        }
    }

    config.trustedWiFiNetworks = networks
    do {
        try config.save()
    } catch {
        fputs("Error: Failed to save config: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

func handleTestAlert() -> Never {
    let event: NotificationSender.Event = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "connected"
        ? .connected
        : .disconnected
    let config = Config.load()
    let label = event == .disconnected ? "disconnected" : "connected"
    print("Sending test \(label) alert...")
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await NotificationSender.send(config: config, event: event)
        semaphore.signal()
    }
    semaphore.wait()
    print("Done.")
    exit(0)
}

func handleHelp() -> Never {
    printUsage()
    exit(0)
}

func printUsage() {
    print("""
    Usage: charge-alert [command]

    Commands:
      trust        Add current WiFi network to trusted list
      untrust      Remove current WiFi network from trusted list
      trust-list   Show trusted networks and current connection
      trust-pick   Pick from known WiFi networks to trust
      test-alert   Send a test notification (default: disconnected, pass 'connected' for connected)
      help         Show this help message

    Running without a command starts the daemon.
    """)
}

// MARK: - Daemon Mode

Log.info("charge-alert v1.0.0")

nonisolated(unsafe) var app: App?

signal(SIGINT) { _ in
    Log.info("Received SIGINT, shutting down...")
    Task { @MainActor in
        app?.stop()
        exit(0)
    }
}

signal(SIGTERM) { _ in
    Log.info("Received SIGTERM, shutting down...")
    Task { @MainActor in
        app?.stop()
        exit(0)
    }
}

Task { @MainActor in
    let instance = App()
    app = instance
    instance.start()
}

RunLoop.main.run()
