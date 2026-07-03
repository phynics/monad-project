// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonadProject",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "MonadShared", targets: ["MonadShared"]),
        .library(name: "MonadClient", targets: ["MonadClient"]),
        .executable(name: "MonadServer", targets: ["MonadServer"]),
        .executable(name: "MonadCLI", targets: ["MonadCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.11.2"),
        .package(url: "https://github.com/unum-cloud/USearch", from: "2.0.0"),
        .package(url: "https://github.com/FlineDev/ErrorKit", from: "1.0.0"),
        .package(url: "https://github.com/phynics/PositronicKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MonadShared",
            dependencies: [
                .product(name: "PKShared", package: "PositronicKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
            ],
            path: "Sources/MonadShared"
        ),
        .executableTarget(
            name: "MonadServer",
            dependencies: [
                "MonadShared",
                .product(name: "PositronicKit", package: "PositronicKit"),
                .product(name: "PKShared", package: "PositronicKit"),
                .product(name: "PKPrompt", package: "PositronicKit"),
                .product(name: "PKLocalEmbeddings", package: "PositronicKit"),
                .product(name: "PKOpenAIProvider", package: "PositronicKit"),
                .product(name: "PKOpenRouterProvider", package: "PositronicKit"),
                .product(name: "PKOllamaProvider", package: "PositronicKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "USearch", package: "USearch"),
                .product(name: "ErrorKit", package: "ErrorKit"),
            ],
            path: "Sources/MonadServer"
        ),
        .target(
            name: "MonadClient",
            dependencies: [
                "MonadShared",
                .product(name: "PKShared", package: "PositronicKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ErrorKit", package: "ErrorKit"),
            ],
            path: "Sources/MonadClient"
        ),
        .executableTarget(
            name: "MonadCLI",
            dependencies: [
                "MonadClient",
                "MonadShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ErrorKit", package: "ErrorKit"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MonadCLI"
        ),
        .testTarget(
            name: "MonadSharedTests",
            dependencies: [
                "MonadShared",
                .product(name: "PKShared", package: "PositronicKit"),
            ],
            path: "Tests/MonadSharedTests"
        ),
        .testTarget(
            name: "MonadServerTests",
            dependencies: [
                "MonadServer",
                "MonadShared",
                .product(name: "PositronicKit", package: "PositronicKit"),
                .product(name: "PKShared", package: "PositronicKit"),
                .product(name: "PKTestSupport", package: "PositronicKit"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "USearch", package: "USearch"),
            ],
            path: "Tests/MonadServerTests"
        ),
        .testTarget(
            name: "MonadCLITests",
            dependencies: [
                "MonadCLI",
                "MonadClient",
                "MonadShared",
                .product(name: "PKTestSupport", package: "PositronicKit"),
            ],
            path: "Tests/MonadCLITests"
        ),
        .testTarget(
            name: "MonadClientTests",
            dependencies: [
                "MonadClient",
                "MonadShared",
                .product(name: "PositronicKit", package: "PositronicKit"),
                .product(name: "PKTestSupport", package: "PositronicKit"),
            ],
            path: "Tests/MonadClientTests"
        ),
    ]
)
