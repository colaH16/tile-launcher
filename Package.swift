// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TileLauncher",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "TileLauncher", targets: ["TileLauncher"])],
    targets: [
        .target(name: "DeckCore"),
        .executableTarget(name: "TileLauncher", dependencies: ["DeckCore"],
            swiftSettings: [.define("TILE_LAUNCHER_DIAGNOSTICS", .when(configuration: .debug))]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"])
    ],
    swiftLanguageModes: [.v5]
)
