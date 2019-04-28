// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenNIO",
    platforms: [
        .macOS(.v10_14)
    ],
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
        .package(url: "https://github.com/apple/swift-nio.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-http2.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-extras.git", .branch("master"))
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: [
                "NIO",
                "NIOConcurrencyHelpers",
                "NIOHTTP1",
                "NIOHTTPCompression"
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
            dependencies: ["ZenNIO", "ZenNIOSSL", "ZenNIOH2"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

