// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StockMonitor",
    platforms: [.macOS(.v13)],
    dependencies: [
        // In-app updates (ADR 0015). build.sh embeds Sparkle.framework in Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(name: "StockMonitor",
                          dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/StockMonitor"),
        .testTarget(name: "StockMonitorTests", dependencies: ["StockMonitor"], path: "Tests/StockMonitorTests",
                    resources: [.copy("Fixtures")]),
    ]
)
