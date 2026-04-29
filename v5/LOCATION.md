# Location — Design Specification

**Status:** Implemented (v1)
**Last updated:** March 17, 2026

---

## Overview

The Location module collects device coordinates and makes them available to two
consumers: the `ProfileEnhancing` pipeline (which merges coordinates into
outgoing `identify` calls) and the event pipeline (which emits a
`location_update` track event on each new fix for aggregation or direct upload).

The module never requests location permission on its own. Permission prompts are
entirely the app's responsibility. If the OS has not granted permission, location
requests are silently no-ops.

The Location module has no dependency on the Geofencing module and vice versa.
When both are registered, CoreLocation deduplicates radio work at the OS level.

---

## Goals

- Record device coordinates to encrypted storage on each location update.
- Support four collection modes covering the full range from fully manual to
  continuous background tracking.
- Contribute stored coordinates to every `identify` call via `ProfileEnhancing`.
- Emit a `location_update` track event on each new fix so the aggregation engine
  can control upload frequency server-side.
- Clear stored coordinates on `CIOEvent.ResetEvent` (user logout / clearIdentify).
- Remain iOS-only for live location acquisition; `setLastKnownLocation` is
  available on all platforms for apps that supply coordinates themselves.

---

## Non-Goals (v1)

- **Permission prompting.** The SDK never calls `requestWhenInUseAuthorization()`
  or `requestAlwaysAuthorization()`.
- **Geofence candidate selection.** That responsibility belongs to
  `GeofencingModule` / `GeofenceCoordinator`.
- **QuadKey tile tracking.** No tile history table is maintained by this module.
- **Configurable upload interval from the backend.** The module emits on every
  fix; upload frequency control is the aggregation engine's responsibility.

---

## Configuration

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .location(LocationConfig(mode: .continuous))
    .build()
```

```swift
public struct LocationConfig: Sendable {
    /// How the SDK collects device location. Default: .off
    public var mode: LocationMode
}

public enum LocationMode: Sendable {
    case off            // module is inert; no CLLocationManager activity
    case manual         // app calls setLastKnownLocation() or requestLocationUpdate()
    case singleCapture  // one fix per foreground session (on first didBecomeActive)
    case continuous     // ongoing significant-change monitoring
}
```

`LocationConfig` has no geofencing fields. Geofencing is configured separately
via `SdkConfigBuilder.geofencing(_:)`.

---

## Storage Schema

One table is added via `LocationStorageMigration` (migration id
`002-location-schema`), encrypted by SqlCipherKit alongside the core SDK tables.
Storage methods use the generic `getString`/`setString` API on `StorageManager`
directly — no module-specific extension is needed.

```sql
CREATE TABLE IF NOT EXISTS location_state (
    key   TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);
```

| Key | Value | Set when |
|---|---|---|
| `last_lat` | Decimal string | On each recorded fix |
| `last_lon` | Decimal string | On each recorded fix |
| `last_accuracy` | Decimal string (metres) | On each recorded fix |
| `last_timestamp` | ISO 8601 string | On each recorded fix |
| `last_uploaded_at` | ISO 8601 string | When ProfileEnhancing reads and returns non-empty data |

All keys are cleared on `ResetEvent`.

---

## Lifecycle

### Startup

`LocationModule.configure()` is called by the root `CustomerIO` actor during SDK
initialisation. If `mode` is `.off` the module returns immediately and no
`LocationCoordinator` is created.

For any other mode, a `CoreLocationProvider` and `AppLifecycleObserver` are
created and a `LocationCoordinator` is started. The coordinator subscribes to
`ResetEvent` on the event bus before any location work begins.

| Mode | Coordinator behaviour on start |
|---|---|
| `.manual` | Idle; waits for explicit API calls. |
| `.singleCapture` | Starts observing `UIApplication` lifecycle notifications. |
| `.continuous` | Calls `CLLocationManager.startMonitoringSignificantLocationChanges()`. |

### `.singleCapture` Session Lifecycle

- On `applicationDidBecomeActive`: if no fix has been taken this session,
  request a single location update. Mark the session as used.
- On `applicationDidEnterBackground`: reset the session flag so the next
  foreground activation may take a fix.

This ensures one fix per continuous foreground session (app launch or return
from background), never more.

---

## Coordinate Recording

Every new fix (from any mode) goes through `recordLocation(latitude:longitude:accuracy:)`:

1. Write `last_lat`, `last_lon`, `last_accuracy`, `last_timestamp` to
   `location_state`.
2. Enqueue a `location_update` track event:

```json
{
  "type": "track",
  "event": "location_update",
  "properties": {
    "latitude":  37.7749,
    "longitude": -122.4194,
    "accuracy":  48.0,
    "timestamp": "2026-03-17T12:00:00Z"
  }
}
```

The aggregation engine receives this event and controls how often it is actually
uploaded to the server. No throttling happens in `LocationCoordinator` itself.

---

## ProfileEnhancing

`LocationModule` conforms to `ProfileEnhancing`. During every `identify` call,
`EventEnricher` collects the module's contribution and merges it into the
outgoing traits:

```swift
[
    "latitude":  .float(lat),
    "longitude": .float(lon),
    "accuracy":  .float(acc),   // horizontal accuracy in metres
    "timestamp": .string(iso8601),
]
```

If no coordinates are stored (mode is `.off`, or `clearIdentify()` was called),
the module returns an empty dictionary and identify proceeds without location
traits.

Every non-empty read also stamps `last_uploaded_at` in `location_state`.

---

## Public API

Accessible via `cio.location.*` (requires `CustomerIO_Location` to be registered):

| Method | Notes |
|---|---|
| `setLastKnownLocation(latitude:longitude:accuracy:)` | Primary entry point for `.manual` mode. Records and emits immediately. Accuracy defaults to 0 if omitted. |
| `requestLocationUpdate()` | Asks the OS for a fresh fix. No-op if permission not granted. Available in `.manual` mode; also usable in other modes for an on-demand fix. |

---

## Reset Behaviour

On `CIOEvent.ResetEvent`, `LocationCoordinator` deletes all keys from
`location_state` (`last_lat`, `last_lon`, `last_accuracy`, `last_timestamp`,
`last_uploaded_at`). Ongoing location monitoring (if any) continues — the
module does not stop collecting; it only clears the previously stored identity.

---

## Platform Notes

- `CoreLocationProvider` and `AppLifecycleObserver` are only instantiated on
  iOS (`#if os(iOS)`). On macOS the module registers and `configure()` succeeds,
  but the coordinator is never created.
- `setLastKnownLocation` and `requestLocationUpdate` are guarded by
  `guard let coordinator` and silently no-op if the coordinator was never
  created (mode `.off`, or non-iOS platform).
