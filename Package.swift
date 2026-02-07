// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonadProject",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MonadCore", targets: ["MonadCore"]),
        .library(name: "MonadClient", targets: ["MonadClient"]),
        .executable(name: "MonadServer", targets: ["MonadServer"]),
        .executable(name: "MonadCLI", targets: ["MonadCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "MonadCore",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MonadCore"
        ),
        .executableTarget(
            name: "MonadServer",
            dependencies: [
                "MonadCore",
                .product(name: "Hummingbird", package: "hummingbird"),
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
                "MonadServer", // Now testing the executable target if possible, or just depending on source files.
                // Wait, testing executable targets is tricky. 
                // Usually we test a library. Since I merged correct into executable, I have to be careful.
                // Re-reading: "MonadServer" is .executableTarget.
                // Can I test it? Yes, but usually we extract logic to a library.
                // User explicitly asked to merge.
                // If I merge, I might lose ability to test easily unless I expose internals or `MonadServer` is a valid dependency.
                // Swift Package Manager allows testing executables if we use `@testable import`.
                // Let's assume I can depend on "MonadServer" or just "MonadCore".
                // Actually, the tests likely depend on code that was in `MonadServerCore`.
                // If that code is now in `MonadServer`, the tests need to import `MonadServer`.
                // But `MonadServer` is an executable, so it might not be linkable as a library by default without `package` access.
                // Let's try to add "MonadCore" and assume I can import the module.
                "MonadCore",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
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
