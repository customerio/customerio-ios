// swift-tools-version: 5.10
// This file is used by Tuist to resolve external Swift Package dependencies.
// Run `tuist install` to resolve packages via git (normal).
// Run `tuist install --replace-scm-with-registry` to reproduce the resolution
// failure caused by the `+cio.1` build metadata suffix in version `1.7.3+cio.1`.

import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers
#endif

let package = Package(
    name: "TuistAPN",
    dependencies: [
        // ⚠️ Reproduction target:
        // Uses URL-based resolution, matching the customer's actual setup.
        // With --replace-scm-with-registry, SwiftPM asks the configured registry
        // "do you have a package for this URL?" and routes through it when indexed.
        // The failure occurs transitively: customerio-ios resolves fine, but its
        // dependency cdp-analytics-swift at `1.7.3+cio.1` cannot be matched by the
        // registry because build metadata (+cio.1) is ignored during SemVer comparison.
        .package(url: "https://github.com/customerio/customerio-ios.git", from: "4.4.0")
    ]
)
