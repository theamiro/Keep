// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Keep",
    products: [
        .library(
            name: "Keep", targets: ["Keep"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.2"),
    ],
    targets: [
        .target(name: "Keep", dependencies: [.product(name: "Logging", package: "swift-log")], resources: [.process("Resources/log.json")]),
        .testTarget(name: "KeepTests", dependencies: ["Keep"]),
    ]
)
