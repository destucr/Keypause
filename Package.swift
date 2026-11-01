// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keypause",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Keypause",
            path: "Sources/Keypause",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
