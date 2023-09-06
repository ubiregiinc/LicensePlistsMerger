// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LicensesPlistMerger",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "license-plists-merger", targets: ["LicensesPlistMerger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.3"),
    ],
    targets: [
        .executableTarget(
            name: "LicensesPlistMerger",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"),
    ]
)
