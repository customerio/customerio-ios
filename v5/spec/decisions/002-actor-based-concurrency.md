# ADR 002 — Swift 6.2 Actor-Based Concurrency Throughout

**Status:** Accepted

---

## Context

The previous SDK was not written with `Sendable` enforcement or actor isolation.
`cdp-analytics-swift` produced `@preconcurrency` wrappers or suppressed warnings
that hid real data races. The reimplementation targets Swift 6.2 with strict
concurrency enabled, which is structurally incompatible with the previous
library's concurrency model. This is one of the requirements addressed in ADR 003.

## Decision

Adopt **Swift 6.2 strict concurrency** throughout:

- All public-facing mutable state lives in `actor` types.
- All cross-boundary types conform to `Sendable`.
- Event-tracking methods (`track`, `identify`, `screen`, etc.) on `CustomerIO`
  are `nonisolated` — callable from any thread or isolation domain without `await`.
- Pre-configure event buffering is handled by `AsyncStream`'s built-in buffer
  (capped at 100 events, oldest-first). No separate two-mode buffer is needed.
- `Synchronized<T>` bridges actor-owned state to `nonisolated` access sites
  (e.g. module loggers, push token mirrors) without crossing actor boundaries.

## Consequences

### What this enables

- No data races possible in the SDK's own code under strict checking.
- `nonisolated` tracking methods allow the SDK to be called from `@MainActor`
  views, background threads, and notification extensions without `await`.
- Pre-configure events are buffered automatically and drained in order once
  `configure()` completes.
- Modules that need `@MainActor` (e.g. `MessagingInApp`) dispatch internally
  without requiring the root actor to be `@MainActor`.

### What this constrains

- iOS 13+ minimum deployment target required (Swift concurrency embedded runtime).
- `os.Logger` structured logging (iOS 14+) and `Clock`/`ContinuousClock`
  (iOS 16+) are not used. Flush timing relies on app lifecycle events, not
  background timers.
- `URLSession` async APIs (iOS 15+) are not used. The HTTP client wraps the
  completion-handler API in `withCheckedContinuation` for iOS 13/14 compatibility.
- `@preconcurrency` annotations are used sparingly and only where Swift's region
  checker produces a known false positive (documented inline).
