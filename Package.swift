// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iCloudSyncWatch",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "iCloudSyncWatch",
            targets: ["iCloudSyncWatch"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "iCloudSyncWatch",
            path: "Sources/iCloudSyncWatch",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "iCloudSyncWatchTests",
            dependencies: ["iCloudSyncWatch"],
            path: "Tests/iCloudSyncWatchTests"
        ),
    ]
)
