// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-arazzo",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        // The core models, runtime expressions, condition evaluation and validation.
        // Depends only on swift-jsonpath; uses FoundationEssentials where available.
        .library(name: "ArazzoKit", targets: ["ArazzoKit"]),
        // Optional YAML support (decoding/encoding) built on Yams.
        .library(name: "ArazzoKitYAML", targets: ["ArazzoKitYAML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mackoj/swift-jsonpath.git", branch: "main"),
        .package(url: "https://github.com/jpsim/Yams.git", "5.1.0"..<"7.0.0"),
    ],
    targets: [
        .target(
            name: "ArazzoKit",
            dependencies: [
                .product(name: "JSONPath", package: "swift-jsonpath")
            ]
        ),
        .target(
            name: "ArazzoKitYAML",
            dependencies: [
                "ArazzoKit",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "ArazzoKitTests",
            dependencies: [
                "ArazzoKit",
                "ArazzoKitYAML",
            ],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
