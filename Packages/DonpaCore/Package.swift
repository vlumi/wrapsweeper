// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DonpaCore",
    // Enables localized resources (String Catalogs) in this package's targets;
    // EN is the development/base language.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        // Pure game logic — no UI dependencies. Headlessly testable.
        .library(name: "DonpaCore", targets: ["DonpaCore"]),
        // SpriteKit rendering + SwiftUI glue. Depends on DonpaCore.
        .library(name: "DonpaKit", targets: ["DonpaKit"]),
    ],
    targets: [
        .target(
            name: "DonpaCore",
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "DonpaKit",
            dependencies: ["DonpaCore"],
            resources: [
                .process("Resources/Panels.xcassets"),
                .process("Resources/Localizable.xcstrings"),
            ]
        ),
        // Dev-only tool: simulates the solver over candidate board configs to
        // pick difficulty tiers. Run with `swift run TierAnalysis`. Not shipped.
        .executableTarget(
            name: "TierAnalysis",
            dependencies: ["DonpaCore"]
        ),
        .testTarget(
            name: "DonpaCoreTests",
            dependencies: ["DonpaCore"]
        ),
        .testTarget(
            name: "DonpaKitTests",
            dependencies: ["DonpaKit"]
        ),
    ]
)
