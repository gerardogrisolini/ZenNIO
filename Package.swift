// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenNIO",
    products: [
        .library(
            name: "ZenNIO",
            targets: ["ZenNIO"]),
        .library(
            name: "ZenNIOSSL",
            targets: ["ZenNIOSSL"]),
        .library(
            name: "ZenNIOH2",
            targets: ["ZenNIOH2"]),
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
                "NIOHTTP1",
                "PathKit"
            ]
        ),
        .target(
            name: "ZenNIOSSL",
            dependencies: [
                "ZenNIO",
                "NIOSSL"
            ]
        ),
        .target(
            name: "ZenNIOH2",
            dependencies: [
                "ZenNIO",
                "ZenNIOSSL",
                "NIOHTTP2"
            ]
        ),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: ["ZenNIO", "ZenNIOSSL", "ZenNIOH2"])
    ]
)
