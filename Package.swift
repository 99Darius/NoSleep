// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NoSleepCore"),
        .executableTarget(
            name: "NoSleepApp",
            dependencies: ["NoSleepCore"]
        ),
        .executableTarget(
            name: "nosleep",
            dependencies: ["NoSleepCore"]
        ),
        .testTarget(
            name: "NoSleepCoreTests",
            dependencies: ["NoSleepCore"]
        ),
    ]
)
