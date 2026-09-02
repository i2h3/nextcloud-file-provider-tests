// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NextcloudFileProviderTests",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "NextcloudFileProviderTests",
            targets: ["NextcloudFileProviderTests"]
        ),
    ],
    targets: [
        .target(
            name: "NextcloudFileProviderTests"
        ),
        .testTarget(
            name: "NextcloudFileProviderTestsTests",
            dependencies: ["NextcloudFileProviderTests"]
        ),
    ]
)
