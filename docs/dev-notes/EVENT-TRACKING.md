# Event Tracking and Screen View Lifecycle

## Overview

All events (track, screen, identify) flow through the `CioAnalytics` engine (the `cdp-analytics-swift` dependency), which is a fork of Segment's analytics-swift library. The SDK wraps this engine with Customer.io-specific plugins and configuration.

---

## Plugin Pipeline

Events pass through an ordered plugin chain before being stored and uploaded. Plugin types, in execution order:

| Phase | `PluginType` | Plugins registered by this SDK |
|---|---|---|
| 1. Before | `.before` | `Context` (CIO — overwrites device token, visionOS fix, sets user-agent, strips `library` key), `DataPipelinePublishedEvents` (fires EventBus events), Segment's built-in `iOSLifecycleEvents` |
| 2. Enrichment | `.enrichment` | `IdentifyContextPlugin` (merges `ProfileEnrichmentProvider` attributes into identify context), `ScreenFilterPlugin` (drops screen events when `screenViewUse == .inApp`), `DeviceContexualAttributes` (copies network/screen/ip/timezone fields into device track event properties) |
| 3. Destination | `.destination` | `CustomerIODestination` (extends `SegmentDestination`) — writes events to disk and uploads |
| 4. Utility | `.utility` | `AutoTrackingScreenViews` (UIViewController swizzle for automatic screen tracking) |

---

## Track Events

### Manual tracking

```swift
// [String: Any] properties
CustomerIO.shared.track(name: "Order Placed", properties: ["sku": "ABC-123", "revenue": 9.99])

// Codable properties
CustomerIO.shared.track(name: "Order Placed", properties: myStruct)
```

Flows: `DataPipeline.track()` → `DataPipelineImplementation.track()` → `analytics.track()` → `TrackEvent` created → plugin pipeline → stored to disk.

### Automatic lifecycle events (when `trackApplicationLifecycleEvents: true`)

Emitted by `iOSLifecycleEvents` (Segment platform plugin):

| Event name | Trigger | Properties |
|---|---|---|
| `Application Installed` | First launch (no previous build in `UserDefaults`) | `version`, `build` |
| `Application Updated` | Launch with different `CFBundleVersion` than stored | `previous_version`, `previous_build`, `version`, `build` |
| `Application Opened` | `didFinishLaunching` | `from_background: false`, `version`, `build`, `referring_application`, `url` |
| `Application Opened` | `applicationWillEnterForeground` | `from_background: true`, `version`, `build` |
| `Application Backgrounded` | `applicationDidEnterBackground` | _(none)_ |
| `Application Foregrounded` | `applicationDidBecomeActive` | _(none)_ |

### Internal SDK track events

| Event name | Trigger | Properties |
|---|---|---|
| `Device Created or Updated` | `registerDeviceToken()` | device attributes (OS, push tokens, etc.) |
| `Device Deleted` | `clearIdentify()` or profile switch with existing token | _(none)_ |
| `Report Delivery Event` | Push or in-app metric received | `metric`, `deliveryId`, `recipient` (push only), plus any in-app `metaData` |

---

## Screen Events

### Manual tracking

```swift
CustomerIO.shared.screen(title: "Home", properties: ["referrer": "push"])
```

Flows: `DataPipeline.screen()` → `DataPipelineImplementation.screen()` → `analytics.screen()` → `ScreenEvent` created → plugin pipeline.

`ScreenFilterPlugin` drops the event if `screenViewUse == .inApp` (i.e. the SDK is configured to send screen events only to the in-app module, not to the server).

`DataPipelinePublishedEvents` intercepts the `ScreenEvent` and fires `ScreenViewedEvent` on the `EventBus` for the MessagingInApp module to consume.

### Automatic screen tracking (`AutoTrackingScreenViews` plugin)

When the plugin is added (`DataPipeline.shared.add(plugin: AutoTrackingScreenViews())`):

1. `UIViewController.viewDidAppear` and `viewDidDisappear` are swizzled.
2. On each call, the plugin walks the view controller hierarchy to find the currently visible `UIViewController`.
3. The view controller's class name (with "ViewController" stripped) is used as the screen title.
4. Events are deduplicated — a screen is only tracked if its name differs from the last tracked name.
5. Default filter: events from `com.apple.*` bundles are dropped. Customer app can supply a custom `filterAutoScreenViewEvents` closure.
6. Custom properties can be injected via `autoScreenViewBody`.

---

## Storage

Events are written to disk by `DirectoryStore` in JSON–Lines format, one event per line, up to a max file size of **475 KB** (server limit: 500 KB).

File format (assembled into a batch at flush time):

```json
{ "batch": [
  { ...event1... },
  { ...event2... }
],
  "sentAt": "2026-03-11T12:00:00Z",
  "writeKey": "<cdp_api_key>"
}
```

Storage location: `<app_documents>/analytics/<writeKey>/` (via `CioAnalytics.eventStorageDirectory(writeKey:)`).

Each in-progress file is named `<index>-segment-events`. When full or at flush time, it is renamed with a `.temp` extension to mark it as ready for upload.

---

## Flush Policies

Two flush policies are active by default (configurable via `SDKConfigBuilder.flushPolicies()`):

| Policy | Trigger | Default |
|---|---|---|
| `CountBasedFlushPolicy` | Fires when accumulated event count ≥ `flushAt` | `flushAt = 20` |
| `IntervalBasedFlushPolicy` | Fires on a timer, suspends in background | `flushInterval = 30s` |

Additional flush triggers:
- App enters background (`SegmentDestination.enterBackground()`)
- Manual call: `CustomerIO.shared.flush()` / `DataPipeline.shared.analytics.flush()`

---

## Upload (HTTP)

### Endpoint

```
POST https://<apiHost>/b
```

Where `<apiHost>` defaults to:

| Region | `apiHost` |
|---|---|
| US | `cdp.customer.io/v1` |
| EU | `cdp-eu.customer.io/v1` |

Full upload URL example (US): `https://cdp.customer.io/v1/b`

### Request headers

| Header | Value |
|---|---|
| `Content-Type` | `application/json; charset=utf-8` |
| `User-Agent` | `analytics-ios/<version>` (overridden per-request by CIO's `Context` plugin with a CIO-specific user-agent string) |
| `Accept-Encoding` | `gzip` |
| `Authorization` | `Basic <base64("<cdpApiKey>:")>` |

### Batch JSON schema

Every upload is a single JSON object:

```json
{
  "writeKey": "<cdp_api_key>",
  "sentAt": "<ISO 8601 timestamp>",
  "batch": [
    <RawEvent>,
    ...
  ]
}
```

#### Common fields on every `RawEvent`

```json
{
  "type":        "track" | "identify" | "screen" | "group" | "alias",
  "messageId":   "<uuid>",
  "anonymousId": "<uuid>",
  "userId":      "<string | null>",
  "timestamp":   "<ISO 8601>",
  "context": {
    "app": {
      "name":      "<string>",
      "version":   "<string>",
      "build":     "<string>",
      "namespace": "<bundle_id>"
    },
    "device": {
      "manufacturer": "<string>",
      "type":         "ios",
      "model":        "<string>",
      "name":         "<string>",
      "id":           "<identifierForVendor>",
      "token":        "<apns_or_fcm_token | omitted>"
    },
    "os": {
      "name":    "<string>",
      "version": "<string>"
    },
    "screen": {
      "width":  <number>,
      "height": <number>
    },
    "network": {
      "bluetooth": <bool>,
      "cellular":  <bool>,
      "wifi":      <bool>
    },
    "locale":    "<BCP 47 language tag>",
    "timezone":  "<IANA timezone>",
    "userAgent": "<CIO SDK user-agent string>",
    "instanceId": "<uuid per analytics instance>"
  },
  "integrations": {}
}
```

> Note: the `library` key that Segment adds is stripped by the CIO `Context` plugin. SDK identity is sent via the `userAgent` header and field instead.

#### `TrackEvent`-specific fields

```json
{
  "type":       "track",
  "event":      "<event name>",
  "properties": { ... }
}
```

#### `ScreenEvent`-specific fields

```json
{
  "type":       "screen",
  "name":       "<screen title>",
  "category":   "<string | null>",
  "properties": { ... }
}
```

#### `IdentifyEvent`-specific fields

```json
{
  "type":   "identify",
  "traits": { ... }
}
```

---

## Retry and Error Handling

- **HTTP 1xx–2xx**: success; the batch file is deleted from disk.
- **HTTP 400** (malformed JSON): batch is deleted without retry (no point retrying bad data).
- **HTTP 429** (rate limited): task fails; file remains on disk and will be retried at the next flush.
- **Other 4xx / 5xx**: task fails; file remains on disk and will be retried.
- **Network error**: task fails; file remains on disk and will be retried.

---

## Screen View → In-App Routing

`ScreenViewedEvent` is published to the `EventBus` by `DataPipelinePublishedEvents` for every screen call that reaches the plugin (i.e. not filtered by `ScreenFilterPlugin`). `MessagingInAppImplementation` subscribes to this event and calls `gist.setCurrentRoute(name)` to route in-app messages to the correct screen.
