// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xbloom-cli",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "xbloom-cli",
            path: "Sources/XBloomCLI"
        )
    ]
)
