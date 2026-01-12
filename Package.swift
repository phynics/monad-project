// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonadAssistant",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "MonadCore", targets: ["MonadCore"]),
        .library(name: "MonadMCP", targets: ["MonadMCP"]),
        .library(name: "MonadUI", targets: ["MonadUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "MonadCore",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/MonadCore",
            exclude: [
                "monad.proto",
                "swift-protobuf-config.json"
            ]
        ),
        .target(
            name: "MonadMCP",
            dependencies: ["MonadCore"],
            path: "Sources/MonadMCP"
        ),
        .target(
            name: "MonadUI",
            dependencies: [
                "MonadCore",
                "MonadMCP",
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/MonadUI"
        ),
        .testTarget(
            name: "MonadCoreTests",
            dependencies: ["MonadCore", "MonadUI"],
            path: "Tests/MonadCoreTests"
        ),
        .testTarget(
            name: "MonadMCPTests",
            dependencies: ["MonadMCP", "MonadCore"],
            path: "Tests/MonadMCPTests"
        )
    ]
)
