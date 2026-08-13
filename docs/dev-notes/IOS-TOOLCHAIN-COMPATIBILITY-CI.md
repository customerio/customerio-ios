# iOS toolchain compatibility CI

`iOS toolchain compatibility` compiles the same native APN and CocoaPods FCM fixtures on the supported Xcode 26.6 toolchain and the floating Xcode 27 preview runner. Its pull-request trigger is path-scoped, while every push to `main` records a baseline. When the workflow runs, stable cells are blocking regression controls and preview cells are experimental and non-blocking. Do not configure these path-scoped pull-request checks as universally required branch-protection checks without an always-run fallback.

The stable cells intentionally use the same focused commands and dependency setup as the preview cells. Existing sample-app workflows provide broader regression coverage, but they are not a controlled before-and-after comparison for failures introduced by a toolchain change.

The workflow deliberately verifies only the Xcode and iOS SDK major families. It records the hosted image, macOS, architecture, exact Xcode build, SDK versions, and installed runtimes through the shared `mobile-ci-tools` action. It does not copy an exact beta-image pin into this repository.

Exact beta-image validation belongs in a temporary, explicitly test-only PR. It can establish a reproducible point-in-time baseline, but must not be merged as permanent CI because the `xcode-27` hosted label moves between preview images.

When Xcode 27 becomes stable, change its matrix cells to the supported stable runner/version and make them blocking. Remove preview wording at the same time. A compile pass proves only unsigned simulator compilation of the named fixtures. It does not prove app launch, lifecycle callback delivery, physical-device push delivery, signing, export, or App Store acceptance.
