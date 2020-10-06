// swift-tools-version:5.1
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
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.23.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.9.2"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "ZenNIO",
            dependencies: [
                "NIO",
                "NIOConcurrencyHelpers",
                "NIOHTTP1",
                "NIOHTTPCompression",
                "Logging"
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

