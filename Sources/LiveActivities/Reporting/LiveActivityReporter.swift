import CioInternalCommon
import Foundation

/// Maps Live Activities lifecycle and token registration to Customer.io CDP track events.
///
/// Emits two events — `Live Notification Event` (start/update/end) and
/// `Live Notification Token` (push_to_start/instance) — carrying the contract fields under
/// the event's `properties`. The data pipeline owns batching, retry and flush, so this type
/// is a thin mapper.
///
/// Live Activities require an identified user and a registered device token: any event
/// emitted while anonymous or before a device token exists is dropped (logged at debug),
/// matching the Android contract. The `userId` itself rides the CDP identify context, so it
/// is not duplicated into `properties`.
final class LiveActivityReporter: @unchecked Sendable {
    private let track: (String, [String: Any]) -> Void
    private let isUserIdentified: () -> Bool
    private let deviceToken: () -> String?
    private let logger: Logger

    init(
        track: @escaping (String, [String: Any]) -> Void,
        isUserIdentified: @escaping () -> Bool,
        deviceToken: @escaping () -> String?,
        logger: Logger
    ) {
        self.track = track
        self.isUserIdentified = isUserIdentified
        self.deviceToken = deviceToken
        self.logger = logger
    }

    // MARK: - Lifecycle events (local operations only)

    /// Reports a `start`: sends both the static `attributes` object and the dynamic
    /// `contentState` object (both nil-omitted if not encodable).
    func reportStart(instanceUUID: String, notificationType: String, attributes: [String: Any]?, contentState: [String: Any]?) {
        reportLifecycle(
            eventType: LiveActivityContract.EventType.start,
            instanceUUID: instanceUUID,
            notificationType: notificationType,
            attributes: attributes,
            contentState: contentState
        )
    }

    /// Reports an `update`: sends the dynamic `contentState` object.
    func reportUpdate(instanceUUID: String, notificationType: String, contentState: [String: Any]?) {
        reportLifecycle(
            eventType: LiveActivityContract.EventType.update,
            instanceUUID: instanceUUID,
            notificationType: notificationType,
            attributes: nil,
            contentState: contentState
        )
    }

    /// Reports an `end`: optionally sends a final `contentState` object (nil-omitted).
    func reportEnd(instanceUUID: String, notificationType: String, contentState: [String: Any]? = nil) {
        reportLifecycle(
            eventType: LiveActivityContract.EventType.end,
            instanceUUID: instanceUUID,
            notificationType: notificationType,
            attributes: nil,
            contentState: contentState
        )
    }

    private func reportLifecycle(eventType: String, instanceUUID: String, notificationType: String, attributes: [String: Any]?, contentState: [String: Any]?) {
        guard let deviceId = gatedDeviceId(for: "\(eventType) event") else { return }
        var properties: [String: Any] = [
            LiveActivityContract.Key.eventType: eventType,
            LiveActivityContract.Key.cioInstanceId: instanceUUID,
            LiveActivityContract.Key.deviceId: deviceId,
            LiveActivityContract.Key.platform: LiveActivityContract.platform,
            LiveActivityContract.Key.notificationType: notificationType
        ]
        if let attributes, !attributes.isEmpty {
            properties[LiveActivityContract.Key.attributes] = attributes
        }
        if let contentState, !contentState.isEmpty {
            properties[LiveActivityContract.Key.contentState] = contentState
        }
        track(LiveActivityContract.Event.lifecycle, properties)
        logger.debug(
            "Sent 'Live Notification Event' eventType=\(eventType) instanceUUID=\(instanceUUID) notificationType=\(notificationType)",
            "LiveActivities"
        )
    }

    // MARK: - Token registration events

    func sendPushToStartToken(notificationType: String, attributesType: String, pushToStartToken: String) {
        guard let deviceId = gatedDeviceId(for: "push_to_start token") else { return }
        track(LiveActivityContract.Event.token, [
            LiveActivityContract.Key.registrationType: LiveActivityContract.RegistrationType.pushToStart,
            LiveActivityContract.Key.notificationType: notificationType,
            LiveActivityContract.Key.platform: LiveActivityContract.platform,
            LiveActivityContract.Key.deviceId: deviceId,
            LiveActivityContract.Key.pushToStartToken: pushToStartToken,
            LiveActivityContract.Key.attributesType: attributesType
        ])
        logger.debug(
            "Sent 'Live Notification Token' registrationType=push_to_start notificationType=\(notificationType) attributesType=\(attributesType)",
            "LiveActivities"
        )
    }

    func sendInstanceToken(notificationType: String, instanceUUID: String, instanceToken: String) {
        guard let deviceId = gatedDeviceId(for: "instance token") else { return }
        track(LiveActivityContract.Event.token, [
            LiveActivityContract.Key.registrationType: LiveActivityContract.RegistrationType.instance,
            LiveActivityContract.Key.notificationType: notificationType,
            LiveActivityContract.Key.platform: LiveActivityContract.platform,
            LiveActivityContract.Key.deviceId: deviceId,
            LiveActivityContract.Key.cioInstanceId: instanceUUID,
            LiveActivityContract.Key.instanceToken: instanceToken
        ])
        logger.debug(
            "Sent 'Live Notification Token' registrationType=instance notificationType=\(notificationType) instanceUUID=\(instanceUUID)",
            "LiveActivities"
        )
    }

    // MARK: - Gate

    /// Returns the device token when an identified user and a non-empty device token both
    /// exist; otherwise logs the reason and returns `nil` so the caller drops the event.
    private func gatedDeviceId(for what: String) -> String? {
        // isUserIdentified is updated synchronously on identify(), so an identify() immediately
        // followed by startLiveActivity() is reported rather than dropped by a stale flag.
        guard isUserIdentified() else {
            logger.debug("Live Notifications require an identified user; dropping \(what).", "LiveActivities")
            return nil
        }
        guard let token = deviceToken(), !token.isEmpty else {
            logger.debug("No device token available yet; dropping \(what).", "LiveActivities")
            return nil
        }
        return token
    }

    // MARK: - Payload encoding

    // Pinned encoder for the `attributes` / `contentState` objects. Date fields are modeled
    // with `EpochSecondsDate`, which encodes to an epoch-second number, so no
    // `dateEncodingStrategy` is needed here — this keeps the local CDP-event wire format
    // byte-for-byte consistent with what ActivityKit decodes on a server push.
    static let payloadEncoder = JSONEncoder()

    /// Encodes a `Codable` value (`Attributes` or `ContentState`) into a JSON object.
    /// Returns `nil` when the value is not encodable as a JSON object.
    static func encode(_ value: some Encodable) -> [String: Any]? {
        guard
            let data = try? payloadEncoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
