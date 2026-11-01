// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keypause",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Keypause",
            dependencies: [.product(name: "Lottie", package: "lottie-ios")],
            path: "Sources/Keypause",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
