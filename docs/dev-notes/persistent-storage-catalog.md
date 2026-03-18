# Customer.io iOS SDK — Persistent Storage Catalog

This document catalogs every location where the Customer.io iOS SDK (and its bundled Segment analytics library) persists data on device.

---

## UserDefaults

### CIO SDK — Sandboxed per Site ID

Suite name pattern: `io.customer.sdk[.<appBundleId>].<siteId>`

| Key | Written by | Data type | Purpose |
|---|---|---|---|
| `identifiedProfileId` | `ProfileStore` | String | The identified customer's profile/user ID |
| `inAppUserQueueFetchCachedResponse` | `QueueManager` (MessagingInApp) | Data (JSON) | Cached in-app message queue response from server |
| `broadcastMessages` | `AnonymousMessageManager` | String (JSON) | Anonymous/broadcast in-app messages |
| `broadcastMessagesExpiry` | `AnonymousMessageManager` | Double | Expiry timestamp for broadcast messages |
| `broadcastMessagesTracking` | `AnonymousMessageManager` | String (JSON) | Tracking state for anonymous messages |
| `inboxMessagesOpenedStatus` | `InboxMessageCacheManager` | Data (JSON) | Inbox message opened/closed state dictionary |

### CIO SDK — Shared (across all sites)

Suite name pattern: `io.customer.sdk[.<appBundleId>].shared`

| Key | Written by | Data type | Purpose |
|---|---|---|---|
| `pushDeviceToken` | `GlobalDataStore` | String | APN or FCM device push token |

### Segment Analytics (cdp-analytics-swift) — Per Write Key

Suite name pattern: `com.segment.storage.<writeKey>`

| Key | Data type | Purpose |
|---|---|---|
| `segment.userId` | String (PropertyList encoded) | Current user ID |
| `segment.traits` | Object (PropertyList encoded) | User traits/attributes |
| `segment.anonymousId` | String (PropertyList encoded) | Anonymous user identifier |
| `segment.settings` | Object (PropertyList encoded) | SDK settings fetched from CDN |
| `segment.events` | Integer | Index counter for event batch files |

### Segment Analytics — `UserDefaults.standard` (global, not suite-scoped)

| Key | Data type | Purpose |
|---|---|---|
| `SEGVersionKey` | String | App version string, used for lifecycle event tracking |
| `SEGBuildKeyV2` | String | App build number, used for lifecycle event tracking |

---

## File System

### CIO SDK — Background Queue

Base path: `~/Library/Application Support/io.customer/<siteId>/queue/`

| File | Format | Purpose |
|---|---|---|
| `inventory.json` | JSON array of `QueueTaskMetadata` | Ordered list of pending background queue tasks |
| `tasks/<taskId>.json` | JSON `QueueTask` | Individual background queue task payloads |

### CIO SDK — Event Bus Storage

Base path: `~/Library/Application Support/Events/<eventType>/`

| File | Format | Purpose |
|---|---|---|
| `<storageId>.json` | JSON | Serialized SDK events, one file per event |

Events are sorted by timestamp on retrieval. Each event type gets its own subdirectory.

### CIO SDK — Temporary Rich Push Images

Base path: `~/tmp/cio_sdk/`

| File | Purpose |
|---|---|
| `<UUID>_<filename>` | Image downloaded for a rich push notification, deleted immediately after use |

### Segment Analytics — Event Batches (cdp-analytics-swift)

Base path: `~/Documents/segment/<writeKey>/` (iOS & watchOS)  
Base path: `~/Library/Caches/segment/<writeKey>/` (macOS & tvOS)

| File pattern | Format | Purpose |
|---|---|---|
| `<index>-segment-events` | Newline-delimited JSON | In-progress event batch currently being written (max 475 KB) |
| `<index>-segment-events.temp` | JSON batch | Completed batch queued for upload to server |

Each completed `.temp` file is a JSON object of the form:

```json
{
  "batch": [ /* individual events */ ],
  "sentAt": "<ISO8601 timestamp>",
  "writeKey": "<write key>"
}
```

Files roll over to a new index once the 475 KB size limit is reached.

---

## Not Used

| Mechanism | Notes |
|---|---|
| **Keychain** | Not used. Push tokens are stored in UserDefaults. |
| **Core Data** | Not used. |
| **SQLite** | Not used. |
| **NSKeyedArchiver** | Not used. `Codable` with `JSONEncoder` / `PropertyListEncoder` is used instead. |
| **URLCache** | Not used. Network requests are made with `.reloadIgnoringCacheData`. |
| **NSCache** | Not used for persistence. In-memory-only stores (e.g. `PushHistory`, `QueueInventoryMemoryStore`) use plain collections. |
