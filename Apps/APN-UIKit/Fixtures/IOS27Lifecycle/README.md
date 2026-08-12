# iOS 27 disposable source probe

This fixture exposes existing Customer.io notification-center and provider-token seats to the
sample app's one process-wide recorder. It does not add an application, scene, notification-center,
or provider delegate. It posts safe in-process observations before or after existing calls and
passes every production completion object through unchanged.

`run_disposable_source_patch.py` verifies the four production source files against hashes recorded
at `2e64ddf8802c1b74c9be637eca5f94ee27737444`, the commit that introduced this lock, creates a temporary local clone, overlays only
the current producer/test files, applies the checked patch there, runs the requested command from
that checkout, verifies the original sources again, and removes the checkout. A mismatch or patch
drift fails closed. `source-files.lock.json` also pins the exact repository-owned patch SHA-256, so
an alternate or same-path-modified patch cannot be selected by the CLI or accepted by the runner.
Each file also has an exact post-patch digest, checked after application, so a same-path patch that
produces different source bytes cannot enter a capture.

The patch transports raw token and notification objects only through the process-wide default
`NotificationCenter` to the fixture observer. They never leave the process, and the recorder emits
only canonical safe facts and ephemeral aliases. This in-process visibility is an instrumentation
delta and must be included in the capture provenance.

Example:

```sh
python3 Apps/APN-UIKit/Fixtures/IOS27Lifecycle/run_disposable_source_patch.py \
  --source-root . -- \
  xcodebuild -project 'Apps/APN-UIKit/APN UIKit.xcodeproj' -scheme 'APN UIKit' \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' build
```

The command inherits the harness-injected `CIO_LIFECYCLE_*` environment and receives
`CIO_LIFECYCLE_FIXTURE_REPO_ROOT` for an explicit build path. Missing or invalid trace identity and
provenance disables trace emission and produces a fixed diagnostic. Existing terminal app and
provider seats call `LifecycleTraceHarness.endScenario(after:)`; after the final trace record drains,
the file sink atomically writes the manifest-ready receipt to
`${CIO_LIFECYCLE_OUTPUT_PATH}.receipt.json`. The trace output path itself remains prefixed NDJSON
only.

Foreground notification and notification-settings L2 remain blocked. The pristine APN and CocoaPods-FCM hosts do not own an
active `UNUserNotificationCenterDelegate.willPresent` presentation completion seat. The patch can
observe the real Customer.io ingress, but it does not wrap a production completion or invent a host
presentation result. Quick-action and background-fetch callbacks are likewise absent and are not
added by this fixture.

Notification-response acceptance is limited to the default action. Dismiss and custom actions do
not emit the Customer.io-open result or the terminal seat. When a wrapped notification delegate
owns an asynchronous completion, the passive patch passes that completion through unchanged and
does not close the native stream because it cannot observe completion without interposition.

The focused test target compiles a fixture-local copy of the recorder types so it can stress the
buffer and serializer without linking SampleAppsCommon into notification extensions. Therefore the
process-wide singleton/probe wiring remains an integration boundary for an actual capture runner.
An invalid early terminal intentionally leaves the observer registered because the
`app-background-foreground` scenario must ignore its initial active seat and wait for the real
background-to-active transition. Supported producer paths do not emit any other speculative
terminal.

The capture CLI rejects those unsupported scenarios before launching a controller. Its accepted
scenario set is limited to the real terminal seats implemented by this producer.

## Capture manifest runner

`run_lifecycle_capture.py` runs one native Swift stream and will only leave a reusable capture when
the canonical validator accepts it. The runner issues the manifest, run, stream, and process-instance
UUIDs; snapshots the Git-visible source worktree described below; records Xcode, Swift, simulator
SDK, and booted simulator provenance; and injects every `CIO_LIFECYCLE_*` key both directly and with
the `SIMCTL_CHILD_` prefix. The output directory must be new and outside the source checkout, so
capture artifacts cannot change the source snapshot.

For a dirty worktree, `tree_hash` is SHA-256 over sorted `sha256  path` entries for tracked and
untracked, non-ignored regular files. `diff_hash` is SHA-256 over `git diff --binary HEAD`, followed
by a domain separator and the SHA-256 digest of the sorted untracked entries. Symlink or undecodable
source paths fail closed.

The APN sample also requires the gitignored `Apps/APN-UIKit/BuildEnvironment.swift`. It is external
secret build configuration, not callback-topology source evidence, and is intentionally outside the
Git-visible `tree_hash` and `diff_hash`. The disposable runner treats it as an opaque build input: it
does not read it as evidence, log it, or hash it, and only copies it into the temporary checkout so
the existing sample can compile. A capture must prove provider/backend behavior separately through
the controller-written `provider_provenance`; neither the source snapshot nor this opaque local
configuration establishes that proof. Therefore the manifest snapshot is not a claim that every
compiled byte was hashed. The manifest carries `ignored_build_inputs_excluded: true` inside this
repository's `source_snapshot` so that qualification travels with the capture artifact.

The required blueprint is deliberately limited to facts the runner cannot discover without guessing.
Its build identity and framework versions are operator assertions, not runtime-derived facts. A
controller must generate them from the exact application build, and the runner rejects any
non-application `product_kind`; until that controller exists, these fields cannot support L2/L3:

```json
{
  "schema": "cio-lifecycle-capture-blueprint/1",
  "build": {
    "configuration": "Debug",
    "scheme": "APN UIKit",
    "target_name": "APN UIKit",
    "product_kind": "application",
    "deployment_target": "15.0"
  },
  "frameworks": [
    {
      "name": "customerio-ios",
      "role": "sdk",
      "version": "4.7.3",
      "commit_sha": null
    },
    {
      "name": "customerio-messaging-push",
      "role": "sdk",
      "version": "4.7.3",
      "commit_sha": null
    },
    {
      "name": "apple-usernotifications",
      "role": "platform-framework",
      "version": null,
      "commit_sha": null
    }
  ],
  "aggregate_assertions": []
}
```

Push, notification, and token-registration captures must compose the two runners so the capture
process executes inside the temporary checkout after the four production source patches are
applied. For example, with a blueprint and output parent outside this repository:

```sh
python3 Apps/APN-UIKit/Fixtures/IOS27Lifecycle/run_disposable_source_patch.py \
  --source-root . -- \
  python3 Apps/APN-UIKit/Fixtures/IOS27Lifecycle/run_lifecycle_capture.py \
  --source-root . \
  --blueprint /path/outside/customerio-ios/apn-blueprint.json \
  --output-dir /path/outside/customerio-ios/token-registration-capture \
  --simulator-id SIMULATOR_ID \
  --scenario token-registration \
  --evidence-level L2 \
  --provider apn -- \
  /path/to/scenario-controller
```

The disposable runner overlays this fixture directory before invoking the nested command and sets
`CIO_LIFECYCLE_FIXTURE_REPO_ROOT` to the temporary checkout. The capture runner requires that marker
to resolve to `--source-root` and requires all four locked production paths to differ from `HEAD` for
patch-dependent scenarios. It then snapshots that dirty temporary checkout after both the producer
overlays and production patch, so its `tree_hash` and `diff_hash` describe the code actually built.
Invoking a patch-dependent capture directly against the outer producer worktree fails closed.

The runner replaces Customer.io framework commits and the Apple framework version with the observed
repository commit and simulator SDK version. The launched scenario controller receives
`CIO_LIFECYCLE_CONTROL_PATH` and must atomically write one
regular JSON file when it has actually initiated the stimulus and observed the provider result. Times
or provenance are never inferred from callbacks after the run:

```json
{
  "schema": "cio-lifecycle-capture-control/1",
  "stimulus": {
    "scenario": "token-registration",
    "source": "system-registration",
    "initiated_at": "2026-08-11T16:00:02Z"
  },
  "provider_provenance": {
    "provider": "apn",
    "source": "system-registration",
    "environment": "simulator",
    "receipt_result": "registered",
    "receipt_recorded_at": "2026-08-11T16:00:03Z",
    "provider_sdk": null
  }
}
```

The runner's `CIO_LIFECYCLE_OUTPUT_PATH` is a host path, and a simulator application cannot be
assumed to write there from its sandbox. A scenario controller that installs or launches the app must
retain that host path, resolve a writable path inside the installed app's data container, and override
`SIMCTL_CHILD_CIO_LIFECYCLE_OUTPUT_PATH` with the container path for the actual `simctl launch`. It
must wait for the app to atomically publish `<container-path>.receipt.json`, then copy both the trace
and receipt bytes back to the original host trace and receipt paths before it exits. The receipt must
not be synthesized by the controller. The generic runner intentionally cannot perform this mapping
because it does not own the bundle identifier, installation, launch, or termination policy.

No scenario controller implementing that container handoff is included in this fixture. Therefore
the generic runner and locally compiled producer establish only the capture contract and fail-closed
validation path; they are not, by themselves, an executable L2 runtime proof.

After the command exits successfully, the runner requires the recorder's post-drain receipt, rejects
drops, overflow, identity drift, mixed process IDs, or an L2/L3 control-only stream, assembles the
manifest, and invokes `validate_ios27_lifecycle_trace.py`. Use the contract virtual environment as
`--validator-python` when `jsonschema[format]` is not installed in the system Python.

Scenario-controller stdout and stderr are discarded because they may contain raw URLs, tokens, or
payloads. On failure the runner reports only a fixed message with the numeric exit status. Toolchain
and canonical-validator commands use a separate diagnostic path because their output is required to
establish or reject provenance and they are never given scenario payloads.
