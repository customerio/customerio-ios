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
        .library(name: "SDK", targets: ["SDK"])
    ],
    dependencies: [],
    targets: [
        .target(name: "SDK",
                path: "Sources/SDK"),
        .testTarget(name: "SDKTests",
                    dependencies: ["SDK"],
                    path: "Tests/SDK")
    ]
)
