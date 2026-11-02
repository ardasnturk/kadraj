// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kadraj",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Kadraj",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Kadraj",
            // Sparkle.framework is copied to Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
