import Foundation

/// Single source of truth for the Live Activities CDP wire contract.
///
/// Event names, property keys, and enumerated values are shared with the Android SDK
/// (`LiveNotificationLifecycleClient`) so one backend contract serves both platforms.
/// Changing any value here changes the wire format — keep it in lockstep with Android.
enum LiveActivityContract {
    /// Track event names.
    enum Event {
        /// Lifecycle event: start / update / end.
        static let lifecycle = "Live Notification Event"
        /// Token registration event: push_to_start / instance.
        static let token = "Live Notification Token"
    }

    /// Property keys carried under an event's `properties`.
    enum Key {
        static let eventType = "eventType"
        static let registrationType = "registrationType"
        static let instanceUUID = "instanceUUID"
        static let deviceId = "deviceId"
        static let platform = "platform"
        static let notificationType = "notificationType"
        /// Static attributes object (encoded `Attributes`). Sent on `start` only.
        static let attributes = "attributes"
        /// Dynamic content-state object (encoded `ContentState`). Sent on `start`/`update`,
        /// and optionally on `end`.
        static let contentState = "contentState"
        static let pushToStartToken = "pushToStartToken"
        static let attributesType = "attributesType"
        static let instanceToken = "instanceToken"
    }

    /// `eventType` values for the lifecycle event.
    enum EventType {
        static let start = "start"
        static let update = "update"
        static let end = "end"
    }

    /// `registrationType` values for the token event.
    enum RegistrationType {
        static let pushToStart = "push_to_start"
        static let instance = "instance"
    }

    /// `platform` value for this SDK.
    static let platform = "ios"
}
