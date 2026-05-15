# ADR 005 — Server-Driven Event Aggregation Engine

**Status:** Accepted

---

## Context

The previous SDK forwarded every event individually to the upload queue. For
high-frequency events (screen views, location pings, lifecycle events), this
produces excessive server load and inflated analytics noise. Reducing volume
client-side requires a configurable ruleset.

## Decision

Introduce a server-driven `AggregationEngine` that evaluates every event
before it enters the queue. The engine fetches its ruleset from a static
endpoint relative to the region base URL.

### Rule evaluation

Each `AggregationRule` specifies an event name and one or more `AggregateOperation`
values. Supported operations: `count`, `sum`, `min`, `max`, `assign`,
`assignIfNull`, `countUnique`, `histogram`, `discard`.

Evaluation outcomes (`AggregationResult`):
- `.passThrough` — event proceeds to the queue unchanged
- `.aggregated` — event is absorbed into an accumulator; not queued individually
- `.discarded` — event is silently dropped

### Accumulator lifecycle

- Accumulators are persisted encrypted to SqlCipher so partial counts survive
  app kills.
- On flush, the engine synthesises a `trackSynthesized` event (bypasses
  aggregation re-evaluation), injects it into the pipeline via a stored
  `@Sendable (PendingEvent) -> Void` closure, and resets the accumulator.
- Flush checks occur only at app lifecycle events (startup, foreground,
  background). No background timers are used.
- Flush schedules in rule configs are **minimum durations** ("no sooner than").

### Config refresh

- Fetched on SDK startup and on app foreground.
- Rate-limited to once per 24 hours (last fetch timestamp persisted to `sdk_meta`).
- A new ruleset is applied atomically; in-progress accumulator state is preserved
  for rules whose `id` is unchanged.

### Back-reference pattern

`AggregationEngine` injects synthesised events via a closure rather than holding
a back-reference to `CustomerIO`. This avoids a retain cycle and makes the engine
testable without SDK infrastructure.

## Consequences

### What this enables

- High-frequency events can be aggregated client-side without app updates — the
  server controls the rules.
- Events matching `discard` rules never reach the server, reducing data noise.
- The engine is fully testable: a `MockHttpClient` and a lambda enqueue closure
  are sufficient; no real database or scheduler is needed.

### What this constrains

- The `predicate` field in rule configs is reserved but **not evaluated in v1**.
  All v1 use cases require only event-name matching. Property-level filtering
  (e.g. "count only purchases where currency == USD") requires a future CEL
  interpreter (see OPEN_QUESTIONS.md item 2).
- Flush timing is coarse — only at lifecycle checkpoints, not on a timer.
  A flush overdue by hours will not fire until the next foreground event.
