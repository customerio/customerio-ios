# ADR 003 — Remove cdp-analytics-swift Dependency

**Status:** Accepted

---

## Context

The previous SDK depended on `cdp-analytics-swift` (Segment's analytics library)
for its event pipeline, upload scheduler, and retry logic. Two prior
architectural requirements make this dependency untenable:

- **ADR 001 — Encrypted storage**: All on-device data must be encrypted via
  SqlCipher. `cdp-analytics-swift` writes its event queue to plain SQLite with
  no encryption path. This cannot be addressed by configuration or extension —
  it requires owning the storage layer entirely.

- **ADR 002 — Swift 6.2 strict concurrency**: The SDK must compile cleanly
  under Swift 6.2 with full `Sendable` enforcement. `cdp-analytics-swift` was
  not written with actor isolation; it produces `@preconcurrency` suppressions
  that hide real data races and is structurally incompatible with the required
  concurrency model.

A third requirement compounds this: the server-driven `AggregationEngine`
(see ADR 005) evaluates events before they enter the upload queue and may absorb
them into accumulators rather than forwarding them immediately. This does not
map onto the drain-on-queue assumptions built into `analytics-swift`'s scheduler.
Implementing the aggregation model requires controlling the full path from event
receipt to upload.

None of these requirements can be met by patching or wrapping the existing
library. The dependency must be removed.

## Decision

Remove `cdp-analytics-swift` entirely. Own the full event pipeline:
enrichment → aggregation → queue → upload/retry.

## Consequences

### What this constrains

- The upload/retry pipeline must be reimplemented from scratch. The area of
  `cdp-analytics-swift` most worth preserving as *reference* — not reinventing —
  is the batch upload pipeline: exponential backoff with jitter, deduplication
  across restarts, ordering guarantees, and partial-batch failure handling.
  These have years of production hardening. Treat the `cdp-analytics-swift`
  source as the specification for this layer.
- Any plugin-based interception model (`analytics-swift`'s `Plugin` API) is not
  carried forward. There is no public plugin protocol for customer code to
  intercept the event pipeline.
