// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "default-app-switcher",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "das", targets: ["DASApp"]),
        .executable(name: "das-helper", targets: ["DASHelper"]),
    ],
    targets: [
        .target(name: "DASCore", path: "Sources/Core"),
        .target(name: "TerminalSupport", path: "Sources/TerminalSupport"),
        .target(name: "DASCLI", dependencies: ["DASCore", "TerminalSupport"], path: "Sources/CLI"),
        .executableTarget(name: "DASApp", dependencies: ["DASCLI"], path: "Sources/App"),
        .target(name: "DASHelperSupport", dependencies: ["DASCore"], path: "Sources/HelperSupport"),
        .executableTarget(
            name: "DASHelper", dependencies: ["DASCore", "DASHelperSupport"], path: "Sources/Helper"
        ),
        .executableTarget(
            name: "DASTests", dependencies: ["DASCore", "DASCLI", "DASHelperSupport"],
            path: "Tests/DASTests"),
    ]
)
