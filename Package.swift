// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "charge-alert",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "charge-alert",
            path: "Sources/ChargeAlert",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ChargeAlert/Resources/Info.plist",
                ]),
            ]
        ),
    ]
)
