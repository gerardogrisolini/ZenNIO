// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenNIO",
    products: [
        .library(
            name: "ZenNIO",
            targets: ["ZenNIO"])
    ],
    dependencies: [
    	.package(url: "https://github.com/apple/swift-nio.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-http2.git", .branch("master")),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.13.1")
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: ["NIO", "NIOConcurrencyHelpers", "NIOOpenSSL", "NIOHTTP1", "NIOHTTP2", "Stencil"]),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: ["ZenNIO"])
    ]
)
