# Maestro E2E — iOS (APN-UIKit)

End-to-end Maestro flows that drive the `APN-UIKit` sample app through
identify + event tracking and assert against the Customer.io Ext API that
the backend received the events and dispatched the expected in-app + push.

The main cross-platform flow (Campaign 141) lives in the shared harness at
[customerio/mobile-e2e](https://github.com/customerio/mobile-e2e). It's
pulled into `.maestro/harness/` automatically on the first `./run.sh`. This
directory holds only the platform-specific wrapper: `run.sh`, workspace
config, and smoke/inline flows that exercise iOS-specific surfaces.

## Prereqs

1. `maestro` CLI (tested with 2.0.9).
2. Xcode + a booted iOS Simulator (tested on iPhone 17, iOS 26.4).
3. `ffmpeg`, Python 3 with Pillow (`pip3 install pillow`).
4. An Ext API bearer token for the test-prod Customer.io workspace.
5. `cdpApiKey` and `siteId` set in
   [`Apps/APN-UIKit/BuildEnvironment.swift`](../BuildEnvironment.swift)
   matching the workspace the Ext API key queries (currently
   `cdpApiKey = "45468ceeed7b7057c583"`, `siteId = "38eda114ab3f4593e11f"`).

## Setup

```bash
cp .maestro/.env.example .maestro/.env
# paste MAESTRO_EXT_API_KEY into .maestro/.env

# Build + install onto the booted simulator (re-run when BuildEnvironment.swift changes):
xcodebuild \
  -project "APN UIKit.xcodeproj" \
  -scheme "APN UIKit" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -configuration Debug -derivedDataPath /tmp/apn-uikit-build build
xcrun simctl install booted "/tmp/apn-uikit-build/Build/Products/Debug-iphonesimulator/APN UIKit.app"
```

## Run

```bash
./.maestro/run.sh                             # default: campaign_141 (shared)
./.maestro/run.sh smoke_login_event.yaml      # also shared (in harness)
./.maestro/run.sh inline_messages.yaml        # also shared (in harness)
```

All three flows live in [customerio/mobile-e2e/flows/](https://github.com/customerio/mobile-e2e/tree/main/flows) — the `run.sh` wrapper resolves them from `.maestro/harness/flows/` automatically.

`run.sh` auto-detects the booted simulator, clones/pulls the shared harness
into `.maestro/harness/`, starts the sink + screenshot capture loop, runs
Maestro, and renders the outputs.

Outputs land in `artifacts/<flow>/` (gitignored):

| File | What it is |
|---|---|
| `device.mp4` | Simulator recording assembled from 5 fps screenshot poll |
| `annotated.mp4` | Side-by-side device + live step panel + backend response card |
| `tickmarks.html` | Per-step pass/fail with Ext API responses inline |
| `sink.jsonl` | Raw JSON events posted by the flow's assertion scripts |
| `debug/` | Maestro's native debug output |

## Files here

| File | Purpose |
|---|---|
| `run.sh` | Starts sink + simulator capture, runs Maestro, renders HTML + annotated video |
| `.env.example` | Template — copy to `.env` and fill in `MAESTRO_EXT_API_KEY` |
| `.env` | Your `MAESTRO_EXT_API_KEY` (gitignored) |
| `harness/` | Shared scripts + flows auto-cloned from [`customerio/mobile-e2e`](https://github.com/customerio/mobile-e2e) (gitignored) |

## Selector strategy

The sample exposes the same accessibility ID on every widget the shared
flow drives, matching the Android java_layout sample — one snake_case
vocabulary:

| id | widget |
|---|---|
| `login_button` | Login button |
| `first_name_input` | First-name text field |
| `email_input` | Email text field |
| `custom_event_button` | Dashboard "Custom Event" |
| `event_name_input` | Custom-event name field |
| `property_name_input` | Custom-event property name |
| `property_value_input` | Custom-event property value |
| `send_event_button` | Fire-event button |

Set via `setAccessibilityId(..., to: "login_button")` in the view
controllers (see `LoginViewController.swift`, `DashboardViewController.swift`,
`View/Customisation/CustomDataViewController.swift`).

## Known limitations

- Real APNs delivery to the simulator isn't wired up yet, so Campaign 141's
  push-shade + push-tap assertions fire only when the workspace has a
  working APNs cert for this bundle id. The shared flow wraps them in
  `runFlow: when: visible: Maestro Push` so they skip cleanly when push
  doesn't materialize.
- `simctl io recordVideo` collides with Maestro's live simulator session,
  so `run.sh` falls back to a 5 fps `simctl screenshot` poll assembled
  with `ffmpeg` (see `harness/scripts/capture_frames.sh`).
- No cleanup of created customers; test-prod workspace is fine for now.
