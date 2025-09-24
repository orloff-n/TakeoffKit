// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TakeoffKit",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "TakeoffKit",
            type: .static,
            targets: ["TakeoffKit"])
    ],
    targets: [
        .target(
            name: "TakeoffKit",
            path: "Sources"
        ),
        .testTarget(
            name: "TakeoffKitTests",
            dependencies: ["TakeoffKit"],
            path: "Tests"
        )
    ]
)
