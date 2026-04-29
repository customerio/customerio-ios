# ADR 008 — Separate `CustomerIO_MessagingPushNSE` Module

**Status:** Accepted
**Date:** 2026-04-01

---

## Context

The original NSE integration exposed a static factory method
`MessagingPushModule.configureForExtension(_:)` that returned a
`MessagingPushExtension` object, which the host app's
`UNNotificationServiceExtension` subclass held and forwarded events to.

This design had two problems:

1. **Poor separation of concerns.** The `CustomerIO_MessagingPush` module
   carried NSE-specific config (`extensionCdpApiKey`, `region`, `apiHost`) in
   `PushConfig` and the `PushConfigBuilder.forExtension` factory, even though
   those fields are meaningless in the main app context. The extension process
   also pulled the entire push module — with its actor model, event bus wiring,
   and UIKit dependencies — into the extension binary, where none of it runs.

2. **Awkward host-app interface.** The delegation pattern (hold a
   `MessagingPushExtension`, forward two methods) is un-Swift-like boilerplate
   that discourages adoption. It also cannot benefit from the base-class
   approach because `UNNotificationServiceExtension` is an ObjC class and the
   SDK cannot inject a base class externally.

---

## Decision

Introduce a new `CustomerIO_MessagingPushNSE` Swift Package product backed by a
standalone source target at `Sources/MessagingPushNSE/`. It links only against
Foundation and UserNotifications — no SDK modules.

The public interface is an `open class`:

```swift
open class CIONotificationServiceExtension: UNNotificationServiceExtension {
    public init(
        cdpApiKey: String,
        region: CIONSERegion = .us,
        apiHost: URL? = nil,
        appGroupId: String? = nil
    )
}
```

Host apps subclass it and supply credentials in their own `init()`. Overriding
`didReceive(_:withContentHandler:)` is possible because the class is `open`.

The following are removed from `CustomerIO_MessagingPush`:

- `MessagingPushExtension` (entire file)
- `PushConfigBuilder.forExtension(cdpApiKey:region:provider:)`
- `PushConfigBuilder.apiHost(_:)`
- `MessagingPushModule.configureForExtension(_:)`
- `PushConfig.extensionCdpApiKey`, `PushConfig.region`, `PushConfig.apiHost`

`CIONSERegion`, `DeliveryQueue` (write+delete side only), and
`DeliveryQueueRecord` are duplicated in the new module rather than shared
through `CustomerIO_Utilities`. The duplication is small and avoids coupling
the zero-dependency NSE module to the SDK's internal utilities.

The `DeliveryQueue` in `CustomerIO_MessagingPushNSE` exposes only `write(_:)`
and `deleteRecord(at:)`. The drain side (`processRecords`, `wipe`) stays
exclusively in `CustomerIO_MessagingPush`, which runs in the main app process.

Thread safety in `CIONotificationServiceExtension` uses `NSLock` rather than
`Synchronized<T>` (no utilities dependency) or `Swift.Mutex` (requires iOS 18).

---

## Consequences

**Enables:**
- Minimal extension binary — Foundation + UserNotifications only.
- Clean, idiomatic Swift interface that reduces integration boilerplate to
  overriding `init()`.
- `open class` allows content modification before SDK processing if needed.
- `CustomerIO_MessagingPush.PushConfig` is now unambiguously main-app–only.

**Constrains:**
- `CIONSERegion` and `DeliveryQueue`/`DeliveryQueueRecord` are duplicated.
  Any change to the wire format or queue layout must be mirrored in both modules.
- The `CustomerIO_MessagingPushNSE` test target (`CustomerIO_MessagingPushNSETests`)
  requires a stub directory at `Tests/MessagingPushNSETests/` before SPM will
  resolve the package; no tests are written yet (see TODO.md).

---

## Supersedes

Nothing. Superseded by: nothing.
