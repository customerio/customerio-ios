// swift-tools-version:5.3

/**
 Manifest file for Swift Package Manager. This file defines our Swift Package for customers to install our SDK modules into their app. 

 Resources to learn more about this file:
 * https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
 * https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md
 */

import PackageDescription
import Foundation

// Swift Package Manager products are public-facing modules that developers can install into their app. 
// All .library() products will be visible to customers in Xcode when they install our SDK into their app.
// Therefore, it's important that we only expose modules that we want customers to use. Internal modules should not be included in this array.
var products: [PackageDescription.Product] = [
    .library(name: "Tracking", targets: ["CioTracking"]),
    .library(name: "MessagingPushAPN", targets: ["CioMessagingPushAPN"]),
    .library(name: "MessagingPushFCM", targets: ["CioMessagingPushFCM"]),
    .library(name: "MessagingInApp", targets: ["CioMessagingInApp"])
]

// When we execute the automated test suite, we use tools to determine the code coverage of our tests. 
// Xcode generates this code coverage report for us, for all of the products in this Package.swift file. 
// It's important that we track the test code coverage of our internal modules, but we don't want to expose internal modules to customers when they install our SDK. 
// Therefore, we dynamically modify the products array to include the internal modules only when executing the test suite and generating code coverage reports.
if (ProcessInfo.processInfo.environment["CI"] != nil) { // true if running on a CI machine. Important this is false for a customer trying to install our SDK on their machine. 
    // append all internal modules to the products array.
    products.append(.library(name: "InternalCommon", targets: ["CioInternalCommon"]))
}

let package = Package(
    name: "Customer.io",
    platforms: [
        .iOS(.v13)
    ],
    products: products,
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
                    .copy("SampleDataFiles") // static files that are used in test functions.
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
