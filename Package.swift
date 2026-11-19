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
                          path: "Sources/StockMonitor",
                          // SwiftPM copies Sparkle.framework next to the executable in .build/<config>/
                          // but adds no rpath for it, so `swift run` and .build/*/StockMonitor would
                          // not start. build.sh adds @executable_path/../Frameworks for the app bundle.
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path"])]),
        .testTarget(name: "StockMonitorTests", dependencies: ["StockMonitor"], path: "Tests/StockMonitorTests",
                    resources: [.copy("Fixtures")]),
    ]
)
