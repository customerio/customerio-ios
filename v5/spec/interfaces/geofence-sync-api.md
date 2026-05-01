# Geofence Sync — SDK API

> **Status:** Draft — endpoint paths and response schema provisional pending
> backend confirmation.
>
> This document describes the HTTP surface the Customer.io iOS SDK calls to
> synchronise the geofence dataset from the CIO-hosted backend. Host apps
> never call this endpoint directly.
>
> For the full geofencing feature — configuration, storage schema, monitoring
> lifecycle, and QuadKey candidate selection — see
> [`spec/features/geofencing.md`](../features/geofencing.md).

---

## Overview

The SDK uses a cursor-based diff protocol to keep its local geofence dataset
current. On each startup, if `syncURL` is configured, `GeofenceSyncClient`
calls the CIO-hosted endpoint once. The server responds with only the changes
since the last seen cursor, minimising payload size on subsequent syncs.

On the first sync (no stored cursor), the server responds with the full
dataset via `reloadRequired: true`.

---

## Conventions

| Convention | Detail |
|---|---|
| Endpoint URL | CIO-hosted. Configured at SDK init via `GeofenceConfig.syncURL`. Will be derived from `SdkConfig.region` once backend paths are finalised. |
| Method | `GET` |
| Response body | `application/json` |
| Cursor | Opaque string stored under `geofence_update_token` in `sdk_meta`. Omitted on first request. |

---

## Authentication

All SDK requests to this endpoint carry:

| Header | Value |
|---|---|
| `Authorization` | `Basic <base64("cdpApiKey:")>` |
| `User-Agent` | The SDK's standard `User-Agent` string. |

---

## Request

```
GET <syncURL>?token=<updateToken>
```

| Parameter | Required | Description |
|---|---|---|
| `token` | No | The opaque cursor from the previous sync response. Omitted on first sync. When omitted, the server must respond with `reloadRequired: true` and the full dataset in `inserted`. |

---

## Response

**200 OK**

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
| `updateToken` | string | Opaque cursor. The SDK persists this to `sdk_meta` and sends it on the next request. |
| `reloadRequired` | bool | When `true`, the SDK replaces the entire `geofences` table from `inserted`. When `false`, `inserted` and `deleted` are applied as a diff. |
| `inserted` | array | Full geofence records to add or replace. Empty array `[]` when there are none. |
| `deleted` | array of strings | Geofence IDs to remove. Empty array `[]` when there are none. |

**Inserted record fields**

| Field | Type | Notes |
|---|---|---|
| `id` | string | UUID or any globally-unique string. Used as the `CLRegion` identifier and in server events. |
| `title` | string | Human-readable name. Passed to callbacks; not sent to server. |
| `address` | string | Human-readable address. Passed to callbacks; not sent to server. |
| `center.latitude` | double | WGS-84. |
| `center.longitude` | double | WGS-84. |
| `radius_meters` | double | Monitoring radius. iOS minimum is ~100 m; values below that are clamped by the OS. |

---

## SDK Handling

### Full-Reload Path (`reloadRequired: true`)

`replaceGeofences(_:updateToken:quadkeyZoom:)` executes atomically:

1. `DELETE FROM geofence_state`
2. `DELETE FROM geofences`
3. `INSERT` each row from `inserted` with a freshly computed QuadKey.
4. Upsert `geofence_update_token` and `geofence_quadkey_zoom` into `sdk_meta`.

All four steps occur within a single `BEGIN`/`COMMIT` so the stored token
always matches the on-disk dataset.

### Incremental Path (`reloadRequired: false`)

`applyGeofenceDiff(upserts:deletions:updateToken:)` executes atomically:

1. `INSERT OR REPLACE` each upsert row.
2. `DELETE FROM geofences WHERE id = ?` for each deleted ID.
3. Upsert `geofence_update_token` into `sdk_meta`.

---

## Record Immutability

Geofence records are immutable by ID. The server never mutates an existing
record in place — to change a geofence it must be deleted and re-inserted with
a new ID. This collapses the changelog to inserts and deletes only and
eliminates the need for update tracking.

Deletion records on the server need only be retained for a window covering the
maximum expected gap between client syncs. Recommended: 3× the sync interval
(e.g. 21 days at a 7-day cycle).
