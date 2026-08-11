# iOS Deployment Target Policy

Customer.io's published Apple SDK artifacts require iOS 15 or later. This floor applies to every
Swift Package Manager product and CocoaPods podspec owned by `customerio-ios`.

## Package manager behavior

- Swift Package Manager manifests declare iOS 15 directly.
- Customer.io podspecs declare iOS 15 directly.
- Sample applications use the same floor so local and hosted builds exercise the supported target.
- Availability guards and older compatibility helpers may remain in source until separate cleanup
  work in MBL-2279 proves they are no longer useful. They do not change the published deployment
  target.

Changing Customer.io manifests does not raise deployment targets declared by transitive CocoaPods.
Apple's official [Xcode requirements](https://developer.apple.com/support/xcode/) list iOS 15 as
the minimum deployment target for Xcode 27. Xcode 27 rejects a generated Pods project when any
target, including a resource bundle, remains below iOS 15. The current pinned native FCM evidence is
`customerio-ios` PR #1205, GitHub Actions run
[31521101922, attempt 2](https://github.com/customerio/customerio-ios/actions/runs/31521101922/attempts/2).
MBL-2278 owns the consumer-facing CocoaPods normalization and its generated-project validation. A
green SwiftPM build does not prove the corresponding CocoaPods graph is compatible.

## Release-gated coordination

As recorded on 2026-08-11, MBL-2235 must coordinate the following pins after releasable versions
exist. This policy change does not invent or publish those versions; MBL-2235 becomes the source of
record as releases move.

- `customerio-ios` currently pins `AnalyticsSwiftCIO` `1.7.3+cio.1`. A release containing its iOS 15
  podspec and SwiftPM floor is required before updating this exact pin.
- `customerio-ios` currently pins `Jist` `0.1.0`. A Jist release containing its iOS 15 manifests is
  required before updating this exact pin.
- `CioFirebaseWrapper` `1.0.0` already declares iOS 15, but its SwiftPM dependency starts at native
  SDK 4.x and excludes a future native major. Its next coordinated release must adopt the released
  native SDK version without guessing that version here.
- Flutter currently pins native iOS SDK `4.7.2` and CioFirebaseWrapper `1.0.0`.
- React Native currently pins native iOS SDK `4.7.2` and CioFirebaseWrapper `1.0.0`.
- Expo currently peers on React Native wrapper `6.6.2`.

Each affected package must ship this floor change only in its next coordinated major release.
MBL-2235 owns the exact versions and dependency pins. Do not publish the iOS 15 floor as a minor or
patch release in an existing iOS 13 compatibility line.

The last release line that declared iOS 13 remains the legacy compatibility line. The Xcode 27 iOS
SDK supports deployment targets starting at iOS 15, so legacy metadata is not evidence that a new
Xcode 27 build can continue targeting iOS 13 or iOS 14.

## Validation boundary

Local Xcode 26.6 simulator builds and unsigned archive evidence do not prove physical-device
behavior, signing or export, App Store submission, or the after-change Xcode 27 result. MBL-2233
and MBL-2248 own those remaining device, distribution, submission, and hosted-toolchain proofs as
assigned in the project. MBL-2278 owns the Xcode 27 CocoaPods generated-project proof, including
transitive pod and resource-bundle targets.
