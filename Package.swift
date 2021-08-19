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
        .library(name: "CioMessagingPushAPN", targets: ["MessagingPushAPN"]),
        .library(name: "CioTracking", targets: ["Tracking"])
    ],
    dependencies: [],
    targets: [
        // Common 
        .target(name: "Common",
                path: "Sources/Common"),
        .testTarget(name: "CommonTests",
                    dependencies: ["Common", "SharedTests"],
                    path: "Tests/Common"),
        .target(name: "SharedTests",
                path: "Tests/Shared"),
        // Messaging Push 
        .target(name: "MessagingPush",
                dependencies: ["Common"],
                path: "Sources/MessagingPush"),
        .testTarget(name: "MessagingPushTests",
                    dependencies: ["MessagingPush", "SharedTests"],
                    path: "Tests/MessagingPush"),

        .target(name: "MessagingPushAPN",
                dependencies: ["MessagingPush"],
                path: "Sources/MessagingPushAPN"),
        .testTarget(name: "MessagingPushAPNTests",
                    dependencies: ["MessagingPushAPN", "SharedTests"],
                    path: "Tests/MessagingPushAPN"),
        
        // Tracking
        .target(name: "Tracking",
                dependencies: ["Common"],
                path: "Sources/Tracking"),
        .testTarget(name: "TrackingTests",
                    dependencies: ["Tracking", "SharedTests"],
                    path: "Tests/Tracking"),
    ]
)
