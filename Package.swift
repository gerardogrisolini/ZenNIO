// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenNIO",
    products: [
        .library(
            name: "ZenNIO",
            targets: ["ZenNIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.1"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.0.1"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: [
                "NIO",
                "NIOConcurrencyHelpers",
                "NIOSSL",
                "NIOHTTP1",
                "NIOHTTP2",
                "PathKit"
            ]
        ),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: ["ZenNIO"])
    ]
)
