# ADR 006 — No Direct Firebase Dependency in Push Module

**Status:** Accepted

---

## Context

The previous `MessagingPushFCM` target depended directly on `firebase-ios-sdk`.
Apps using APNs were forced to include Firebase in their dependency graph anyway,
and apps already using Firebase were loading it twice (once from their own import
and once through the SDK). Firebase is a large dependency with significant binary
size and initialization overhead.

## Decision

The `MessagingPush` module has **no direct dependency on Firebase**. All Firebase
interaction is abstracted behind the `FirebaseService` and `PushTokenProvider`
protocols. Apps that use FCM implement `PushTokenProvider` by wrapping their own
`Firebase.Messaging` instance and passing it to `PushConfigBuilder(provider:)`.

The SDK-supplied `APNPushProvider` implements `PushTokenProvider` for APNs apps
and has no Firebase paths.

## Consequences

### What this enables

- APNs apps incur no binary overhead from Firebase code — there is none in the SDK.
- Apps already using Firebase are not double-loading it through the SDK.
- `PushTokenProvider` conformance is trivially mockable in tests with no Firebase
  dependency in the test target.
- If Firebase changes its token delivery API, only the app's thin wrapper adapts;
  the SDK module is unchanged.
- `CustomerIO_MessagingPush` has no SPM dependency on `firebase-ios-sdk` and
  never will.

### What this constrains

- FCM apps must write a small `PushTokenProvider` conformance wrapping their own
  `Firebase.Messaging` instance. This is a one-time ~10 line implementation.
- The SDK cannot automatically configure Firebase behavior (e.g. auto-init) —
  the app controls Firebase entirely.
