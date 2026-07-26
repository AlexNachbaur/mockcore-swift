// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MockCore",
    // Minimum Apple OS versions only — required for Swift concurrency APIs on Apple targets.
    // This does NOT limit platform support: Linux, Windows, and Android ignore this field.
    // Both products build and test on all four, and CI proves it on every one.
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Portable foundation (no SwiftNIO): value model, state store, generators, seed
        // primitives, diagnostics. Usable anywhere Swift runs.
        .library(name: "MockCore", targets: ["MockCore"]),
        // The shared HTTP/WebSocket listener (MockHost) and the MockService extension seam.
        .library(name: "MockCoreTransport", targets: ["MockCoreTransport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.70.0"),
        // Build-time only: enables `swift package generate-documentation` for the DocC catalogs.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "MockCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(
            name: "MockCoreTransport",
            dependencies: [
                "MockCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),
        .testTarget(name: "MockCoreTests", dependencies: ["MockCore"]),
        .testTarget(name: "MockCoreTransportTests", dependencies: ["MockCoreTransport"]),
    ]
)
