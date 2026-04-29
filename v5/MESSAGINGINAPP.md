# Messaging In-App — Design Specification

**Status:** Stub — implementation not yet started
**Last updated:** March 17, 2026

---

## Overview

The In-App Messaging module displays contextual messages to the user while the
app is in the foreground. Messages are triggered by SDK events (profile
identified, screen viewed) and rendered by a display engine (currently Gist;
a new engine is under consideration).

`MessagingInAppModule` is registered via `SdkConfigBuilder` and conforms to
`CIOModule`. It subscribes to SDK-level events on the `CommonEventBus` to
forward user and screen context to the display engine.

---

## Goals

- Initialize and configure the in-app message display engine on `configure()`.
- Forward identity changes to the engine so messages can be personalised and
  targeted by user segment.
- Forward screen view events to the engine for trigger matching (show message X
  when screen Y is viewed).
- Reset engine state on `ResetEvent` (user logout / `clearIdentify()`).
- Provide a callback surface for the app to react to message lifecycle events
  (message displayed, dismissed, action taken).

---

## Event Bus Subscriptions

`MessagingInAppModule` subscribes to four SDK-level event types on the
`CommonEventBus` passed into `configure()`:

| Event | Engine action |
|---|---|
| `ProfileIdentifiedEvent(identifier:)` | `engine.setUserToken(identifier)` |
| `AnonymousProfileIdentifiedEvent(identifier:)` | `engine.setAnonymousId(identifier)` |
| `ScreenViewedEvent(name:)` | `engine.screenViewed(name)` — checks active triggers |
| `ResetEvent` | `engine.resetState()` — clears user context and pending messages |

These event types are defined in `Sources/CustomerIO/Events/`.

---

## Display Engine Interface

The specific engine API is TBD and depends on which display engine is chosen.
The module will hold a reference to the engine and forward calls to it. The
engine is expected to be `@MainActor`-isolated (UI work) — the module will
dispatch to `MainActor` internally.

Current assumption: the engine is Gist-compatible (`CustomerIO/in-app-messaging-ios`).
A replacement engine is under consideration but no decision has been made.

---

## Configuration

No `MessagingInAppConfig` struct exists yet. When the engine is wired, a config
type will be added and attached to `SdkConfigBuilder` following the same pattern
as other modules:

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .messagingInApp(MessagingInAppConfig(/* ... */))
    .build()
```

---

## Current Implementation State

`MessagingInAppModule` is a stub actor. `configure()` contains two `// TODO`
comments:

```swift
// TODO: initialise in-app message display engine
// TODO: subscribe to identity change events via CommonEventBus
```

No engine is wired, no event subscriptions are registered. The module compiles
and can be included in an `SdkConfig`, but has no runtime behaviour.

---

## Outstanding Work

See `TODO.md` item 6 for the full checklist. Summary:

- `configure()`: initialise the display engine.
- Subscribe to `ProfileIdentifiedEvent` → call engine's `setUserToken(_:)`.
- Subscribe to `AnonymousProfileIdentifiedEvent` → call engine's `setAnonymousId(_:)`.
- Subscribe to `ScreenViewedEvent` → forward to engine for trigger matching.
- Subscribe to `ResetEvent` → call engine's `resetState()`.

---

## Open Questions

- **Engine selection.** Continue with Gist (`in-app-messaging-ios`), build a new
  engine, or adopt a third-party renderer? This decision gates all implementation
  work.
- **Engine API surface.** What methods does the chosen engine expose? The event
  subscription wiring above assumes a simple delegate-style API; actual method
  names and parameter types depend on the engine.
- **Message lifecycle callbacks.** What events does the app need to observe?
  Common candidates: `onMessageDisplayed`, `onMessageDismissed`,
  `onMessageActionTaken(url:)`. How are these delivered (delegate, closure,
  `EventBus`)?
- **Storage.** Does the module need its own database tables (e.g. for message
  history or suppression state)? If so, a `MessagingInAppStorageMigration` will
  be needed following the module extension pattern.
- **macOS support.** In-app rendering on macOS (Catalyst or native) is unclear.
  Should the module be gated `#if os(iOS)` like Geofencing?
