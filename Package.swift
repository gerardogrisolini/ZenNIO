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
            name: "ZenSMTP",
            targets: ["ZenSMTP"]),
        .library(
            name: "ZenUI",
            targets: ["ZenUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-http2.git", .branch("master")),
        .package(url: "https://github.com/stencilproject/Stencil.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: ["NIO", "NIOConcurrencyHelpers", "NIOSSL", "NIOHTTP1", "NIOHTTP2", "Stencil"]),
        .target(
            name: "ZenSMTP",
            dependencies: ["NIO", "NIOFoundationCompat", "NIOSSL"]),
        .target(
            name: "ZenUI",
            dependencies: ["ZenNIO", "Stencil"]),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: ["ZenNIO", "ZenSMTP"])
    ]
)
