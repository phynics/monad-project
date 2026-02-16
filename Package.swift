// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonadProject",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MonadCore", targets: ["MonadCore"]),
        .library(name: "MonadClient", targets: ["MonadClient"]),
        .executable(name: "MonadServer", targets: ["MonadServer"]),
        .executable(name: "MonadCLI", targets: ["MonadCLI"]),
        .library(name: "MonadShared", targets: ["MonadShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/unum-cloud/USearch", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MonadShared",
            dependencies: [],
            path: "Sources/MonadShared"
        ),
        .target(
            name: "MonadCore",
            dependencies: [
                "MonadShared",
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "USearch", package: "USearch"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            path: "Sources/MonadCore"
        ),
        .executableTarget(
            name: "MonadServer",
            dependencies: [
                "MonadCore",
                "MonadClient",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MonadServer"
        ),
        .target(
            name: "MonadClient",
            dependencies: [
                "MonadCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MonadClient"
        ),
        .executableTarget(
            name: "MonadCLI",
            dependencies: [
                "MonadClient",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MonadCLI"
        ),
        .testTarget(
            name: "MonadCoreTests",
            dependencies: ["MonadCore"],
            path: "Tests/MonadCoreTests"
        ),
        .testTarget(
            name: "MonadServerTests",
            dependencies: [
                "MonadServer",
                "MonadCore",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Tests/MonadServerTests"
        ),
        .testTarget(
            name: "MonadCLITests",
            dependencies: ["MonadCLI", "MonadClient"],
            path: "Tests/MonadCLITests"
        ),
    ]
)
