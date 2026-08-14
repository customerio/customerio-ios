# iOS toolchain compatibility CI

`Xcode 27 preview compatibility` compiles the native APN and CocoaPods FCM fixtures on the floating Xcode 27 preview runner. It runs nightly at 05:17 UTC, on manual dispatch, and when its own workflow definition changes. Ordinary source pull requests and pushes do not trigger it; a pull request changing the workflow intentionally opts into the preview jobs.

The regular sample-app and test workflows remain the required stable-Xcode regression coverage. Repeating those builds in this workflow would consume scarce hosted macOS capacity without adding a distinct release gate. A nightly run instead detects preview-image changes and incompatibilities on `main`. A pull request specifically changing iOS toolchain integration can be validated before merge with a manual dispatch or an explicitly test-only workflow change.

Preview failures are recorded as failed scheduled or manually dispatched runs. They cannot block ordinary pull requests because those pull requests do not trigger this workflow. A hosted preview label can become unavailable before a job starts, and job timeouts do not cover queue time, so a missing or persistently queued nightly is an infrastructure alert rather than a pass.

The workflow deliberately verifies only the Xcode and iOS SDK major families. It records the hosted image, macOS, architecture, exact Xcode build, SDK versions, and installed runtimes through the shared `mobile-ci-tools` action. It does not copy an exact beta-image pin into this repository.

Exact beta-image validation belongs in a temporary, explicitly test-only PR. It can establish a reproducible point-in-time baseline, but must not be merged as permanent CI because the `xcode-27` hosted label moves between preview images.

When Xcode 27 becomes stable, remove this temporary preview workflow and add Xcode 27 to the normal required CI path. A compile pass proves only unsigned simulator compilation of the named fixtures. It does not prove app launch, lifecycle callback delivery, physical-device push delivery, signing, export, or App Store acceptance.
