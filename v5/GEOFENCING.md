# Geofencing — Design Specification

**Status:** Implemented (v1)
**Last updated:** March 17, 2026

---

## Overview

Geofencing allows the SDK to monitor a set of named geographic regions and emit
events when the device enters or exits them. Geofence definitions are loaded
from a bundled JSON file on first launch, then kept current via a cursor-based
diff protocol synced from a server endpoint on each startup. Regions are indexed
using the QuadKey tile system (in `CustomerIO_Utilities`) so that candidate
selection — choosing which 20 regions to hand to `CLLocationManager` — is a
single indexed table scan rather than a full dataset evaluation.

The Geofencing module is independent of the Location module. An app that wants
geofence enter/exit events but no CIO location tracking registers
`GeofencingModule` alone. `GeofenceCoordinator` self-supplies the coarse
position (~500 m) needed for candidate tile selection via
`CLLocationManager.startMonitoringSignificantLocationChanges()`. When the
Location module is also active, CoreLocation deduplicates the radio work at the
OS level with no additional power cost.

---

## Goals

- Load a geofence dataset (up to ~10,000 regions) from a bundled JSON file or a
  remote API endpoint.
- On import, compute the QuadKey tile of each geofence's centre coordinate for
  fast spatial lookup. The zoom level is taken from `GeofenceConfig.quadKeyZoom`
  (default 13, ~4.9 km tiles at the equator, ~3.5 km at 45°N).
- When the device's location changes, select the geofences most likely to be
  relevant by querying the 3×3 neighbourhood of tiles around the current tile
  (9 tiles total, roughly a 15 × 15 km candidate window at zoom 13 near the
  equator).
- Register the best candidates with `CLLocationManager`'s region monitoring API
  (max 20 regions enforced by iOS).
- When a region is entered, send a `geofence_entered` event to the server and
  optionally invoke a user-supplied callback.
- When a region is exited, optionally send a `geofence_exited` event and invoke
  the callback.
- Guard against re-entry noise (GPS jitter, users living adjacent to a fence)
  with a dual-condition cooldown: a second enter event for the same geofence
  cannot fire until **both** a minimum time has elapsed **and** the device has
  travelled a minimum distance away from the fence boundary.
- Support three monitoring lifecycle modes: `off`, `manual`, and `automatic`.
- Sync the geofence dataset from a server on each startup using a cursor-based
  diff protocol that sends only inserts and deletes since the last seen token.

---

## Non-Goals (v1)

- **Background monitoring.** Region monitoring operates only while the app is in
  the foreground. See [Future Considerations](#future-considerations).
- **Per-geofence exit event suppression.** Whether exit events are sent is a
  single global flag. Fine-grained filtering can be handled by the aggregation
  rules engine.
- **Multi-platform support.** `CLLocationManager` region monitoring is iOS-only.
  The geofencing subsystem is gated `#if os(iOS)` throughout.
- **Geofence authoring UI or tooling.**

---

## Geofence JSON Schema

The canonical geofence dataset is a single JSON object. The SDK parses the same
schema regardless of whether the data comes from the bundle or the network.

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-03-13T00:00:00Z",
  "geofences": [
    {
      "id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
      "title": "KwikTrip #512",
      "address": "1234 Main St, La Crosse, WI 54601",
      "center": {
        "latitude": 43.8014,
        "longitude": -91.2396
      },
      "radius_meters": 150.0
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | Semver; SDK rejects files with an unrecognised major version. |
| `generated_at` | ISO 8601 string | Informational; not used for refresh scheduling. |
| `geofences[].id` | string | UUID or any globally-unique string. Used as the `CLRegion` identifier and in server events. |
| `geofences[].title` | string | Human-readable name. Passed to callbacks; not sent to server. |
| `geofences[].address` | string | Human-readable address. Passed to callbacks; not sent to server. |
| `geofences[].center.latitude` | double | WGS-84. |
| `geofences[].center.longitude` | double | WGS-84. |
| `geofences[].radius_meters` | double | Monitoring radius. iOS minimum is ~100 m; values below that are clamped by the OS. |

At import time the SDK computes and stores the QuadKey for each centre
coordinate. The zoom level is taken from `GeofenceConfig.quadKeyZoom` (default
13). This derived value is written to the local DB; it is **not** part of the
JSON schema.

---

## Storage Schema

Two tables are added to the existing encrypted SQLite database via
`GeofenceStorageMigration` (migration id `003-geofence-schema`). The storage
methods for these tables live in `StorageManager+Geofences.swift` inside the
`CustomerIO_Geofencing` target, following the [StorageManager extension
pattern](ARCHITECTURE.md).

### `geofences`

Stores the imported geofence dataset. Rebuilt atomically on each successful sync.

```sql
CREATE TABLE IF NOT EXISTS geofences (
    id              TEXT    NOT NULL PRIMARY KEY,
    title           TEXT    NOT NULL,
    address         TEXT    NOT NULL,
    latitude        REAL    NOT NULL,
    longitude       REAL    NOT NULL,
    radius_meters   REAL    NOT NULL,
    quadkey         TEXT    NOT NULL,    -- computed at import time
    imported_at     INTEGER NOT NULL     -- Unix epoch seconds
);
CREATE INDEX IF NOT EXISTS idx_geofences_quadkey ON geofences (quadkey);
```

### `geofence_state`

Tracks per-geofence cooldown state so that re-entry guards survive app restarts.

```sql
CREATE TABLE IF NOT EXISTS geofence_state (
    geofence_id     TEXT    NOT NULL PRIMARY KEY,
    last_entered_at INTEGER,            -- Unix epoch seconds; NULL if never entered
    last_exited_at  INTEGER,            -- Unix epoch seconds; NULL if never exited
    exit_latitude   REAL,               -- coordinate at the time of last exit
    exit_longitude  REAL                -- used for the distance cooldown check
);
```

Note: the `geofence_state` table does not declare a foreign-key constraint to
`geofences`. `replaceGeofences` deletes `geofence_state` rows explicitly before
replacing the `geofences` table, and `applyGeofenceDiff` handles state cleanup
per deletion.

---

## Configuration

`GeofenceConfig` is a top-level SDK config struct, separate from `LocationConfig`.
It is attached via `SdkConfigBuilder.geofencing(_:)`:

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .geofencing(GeofenceConfig(mode: .automatic, syncURL: serverURL))
    .build()
```

```swift
public struct GeofenceConfig: Sendable {

    /// Controls when geofence monitoring starts.
    public var mode: GeofenceMode

    /// Whether to send a `geofence_exited` event (and invoke `onGeofenceExited`)
    /// when a monitored region is left. Default: true.
    public var sendExitEvents: Bool

    /// Minimum elapsed time after a geofence exit before the same geofence
    /// can fire an enter event again. Both this condition AND
    /// `reentryMinDistance` must be satisfied. Default: 15 minutes.
    public var reentryMinInterval: TimeInterval

    /// Minimum distance (metres) the device must travel from the geofence
    /// boundary after exiting before an enter event can re-fire. Both this
    /// condition AND `reentryMinInterval` must be satisfied. Default: 500 m.
    public var reentryMinDistance: Double

    /// Called on the main thread when the device enters a monitored geofence.
    public var onGeofenceEntered: (@Sendable (Geofence) -> Void)?

    /// Called on the main thread when the device exits a monitored geofence,
    /// if `sendExitEvents` is true.
    public var onGeofenceExited: (@Sendable (Geofence) -> Void)?

    /// Full URL of the geofence sync endpoint.
    ///
    /// When set, the coordinator runs the cursor-based diff sync on each startup.
    /// When nil (the default), the SDK seeds from the bundled example file once
    /// and makes no further network requests.
    public var syncURL: URL?

    /// Zoom level used when encoding geofence centre coordinates as QuadKey
    /// tiles for candidate selection. Default: 13 (~4.9 km tiles at the equator).
    public var quadKeyZoom: Int
}

public enum GeofenceMode: Sendable {
    case off        // module is inert; no CLLocationManager activity
    case manual     // monitoring starts only when startGeofenceMonitoring() is called
    case automatic  // monitoring starts immediately after configure() completes
}
```

---

## Lifecycle and Monitoring Flow

### Startup

`GeofencingModule.configure()` is called by the root `CustomerIO` actor during
SDK initialisation. It checks `GeofenceConfig.mode`:

- `.off` — nothing starts; the module is inert.
- `.manual` — a `GeofenceCoordinator` is created and waits for an explicit
  `cio.geofencing.startGeofenceMonitoring()` call.
- `.automatic` — `GeofenceCoordinator.start()` runs immediately.

On start, `GeofenceCoordinator`:

1. Subscribes to `CIOEvent.ResetEvent` on the event bus.
2. Calls `CLLocationManager.startMonitoringSignificantLocationChanges()` to
   self-supply coarse position for candidate tile selection.
3. Runs `bootstrapDataset()` — syncs from the server if `syncURL` is set,
   otherwise seeds from the bundle if the local DB is empty.
4. Runs `reindexIfNeeded()` — rewrites QuadKey columns if `quadKeyZoom` has
   changed since the last import.
5. If mode is `.automatic`, sets `isMonitoring = true` so the next location
   update triggers candidate selection.

### Candidate Selection

When a significant-change location event arrives from the coordinator's own
`CLLocationManager`:

1. Compute the QuadKey for the coordinate at `GeofenceConfig.quadKeyZoom`.
2. Compute the 8 neighbouring tiles (Moore neighbourhood), giving 9 tiles total.
3. Query `geofences` for all rows whose `quadkey` is in those 9 tiles.
4. If ≤ 20 candidates, register all with `CLLocationManager.startMonitoring(for:)`.
5. If > 20, sort by straight-line distance (ascending), take the nearest 20, and
   emit a `geofence_candidate_overflow` track event with `candidate_count` and
   `monitored_count`.
6. Stop monitoring any previously registered regions no longer in the candidate set.

### Enter/Exit Event Handling

**Enter (`locationManager(_:didEnterRegion:)`)**

1. Check cooldown: if `geofence_state` has a record, both conditions must be met:
   - `now − last_exited_at ≥ reentryMinInterval`
   - distance from exit coordinates to current position ≥ `reentryMinDistance`
   If either fails, suppress and return. If no exit location was recorded,
   the distance condition passes automatically.
2. Record `last_entered_at = now` in `geofence_state`.
3. Enqueue `geofence_entered` event: `{ "geofence_id": "<id>" }`.
4. Invoke `onGeofenceEntered` on the main thread (if set).

**Exit (`locationManager(_:didExitRegion:)`)**

1. Record `last_exited_at`, `exit_latitude`, `exit_longitude` in `geofence_state`
   regardless of `sendExitEvents` (exit position is needed for the cooldown check).
2. If `sendExitEvents` is false, return.
3. Enqueue `geofence_exited` event: `{ "geofence_id": "<id>" }`.
4. Invoke `onGeofenceExited` on the main thread (if set).

### Monitoring Set Swap

When candidate selection runs again and the monitored set changes, regions being
de-registered while the device is still inside them do **not** produce a
synthesised exit event. iOS will re-fire `didEnterRegion` naturally on the next
candidate refresh if the device is still within range.

### Reset

On `CIOEvent.ResetEvent`, `GeofenceCoordinator` stops monitoring all regions
and clears the `geofence_state` table. The `geofences` table is **not** cleared
— the dataset is tied to app configuration, not user identity.

---

## Dataset Sync Protocol

`GeofenceSyncClient` implements a cursor-based diff protocol. On each SDK
startup, if `syncURL` is configured, the coordinator calls `sync(url:token:)`.

### Request

```
GET <syncURL>?token=<updateToken>
```

On first sync (no stored token), the `token` parameter is omitted. The server
responds with `reloadRequired: true` and the full dataset in `inserted`.

### Response Wire Format

```json
{
  "updateToken": "cursor-opaque-string",
  "reloadRequired": false,
  "inserted": [
    {
      "id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
      "title": "KwikTrip #512",
      "address": "1234 Main St, La Crosse, WI 54601",
      "center": { "latitude": 43.8014, "longitude": -91.2396 },
      "radius_meters": 150.0
    }
  ],
  "deleted": ["a1b2c3d4-0000-0000-0000-000000000001"]
}
```

| Field | Type | Notes |
|---|---|---|
| `updateToken` | string | Opaque cursor. Persisted to `sdk_meta` and sent on the next request. |
| `reloadRequired` | bool | When `true`, the SDK replaces the entire `geofences` table from `inserted`. |
| `inserted` | array | Full geofence records to add. Empty array `[]` when there are none. |
| `deleted` | array of strings | Geofence IDs to remove. Empty array `[]` when there are none. |

### Full-Reload Path (`reloadRequired: true`)

`replaceGeofences(_:updateToken:quadkeyZoom:)` executes atomically:

1. `DELETE FROM geofence_state`
2. `DELETE FROM geofences`
3. `INSERT` each row from `inserted` with a freshly computed QuadKey.
4. Upsert `geofence_update_token` and `geofence_quadkey_zoom` into `sdk_meta`.

All four steps occur within a single `BEGIN`/`COMMIT` so the stored token always
matches the on-disk dataset.

### Incremental Path

`applyGeofenceDiff(upserts:deletions:updateToken:)` executes atomically:

1. `INSERT OR REPLACE` each upsert row.
2. `DELETE FROM geofences WHERE id = ?` for each deleted ID.
3. Upsert `geofence_update_token` into `sdk_meta`.

### Geofence Record Immutability

Geofence records are immutable by ID. The server never mutates an existing record
in place — to change a geofence it must be deleted and re-inserted with a new ID.
This collapses the changelog to inserts and deletes only and eliminates the need
for update tracking.

Delete records on the server need only be retained for a window covering the
maximum expected gap between client syncs (recommended: 3× the sync interval,
e.g. 21 days at a 7-day cycle).

---

## QuadKey Zoom Reindex

On each startup, `reindexIfNeeded()` compares the stored zoom level
(`sdk_meta.geofence_quadkey_zoom`) against the configured `quadKeyZoom`:

- If they match: no-op.
- If they differ (or no stored zoom exists): recompute the `quadkey` column for
  every row in `geofences` using the new zoom, then update `sdk_meta`.

This allows changing `quadKeyZoom` between releases without requiring a full
dataset reload. The reindex runs before candidate selection on startup.

---

## Local Fixture

A bundled JSON file (KwikTrip store locations, ~600 real locations across
Wisconsin and the Upper Midwest) is included in the `CustomerIO_Geofencing`
target under `Resources/geofences_example.json`. It is used:

- As the default dataset before the first server sync completes (when
  `syncURL` is configured and the local DB is empty).
- As the sole dataset when no `syncURL` is configured (offline / dev mode).
- As a realistic input for manual testing.

The bundle-seeded dataset is stored with an empty string as the `updateToken`
sentinel, ensuring the first sync always fetches the full dataset from the server.

---

## Future Considerations

### Background Monitoring

iOS's `CLLocationManager.startMonitoring(for:)` natively delivers enter/exit
callbacks in the background when the app holds "Always" location permission.
`GeofenceCoordinator` is already implemented as a `CLLocationManagerDelegate`
receiving `didEnterRegion`/`didExitRegion` directly, so enabling background
support requires only a permission handling change and a config flag — no
architectural surgery.

### Geofence-Level Event Configuration

Exit events are currently a global toggle. Per-geofence control can be added
as an optional `"send_exit_event": false` field in the JSON schema without
breaking existing parsers.

### Android / Cross-Platform Parity

The geofencing subsystem is iOS-only. Android parity, if required, would use
the Geofencing API from Google Play Services and share the same JSON schema
and server event format.

---

## Open Questions

No unresolved questions at this time.
