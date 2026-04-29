# Aggregation Rules Engine — Design

This document specifies the full design of the server-driven aggregation rules engine
described at a high level in `ARCHITECTURE.md § Dynamic Event Aggregation`. Implement
this document rather than the stub in ARCHITECTURE.md; the stub will be updated to
defer here once this design is ratified.

---

## Purpose

The aggregation engine sits between the `track()` / `identify()` call-site and the upload
queue. It intercepts events and, for each matching rule, accumulates derived values in
encrypted local storage. At scheduled flush points those accumulated values are synthesised
into one or more upload events. This lets the server control what CIO receives — rolling it
into a daily summary rather than thousands of raw events, for example — without an app
update.

---

## Rule Schema

### Top-level structure

A ruleset is an array of rule objects. Each rule owns an accumulator (the storage bucket
that collects values and flushes them on a schedule) and one or more **event rules** that
describe which event types feed into that accumulator and what operations to apply.

Having multiple event rules under one parent rule is what enables multi-event aggregation:
different event types write into the same accumulator and are flushed together as a unit.

```json
{
  "id": "session_lifecycle_summary",
  "uploadInterval": 86400,
  "eventRules": [
    {
      "eventType": "app_backgrounded",
      "operations": [
        { "op": "count", "outputKey": "background_count" }
      ]
    },
    {
      "eventType": "app_foregrounded",
      "operations": [
        { "op": "count", "outputKey": "foreground_count" }
      ]
    },
    {
      "eventType": "session_ended",
      "operations": [
        { "op": "count", "outputKey": "session_count" },
        { "op": "sum",   "field": "event.properties.durationSeconds", "outputKey": "total_session_seconds" },
        { "op": "max",   "field": "event.properties.durationSeconds", "outputKey": "longest_session_seconds" }
      ]
    }
  ]
}
```

A single-event rule is just the degenerate case: one entry in `eventRules`.

```json
{
  "id": "screen_view_counts",
  "uploadInterval": 86400,
  "eventRules": [
    {
      "eventType": "screen_viewed",
      "operations": [
        { "op": "count",       "outputKey": "screen_view_count" },
        { "op": "countUnique", "field": "event.properties.name", "outputKey": "unique_screens_viewed" }
      ]
    }
  ]
}
```

### Rule fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `String` | Yes | Stable identifier for this rule. Used as the accumulator storage key and for diagnostics. Must be unique within a ruleset. |
| `uploadInterval` | `Int` (seconds) | Yes | Minimum elapsed seconds between accumulator flushes. Use `-1` to indicate a local-only rule that never flushes or uploads. Any other negative value is treated as malformed (rule is skipped, fail-open). The engine only checks at app lifecycle events (foreground, background, configure); see Flush Scheduling below. |
| `scope` | `String` | No | `"profile"` *(default)* or `"device"`. Controls whether the accumulator is cleared on `clearIdentify()`. Profile-scoped accumulators are tied to the current user; device-scoped accumulators survive profile changes and `reset()`. Use `"device"` for lifetime counters such as launch counts. |
| `eventRules` | `[EventRule]` | Yes | One or more event matchers that write into this rule's accumulator. Must contain at least one entry. |

### EventRule fields

| Field | Type | Required | Description |
|---|---|---|---|
| `eventType` | `String` | Yes | Name of the `track()` event this entry matches. Exact match. |
| `predicate` | `String` | No | Reserved for future CEL expression support. **Not evaluated in v1 — any value is accepted and ignored.** Omit this field in v1 rulesets. |
| `operations` | `[Operation]` | Yes | Ordered list of aggregate operations to apply when this event type is matched. Each writes to a distinct `outputKey` in the parent rule's accumulator. |

---

## Operations

All operations write their result to an `outputKey` in the accumulated state object.
On flush, the accumulated state is uploaded as profile attributes (`identify`) keyed by
`outputKey`. Multiple operations in the same rule share a single accumulated state object
and are reset together at flush time.

### `count`

Increments a counter by 1 on each matching event.

```json
{ "op": "count", "outputKey": "login_count" }
```

| Param | Required | Description |
|---|---|---|
| `outputKey` | Yes | Attribute name for the running total. |

Stored as `Int`. Resets to 0 after flush.

---

### `sum`

Adds the numeric value at `field` (a CEL path expression) to a running total.
Non-numeric or missing values are silently skipped.

```json
{ "op": "sum", "field": "event.properties.amount", "outputKey": "total_spend" }
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the numeric value within the event context. |
| `outputKey` | Yes | Attribute name for the running total. |

Stored as `Double`. Resets to 0 after flush.

---

### `min`

Tracks the smallest numeric value seen at `field` since the last flush.

```json
{ "op": "min", "field": "event.properties.responseTime", "outputKey": "min_response_ms" }
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the numeric value. |
| `outputKey` | Yes | Attribute name for the running minimum. |

Stored as `Double?` (nil until at least one value is observed). Resets to nil after flush.

---

### `max`

Tracks the largest numeric value seen at `field` since the last flush.

```json
{ "op": "max", "field": "event.properties.score", "outputKey": "high_score" }
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the numeric value. |
| `outputKey` | Yes | Attribute name for the running maximum. |

Stored as `Double?` (nil until at least one value is observed). Resets to nil after flush.

---

### `assign`

Overwrites the stored value with the most recently seen value at `field` (last-write wins).
Equivalent to "last seen." Accepts any CEL-evaluable value (string, number, bool).

```json
{ "op": "assign", "field": "event.properties.planTier", "outputKey": "last_seen_plan" }
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the value to capture. |
| `outputKey` | Yes | Attribute name to overwrite. |

Does **not** reset on flush — the attribute persists as the last observed value.

---

### `assignIfNull`

Writes the value at `field` once and then never overwrites it (first-write wins).
Equivalent to "first seen." Useful for recording the first event property value observed
across the lifetime of the rule.

```json
{ "op": "assignIfNull", "field": "event.properties.referrerCode", "outputKey": "first_referrer" }
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the value to capture on first observation. |
| `outputKey` | Yes | Attribute name to set once. |

Does **not** reset on flush — once written the stored value is permanent until the rule
is removed from the ruleset.

---

### `countUnique`

Counts the number of distinct values observed at `field` since the last flush.

```json
{ "op": "countUnique", "field": "event.properties.productId", "outputKey": "unique_products_viewed" }
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the value whose distinct occurrences are counted. |
| `outputKey` | Yes | Attribute name for the distinct-value count. |

**Implementation note:** Exact counting via a persisted `Set<String>`. For the expected
dataset sizes (flush intervals of hours to days on a single device) cardinality is bounded
and HyperLogLog approximation is not needed. Revisit if a rule produces sets exceeding
~10,000 members in practice. Resets to an empty set after flush.

---

### `histogram`

Buckets a numeric value into predefined ranges and tracks a count per bucket.

```json
{
  "op": "histogram",
  "field": "event.properties.sessionDurationSeconds",
  "outputKey": "session_duration_dist",
  "buckets": [0, 30, 120, 300, 900]
}
```

| Param | Required | Description |
|---|---|---|
| `field` | Yes | CEL path to the numeric value to bucket. |
| `outputKey` | Yes | Attribute name for the bucket map. |
| `buckets` | Yes | Sorted array of `N` boundary values defining `N+1` buckets: `(-∞, b0)`, `[b0, b1)`, …, `[bN-1, bN)`, `[bN, +∞)`. |

The flushed value is an object keyed by bucket label:

```json
{
  "session_duration_dist": {
    "<0":    0,
    "0–30":  14,
    "30–120": 9,
    "120–300": 4,
    "300–900": 2,
    "900+":  1
  }
}
```

Bucket label format: `"<B0"` for underflow, `"B(n–1)–Bn"` for interior buckets,
`"Bn+"` for overflow. Labels are generated from the `buckets` array and are stable
across flushes. Resets all counts to 0 after flush.

---

## CEL Predicate Environment (deferred — not implemented in v1)

The `predicate` field is reserved in the rule schema but **not evaluated in v1**. All
rules fire solely on `eventType` match. This is sufficient for the three immediate use
cases driving the v1 engine:

- **Screen view volume reduction** — `eventType` match + `count`/`countUnique` with a
  daily `uploadInterval`. No per-property filtering needed.
- **Noise suppression** — `eventType` match + `discard`. The event name *is* the predicate.
- **App lifecycle aggregation** — `eventType` match + operations TBD.

When a concrete need for cross-property filtering arises (e.g. count purchases *only* where
`currency == 'USD'`), predicate evaluation can be added without changing the wire format
or breaking existing rules — rulesets that omit `predicate` continue to behave as "match
all." See `OPEN_QUESTIONS.md` for the deferred decision on interpreter strategy.

The intended predicate context variables and built-in functions are documented below for
future reference; they have no effect in the current implementation.

### Event context variable: `event` (future)

```
event.type                   // "track" | "identify" | "screen" | "page" | "alias"
event.name                   // Track event name (same as rule's eventType for track rules)
event.properties.<key>       // Arbitrary event property value; absent keys evaluate to null
event.context.<key>          // Standard context fields (app, device, os, screen, locale, …)
event.timestamp              // ISO-8601 string of the event timestamp
```

### Profile context variable: `profile` (future)

```
profile.id                   // Current identified user ID, or null if anonymous
profile.anonymousId          // Always present
profile.attributes.<key>     // Current known profile attributes (best-effort; may be stale)
```

### Built-in functions (future)

| Function | Return type | Description |
|---|---|---|
| `days_since_install()` | `Int` | Days elapsed since the SDK's first `configure()` on this install. |
| `days_since_last_open()` | `Int` | Days elapsed since the last app foreground event recorded by the SDK. |
| `app_version()` | `String` | Current `CFBundleShortVersionString`. |
| `app_build()` | `String` | Current `CFBundleVersion`. |
| `platform()` | `String` | Always `"ios"` on this SDK. |
| `os_version()` | `String` | iOS/macOS version string, e.g. `"17.4"`. |
| `is_first_event()` | `Bool` | True if this is the first time this specific rule has ever fired for this profile. |

---

## Accumulator Storage Model

Each rule×profile combination gets one row in `aggregation_state`:

| Column | Type | Description |
|---|---|---|
| `rule_id` | `TEXT` | Matches `AggregationRule.id` |
| `profile_id` | `TEXT` | Current profile or anonymous ID |
| `state_json` | `TEXT` | JSON blob: one key per `outputKey`, containing the current accumulated value |
| `last_flushed_at` | `INTEGER` | Unix timestamp of the last flush; used to evaluate `uploadInterval` |
| `created_at` | `INTEGER` | Unix timestamp; used for `is_first_event()` and diagnostics |

The whole table is encrypted via SqlCipher. Writes are transactional — state update and
`last_flushed_at` update always happen in the same `BEGIN`/`COMMIT`.

The `assign` and `assignIfNull` operations use the `profile_attributes` table directly
(or a sidecar) rather than `aggregation_state`, since their values are not reset on flush.
(TBD — may be simplest to write them into `aggregation_state` and treat "no reset" as a
flush behavior flag.)

---

## Flush Scheduling

`uploadInterval` is a **minimum** duration in seconds, not an exact timer. The engine
checks at three lifecycle events only:

1. `CustomerIO.configure(_:)` completes
2. App enters foreground (via `UIApplication.willEnterForegroundNotification`)
3. App enters background (via `UIApplication.didEnterBackgroundNotification`)

At each checkpoint, any rule whose `uploadInterval >= 0` and
`(now - last_flushed_at) >= uploadInterval` is flushed. Rules with `uploadInterval == -1`
are skipped entirely during flush scheduling — their accumulators grow indefinitely and
are never synthesised into an upload event.

**`uploadInterval` sentinel values:**

| Value | Meaning |
|---|---|
| Any positive integer | Minimum seconds between flushes |
| `0` | Flush at every lifecycle checkpoint |
| `-1` | Local-only — never flush, never upload, never reset |
| Any other negative value | Malformed — rule is skipped (fail-open) |

**Flush action (for rules where `uploadInterval >= 0`):**

1. Snapshot the current `state_json` for the rule.
2. Synthesise an `identify` call with the snapshot values as profile attributes.
3. Enqueue the synthesised event into the upload queue (it goes through the full pipeline,
   including other aggregation rules that may match `identify` events).
4. Reset the accumulator (operations that reset do so; `assign`/`assignIfNull` do not).
5. Write the new `last_flushed_at` in the same transaction as step 4.

---

## Ruleset Lifecycle

- On startup the engine loads the cached ruleset from `aggregation_rules`.
- In the background it fetches a fresh ruleset from the server (24-hour minimum refresh
  interval; see ARCHITECTURE.md).
- When a new ruleset arrives it is diffed against the in-progress accumulators:
  - Rules that exist in both old and new (same `id`) — accumulator state is preserved.
  - Rules removed from the new ruleset — if `uploadInterval >= 0`, the accumulator is
    flushed immediately before being discarded (data is not silently dropped). If
    `uploadInterval == -1`, the accumulator is discarded without uploading (it was
    never intended for upload).
  - Rules added in the new ruleset — fresh accumulators initialised from zero.
- Ruleset swap and accumulator preservation happen atomically in a single transaction.

---

## Engine Internals

### Dispatch table

At ruleset load time, the engine builds a flat dispatch table:

```
[String: [(accumulatorId: String, operations: [Operation])]]
```

Keyed by event name. For the session lifecycle example above this produces:

```
"app_backgrounded" → [(accumulatorId: "session_lifecycle_summary", ops: [count → background_count])]
"app_foregrounded" → [(accumulatorId: "session_lifecycle_summary", ops: [count → foreground_count])]
"session_ended"    → [(accumulatorId: "session_lifecycle_summary", ops: [count, sum, max → …])]
"screen_viewed"    → [(accumulatorId: "screen_view_counts",        ops: [count, countUnique → …])]
```

The group structure is fully flattened at load time. Hot-path event processing only sees
this table — O(1) lookup by event name, O(k) work where k is the number of matching rules
(typically 1).

### Accumulator registry

A separate `[String: AccumulatorEntry]` keyed by rule `id` holds:

- `stateJson` — JSON blob of current accumulated values, one key per `outputKey`
- `lastFlushedAt` — Unix timestamp of the last flush (unused for `uploadInterval == -1`)
- `uploadInterval` — copied from the rule for flush checking (`-1` means never flush)
- `scope` — `"profile"` or `"device"`; controls reset-on-clear-identify behavior

This is the only structure consulted during flush scheduling. The registry knows
nothing about event types — it only tracks accumulator values and timing.

### Hot path per event

1. Look up `event.name` in the dispatch table.
2. For each hit: read accumulator state from registry, apply operations, write back.
3. All reads and writes for a single event are wrapped in one `BEGIN`/`COMMIT`.

### Output shape on flush

When a rule's `uploadInterval` elapses the engine emits a **`track` event** whose name
is the rule's `id` and whose properties are the flat accumulated attribute map across all
contributing event rules:

```json
{
  "type": "track",
  "event": "session_lifecycle_summary",
  "properties": {
    "background_count": 12,
    "foreground_count": 13,
    "session_count": 11,
    "total_session_seconds": 4820,
    "longest_session_seconds": 720
  }
}
```

No nested structure is needed on the server side. The server receives and processes this
as a regular track event; knowing it originated from an aggregation flush is implicit in
the event name matching a known rule `id`.

### Flush event lifecycle and cycle prevention

The engine calls `root.enqueueEvent(.trackSynthesized(ruleId, attributes))` rather than
`.track(...)`. `trackSynthesized` is an internal `PendingEvent` case that is **invisible
to callers of the public SDK API** and carries no semantic difference to the server —
it is serialised to the wire as an ordinary `track` event.

Its purpose is to prevent an infinite re-interception cycle:

```
track("location_update") → engine absorbs → accumulates
          ↓  flush
trackSynthesized("location_update", attrs)
          ↓  event loop
  case .trackSynthesized → skip aggregation.evaluate()
          ↓
  eventQueue.enqueue  →  upload
```

The event loop in `CustomerIO` checks the original `PendingEvent` discriminant **before**
calling `aggregation.evaluate()`. Any `.trackSynthesized` event is forwarded directly to
the upload queue without evaluation. This means:

- Flush events are **never** matched by any aggregation rule, even if a rule's `eventType`
  matches the rule `id` used as the flush event name.
- The guarantee is structural — it does not depend on rule naming conventions or the
  absence of matching rules in the active ruleset.

---

## Wire Format (server → SDK)

```json
{
  "version": 4,
  "rules": [
    {
      "id": "session_lifecycle_summary",
      "uploadInterval": 86400,
      "eventRules": [
        {
          "eventType": "app_backgrounded",
          "operations": [
            { "op": "count", "outputKey": "background_count" }
          ]
        },
        {
          "eventType": "app_foregrounded",
          "operations": [
            { "op": "count", "outputKey": "foreground_count" }
          ]
        },
        {
          "eventType": "session_ended",
          "operations": [
            { "op": "count", "outputKey": "session_count" },
            { "op": "sum",   "field": "event.properties.durationSeconds", "outputKey": "total_session_seconds" },
            { "op": "max",   "field": "event.properties.durationSeconds", "outputKey": "longest_session_seconds" }
          ]
        }
      ]
    },
    {
      "id": "screen_view_counts",
      "uploadInterval": 86400,
      "eventRules": [
        {
          "eventType": "screen_viewed",
          "operations": [
            { "op": "count",       "outputKey": "screen_view_count" },
            { "op": "countUnique", "field": "event.properties.name", "outputKey": "unique_screens_viewed" }
          ]
        }
      ]
    },
    {
      "id": "launch_counter",
      "uploadInterval": -1,
      "scope": "device",
      "eventRules": [
        {
          "eventType": "app_launched",
          "operations": [
            { "op": "count", "outputKey": "lifetime_launch_count" }
          ]
        }
      ]
    },
    {
      "id": "discard_debug_events",
      "uploadInterval": 0,
      "eventRules": [
        {
          "eventType": "debug_ping",
          "operations": [
            { "op": "discard" }
          ]
        }
      ]
    }
  ]
}
```

### `discard` operation

An explicit `"op": "discard"` entry is the **only** way to express that a matching event
should be consumed and not forwarded to the upload queue. It takes no other parameters.

```json
{ "op": "discard" }
```

When `discard` appears in the `operations` array it is evaluated before all other
operations — if the predicate matched, the event is dropped and no other operations run.
Combining `discard` with other operations in the same rule is illegal; the SDK treats
that as a malformed rule and skips it (event passes through).

`version` is a monotonically increasing integer. The SDK stores the last-seen version and
skips a config response whose version is less than or equal to the stored version (stale
delivery from a CDN).

---

## Forward Compatibility

SDK versions tend to remain in production apps for months or years after release. The
server will inevitably deliver rulesets containing operation types that old SDK versions
do not recognise. The engine must handle that gracefully.

### Failure hierarchy (fail-open)

The guiding principle is: **an unrecognised operation must never silently stop data from
reaching the upload queue.** The fallback is always to let the event through rather than
to drop it.

| Situation | Engine behaviour |
|---|---|
| Unknown `op` value in an otherwise valid rule | Skip that operation only. Process all recognised operations in the rule normally. The event is still consumed by the rule (not forwarded). |
| All operations in a rule are unknown | The rule produces no accumulation. **The event passes through to the upload queue** as if no rule matched — raw events flow rather than silence. |
| Rule itself is unparseable (malformed JSON, missing required field) | Skip the rule entirely. Event passes through. |
| `discard` combined with other operations | Malformed rule. Skip the rule. Event passes through. |
| Zero operations in the `operations` array (empty array) | Treated the same as "all operations unknown" — event passes through. **An empty operations array is not a discard rule.** Discard requires an explicit `"op": "discard"` entry. |

### Why explicit `discard` matters

If zero operations were treated as discard, a future rule whose operations are all
unrecognised by an old SDK version would silently black-hole data with no observable
signal. Making discard explicit means:

- An old SDK that doesn't recognise any operation in a rule lets events through (visible
  as a spike in raw events on the dashboard — detectable).
- Only events that explicitly match a `"op": "discard"` rule are ever dropped, and that
  operation type is intentionally kept stable across all versions (it carries no parameters
  and requires no interpretation).

### Server-side assistance

The server can additionally version-gate rules — inspecting the SDK version reported in
event context and omitting operations the client version is known not to support. This
reduces unnecessary noise in old clients but is **not** relied upon for correctness;
the client-side fail-open behaviour is the authoritative safety net.
