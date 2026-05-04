# ADR 001 — Remove cdp-analytics-swift Dependency

**Status:** Accepted

---

## Context

The previous SDK depended on `cdp-analytics-swift` (Segment's analytics library)
for its event pipeline, upload scheduler, and retry logic. Three requirements
in the reimplementation made this dependency untenable.

## Decision

Remove `cdp-analytics-swift` entirely. Own the full event pipeline:
enrichment → aggregation → queue → upload/retry.

## Consequences

### What this enables

- **Encrypted storage**: `cdp-analytics-swift` writes its event queue to plain
  SQLite with no encryption path. SqlCipher can only be adopted if the SDK owns
  the queue entirely.
- **Swift 6.2 strict concurrency**: The library was not written with `Sendable`
  enforcement or actor isolation. A clean Swift 6.2 codebase is structurally
  incompatible with this dependency in its current form.
- **Server-driven aggregation**: The `AggregationEngine` model (count
  accumulators, property stats, discard rules, flush scheduling) does not map
  onto the upload-on-drain assumptions built into analytics-swift's scheduler.

### What this constrains

- The upload/retry pipeline must be reimplemented from scratch. The area of
  analytics-swift most worth preserving as *reference* — not reinventing — is
  the batch upload pipeline: exponential backoff with jitter, deduplication
  across restarts, ordering guarantees, and partial-batch failure handling.
  These have years of production hardening. Treat the analytics-swift source as
  the specification for this layer.
- Any plugin-based interception model (analytics-swift's `Plugin` API) is not
  carried forward. There is no public plugin protocol for customer code to
  intercept the event pipeline.
