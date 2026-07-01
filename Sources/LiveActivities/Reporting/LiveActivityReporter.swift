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
    private let currentUserId: () -> String?
    private let deviceToken: () -> String?
    private let logger: Logger

    init(
        track: @escaping (String, [String: Any]) -> Void,
        currentUserId: @escaping () -> String?,
        deviceToken: @escaping () -> String?,
        logger: Logger
    ) {
        self.track = track
        self.currentUserId = currentUserId
        self.deviceToken = deviceToken
        self.logger = logger
    }

    // MARK: - Lifecycle events (local operations only)

    func reportStart(instanceUUID: String, notificationType: String, payload: [String: Any]?) {
        reportLifecycle(eventType: "start", instanceUUID: instanceUUID, notificationType: notificationType, payload: payload)
    }

    func reportUpdate(instanceUUID: String, notificationType: String, payload: [String: Any]?) {
        reportLifecycle(eventType: "update", instanceUUID: instanceUUID, notificationType: notificationType, payload: payload)
    }

    func reportEnd(instanceUUID: String, notificationType: String) {
        reportLifecycle(eventType: "end", instanceUUID: instanceUUID, notificationType: notificationType, payload: nil)
    }

    private func reportLifecycle(eventType: String, instanceUUID: String, notificationType: String, payload: [String: Any]?) {
        guard let deviceId = gatedDeviceId(for: "\(eventType) event") else { return }
        var properties: [String: Any] = [
            "eventType": eventType,
            "instanceUUID": instanceUUID,
            "deviceId": deviceId,
            "platform": "ios",
            "notificationType": notificationType
        ]
        if let payload, !payload.isEmpty {
            properties["payload"] = payload
        }
        track("Live Notification Event", properties)
        logger.debug(
            "Sent 'Live Notification Event' eventType=\(eventType) instanceUUID=\(instanceUUID) notificationType=\(notificationType)",
            "LiveActivities"
        )
    }

    // MARK: - Token registration events

    func sendPushToStartToken(notificationType: String, attributesType: String, pushToStartToken: String) {
        guard let deviceId = gatedDeviceId(for: "push_to_start token") else { return }
        track("Live Notification Token", [
            "registrationType": "push_to_start",
            "notificationType": notificationType,
            "platform": "ios",
            "deviceId": deviceId,
            "pushToStartToken": pushToStartToken,
            "attributesType": attributesType
        ])
        logger.debug(
            "Sent 'Live Notification Token' registrationType=push_to_start notificationType=\(notificationType) attributesType=\(attributesType)",
            "LiveActivities"
        )
    }

    func sendInstanceToken(notificationType: String, instanceUUID: String, instanceToken: String) {
        guard let deviceId = gatedDeviceId(for: "instance token") else { return }
        track("Live Notification Token", [
            "registrationType": "instance",
            "notificationType": notificationType,
            "platform": "ios",
            "deviceId": deviceId,
            "instanceUUID": instanceUUID,
            "instanceToken": instanceToken
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
        guard currentUserId() != nil else {
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

    // Pinned encoder for content-state payloads. `.millisecondsSince1970` matches the Android
    // convention; the exact wire contract (units / key casing) is still pending backend
    // confirmation (see plan decision #3).
    static let payloadEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    /// Encodes a `Codable` content state into a JSON object for the `payload` field.
    /// Returns `nil` when the state is not encodable as a JSON object.
    static func payload<State: Encodable>(from state: State) -> [String: Any]? {
        guard
            let data = try? payloadEncoder.encode(state),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
