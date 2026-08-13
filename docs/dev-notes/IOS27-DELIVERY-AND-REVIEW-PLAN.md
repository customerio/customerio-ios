# Xcode 27 delivery and PR review plan

## Goal

Add continuous Xcode 27 compile evidence without changing released SDK behavior. Runtime lifecycle work ships later as one complete backward-compatible feature after native ownership and wrapper forwarding are proven together.

## Permanent CI design

- Stable controls run the same fixture on `macos-26` with Xcode 26.6 and are blocking when the path-scoped workflow runs.
- Preview cells run on the floating `xcode-27` hosted label. The setup action leaves the image-bundled Xcode selected, then the shared reporter fails closed unless Xcode and the iOS SDK are major version 27.
- Preview cells use `continue-on-error: true` and must not be configured as required branch-protection checks. Path-scoped stable checks also need an always-run fallback before they can be universally required.
- New matrices pin `customerio/mobile-ci-tools/github-actions/ios/report-toolchain/v1@<merge-sha>` to an immutable commit. Existing release/test workflows that reference other `mobile-ci-tools` actions through `@main` are outside this rollout and are not repinned.
- Exact beta-image validation remains only in clearly titled test-only PRs. It is point-in-time diagnostic evidence, not permanent CI.
- When Xcode 27 becomes stable, replace `xcode-27` with the supported stable runner/version, make those cells blocking, and remove preview wording.

## Merge order

| Order | PR | Current base | Must merge first | Final target and purpose | Release effect |
| --- | --- | --- | --- | --- | --- |
| 1 | [mobile-ci-tools #15](https://github.com/customerio/mobile-ci-tools/pull/15) | `main` | None | `main`: add the shared reporter as a new action | No SDK release |
| 2 | [Flutter #393](https://github.com/customerio/customerio-flutter/pull/393) | `main` | None | `main`: keep floating-Flutter CI deterministic | No package release |
| 3 | [Flutter #388](https://github.com/customerio/customerio-flutter/pull/388) | `main` | None | `main`: pin samples to Flutter 3.44.8 with the Xcode 27 lipo fix | No package release |
| 4 | [iOS #1208](https://github.com/customerio/customerio-ios/pull/1208) | `main` | None | `main`: normalize generated CocoaPods sample targets | No SDK release |
| 5 | [Flutter #389](https://github.com/customerio/customerio-flutter/pull/389) | `main` | None | `main`: normalize the Flutter CocoaPods sample | No package release |
| 6 | [Expo #389](https://github.com/customerio/customerio-expo-plugin/pull/389) | `main` | mobile-ci-tools #15 | `main`: add stable/preview APN and FCM cells | No package release |
| 7 | [iOS #1213](https://github.com/customerio/customerio-ios/pull/1213) | `codex/mbl-2278-cocoapods-target-normalization` | mobile-ci-tools #15, iOS #1208 | Rebase and retarget to `main`: add native APN and FCM stable/preview cells | No SDK release |
| 8 | [Flutter #392](https://github.com/customerio/customerio-flutter/pull/392) | `codex/mbl-2248-flutter-xcode27-prereqs` | mobile-ci-tools #15, Flutter #393, Flutter #388, Flutter #389 | Rebase and retarget to `main`: add SwiftPM and CocoaPods stable/preview cells | No package release |

Orders 2 through 5 are independent and may merge in parallel. Use squash merge with the reviewed `ci:` or `chore:` title. This matters because semantic-release runs on `main`; preserving a release-bearing `feat:` or `fix:` commit from branch history could publish a package.

After mobile-ci-tools #15 squash-merges, update only these three new reporter references to its final merge SHA: Expo #389, iOS #1213, and Flutter #392. Rerun their matrices. Do not repo-wide repin unrelated existing `mobile-ci-tools@main` consumers. The action is additive, so rollback before consumer merge is simply reverting #15; after a consumer matrix merges, revert that matrix first.

After the other prerequisites merge, rebase iOS #1213 and Flutter #392 onto current `main`, retarget them to `main`, and rerun exact-head checks. Delete Flutter's temporary `codex/mbl-2248-flutter-xcode27-prereqs` branch after #392 is retargeted.

These CI and sample-tooling PRs may merge directly to `main` because they do not change published runtime code and their squash titles do not request a semantic release. No feature branch is required for this CI rollout.

## Test-only PRs, never merge

| PR | Purpose | Close when |
| --- | --- | --- |
| [iOS #1205](https://github.com/customerio/customerio-ios/pull/1205) | Exact Xcode 27 beta 4 native baseline | iOS #1213 records retained stable/preview evidence |
| [Flutter #386](https://github.com/customerio/customerio-flutter/pull/386) | Exact beta baseline and original Flutter lipo diagnosis | Flutter #392 records retained stable/preview evidence |
| [Expo #386](https://github.com/customerio/customerio-expo-plugin/pull/386) | Exact beta Expo 57 FCM baseline | Expo #389 records retained stable/preview evidence |

Before closing a test-only PR, copy its exact run/job IDs, image/Xcode build, result, and diagnostic conclusion into the corresponding mergeable PR body. Do not rely on expiring Actions logs or artifacts as the only durable record.

## Runtime lifecycle work is a later release

Compile matrices prove source compatibility only. They do not prove callback ownership, delivery, or backward compatibility, so lifecycle runtime PRs remain draft.

Runtime release order:

1. Correct and freeze the lifecycle contract with explicit host topology and callback-seat rules.
2. Complete the native coordinator and notification-delegate composition on an integration branch.
3. Prove AppDelegate-only backward compatibility and scene-based correctness.
4. Publish the complete native candidate from the repository's `beta` prerelease branch and validate real wrapper consumers against it.
5. Re-vendor the final contract into Flutter, Expo, and React Native and capture supported lifecycle paths.
6. Squash-merge one complete native release-bearing PR to `main`, release native, then update and release each wrapper independently.

Native delegate-composition PR [#1211](https://github.com/customerio/customerio-ios/pull/1211) and the current contract/wrapper drafts are not merge candidates until their recorded adversarial-review blockers are resolved.

## Required gate before removing draft status

This gate applies to Expo #389, iOS #1213, and Flutter #392. Lifecycle PRs are additionally gated by the runtime release order above.

- Record the exact head and current base in the PR body.
- Confirm the stable and preview cells exercise the same fixture and dependency setup.
- Require stable cells that actually ran on the exact head and are green. A skipped or filtered-out stable job is not evidence and must be forced to run on the exact head through `workflow_dispatch` or an always-run fallback. Classify any preview failure as toolchain, fixture-setup, or SDK-compile failure. Record a toolchain or fixture-setup failure in the PR body as non-blocking evidence. Record an SDK-compile failure and file a tracked source-compatibility issue; the additive matrix may still merge because preview cells are explicitly non-blocking.
- Confirm release workflows and squash titles do not request a package release.
- Confirm generated locks and sample projects have no unexplained churn.
- Run the Customer.io source-command review manually with Claude Opus against the exact head. Record the substantive verdict in the PR body; empty output, timeout, or quota failure is not acceptance.
- Reproduce and reconcile every actionable finding, then obtain an exact-head ACCEPT or a documented independent dismissal with evidence.

Delete this dev note after all three permanent matrices merge and the three test-only PRs close.
