// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bak-bak",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "bak-bak", targets: ["bak-bak"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "bak-bak",
            dependencies: [
                "Pipeline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "Pipeline",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: ["Pipeline"]
        ),
    ]
)
