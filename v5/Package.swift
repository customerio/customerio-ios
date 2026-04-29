// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "customerio-ios",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [],
    dependencies: [
        .package(
            url: "https://github.com/customerio/SqlCipherKit",
            .upToNextMajor(from: "0.9.0")),
    ],
    targets: [

        // MARK: - Internal utilities (not a public product)

        .target(
            name: "CustomerIO_Utilities",
            dependencies: [
                .product(name: "SqlCipherKit", package: "SqlCipherKit")
            ],
            path: "Sources/CustomerIO_Utilities",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CustomerIO_UtilitiesTests",
            dependencies: ["CustomerIO_Utilities"],
            path: "Tests/CustomerIO_UtilitiesTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
