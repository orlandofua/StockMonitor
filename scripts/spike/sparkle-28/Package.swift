// swift-tools-version:5.10
// Throwaway package for spike #28. It is not part of the shipped app.
// run.sh copies this directory to a work folder outside the repository and builds it there.
import PackageDescription

let package = Package(
    name: "SparkleSpike",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "SparkleSpike",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SparkleSpike",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
