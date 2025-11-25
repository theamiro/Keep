// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Keep",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "Keep", targets: ["Keep"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.3")
    ],
    targets: [
        .target(name: "Keep", dependencies: [.product(name: "Logging", package: "swift-log")]),
        .testTarget(name: "KeepTests", dependencies: ["Keep"])
    ]
)
