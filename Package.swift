// swift-tools-version:4.2
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
    	.package(url: "https://github.com/apple/swift-nio.git", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "1.3.2"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "0.2.0")
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: ["NIO", "NIOConcurrencyHelpers", "NIOOpenSSL", "NIOHTTP1", "NIOHTTP2"]),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: ["ZenNIO"]),
    ]
)
