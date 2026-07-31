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

1. `maestro` CLI.
2. Full Xcode with an iOS runtime. The runner boots the Simulator.
3. `ffmpeg` and Python 3. Pillow is optional but enables annotated MP4s.
4. An Ext API bearer token for the test-prod Customer.io workspace.
5. `cdpApiKey` and `siteId` set in
   [`Apps/APN-UIKit/BuildEnvironment.swift`](../BuildEnvironment.swift)
   matching the workspace the Ext API key queries.

## Setup

```bash
cp .maestro/.env.example .maestro/.env
# Fill MAESTRO_EXT_API_KEY; message Inbox uses fixture ID 21.
make e2e-setup
```

## Run

```bash
make e2e          # smoke + geofence + Inbox + local Live Activities; one build
make e2e-quick    # smoke only
make e2e-inbox    # message Inbox only
make e2e-remote   # explicit backend/APNs Live Activities lane
```

`make e2e` clones/updates the shared harness, provisions the Simulator, builds
and installs the sample, runs the deterministic iOS profile, and prints one
combined summary. Nothing needs to be started manually.

`./.maestro/run.sh <flow.yaml>` remains available when an app is already
installed and a single low-level flow is being debugged.

Outputs land in `artifacts/e2e/ios/<flow>/` (gitignored):

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
| `e2e.sh` | One-command setup/profile wrapper around the shared top-level runner |
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

- Remote Live Activities require a supported host, APNs sandbox credentials,
  the Live Notifications workspace entitlement/actions, and the explicit
  `remote` profile. They are not part of the default local or PR gate.
- `simctl io recordVideo` collides with Maestro's live simulator session,
  so `run.sh` falls back to a 5 fps `simctl screenshot` poll assembled
  with `ffmpeg` (see `harness/scripts/capture_frames.sh`).
- No cleanup of created customers; test-prod workspace is fine for now.
