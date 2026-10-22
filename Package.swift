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
        // A standalone JSONPath engine (RFC 9535 and Jayway dialects), JSON value/parser and JSON Pointer.
        // Pure Swift: no dependencies beyond the standard library (not even Foundation).
        .library(name: "JSONPath", targets: ["JSONPath"]),
        // The core models, runtime expressions, condition evaluation and validation.
        // Depends only on JSONPath; uses FoundationEssentials where available.
        .library(name: "ArazzoKit", targets: ["ArazzoKit"]),
        // Optional YAML support (decoding/encoding) built on Yams.
        .library(name: "ArazzoKitYAML", targets: ["ArazzoKitYAML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", "5.1.0"..<"7.0.0"),
    ],
    targets: [
        .target(
            name: "JSONPath",
            linkerSettings: [
                // `rounded()` / `squareRoot()` come from libm, which Foundation would otherwise pull in.
                .linkedLibrary("m", .when(platforms: [.linux, .android]))
            ]
        ),
        .target(
            name: "ArazzoKit",
            dependencies: ["JSONPath"]
        ),
        .target(
            name: "ArazzoKitYAML",
            dependencies: [
                "ArazzoKit",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "JSONPathTests",
            dependencies: ["JSONPath"],
            exclude: ["Fixtures"]
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
