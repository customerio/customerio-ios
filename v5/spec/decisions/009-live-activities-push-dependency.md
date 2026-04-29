# ADR 009 — Live Activities Module Depends on MessagingPush

**Status:** Accepted  
**Date:** 2026-04-03

---

## Context

The `CustomerIO_LiveActivities` module needs access to the device push token to
include the `recipient` field in activity state events sent to the Customer.io
backend. Without this field the backend cannot associate the event with the
correct device profile.

Two structural options were considered:

1. **Merge Live Activities into `CustomerIO_MessagingPush`** — one module, shared
   token access.
2. **Keep Live Activities as a separate module with an explicit package-level
   dependency on `CustomerIO_MessagingPush`** — two modules, token read via
   `cio.push.registeredDeviceToken`.

---

## Decision

Option 2: `CustomerIO_LiveActivities` is a separate SPM target that lists
`CustomerIO_MessagingPush` as a dependency.

The device push token is **not** duplicated in the Live Activities module.
`MessagingPushModule.registeredDeviceToken` (a `nonisolated` computed property
added in task 16c) is the single source of truth. The Live Activities module
reads it via the `CustomerIO` root instance when needed.

---

## Consequences

### Enables

- **Clean API surface separation.** Push notification concerns (APNs token
  management, click tracking, delivery reporting) remain in one module; Live
  Activities concerns (ActivityKit observation, push-to-start token rotation)
  in another.
- **Independent adoption.** Apps that use push but not Live Activities, or Live
  Activities without the full push event-tracking stack, can include only what
  they need.
- **`@available(iOS 16.1, *)` containment.** ActivityKit generics and the
  `#if os(iOS)` guards stay inside `CustomerIO_LiveActivities`. The push module
  remains unconditionally available on all platforms.

### Constrains

- **Push is a required sibling module.** `SdkConfigBuilder.liveActivities` docs
  explicitly state that `.push { }` must also be registered. The SDK does not
  enforce this at compile time; a missing push module results in a `fatalError`
  at runtime when `cio.push` is accessed.
- **Package graph coupling.** Any app using `CustomerIO_LiveActivities` transitively
  pulls in `CustomerIO_MessagingPush`. This is intentional and acceptable — Live
  Activities are meaningless without push.

### Supersedes

Nothing. This is a new module.

---

## Rejected Alternative

**Merge into `CustomerIO_MessagingPush`:** rejected because:

- The push module already manages APNs token lifecycle, click handling, delivery
  reporting, and NSE integration. Adding `ActivityKit` generics, `@available`
  version gates, and push-to-start token rotation logic would violate the Single
  Responsibility Principle and inflate the module surface significantly.
- ActivityKit is iOS 16.1+ only. Gating a large new code path inside an
  existing module with `#if os(iOS)` and `@available` checks adds noise and
  makes future extraction harder.
