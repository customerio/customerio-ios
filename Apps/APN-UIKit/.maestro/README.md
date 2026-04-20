# Maestro E2E — iOS (APN-UIKit)

End-to-end smoke test that drives the `APN-UIKit` sample app through login + a
custom event, and asserts against the Customer.io Ext API that the backend
actually received the identify and dispatched the expected in-app + push.

## Current coverage

Each run generates a fresh email `maestro+ios-<uuid>@cio.test` so runs are
isolated on the backend.

Steps (all currently passing — 32/32 commands COMPLETED):

1. Launch app, log in with the unique email.
2. Dashboard appears with action buttons (`Random Event Button`, `Custom Event Button`, `Log Out Button`).
3. **Back-end assertion #1** — poll Ext API for a delivered `in_app` for this email with `metrics.sent` populated. Proves the full chain SDK identify → CDP → services → campaign fire → in-app dispatched actually happened.
4. **Back-end assertion #2** — poll for a `push` with `metrics.drafted`. The simulator has no valid APNs token so delivery can't finalize, but `drafted` confirms the backend tried to send — which is the same signal you'd want on a real device that failed to register. (On a real device, this would assert `sent`/`delivered` instead.)
5. Tap Custom Event, fill in `event=maestro_test_event, run_id=<uuid>`, tap Send Event.
6. Swipe back to dashboard.

## Prereqs

1. `maestro` CLI (tested with 2.0.9).
2. Xcode + an iOS simulator (we used iPhone 17 iOS 26.4).
3. Ext API bearer token for a test-prod Customer.io workspace.
4. The sample's `cdpApiKey` in `BuildEnvironment.swift` must map to the **same** workspace the Ext API key queries. In this repo that's `45468ceeed7b7057c583`.

## Setup

```bash
# 1) Create local env file (gitignored) with your Ext API key:
cp .maestro/.env.example .maestro/.env
# then edit .maestro/.env and paste your key

# 2) Build + install the sample on a booted simulator:
#    (first time only; re-run when BuildEnvironment.swift changes)
cd Apps/APN-UIKit
xcodebuild -project "APN UIKit.xcodeproj" -scheme "APN UIKit" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -configuration Debug -derivedDataPath /tmp/apn-uikit-build build
xcrun simctl install booted "/tmp/apn-uikit-build/Build/Products/Debug-iphonesimulator/APN UIKit.app"
```

## Run

From the iOS repo root:

```bash
export $(grep -v '^#' Apps/APN-UIKit/.maestro/.env | xargs)
maestro -p ios --udid <SIM_UDID> test Apps/APN-UIKit/.maestro/smoke_login_event_logout.yaml
```

Find SIM_UDID via `xcrun simctl list devices booted`.

## Files

| File | Purpose |
|---|---|
| `config.yaml` | Maestro config (appId, tags) |
| `smoke_login_event_logout.yaml` | The flow |
| `scripts/setup_run.js` | Generates `output.run_id` + `output.email` |
| `scripts/assert_message_delivered.js` | Polls Ext API; matches by (email, type, min_metric) |
| `.env.example` | Template for local env (committed) |
| `.env` | Actual key (gitignored) |

## Known limitations

- **Real APNs delivery** to the simulator isn't wired up yet — we assert `drafted` on push, not `sent`/`delivered`. On a real device, change `MIN_METRIC` on the push assertion to `"sent"` or `"delivered"`.
- `Log Out Button` exists in code but isn't rendered on the current sample's dashboard storyboard, so the flow doesn't log out at the end.
- No cleanup of created customers between runs. The workspace is test-prod so this is fine for now.

## Next steps

1. Fix the sample's dashboard so `Log Out Button` is visible → add a logout+re-login assertion.
2. Wire up `xcrun simctl push` delivery from the flow so we can assert real iOS push arrival.
3. Extend the helper to assert specific campaign_id so tests are deterministic against a named campaign (instead of "any in_app").
