# iOS toolchain compatibility CI

`Xcode 27 preview compatibility` compiles the native APN and CocoaPods FCM fixtures on the floating Xcode 27 preview runner, installs each simulator product, launches it, and verifies that the expected executable remains alive for ten seconds. It runs nightly at 05:17 UTC, on manual dispatch, and when its own workflow definition changes. Ordinary source pull requests and pushes do not trigger it; a pull request changing the workflow intentionally opts into the preview jobs.

The regular sample-app and test workflows remain the required stable-Xcode regression coverage. Repeating those builds in this workflow would consume scarce hosted macOS capacity without adding a distinct release gate. A nightly run instead detects preview-image changes and incompatibilities on `main`. A pull request specifically changing iOS toolchain integration can be validated before merge with a manual dispatch or an explicitly test-only workflow change.

Preview failures are recorded as failed scheduled or manually dispatched runs. They cannot block ordinary pull requests because those pull requests do not trigger this workflow. Scheduled and manually dispatched runs on `main` share one concurrency group, so a fresh dispatch replaces a stale nightly instead of competing for the preview runner. A hosted preview label can become unavailable before a job starts, and job timeouts do not cover queue time, so a missing or persistently queued nightly is an infrastructure condition rather than a pass.

The workflow deliberately verifies only the Xcode and iOS SDK major families. It records the hosted image, macOS, architecture, exact Xcode build, SDK versions, and installed runtimes through the shared `mobile-ci-tools` action. It does not copy an exact beta-image pin into this repository.

Exact beta-image validation belongs in a temporary, explicitly test-only PR. It can establish a reproducible point-in-time baseline, but must not be merged as permanent CI because the `xcode-27` hosted label moves between preview images.

The review invariant for this workflow is the known failure mode, not the implementation mechanism: an Xcode 27 product can compile and still terminate during launch when its host lifecycle is incompatible. A change is not adequate unless it can distinguish that failure from a product that launches and survives. The shared launch action owns the launch classification, summary, and bounded simulator log. This workflow uploads that explicit log together with the build log and fails if no diagnostic artifact exists. The smoke test proves unsigned simulator compilation, installation, launch, executable identity, and short process survival on the pre-login screen. It does not prove lifecycle callback delivery, authenticated UI paths, physical-device push delivery, signing, export, or App Store acceptance.

When Xcode 27 becomes stable, remove this temporary preview workflow and add Xcode 27 to the normal required CI path.
