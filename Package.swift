// swift-tools-version:5.3

/**
 Resources for this file:
 * https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
 * https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md
 */

import PackageDescription

let package = Package(
    name: "Customer.io",
    platforms: [
        .iOS(.v9)
    ],
    products: [
        .library(name: "CIO", targets: ["CIO"])
    ],
    dependencies: [],
    targets: [
        .target(name: "CIO",
                path: "Sources/SDK"),
        .testTarget(name: "SDKTests",
                    dependencies: ["CIO"],
                    path: "Tests/SDK")
    ]
)
