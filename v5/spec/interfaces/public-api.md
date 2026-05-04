# Public API — CustomerIO iOS SDK

---

## Overview

This document describes the public API surface of the reimplemented SDK and
notes breaking changes relative to the previous `cdp-analytics-swift`-based SDK.

---

## `CustomerIO` (Root Actor)

```swift
public actor CustomerIO {

    public init()

    // Preferred startup — calls activateModulesForLaunch synchronously
    public func startConfigure(_ config: SdkConfig, onCompletion: (@Sendable (Error?) -> Void)?)

    // Manual startup — caller must call activateModulesForLaunch first
    public func activateModulesForLaunch(_ config: SdkConfig)
    public func configure(_ config: SdkConfig) async throws

    // Tracking — nonisolated, no await required
    public nonisolated func track(_ name: String, properties: [String: Variant] = [:])
    public nonisolated func identify(_ profileId: String, traits: [String: Variant] = [:])
    public nonisolated func screen(_ name: String, category: String? = nil, properties: [String: Variant] = [:])
    public nonisolated func clearIdentify()
    public nonisolated func setProfileAttributes(_ traits: [String: Variant])
    public nonisolated func setDeviceAttributes(_ attributes: [String: Variant])

    // Operations
    public func flush() async
    public func reset() async
}
```

### Breaking Changes vs. Previous SDK

| Change | Old | New |
|--------|-----|-----|
| No static `shared` singleton | `CustomerIO.shared` | `let cio = CustomerIO()` |
| Event properties are `[String: Variant]` | `[String: Any]` | `[String: Variant]` |
| `identify` no longer takes a `userId` label | `identify(userId:traits:)` | `identify(_:traits:)` |
| `screen` has a first-class `category` parameter | `properties["category"]` | `category: String?` |
| No CocoaPods distribution | `.podspec` | SPM only |

---

## `SdkConfigBuilder`

```swift
public struct SdkConfigBuilder {
    public init(cdpApiKey: String)
    public func logLevel(_ level: CIOLogLevel) -> Self
    public func autoTrackScreenViews(_ enabled: Bool) -> Self

    /// Number of queued events that triggers an immediate upload. Default: 20.
    public func flushAt(_ count: Int) -> Self

    /// Maximum seconds events may sit in the queue before a deferred upload
    /// fires. After the first post-flush event arrives, a one-shot timer starts
    /// for this duration. Reaching `flushAt` or entering the background cancels
    /// the timer and uploads immediately. Default: 30.
    public func flushInterval(_ interval: TimeInterval) -> Self

    public func databaseKeyProvider(_ provider: any DatabaseKeyProvider) -> Self

    // Module builder extensions (defined in their respective module targets):
    public func location(_ configure: () -> LocationConfigBuilder) -> Self
    public func geofencing(_ configure: () -> GeofenceConfigBuilder) -> Self
    public func push(_ configure: () -> PushConfigBuilder) -> Self

    public func build() -> SdkConfig
}
```

---

## `SdkConfig`

```swift
public struct SdkConfig: Sendable {
    public let cdpApiKey: String
    public let logLevel: CIOLogLevel
    public let autoTrackScreenViews: Bool
    // Module configs stored as optional sub-structs:
    public let locationConfig: LocationConfig?
    public let geofenceConfig: GeofenceConfig?
    public let pushConfig: PushConfig?
}
```

---

## Module Accessors

Module accessors are defined as extensions in each module's target:

```swift
// Throws if module was not registered
extension CustomerIO {
    public var location: LocationModule { get throws }
    public var geofencing: GeofencingModule { get throws }
    public var push: MessagingPushModule { get throws }
    public var liveActivities: LiveActivitiesModule { get throws }  // @available(iOS 16.1, *)
}
```

---

## `MessagingPushModule`

```swift
public actor MessagingPushModule: CIOModule {

    // App delegate forwarding
    public func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) async throws
    public nonisolated func didFailToRegisterForRemoteNotifications(withError error: Error)

    // Manual push handling (when autoTrackPushEvents is false)
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    )
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    )

    // Event handler registration
    public nonisolated func addEventHandler(_ handler: any PushEventHandler)
    public nonisolated func removeEventHandler(_ handler: any PushEventHandler)

    // Device registration
    /// Removes this device from the current user's backend profile, stopping push
    /// delivery. Does not affect local identity, system push permission, or stored token.
    /// Re-registration is automatic on the next identify() call.
    public nonisolated func unregisterDevice()
}
```

### Breaking Changes vs. Previous SDK

| Change | Old | New |
|--------|-----|-----|
| Single unified push target | `MessagingPushAPN` + `MessagingPushFCM` | `MessagingPush` |
| No direct Firebase dependency | SDK imported `firebase-ios-sdk` | App wraps Firebase via `PushTokenProvider` |
| `deleteDeviceToken()` renamed | `deleteDeviceToken()` | `unregisterDevice()` |

---

## `LocationModule`

```swift
public actor LocationModule: CIOModule, ProfileEnhancing {
    public func setLastKnownLocation(latitude: Double, longitude: Double, accuracy: Double)
    public func requestLocationUpdate()
}
```

---

## `GeofencingModule`

```swift
public actor GeofencingModule: CIOModule {
    // Geofence event handlers (exact API TBD)
}
```

---

## Objective-C Bridge (`CIOBridge`)

`CIOBridge` is a plain `NSObject` subclass for mixed-codebase and ObjC-only
call sites. `configure()` and all `async throws` API are not bridged.

| ObjC Method | Notes |
|-------------|-------|
| `trackEvent:` / `trackEvent:properties:` | `properties` is `NSDictionary *` |
| `identify:` / `identify:traits:` | `traits` is `NSDictionary *` |
| `screenView:` / `screenView:properties:` / `screenView:category:` / `screenView:category:properties:` | |
| `clearIdentify` | |
| `flush` | |
| `isConfigured` | `BOOL` property |

---

## `CIOTrackingClient` Protocol

Narrow protocol for sub-modules (e.g. `MessagingPushModule`) that need to emit
tracking events without holding a full `CustomerIO` reference. Enables mock
substitution in tests.

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

---

## `PushTokenProvider` Protocol

```swift
public protocol PushTokenProvider: Sendable {
    /// Called when APNs delivers a raw device token. Return the FCM token
    /// string (for Firebase wrappers) or convert the raw data to a hex string
    /// (for APNs). Return nil if the token will arrive asynchronously via
    /// observeTokenRefresh.
    func tokenFromAPNSData(_ deviceToken: Data) async throws -> String?

    /// Called once at module startup. Invoke handler whenever the token changes.
    func observeTokenRefresh(_ handler: @Sendable @escaping (String) -> Void) async
}
```

The SDK-supplied `APNPushProvider` implements this protocol for APNs apps.
FCM apps provide their own implementation wrapping `Firebase.Messaging`.

---

## Outstanding Items

The following public API items are specified but not yet implemented:

| Item | TODO ref |
|------|----------|
| Custom API host override in `SdkConfigBuilder` | TODO 15 |
| `registerDeviceToken(_ token: String)` for same-user push re-opt-in | TODO 16b |
| `getRegisteredDeviceToken()` / `registeredDeviceToken` property | TODO 16c |
| Screen view routing mode (`CIOScreenViewMode`) | TODO 13 |
| Application lifecycle event auto-tracking | TODO 14 |
