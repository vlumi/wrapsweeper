// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DonpaCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        // Pure game logic — no UI dependencies. Headlessly testable.
        .library(name: "DonpaCore", targets: ["DonpaCore"]),
        // SpriteKit rendering + SwiftUI glue. Depends on DonpaCore.
        .library(name: "DonpaKit", targets: ["DonpaKit"]),
    ],
    targets: [
        .target(name: "DonpaCore"),
        .target(
            name: "DonpaKit",
            dependencies: ["DonpaCore"],
            resources: [.process("Resources/Panels.xcassets")]
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
