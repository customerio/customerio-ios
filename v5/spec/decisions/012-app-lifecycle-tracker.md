# ADR 012 — Application Lifecycle Event Tracking

**Status:** Accepted

---

## Context

The legacy Customer.io iOS SDK automatically emits four well-known events in
response to app state transitions:

| Event | Trigger |
|---|---|
| `"Application Installed"` | First launch — no prior version stored |
| `"Application Updated"` | Launch with a `CFBundleShortVersionString` that differs from the stored version |
| `"Application Opened"` | `UIApplication.didBecomeActiveNotification` |
| `"Application Backgrounded"` | `UIApplication.didEnterBackgroundNotification` |

These events are a common baseline for mobile lifecycle analytics and are
expected by Customer.io workspace rules, campaigns, and reports. The
reimplemented SDK lacked them entirely (TODO item 14).

---

## Decision

Introduce `AppLifecycleTracker` — an `actor` in
`Sources/CustomerIO/Lifecycle/` — and wire it into `CustomerIO.configure()`
behind the `config.trackApplicationLifecycleEvents` flag (default `true`).

### Type and isolation

`AppLifecycleTracker` is an `actor` because it holds mutable state
(`_didCheckInstallOrUpdate: Bool`) that protects against double-firing. Actor
isolation makes this guarantee without requiring an external `Synchronized<T>`.

The `enqueueEvent: @Sendable (PendingEvent) -> Void` dependency is declared
`nonisolated let` so that `startObservingLifecycle()` — which registers
`NotificationCenter` observers outside actor isolation — can capture it
directly without a `Task { await ... }` hop.

### Event routing

All four events are emitted via `.trackSynthesized(name, properties)` rather
than `.track(...)`. This causes them to bypass `AggregationEngine` evaluation
(preventing re-interception cycles) while still flowing through enrichment and
upload — the same pattern used for aggregation flush events.

### Install / update detection

`checkInstallOrUpdate()` reads `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
and compares it against the value stored in `sdk_meta` under the key
`CIOKeys.Lifecycle.lastKnownAppVersionKey`. It writes the current version back
to storage unconditionally after the comparison, so the correct baseline is in
place for the next launch regardless of outcome.

The method is guarded by `_didCheckInstallOrUpdate` to ensure it fires at most
once per process lifetime, even if `configure()` were somehow called more than
once.

### String constants

Event names and property keys are collected in
`Sources/CustomerIO/Keys/CIOKeys+Lifecycle.swift` as an `internal` extension
on `CIOKeys.Lifecycle`, following the project's `CIOKeys` namespace convention.
They do not live in `CustomerIO_Utilities` because they are not shared across
modules.

### Configuration surface

`trackApplicationLifecycleEvents: Bool` (default `true`) is added to
`SdkConfig` and `SdkConfigBuilder` using the same copy-on-write pattern as all
other boolean flags. Setting it to `false` skips `AppLifecycleTracker`
construction entirely; no observers are registered and no storage reads occur.

---

## Consequences

- Apps that rely on Customer.io campaign triggers keyed on these events will
  receive them automatically without any code changes.
- Apps that previously tracked these events manually should set
  `trackApplicationLifecycleEvents(false)` to avoid double-counting.
- The `"Application Opened"` event fires on every foreground activation,
  including the initial launch. If the app is already in the foreground when
  `configure()` is called (e.g., in a unit test host), the observer will not
  fire for the current session's "open" — this is acceptable for an SDK that
  is designed to be configured at `didFinishLaunchingWithOptions`.
