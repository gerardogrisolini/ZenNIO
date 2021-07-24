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
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "ZenNIOSSL",
            dependencies: [
                "ZenNIO",
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2")
            ]
        ),
        .testTarget(
            name: "ZenNIOTests",
            dependencies: [
                "ZenNIO",
                "ZenNIOSSL"
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)

