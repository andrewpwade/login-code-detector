// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LoginCodeDetector",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LoginCodeDetector", targets: ["LoginCodeDetectorApp"]),
        .library(name: "LoginCodeDetectorCore", targets: ["LoginCodeDetectorCore"])
    ],
    targets: [
        .target(
            name: "LoginCodeDetectorCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "LoginCodeDetectorApp",
            dependencies: ["LoginCodeDetectorCore"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "LoginCodeDetectorCoreTests",
            dependencies: ["LoginCodeDetectorCore"]
        )
    ]
)
