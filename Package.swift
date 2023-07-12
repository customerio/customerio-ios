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
        .iOS(.v13)
    ],
    products: [ // externally visible products for clients to install. 
        // library name is the name given when installing the SDK. 
        // target name is the name used for `import X`
        .library(name: "Tracking", targets: ["CioTracking"]),
        .library(name: "MessagingPushAPN", targets: ["CioMessagingPushAPN"]),
        .library(name: "MessagingPushFCM", targets: ["CioMessagingPushFCM"]),
        .library(name: "MessagingInApp", targets: ["CioMessagingInApp"])
    ],
    dependencies: [
        // Help for the format of declaring SPM dependencies:
        // https://web.archive.org/web/20220525200227/https://www.timc.dev/posts/understanding-swift-packages/
        //
        // Update to exact version until wrapper SDKs become part of testing pipeline.
        .package(name: "Firebase", url: "https://github.com/firebase/firebase-ios-sdk.git", "8.7.0"..<"11.0.0")
    ],
    targets: [ 
        // Common - Code used by multiple modules in the SDK project.
        // this module is *not* exposed to the public. It's used internally. 
        .target(name: "CioInternalCommon",
                path: "Sources/Common"),
        .testTarget(name: "CommonTests",
                    dependencies: ["SharedTests"],
                    path: "Tests/Common"),
        // Tracking
        .target(name: "CioTracking",
                dependencies: ["CioInternalCommon"],
                path: "Sources/Tracking"),
        .testTarget(name: "TrackingTests",
                    dependencies: ["CioTracking", "SharedTests"],
                    path: "Tests/Tracking"),

        // shared code dependency that other test targets use. 
        .target(name: "SharedTests",
                dependencies: ["CioTracking"],
                path: "Tests/Shared",
                resources: [
                    .copy("SampleDataFiles") // static files that are used in test funnctions.
                ]),

        // Messaging Push 
        .target(name: "CioMessagingPush",
                dependencies: ["CioTracking"],
                path: "Sources/MessagingPush"),
        .testTarget(name: "MessagingPushTests",
                    dependencies: ["CioMessagingPush", "SharedTests"],
                    path: "Tests/MessagingPush"),

        // APN
        .target(name: "CioMessagingPushAPN",
                dependencies: ["CioMessagingPush"],
                path: "Sources/MessagingPushAPN"),
        .testTarget(name: "MessagingPushAPNTests",
                    dependencies: ["CioMessagingPushAPN", "SharedTests"],
                    path: "Tests/MessagingPushAPN"),
        // FCM 
        .target(name: "CioMessagingPushFCM",
                dependencies: ["CioMessagingPush", .product(name: "FirebaseMessaging", package: "Firebase")],
                path: "Sources/MessagingPushFCM"),
        .testTarget(name: "MessagingPushFCMTests",
                    dependencies: ["CioMessagingPushFCM", "SharedTests"],
                    path: "Tests/MessagingPushFCM"),

        // Messaging in-app
        .target(name: "CioMessagingInApp",
                dependencies: ["CioTracking"],
                path: "Sources/MessagingInApp"),
        .testTarget(name: "MessagingInAppTests",
                    dependencies: ["CioMessagingInApp", "SharedTests"],
                    path: "Tests/MessagingInApp"),
    ]
)
