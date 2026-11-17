// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StockMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "StockMonitor", path: "Sources/StockMonitor")
    ]
)
