# Feature Spec — Location Module

---

## Overview

`CustomerIO_Location` tracks device coordinates and contributes them to the
user's profile via the `ProfileEnhancing` protocol. The module never requests
location permissions itself — that is entirely the app's responsibility.

Module accessed at runtime via `cio.location`.

---

## Configuration

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .location {
        LocationConfigBuilder(.continuous)  // LocationMode is a required argument
            .visitedTilesCap(500)
    }
    .build()
```

`LocationMode` is required at builder init time — a zero-arg builder would
produce a config indistinguishable from "module not registered."

---

## Location Modes

`LocationConfig.mode` governs how the SDK obtains device coordinates.

| Mode | Behaviour |
|------|-----------|
| `.off` | Module is inert. No `CLLocationManager` activity, no DB writes. |
| `.manual` | SDK never requests location on its own. App calls `cio.location.setLastKnownLocation(…)` or `cio.location.requestLocationUpdate()` explicitly. |
| `.singleCapture` | One fix per continuous foreground session. Triggered on the first `UIApplication.didBecomeActive` after app start or return from background. Ignored on subsequent `didBecomeActive` in the same session. Session resets on background. |
| `.continuous` | Ongoing monitoring via `CLLocationManager.startMonitoringSignificantLocationChanges()` — low-power, suitable for background use. |

The module never calls `requestWhenInUseAuthorization()` or
`requestAlwaysAuthorization()`. If the OS has not already granted location
permission, requests are silently cancelled.

---

## Storage Schema

`LocationStorageMigration` (migration id `002-location-schema`) adds one table:

```sql
-- Single-row key/value store for the most recent precise fix.
-- Keys: last_lat, last_lon, last_accuracy, last_timestamp, last_uploaded_at
CREATE TABLE location_state (
    key   TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
)
```

`location_state` is cleared on `ResetEvent` (user logout / `clearIdentify()`).

---

## ProfileEnhancing — Location Attributes

`LocationModule` conforms to `ProfileEnhancing`. During every `identify(_:traits:)`
call, `EventEnricher` calls the module and merges its result into the outgoing
traits payload:

```swift
[
    "latitude":  .float(lat),
    "longitude": .float(lon),
    "accuracy":  .float(acc),  // horizontal accuracy in metres
    "timestamp": .string(iso8601),
]
```

If no coordinates are stored (mode is `.off`, or `clearIdentify()` was called),
the module returns an empty dictionary and identify proceeds without location traits.

Every time `currentLocationAttributes()` returns non-empty data, it also stamps
`last_uploaded_at` in `location_state`, resetting the weekly fallback timer.

---

## Weekly Fallback Upload

Location-only apps may go weeks without an `identify` call, so coordinates
would never reach the backend via `ProfileEnhancing` alone.

After every location update is recorded, `LocationCoordinator` checks whether
the configured upload interval has elapsed since `last_uploaded_at`. If it has
(default: 7 days), the coordinator synthesises a `track("location_update", …)`
event with the same lat/lon/accuracy/timestamp payload and enqueues it via
`root.enqueueEvent(.track("location_update", props))`.

Fallback upload does **not** bypass the aggregation engine — the synthesised
event flows through the full pipeline and may be aggregated, counted, or
discarded per the active ruleset.

### Remote Interval Override

The upload interval is configurable from the backend. If `location_state`
contains a value under the key `upload_interval_seconds`, it overrides the
7-day default. The intended delivery mechanism is `RemoteConfigUpdatedEvent`
on the internal event bus (not yet implemented in the aggregation engine).

---

## Public API on `LocationModule`

| Method | Description |
|--------|-------------|
| `setLastKnownLocation(latitude:longitude:accuracy:)` | Manual coordinate update (`.manual` mode) |
| `requestLocationUpdate()` | Trigger a one-shot CLLocation fix (`.manual` mode) |

---

## Outstanding Work

See `TODO.md` for remaining implementation tasks related to location.
