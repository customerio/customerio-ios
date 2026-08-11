# Xcode 27 preview CI

The `Xcode 27 compile fixtures` workflow is a compile-only early-warning lane for the iOS 27 SDK. It does not replace the Xcode 26.6 lint, unit-test, sample-app, or Maestro jobs established by MBL-2224, and it is not real-device evidence. MBL-2233 owns simulator and device behavior.

## Reviewed preview pin

The lane runs on GitHub's Apple silicon `xcode-27` preview label. GitHub does not offer an immutable image-version selector for this hosted preview. The label can move without a repository change, so `.github/actions/verify-xcode-27-preview` fails before compilation unless the runner still matches all checked-in values:

| Field | Pin |
| --- | --- |
| GitHub image | `20260810.0090.1` |
| Host | macOS `26.5.2` (`25F84`), `arm64` |
| Xcode | `27.0` beta 4, build `27A5228h` |
| Xcode app | `/Applications/Xcode_27_beta_4.app` |
| SDKs | `iphoneos27.0`, `iphonesimulator27.0` |
| Runtime | `com.apple.CoreSimulator.SimRuntime.iOS-27-0` |

Sources: the official [Xcode 27 preview announcement](https://github.com/actions/runner-images/issues/14404) and the reviewed [xcode-27 image inventory for release 20260810.0090](https://github.com/actions/runner-images/blob/xcode-27-arm64/20260810.0090/images/macos/xcode-27-arm64-Readme.md).

The workflow prints `ImageOS`, `ImageVersion`, macOS version/build, host architecture, Xcode version/build, installed SDKs, and simulator runtimes. The checked-in values are the reviewed pin retained in git history. Customer.io cannot keep a retired GitHub-hosted preview image available after the floating label advances.

## Failure classification

`preview-infrastructure-drift` means the runner image, Xcode app/build, SDK, architecture, or runtime changed before fixture compilation. Compare the official runner inventory, then update the pin deliberately.

`fixture-preparation-failure` means dependency resolution failed, so no SDK compile conclusion is available.

`sdk-compile-failure` means the complete pin guard passed and a named fixture failed during `xcodebuild`. This is the only failure class that should enter SDK source triage immediately.

The two native fixtures are `Apps/APN-UIKit` and `Apps/CocoaPods-FCM`. The latter resolves `CioFirebaseWrapper`, providing the representative `customerio-ios-fcm` integration build requested by MBL-2248. Both builds disable signing and target the iOS 27 simulator SDK. They do not send pushes or prove callback delivery.

## Pin ownership and update procedure

Squad Mobile owns the preview pin. When GitHub or Apple publishes a replacement:

1. Verify the new values in the release-specific `actions/runner-images` inventory linked as `Included Software` by the hosted job, plus the announcement or release history.
2. Update the constants in `.github/actions/verify-xcode-27-preview/action.yml` in one reviewable change.
3. Require both the native APN and `customerio-ios-fcm` jobs to pass on the replacement toolchain. Do not waive the existing Xcode 26 jobs.
4. In the same tracking work, update the repository-local guard copies in Flutter and Expo to the identical reviewed values, then run each repository's own fixture.
5. Keep the previous values in git history for incident comparison. Do not describe the old hosted image as runnable after GitHub removes it.

## Flutter and Expo handoff

Flutter and Expo own their fixture source, dependency resolution, and build command. Each repository carries its own copy of the fail-closed guard so a wrapper pull request does not depend on an unmerged native commit. The handoff contract is the complete checked-in value set above plus the three failure classifications, not an assertion that wrapper fixture code lives in this repository.

An update is complete only when one tracking change records the newly verified official values, applies the identical guard constants in native iOS, Flutter, and Expo, and obtains a named fixture result from every repository. This native workflow deliberately does not check out Flutter or Expo and makes no claim that their fixtures passed.
