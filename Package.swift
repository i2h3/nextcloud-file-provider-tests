// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "NextcloudFileProviderTests",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "ClientHarness", targets: ["ClientHarness"]),
        .executable(name: "tests", targets: ["Runner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/i2h3/nextcloud-container-manager", from: "2.0.0"),
        .package(url: "https://github.com/i2h3/rainmaker", from: "4.0.0"),
    ],
    targets: [
        // Everything which observes and controls the desktop client on this machine. It deliberately has no dependency on Docker or on a Nextcloud server so that its unit tests stay hermetic.
        .target(name: "ClientHarness"),

        // The axis model the end-to-end suites enumerate their cases from. Pure data: no input, no output, no dependency, and deliberately no knowledge of how any of it is established.
        .target(name: "ScenarioMatrix"),

        // Everything which deploys and provisions the Nextcloud servers under test.
        .target(name: "ServerHarness", dependencies: [
            "ClientHarness",
            .product(name: "NextcloudContainerManager", package: "nextcloud-container-manager"),
            .product(name: "Rainmaker", package: "rainmaker"),
        ]),

        // The command line entry point which owns the container lifecycle around a single test process.
        .executableTarget(name: "Runner", dependencies: [
            "ClientHarness",
            "ServerHarness",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),

        // Hermetic unit tests of the harness itself. These are what a bare `swift test` is expected to run anywhere.
        .testTarget(name: "ClientHarnessTests", dependencies: ["ClientHarness"]),
        .testTarget(name: "ServerHarnessTests", dependencies: ["ServerHarness"]),

        // The end-to-end suites. They are gated on a live environment and skip themselves without one.
        .testTarget(name: "FileProviderTests", dependencies: [
            "ClientHarness",
            "ScenarioMatrix",
            "ServerHarness",
            .product(name: "NextcloudContainerManager", package: "nextcloud-container-manager"),
            .product(name: "Rainmaker", package: "rainmaker"),
        ]),
    ]
)
