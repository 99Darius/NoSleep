// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "NoSleepCore"),
        .executableTarget(
            name: "NoSleepApp",
            dependencies: [
                "NoSleepCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
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
