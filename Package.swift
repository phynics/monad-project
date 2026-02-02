// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonadProject",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MonadCore", targets: ["MonadCore"]),
        .library(name: "MonadServerCore", targets: ["MonadServerCore"]),
        .library(name: "MonadClient", targets: ["MonadClient"]),
        .executable(name: "MonadServer", targets: ["MonadServer"]),
        .executable(name: "MonadCLI", targets: ["MonadCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MonadCore",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/MonadCore"
        ),
        .target(
            name: "MonadServerCore",
            dependencies: [
                "MonadCore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/MonadServerCore"
        ),
        .executableTarget(
            name: "MonadServer",
            dependencies: [
                "MonadServerCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MonadServer"
        ),
        .target(
            name: "MonadClient",
            dependencies: [],
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
                "MonadServerCore",
                "MonadCore",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/MonadServerTests"
        ),
    ]
)
