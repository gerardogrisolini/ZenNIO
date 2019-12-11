// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenNIO",
    platforms: [
        .macOS(.v10_14)
    ],
    products: [
        .library(name: "ZenNIO", targets: ["ZenNIO"]),
        .library(name: "ZenNIOSSL", targets: ["ZenNIOSSL"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-http2.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio-extras.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-log.git", .branch("master")),
        //.package(url: "https://github.com/apple/swift-metrics.git", .branch("master"))
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: [
                "NIO",
                "NIOConcurrencyHelpers",
                "NIOHTTP1",
                "NIOHTTPCompression",
                "Logging",
                //"Metrics"
            ]
        ),
        .target(
            name: "ZenNIOSSL",
            dependencies: [
                "ZenNIO",
                "NIOSSL",
                "NIOHTTP2"
            ]
        ),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: ["ZenNIO", "ZenNIOSSL"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

