# Xcode 27 delivery and PR review plan

## Goal

Keep released SDK behavior unchanged while adding continuous Xcode 27 compile evidence. Runtime lifecycle changes ship later as one complete, backward-compatible feature, after native ownership and wrapper forwarding are proven together.

## CI design reviewers should expect

- The supported Xcode 26.x cell remains blocking.
- The floating Xcode 27 preview cell runs the same fixture and is non-blocking until Xcode 27 is stable.
- One shared `mobile-ci-tools` action records the hosted image, macOS, architecture, Xcode build, SDKs, and runtimes. SDK repositories do not copy exact-beta guards.
- Exact beta-image validation is retained only in clearly labeled test-only PRs.
- Expo preview cells run only in pull-request compatibility CI. They do not gate npm release.
- When Xcode 27 is stable, replace the preview runner/version, make the cells blocking, and remove preview-specific wording.

## Merge order

| Order | PR | Target | What it changes | Release effect |
| --- | --- | --- | --- | --- |
| 1 | [mobile-ci-tools #15](https://github.com/customerio/mobile-ci-tools/pull/15) | `main` | Shared toolchain report and major-version validation | No SDK release |
| 2 | [Flutter #393](https://github.com/customerio/customerio-flutter/pull/393) | `main` | Keeps the ordinary floating-Flutter checks deterministic after Flutter 3.47 and fails API extraction closed | No package release |
| 3 | [Flutter #388](https://github.com/customerio/customerio-flutter/pull/388) | `main` | Pins both sample apps to Flutter 3.44.8, the first stable version with the Xcode 27 lipo fix | No package release; keep a `ci:` or `chore:` title |
| 4 | [iOS #1208](https://github.com/customerio/customerio-ios/pull/1208) | `main` | Normalizes generated CocoaPods sample targets for Xcode 27 | No SDK release; keep a `ci:` title |
| 5 | [Flutter #389](https://github.com/customerio/customerio-flutter/pull/389) | `main` | Applies the same normalization to the Flutter CocoaPods sample | No package release; keep a `ci:` title |
| 6 | [iOS #1213](https://github.com/customerio/customerio-ios/pull/1213) | `main`, after #1208 | Xcode 26.6 and Xcode 27 matrix for APN/SwiftPM and FCM/CocoaPods | No SDK release |
| 7 | [Flutter #392](https://github.com/customerio/customerio-flutter/pull/392) | `main`, after #393, #388, and #389 | Xcode 26.6 and Xcode 27 matrix for Flutter SwiftPM and CocoaPods | No package release |
| 8 | [Expo #389](https://github.com/customerio/customerio-expo-plugin/pull/389) | `main`, after mobile-ci-tools #15 | Adds Xcode 27 APN/FCM cells to the existing latest-Expo PR matrix | No package release |

Orders 2 through 5 are independent after review and may merge in parallel. After their prerequisites merge, rebase #1213 and #392 onto current `main`, retarget them to `main`, and delete Flutter's temporary `codex/mbl-2248-flutter-xcode27-prereqs` branch. After mobile-ci-tools #15 merges, update every consumer to its final merge commit SHA.

These CI and sample-tooling PRs may merge directly to `main`. A feature branch would add coordination cost without protecting users because they contain no production runtime behavior and their semantic titles must not request a package release.

## Test-only PRs, never merge

| PR | Purpose | Close when |
| --- | --- | --- |
| [iOS #1205](https://github.com/customerio/customerio-ios/pull/1205) | Exact Xcode 27 beta 4 native baseline | #1213 has retained hosted stable/preview evidence |
| [Flutter #386](https://github.com/customerio/customerio-flutter/pull/386) | Exact beta baseline and original Flutter lipo diagnosis | #392 has retained hosted evidence |
| [Expo #386](https://github.com/customerio/customerio-expo-plugin/pull/386) | Exact beta Expo 57 FCM baseline | Expo #389 has retained hosted evidence |

These PRs intentionally pin a moving preview image. Keep their run links for diagnosis, then close them without merging.

## Runtime lifecycle work is a later release

Do not merge the lifecycle runtime PRs merely because the CI matrix is green. CI compilation proves source compatibility, not callback ownership or delivery.

The runtime release sequence is:

1. Correct and freeze the lifecycle contract, including explicit host topology and callback-seat rules.
2. Complete the native coordinator and notification-delegate composition on a native integration branch.
3. Prove backward compatibility for existing AppDelegate-only hosts and correctness for scene-based hosts.
4. Publish a native beta and validate real wrapper consumers against it.
5. Re-vendor the final contract into Flutter, Expo, and React Native, then capture supported lifecycle paths.
6. Merge one complete native release-bearing PR to `main`, release native, update wrappers to the released native version, and release each wrapper independently.

Current lifecycle PRs remain draft until that sequence is satisfied. In particular, native delegate-composition PR #1211 and the obsolete contract/wrapper heads must resolve their adversarial-review blockers before they are merge candidates.

## Required review gate for every mergeable PR

- Exact head and base are recorded.
- Stable and preview cells exercise the intended same fixture.
- Stable cells are green.
- Preview failures, if any, are classified as toolchain, fixture-preparation, or SDK compile failures.
- Release workflows and semantic titles do not publish a package for CI-only changes.
- Generated lockfiles and sample projects have no unexplained churn.
- A fresh Claude Opus adversarial review returns an actual verdict on the exact head. A timeout, quota failure, or empty output is not acceptance.
- All actionable findings are reproduced, reconciled, and re-reviewed before draft removal.
