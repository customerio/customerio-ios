# Feature Spec — Screen Tracking

---

## Overview

The SDK provides two opt-in mechanisms for tracking screen views: a UIKit
swizzle-based approach and a SwiftUI `ViewModifier`. Both ultimately call
`CustomerIO.screen(_:category:properties:)`, which is `nonisolated` and safe
to invoke from any context without `await`.

---

## Method Signature

```swift
public nonisolated func screen(
    _ name: String,
    category: String? = nil,
    properties: [String: Variant] = [:]
)
```

`category` is a first-class field on the screen event envelope (matching the
Segment spec used by the old SDK), not folded into the `properties` bag.

---

## UIKit — Swizzle-Based Auto-Tracking

UIKit swizzle-based auto-tracking is opt-in and off by default.

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .autoTrackScreenViews(true)
    .build()
```

### Implementation

- Isolated to a single file: `CustomerIO/ScreenTracking/AutoTrackingSwizzle.swift`
- Guarded by `#if canImport(UIKit)`
- Swizzles `UIViewController.viewDidAppear(_:)`
- Bridges back into the `CustomerIO` actor via a `Task` — never a direct
  synchronous call from swizzled context

The UIKit swizzle omits `category` because it cannot be inferred from a
`UIViewController`; `name` is derived from the view controller's class name
as a last-resort fallback.

---

## SwiftUI — `cio_trackScreen` ViewModifier

A `cio_trackScreen(_:category:)` modifier is provided for SwiftUI views.

```swift
MyDetailView()
    .cio_trackScreen("Product Detail", category: "Commerce")
```

The `cio_` prefix namespaces the method against similar modifiers from other
analytics SDKs, where naming collisions are a known problem in mixed-SDK projects.

Screen names are provided as explicit string arguments. Auto-deriving names from
Swift type names (via `String(describing: Self.self)`) is deliberately not a
primary API — type names are compiler-internal identifiers that can change
silently across refactors without breaking the build.

### Avoiding Static Globals via SwiftUI Environment

Rather than a static `CustomerIO.shared`, the modifier reads the `CustomerIO`
instance from SwiftUI's environment. The app injects it once at the root view:

```swift
@main
struct MyApp: App {
    let cio = CustomerIO()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.customerIO, cio)
        }
    }
}
```

### Environment Key

Defined in `CustomerIO/ScreenTracking/CustomerIOEnvironmentKey.swift`:

```swift
private struct CustomerIOEnvironmentKey: EnvironmentKey {
    static let defaultValue: CustomerIO? = nil
}

extension EnvironmentValues {
    public var customerIO: CustomerIO? {
        get { self[CustomerIOEnvironmentKey.self] }
        set { self[CustomerIOEnvironmentKey.self] = newValue }
    }
}
```

### Modifier Implementation

`CustomerIO/ScreenTracking/ScreenTrackingModifier.swift`:

```swift
struct CIOScreenTrackingModifier: ViewModifier {
    let screenName: String
    let category: String?

    @Environment(\.customerIO) private var customerIO

    func body(content: Content) -> some View {
        content.onAppear {
            customerIO?.screen(screenName, category: category)
        }
    }
}
```

`CustomerIO/ScreenTracking/View+CIOTrackScreen.swift`:

```swift
extension View {
    public func cio_trackScreen(_ name: String, category: String? = nil) -> some View {
        modifier(CIOScreenTrackingModifier(screenName: name, category: category))
    }
}
```

### Testing and Xcode Previews

Inject a real or mock `CustomerIO` via the environment key:

```swift
MyView()
    .environment(\.customerIO, mockCIO)
```

If no instance is injected, the modifier silently no-ops (`customerIO` is `nil`
by default) — safe for test targets and Previews that don't configure the SDK.

---

## ObjC Bridge

`CIOBridge` exposes screen tracking to Objective-C:

| ObjC Method | Notes |
|-------------|-------|
| `screenView:` | Name only |
| `screenView:properties:` | `properties` is `NSDictionary *` |
| `screenView:category:` | `category` is `NSString *` |
| `screenView:category:properties:` | Full signature |

Server-side payloads are structurally identical to explicit `screen()` calls.

---

## Screen View Routing Mode

See `TODO.md` item 13 — `CIOScreenViewMode` (`.all` vs. `.inApp`) controls
whether screen events are sent to CDP only or also to the in-app messaging
system. Not yet implemented.
