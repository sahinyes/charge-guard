import Foundation

enum Log {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    static func info(_ message: String) {
        FileHandle.standardError.write(
            Data("[\(timestamp())] [INFO] \(message)\n".utf8)
        )
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(
            Data("[\(timestamp())] [WARN] \(message)\n".utf8)
        )
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(
            Data("[\(timestamp())] [ERROR] \(message)\n".utf8)
        )
    }
}
