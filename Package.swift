// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Pinned exact: 1.16+ uses the #Preview macro, which needs Xcode's
        // PreviewsMacros plugin and fails to compile with Command Line Tools only.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
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
        // Dev-only test runner: this machine has no Xcode/XCTest (CLT only),
        // so `swift test` cannot run. `swift run coretest` mirrors the XCTest
        // suite for NoSleepCore and exits non-zero on any failure.
        .executableTarget(
            name: "coretest",
            dependencies: ["NoSleepCore"]
        ),
        .testTarget(
            name: "NoSleepCoreTests",
            dependencies: ["NoSleepCore"]
        ),
    ]
)
