// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CocoUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CocoUsageBar", targets: ["CocoUsageBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "CocoUsageBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
