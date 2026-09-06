// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EasyRSS",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "EasyRSS",
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("WebKit")
            ]
        )
    ]
)
