# Validation matrix — what Maestro can verify for this SDK

A reference for what's validatable end-to-end, how to implement each check, and
what workspace configuration each check depends on. Mirror copy lives in the
iOS sample repo; both repos share identical patterns.

## Maestro primitives we rely on

| Primitive | What it gives us | Used for |
|---|---|---|
| `assertVisible: "<text>"` | regex match against the native accessibility tree | Native text/button presence |
| `assertVisible: { id: "<id>" }` | matches by accessibilityIdentifier / content-desc / resource-id | Stable targeting when the sample sets IDs |
| `assertNotVisible` | inverse | Dismissed modals, hidden inline slots |
| `extendedWaitUntil: visible:` | polls up to `timeout:` ms for a condition | Async UI renders (in-apps arriving from backend) |
| `takeScreenshot: <path>` | PNG dropped into the test run artifacts | Visual evidence a human can review |
| `runScript: scripts/x.js` with `env:` | Graal JS with `http.get/post` + `output.*` | Poll the Customer.io Ext API for backend state |
| `tapOn`, `inputText`, `swipe`, `back`, `hideKeyboard` | UI driving | Navigation + interaction |

**Not available (important to know):**
- No `setTimeout` / `Thread.sleep` / `await` in the script runtime — wait has to come from YAML (`extendedWaitUntil`, `retry`) or from HTTP round-trip latency.
- No way to speak MySQL or gRPC directly — only HTTP. We query the Customer.io Ext API (`https://api.customer.io/v1/...`).
- WebView-rendered content is sometimes invisible to the accessibility tree. In this sample, the in-app modal uses native text views, so it's fine. Rich HTML in-apps may not be.

## Regex gotcha (learned the hard way)

`assertVisible: "Some text"` is a regex against the full text node. It's **not**
a substring search. If the tree contains `"Thank you for choosing our product. Have a look around..."`
then `assertVisible: "Thank you for choosing"` **fails** — the regex has to
match the full text. Use `".*Thank you for choosing.*"` instead.

## The matrix

### ✅ Currently covered (passing flows on iOS + Android)

| Case | How |
|---|---|
| SDK identify reached the server | `runScript: assert_message_delivered.js` polls `/v1/customers?email=<unique>` → resolves cio_id |
| Identify triggered the expected segment campaign | same script then polls `/v1/customers/:cio_id/messages`, matches `type=in_app` with `metrics.sent` populated |
| In-app modal actually rendered on screen | `extendedWaitUntil: visible: "Continue"` + `assertVisible: ".*Thank you for choosing.*"` + `takeScreenshot` |
| Modal dismissed correctly | `tapOn: "Continue"` + `assertNotVisible` |
| Server drafted a push for this customer | `runScript` polling, match `type=push` with `metrics.drafted` |
| Custom event form works | tap the sequence, send event with `run_id` property |

### 🛠 Coverable with small additions (patterns exist, need either seeded campaigns or small sample-app work)

| Case | How (pattern) | What's needed |
|---|---|---|
| **Inline in-app renders in the correct slot** | Fire a trigger event for a campaign configured to show inline on elementId `X` → navigate to Inline Examples screen → `assertVisible` on the inline body text within the slot | A seeded event-triggered campaign in the workspace whose in-app targets an elementId the sample has (`sticky-header`, `inline`, `below-fold`, or the Compose/Tabs variants) |
| **Page rule: in-app shows only on screen Y** | Navigate to screen Y → `assertVisible` on in-app body. Navigate to screen Z → `assertNotVisible`. | A campaign with a page-rule filter keyed to a screen name the sample actually emits via `CustomerIO.screen("Y")` |
| **Frequency capping: same in-app doesn't show twice** | Trigger once, dismiss, assert visible. Trigger again, `extendedWaitUntil timeout` short, `assertNotVisible`. | A campaign with frequency cap configured |
| **Action button on in-app fires tracking event + deep-link** | `tapOn` the action button inside the rendered in-app → `assertVisible` destination screen → `runScript` poll `/v1/messages/:id` for `metrics.clicked` or `metrics.action_taken` | Known campaign with a known action button label |
| **Push received tracked (real device)** | After campaign fires, `openNotifications` on Android or `assertVisible` notification on iOS lock screen → `runScript` poll for `metrics.delivered` | Real device registered a valid FCM/APNs token. Emulators can't do this for real. |
| **Push tap → deep link** | After `openNotifications` + `tapOn`, assert the expected in-app screen is shown | Real device + a campaign with a push containing a deep link |
| **Profile attribute update visible on server** | tap `Set Profile Attribute` → fill name/value → `runScript` poll `/v1/customers/:cio_id/attributes` | Nothing extra — sample and Ext API both support this today |
| **Device token registered for customer** | after login, `runScript` on `/v1/customers/:cio_id` looking for `devices[]` entry | Real device OR an emulator with Google Play Services + FCM |
| **Logout clears identity** | `tapOn: "Logout"` → `assertVisible: "Login"` → `runScript` confirm no new events for the cio_id | Sample must render the Logout button (Android does; iOS's current dashboard hides it) |
| **Re-identify same email stitches history** | Log in with pre-existing email → `runScript` assert same cio_id returned from lookup → no duplicate customer | Nothing extra |

### ⚠️ Needs investment (real-device bench or sample-app work)

| Case | What's needed |
|---|---|
| Real push delivery on iOS simulator | `xcrun simctl push` wiring from inside a flow, or move to a real device lab |
| Flutter full flow | Add `Semantics(identifier: ...)` wrappers to ~15 widgets in the Flutter sample |
| WebView-based in-app content assertion | Maestro can read WebView text on Android if JS-accessible. On iOS, usually not. Fall back to screenshots. |
| Rich push payloads (images, action buttons) on iOS | Real device + `xcrun simctl push` with rich JSON |

## How to add a new visual in-app assertion

Template:

```yaml
# 1) Put the user in a known identified state
- runScript: { file: scripts/setup_run.js }
- launchApp: { clearState: true }
- tapOn: { id: "Email Input" }
- inputText: ${output.email}
- tapOn: "Login"

# 2) Wait for backend to dispatch + SDK to render the in-app you care about
- extendedWaitUntil:
    visible: "<unique body copy from the campaign's in-app>"
    timeout: 25000

# 3) Visual evidence + richer asserts
- takeScreenshot: artifacts/<scenario-name>
- assertVisible: ".*<other body substring>.*"
- assertVisible: "<cta button text>"

# 4) Optionally also assert server-side state
- runScript:
    file: scripts/assert_message_delivered.js
    env:
      MAESTRO_EXT_API_KEY: ${MAESTRO_EXT_API_KEY}
      RUN_EMAIL: ${output.email}
      EXPECTED_TYPE: "in_app"
      MIN_METRIC: "human_opened"  # proves the render happened, not just dispatch
      MAX_WAIT_MS: "15000"
- assertTrue: ${output.assert_ok === "true"}

# 5) Interact with the in-app (dismiss or action)
- tapOn: "<cta or dismiss>"
- assertNotVisible: "<body copy>"
```

## How to add a page-rule test

```yaml
# Fire the trigger
- tapOn: "Send Custom Event"
- tapOn: { id: "Event Name Input" }
- inputText: "<campaign_trigger_event>"
- tapOn: "Send Event"

# Navigate to screen A — in-app SHOULD render here
- back                             # back to dashboard
- tapOn: "<screen A entry point>"
- extendedWaitUntil:
    visible: "<in-app body>"
    timeout: 15000
- takeScreenshot: artifacts/pagerule_screenA_shows

# Navigate to screen B — same in-app should NOT render
- back
- tapOn: "<screen B entry point>"
- waitForAnimationToEnd: { timeout: 3000 }
- assertNotVisible: "<in-app body>"
- takeScreenshot: artifacts/pagerule_screenB_hidden
```

## Workspace prerequisites (what to seed for best coverage)

If we later land dedicated test campaigns in the test-prod workspace:

- `maestro_modal_triggered` — event-triggered by event `maestro_modal` → shows a modal in-app with body `"MAESTRO MODAL OK"` (or any deterministic string).
- `maestro_inline_dashboard` — event-triggered by `maestro_inline`, page rule: only Dashboard screen, inline targeting `elementId = "inline"`, body `"MAESTRO INLINE DASHBOARD"`.
- `maestro_inline_inbox_only` — same but page rule = Inbox screen, body `"MAESTRO INLINE INBOX"`.
- `maestro_push_generic` — event-triggered by `maestro_push`, push with title+body that includes `{{event.properties.run_id}}` so each test run has a uniquely traceable push.

With these four seeded, every row in the "Coverable with small additions" section above becomes a working flow.

## Artifacts each run produces

Every `maestro test` run drops in `~/.maestro/tests/<timestamp>/`:
- `commands-*.json` — full command-by-command status
- `maestro.log` — engine log
- `screenshot-❌-*.png` — on failure, the screen at the moment of fail
- `artifacts/<name>.png` — anything we explicitly capture via `takeScreenshot`

Those screenshots are what we commit as the visual proof record. Running with
`--format=JUNIT` also produces a JUnit XML that slots into any CI system.
