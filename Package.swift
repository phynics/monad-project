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
        .library(name: "MonadUI", targets: ["MonadUI"]),
        .library(name: "MonadServerCore", targets: ["MonadServerCore"]),
        .executable(name: "MonadServer", targets: ["MonadServer"])
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
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/MonadCore"
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
        .target(
            name: "MonadServerCore",
            dependencies: [
                "MonadCore",
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            path: "Sources/MonadServerCore"
        ),
        .executableTarget(
            name: "MonadServer",
            dependencies: [
                "MonadServerCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/MonadServer"
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
        ),
        .testTarget(
            name: "MonadServerTests",
            dependencies: ["MonadServerCore", "MonadCore"],
            path: "Tests/MonadServerTests"
        )
    ]
)