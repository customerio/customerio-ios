# Feature Spec — Event Aggregation Engine

---

## Overview

The `AggregationEngine` evaluates every event before it enters the upload queue.
It applies a server-fetched ruleset that can count, summarize, or discard events
client-side, reducing upload volume without requiring app updates.

See also: ADR 005 (server-driven aggregation).

---

## Rule Types

```swift
public enum AggregationRule: Codable, Sendable {

    /// Count occurrences of a named event. Upload a summary event on the
    /// defined flush schedule rather than every individual event.
    case count(CountRule)

    /// Collect min/max/sum/count for a numeric property of a named event.
    /// Upload a stats summary on the flush schedule.
    case stats(StatsRule)

    /// Silently discard events matching the filter.
    case discard(DiscardRule)
}
```

Each rule carries:
- `id: String` — stable identifier; used to preserve accumulator state across ruleset refreshes
- `eventName: String` — the event to match
- `flushSchedule: FlushSchedule` — minimum elapsed duration ("no sooner than")
- Rule-specific fields (property key for stats; output event name for count/stats)

---

## Evaluation Outcomes

| `AggregationResult` | Meaning |
|---------------------|---------|
| `.passThrough` | Event proceeds to the queue unchanged |
| `.aggregated` | Event is absorbed into an accumulator; not queued individually |
| `.discarded` | Event is silently dropped |

---

## `trackSynthesized` Bypass

Events emitted via `.trackSynthesized(name, properties)` skip aggregation
evaluation entirely. This case is used for SDK-internal events (flush summaries,
`"Device Deleted"`, `"location_update"` fallback) that must not be re-aggregated.

---

## Accumulator Lifecycle

1. On first event matching a `count` or `stats` rule, an accumulator is created
   and persisted to the `aggregation_state` table (encrypted via SqlCipher).
2. Subsequent matching events update the accumulator in-place.
3. On flush, the engine synthesises a `trackSynthesized` event carrying the
   accumulated values, injects it into the pipeline via the stored enqueue
   closure, and resets the accumulator.
4. Accumulators survive app kills — partial counts are recovered from
   `aggregation_state` on startup.

---

## Event Processing Loop

`EventProcessor` — a stateless `struct` with closure-injected collaborators —
implements the per-event dispatch:

```swift
let processor = EventProcessor(
    enrich:         { try await enricher.enrich($0) },
    evaluate:       { try await aggregation.evaluate($0) },
    enqueue:        { try await eventQueue.enqueue($0) },
    uploadIfNeeded: { await scheduler.uploadIfNeeded() }
)
Task {
    for await pending in eventStream {
        await processor.process(pending)
    }
}
```

Dispatch branches:
1. **`enrich` returns nil** — event is silently dropped (e.g. enrichment guard failed)
2. **`.trackSynthesized`** — bypasses `evaluate`; goes directly to `enqueue`
3. **`.aggregated`** — no queue write; accumulator updated
4. **`.discarded`** — no queue write; event dropped
5. **`.passThrough`** — `enqueue` called; `uploadIfNeeded` called after

---

## Back-Reference Pattern

`AggregationEngine` injects synthesised flush events via a closure rather than
holding a reference to `CustomerIO`. This avoids a retain cycle and makes the
engine testable without SDK infrastructure:

```swift
// CustomerIO.configure
let aggregation = AggregationEngine(
    storage: storage,
    httpClient: httpClient,
    sdkConfig: config,
    enqueueEvent: { [weak self] event in self?.enqueueEvent(event) }
)
```

---

## Flush Scheduling

Flush schedules are **minimum durations**, not exact times. The engine checks
for due flushes only at app lifecycle events:

- SDK startup (`configure()` completes)
- App enters foreground
- App enters background (before process suspension)

No background timers are used. A flush overdue by hours will not fire until the
next lifecycle checkpoint.

---

## Config Refresh

- Endpoint: static path relative to the region base URL (exact path TBD; stored in one constant).
- Fetched on SDK startup and on app foreground.
- Rate-limited to once per 24 hours; last fetch timestamp persisted to `sdk_meta`.
- A new ruleset is applied atomically. Rules whose `id` matches an existing
  accumulator preserve their in-progress state; accumulators for removed rules
  are flushed before the new ruleset activates.

---

## Storage Schema

| Table | Contents |
|-------|----------|
| `aggregation_rules` | Cached server rule config (JSON, encrypted) |
| `aggregation_state` | In-progress accumulator values (encrypted) |

Both tables are managed by `StorageManager+Aggregation.swift` inside the
`CustomerIO` module.

---

## Predicate Evaluation (v2)

The `predicate` field in rule configs is reserved and **not evaluated in v1**.
All v1 rules match on event name only. Property-level filtering (e.g. "count
only purchases where currency == USD") requires a future CEL interpreter — see
`OPEN_QUESTIONS.md` item 2.
