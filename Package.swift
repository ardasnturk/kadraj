// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kadraj",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Kadraj", path: "Sources/Kadraj")
    ]
)
