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
    products: [ // externally visible products for clients to install. 
        .library(name: "CioMessagingPushAPN", targets: ["MessagingPushAPN"])
    ],
    dependencies: [],
    targets: [
        // Common 
        .target(name: "Common",
                path: "Sources/Common"),
        .testTarget(name: "CommonTests",
                    dependencies: ["Common"],
                    path: "Tests/Common"),
        // Messaging Push 
        .target(name: "MessagingPush",
                dependencies: ["Common"],
                path: "Sources/MessagingPush"),
        .testTarget(name: "MessagingPushTests",
                    dependencies: ["MessagingPush"],
                    path: "Tests/MessagingPush"),

        .target(name: "MessagingPushAPN",
                dependencies: ["MessagingPush"],
                path: "Sources/MessagingPushAPN"),
        .testTarget(name: "MessagingPushAPNTests",
                    dependencies: ["MessagingPushAPN"],
                    path: "Tests/MessagingPushAPN")
    ]
)
