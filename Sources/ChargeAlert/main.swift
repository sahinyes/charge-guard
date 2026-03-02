import Foundation

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
