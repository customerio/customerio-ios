# Core Module — Specification

This document covers the `CustomerIO` root module: the `CIOTrackingClient` abstraction, the module configuration builder pattern, the module accessor pattern, and the Objective-C bridge.

For the module graph, event pipeline, storage schema, concurrency model, module startup phases, anonymous ID ownership, and the SDK-internal event bus, see [`spec/domain/domain-model.md`](../domain/domain-model.md).

---

## CIOTrackingClient Protocol

`CIOTrackingClient` is a narrow public protocol that abstracts the CustomerIO tracking surface:

```swift
public protocol CIOTrackingClient: AnyObject, Sendable {
    nonisolated func track(_ name: String, properties: [String: Variant])
    nonisolated func identify(_ profileId: String, traits: [String: Variant])
    nonisolated func screen(_ name: String, category: String?, properties: [String: Variant])
    nonisolated func clearIdentify()
    nonisolated func setProfileAttributes(_ traits: [String: Variant])
    nonisolated func setDeviceAttributes(_ attributes: [String: Variant])
}

extension CustomerIO: CIOTrackingClient {}
```

`CustomerIO` conforms via an empty extension — all methods already satisfy the requirements.

### Why It Exists

Sub-modules (e.g. `MessagingPushModule`) need to call `track(...)` on the root SDK instance to emit metric events. Before this protocol existed, those modules held a direct `CustomerIO` reference. That made unit tests require a real configured `CustomerIO` actor, which in turn requires a real database, migrations, and the full async configure path.

With `CIOTrackingClient`, test targets can supply a simple `MockCIOTrackingClient: CIOTrackingClient` struct that records calls without any SDK infrastructure.

### What It Does NOT Include

- `configure(_:)` / `startConfigure(_:onCompletion:)` — async or throws; not part of the tracking surface
- `flush()` — operational, not a tracking concern for sub-modules
- `enqueueEvent(_:)` — `package` access, a separate internal seam for synthetic events; not part of the public tracking contract

### Constraints

All requirements are `nonisolated` to match `CustomerIO`'s own implementations. Conforming types must guarantee Sendable safety themselves — the protocol does not enforce actor isolation. `CustomerIO` achieves this via `AsyncStream.Continuation.yield()`, which is synchronous and `Sendable`-safe. Mock implementations typically use simple atomic properties or accept the unchecked risk in test context.

The `AnyObject` constraint prevents value-type conformances. Without it, a value-type conformer stored as `any CIOTrackingClient` across isolation boundaries would require `@unchecked Sendable` waivers that the protocol cannot audit.

---

## Module Config Builder Pattern

Module configuration uses **value-type nested-closure builders**. Each module defines its own builder struct and a corresponding `SdkConfigBuilder` extension.

### Extension Signature

Defined in the module target:

```swift
// In CustomerIO_Location:
extension SdkConfigBuilder {
    public func location(_ configure: () -> LocationConfigBuilder) -> Self {
        appendingModule { LocationModule(config: configure().build()) }
    }
}
```

The closure returns a builder struct by value. No `@escaping` annotation is needed because the closure is called immediately and never stored.

### Builder Struct

One builder struct per module or sub-module config:

```swift
public struct LocationConfigBuilder {
    private var config: LocationConfig

    // LocationMode is required — a zero-arg builder would produce a config
    // indistinguishable from "module not registered", making it semantically
    // meaningless to call `.location { LocationConfigBuilder() }`.
    public init(_ mode: LocationMode) {
        config = LocationConfig(mode: mode)
    }

    public func visitedTilesCap(_ cap: Int) -> Self {
        var copy = self; copy.config.visitedTilesCap = cap; return copy
    }

    public func geofencing(_ configure: () -> GeofenceConfigBuilder) -> Self {
        var copy = self; copy.config.geofenceConfig = configure().build(); return copy
    }

    internal func build() -> LocationConfig { config }
}
```

### Required vs. Optional Init Arguments

| Scenario | `init` form |
|---|---|
| Zero-arg builder == "module inactive" (e.g. `LocationMode.off` is the off-switch) | Require the primary mode param: `init(_ mode: LocationMode)` |
| Builder always produces a valid default config (e.g. push defaults are well-defined) | No-arg `init()` is acceptable |

Omitting the `.location { … }` call entirely is the canonical way to not register a module. A builder whose only valid configuration is the default non-op state must not exist as a zero-arg form.

### `build()` Visibility

`build()` is `internal`. Callers never invoke it directly — only the `SdkConfigBuilder` extension does. This enforces that the builder is always consumed through the fluent API.

---

## Module Accessor Pattern

When an app imports a module, that module's target extends `CustomerIO` to expose a typed accessor:

```swift
// In CustomerIO_Location:
extension CustomerIO {
    public var location: LocationModule {
        get throws { try modules.require(LocationModule.self) }
    }
}
```

`cio.location` compiles only when the Location module is imported and initialized. Accessing a module that was never configured throws a descriptive error rather than returning nil or crashing.

`CustomerIO` owns modules via an internal `ModuleRegistry` — a concurrent-safe actor that holds `[ObjectIdentifier: any CIOModule]`.

---

## Objective-C Bridge

The main `CustomerIO` type is pure Swift (`actor`, `async throws`) and is not `@objc`-compatible. A thin `CIOBridge` facade class exposes a minimal surface for mixed-codebase and ObjC-only call sites.

`CIOBridge` is a plain `NSObject` subclass with `@objc`-annotated methods. Each method dispatches fire-and-forget into a `Task` on the Swift side. Properties passed as `NSDictionary` are converted to `[String: Variant]` inside the bridge. No completion handlers are exposed — tracking calls are best-effort by nature.

### Exposed Surface

| ObjC Method | Notes |
|---|---|
| `trackEvent:` / `trackEvent:properties:` | `properties` is `NSDictionary *` |
| `identify:` / `identify:traits:` | `traits` is `NSDictionary *` |
| `screenView:` / `screenView:properties:` / `screenView:category:` / `screenView:category:properties:` | `category` is `NSString *`; `properties` is `NSDictionary *` |
| `clearIdentify` | Logout / profile reset |
| `flush` | Explicit upload trigger; useful in notification extensions |
| `isConfigured` | `BOOL` property; safe to poll from ObjC without async |

### What Stays Swift-Only

- `configure(_:)` and all initialization — `async throws` is not bridgeable
- Module accessors (`.location`, `.push`, etc.)
- All aggregation, pipeline, and storage internals
- Any method with typed `async throws` return values

The wrapper SDKs (React Native, Flutter, Cordova) do not require ObjC compatibility — they call into the Swift API from their own Swift plugin layer.
