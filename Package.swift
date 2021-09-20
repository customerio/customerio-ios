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
        .iOS(.v11)
    ],
    products: [ // externally visible products for clients to install. 
        // library name is the name given when installing the SDK. 
        // target name is the name used for `import X`
        .library(name: "Tracking", targets: ["CioTracking"]),
        .library(name: "MessagingPushAPN", targets: ["CioMessagingPushAPN"]),
        .library(name: "MessagingPushFCM", targets: ["CioMessagingPushFCM"]),
    ],
    dependencies: [
        .package(name: "Firebase",
                   url: "https://github.com/firebase/firebase-ios-sdk.git",
                   from: "8.0.0")

    ],
    targets: [
        // Tracking
        .target(name: "CioTracking",
                path: "Sources/Tracking"),
        .testTarget(name: "TrackingTests",
                    dependencies: ["CioTracking", "SharedTests"],
                    path: "Tests/Tracking"),
            
        // shared code dependency that other test targets use. 
        .target(name: "SharedTests", 
                dependencies: ["CioTracking"],
                path: "Tests/Shared"),
                
        // Messaging Push 
        .target(name: "CioMessagingPush",
                dependencies: ["CioTracking"],
                path: "Sources/MessagingPush"),
        .testTarget(name: "MessagingPushTests",
                    dependencies: ["CioMessagingPush", "SharedTests"],
                    path: "Tests/MessagingPush"),

        .target(name: "CioMessagingPushAPN",
                dependencies: ["CioMessagingPush"],
                path: "Sources/MessagingPushAPN"),
        .testTarget(name: "MessagingPushAPNTests",
                    dependencies: ["CioMessagingPushAPN", "SharedTests"],
                    path: "Tests/MessagingPushAPN"),
        .target(name: "CioMessagingPushFCM",
                dependencies: ["CioMessagingPush", .product(name: "FirebaseMessaging", package: "Firebase")],
                path: "Sources/MessagingPushFCM"),
        .testTarget(name: "MessagingPushFCMTests",
                    dependencies: ["CioMessagingPushFCM", "SharedTests"],
                    path: "Tests/MessagingPushFCM"),
    ]
)
