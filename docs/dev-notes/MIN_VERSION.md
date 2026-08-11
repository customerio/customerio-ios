# Minimum Swift and iOS versions

This project has minimum Swift and iOS versions that it supports.

Follow the checklists below when increasing either version. A manifest edit is not sufficient evidence:
validate the supported package-manager and sample-app paths in CI before release.

## Increase the Swift version

- Update the SwiftFormat version in `Makefile`.
- Update the `swift-tools-version` in each owned `Package.swift` manifest.
- Update `spec.swift_version` in every owned podspec.
- Remove unsupported Swift versions from the CI test matrix.
- Update the README badge.

## Increase the iOS version

- Update the platform in the root and sample-support `Package.swift` manifests.
- Update `spec.ios.deployment_target` in every owned podspec, including sample-support podspecs.
- Update the README badge.
- Update `IOSDeploymentTargetManifestTests` so its exact manifest inventory and active declarations
  enforce the new floor.
- Update [the deployment-target policy](IOS-DEPLOYMENT-TARGET-POLICY.md) with the release boundary,
  dependency pins, and remaining evidence owners.
- Treat a floor increase as a breaking package contract. Use a conventional-commit breaking marker
  and coordinate the next major releases before publishing.
- Validate SwiftPM and CocoaPods apps and extensions. A green SwiftPM build does not prove that
  transitive generated Pods targets satisfy the selected floor.
