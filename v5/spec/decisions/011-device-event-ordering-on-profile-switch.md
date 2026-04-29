# ADR 011 — Device Event Ordering on Profile Switch

**Status:** Accepted
**Date:** 2026-04-03

---

## Context

TODO item 3b specifies that on a profile switch (when `identify()` is called for a
different user), the SDK should emit events in this order:

1. `"Device Deleted"` — disassociate the device token from the **old** profile
2. `"Identify"` — associate the caller with the **new** profile
3. `"Device Created or Updated"` — register the device token under the **new** profile

The goal is to ensure the old profile stops receiving push notifications before the
new profile is associated, preventing cross-profile delivery.

---

## Problem

The current event pipeline processes events from an `AsyncStream` sequentially,
one at a time. The `identify()` method on `CustomerIO` is `nonisolated` and must
not `await` — it yields the `.identify` pending event to the stream synchronously,
then immediately posts `ProfileIdentifiedEvent` on the `CommonEventBus`.

`CommonEventBus.post()` dispatches observer callbacks asynchronously via
`OperationQueue`. This means the push module's `ProfileIdentifiedEvent` handler
runs concurrently with (or after) the event loop begins processing the `.identify`
event already in the stream.

There is no way to inject a `"Device Deleted"` event **before** the `.identify`
event that is already queued, without either:

- Changing `identify()` to be `async` (breaks callers, breaks the `nonisolated`
  contract)
- Replacing `AsyncStream` with a priority queue (significant architecture change)
- Detecting the profile switch in `EventEnricher` and yielding synthetic events
  to the front of the stream (no such mechanism exists; the enricher is single-event
  in / single-event out by design)

---

## Decision

Accept the following upload-queue ordering for a profile switch where a token exists:

1. `"Identify"` (new profile)
2. `"Device Deleted"` (old profile token — emitted synchronously in the `ProfileIdentifiedEvent`
   observer via `_enqueueEvent`, which yields directly to the stream continuation; arrives
   in the stream immediately after the Identify event)
3. `"Device Created or Updated"` (new profile token — emitted after an async `Task` completes
   device-info collection; arrives shortly after)

Items 2 and 3 are enqueued by the `MessagingPushModule`'s `ProfileIdentifiedEvent` observer.
Item 2 is synchronous (no actor hop required, uses `Synchronized` directly). Item 3 requires
a `Task` because `DeviceInfoProvider.collect()` is `async` (it must query
`UNUserNotificationCenter` for push permission status).

This ordering means the backend receives `"Identify"` before `"Device Deleted"`. Whether
this causes any observable correctness issue depends on whether the backend's `"Device Deleted"`
handler resolves the target device by token (correct regardless of identify order) or by
"current profile" (would incorrectly delete from the new profile). CIO's CDP uses token-scoped
device records, so this ordering is safe.

---

## Consequences

**Enables:**
- Profile-switch device lifecycle events are emitted without any breaking architecture changes.
- The `ResetEvent` ("Device Deleted" before token clear) follows correct ordering because it
  is entirely synchronous within the event bus handler.

**Constrains:**
- If the backend's `"Device Deleted"` event semantics ever change to target "current profile"
  rather than a specific token, this ordering could cause issues. This should be verified
  against the backend API contract before shipping.
- The spec's stated order (Device Deleted → Identify) is not achievable without a priority
  insertion mechanism in the event stream. If strict ordering becomes a requirement, revisit
  with an ADR superseding this one.

---

## Supersedes / Superseded by

None.
