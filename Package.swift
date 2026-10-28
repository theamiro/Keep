// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Keep",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Keep", targets: ["Keep"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.3"),
        .package(url: "https://github.com/simonbs/Runestone.git", from: "0.4.1"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", from: "0.1.0")
    ],
    targets: [
        .target(name: "Keep", dependencies: [
            .product(name: "Logging", package: "swift-log"),
            .product(
                name: "Runestone",
                package: "Runestone",
                condition: .when(platforms: [.iOS])
            ),
            .product(
                name: "TreeSitterJSONRunestone",
                package: "TreeSitterLanguages",
                condition: .when(platforms: [.iOS])
            )
        ], swiftSettings: [
            .define("KEEP_RUNESTONE", .when(configuration: .debug))
        ]),
        .testTarget(name: "KeepTests", dependencies: ["Keep"])
    ]
)
