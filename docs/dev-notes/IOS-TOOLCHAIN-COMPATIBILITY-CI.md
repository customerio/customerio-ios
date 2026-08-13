# iOS toolchain compatibility CI

`iOS toolchain compatibility` compiles the same native APN and CocoaPods FCM fixtures on the supported Xcode 26.6 toolchain and the floating Xcode 27 preview runner. When this path-scoped workflow runs, its stable cells are blocking regression controls and its preview cells are experimental and non-blocking. Do not configure these path-scoped checks as universally required branch-protection checks without an always-run fallback.

The workflow deliberately verifies only the Xcode and iOS SDK major families. It records the hosted image, macOS, architecture, exact Xcode build, SDK versions, and installed runtimes through the shared `mobile-ci-tools` action. It does not copy an exact beta-image pin into this repository.

Exact beta-image validation belongs in a temporary, explicitly test-only PR. It can establish a reproducible point-in-time baseline, but must not be merged as permanent CI because the `xcode-27` hosted label moves between preview images.

When Xcode 27 becomes stable, change its matrix cells to the supported stable runner/version and make them blocking. Remove preview wording at the same time. A compile pass proves only unsigned simulator compilation of the named fixtures. It does not prove app launch, lifecycle callback delivery, physical-device push delivery, signing, export, or App Store acceptance.
