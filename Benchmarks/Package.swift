// swift-tools-version: 6.1
import PackageDescription

// swift-arazzo's benchmarks, on ordo-one/package-benchmark (https://www.swift.org/blog/benchmarks/). A separate
// package so the benchmark dependency stays out of ArazzoKit's dependency budget. Run from the repository root:
// `swift package --package-path Benchmarks benchmark`.
let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "swift-arazzo", path: ".."),
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.38.0"),
    ],
    targets: [
        .executableTarget(
            name: "ArazzoBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "ArazzoKit", package: "swift-arazzo"),
                .product(name: "ArazzoKitYAML", package: "swift-arazzo"),
            ],
            path: "Benchmarks/ArazzoBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
