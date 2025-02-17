// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SampleAppsCommon",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // library name is the name given when installing the SDK.
        // target name is the name used for `import X`
        .library(name: "SampleAppsCommon", targets: ["SampleAppsCommon"])
    ],
    dependencies: [
        .package(path: "../../") // import local CIO SDK to use internally.
    ],
    targets: [
        .target(
            name: "SampleAppsCommon",
            dependencies: [
                // List the modules from the Customer.io iOS SDK that you actually use
                .product(name: "DataPipelines", package: "customerio-ios"),
                .product(name: "MessagingPushAPN", package: "customerio-ios"),
                .product(name: "MessagingInApp", package: "customerio-ios")
            ],
            path: "Source"
        )
    ]
)
