// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NerdStats",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NerdStats", targets: ["NerdStats"]),
    ],
    targets: [
        // C declarations for private IOKit interfaces (HID temperature sensors) and the
        // SMC user-client struct, whose exact memory layout is easiest to express in C.
        .target(name: "CNerdStatsPrivate"),

        // Everything that reads and interprets system data. No UI code lives here.
        .target(
            name: "NerdStatsCore",
            dependencies: ["CNerdStatsPrivate"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),

        // The menu bar app: sampling coordinator, settings and SwiftUI views.
        .executableTarget(
            name: "NerdStats",
            dependencies: ["NerdStatsCore"]
        ),

        .testTarget(
            name: "NerdStatsCoreTests",
            dependencies: ["NerdStatsCore"]
        ),
    ]
)
