import ProjectDescription

let project = Project(
    name: "TuistAPN",
    organizationName: "CustomerIO",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    packages: [],
    targets: [
        .target(
            name: "TuistAPN",
            destinations: .iOS,
            product: .app,
            bundleId: "io.customer.TuistAPN",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": .dictionary([:]),
                    "NSLocationWhenInUseUsageDescription": .string("Used for location-based messaging")
                ]
            ),
            sources: ["Sources/TuistAPN/**"],
            dependencies: [
                .external(name: "CioDataPipelines"),
                .external(name: "CioMessagingPushAPN"),
                .external(name: "CioMessagingInApp"),
                .external(name: "CioLocation")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "TuistAPN",
            buildAction: .buildAction(targets: ["TuistAPN"]),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
