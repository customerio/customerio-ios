import CioInternalCommon
import Foundation
import UIKit

public protocol GistDelegate: AnyObject {
    func embedMessage(message: Message, elementId: String)
    func messageShown(message: Message)
    func messageDismissed(message: Message)
    func messageError(message: Message)
    func action(message: Message, currentRoute: String, action: String, name: String)
    func setEventListener(_ eventListener: InAppEventListener?)
}

// sourcery: InjectRegisterShared = "GistDelegate"
// sourcery: InjectSingleton
/// Default implementation of `GistDelegate`.
/// This class is responsible for handling events received when an in-app message is shown, dismissed,
/// received an error, or an action is taken.
/// This class is also responsible for sending events to client callbacks using `InAppEventListener`
/// protocol for similar events.
class GistDelegateImpl: GistDelegate {
    private let logger: Logger
    private let eventBusHandler: EventBusHandler
    private var eventListener: InAppEventListener?
    private let threadUtil: ThreadUtil

    // In-memory set of `campaignDeliveryId` values for which we've already posted
    // a `messageShown` (`opened`) metric this session. Used to suppress duplicate
    // metric emissions when Gist invokes `messageShown` more than once for the
    // same delivery. Lifetime is GistDelegateImpl-scoped (per-process); the
    // backend already dedupes `(deliveryID, opened)` pairs, so this is pure
    // noise reduction. Guarded by `seenMessageShownLock`.
    private var seenMessageShownDeliveryIds: Set<String> = []
    private let seenMessageShownLock = NSLock()

    init(logger: Logger, eventBusHandler: EventBusHandler) {
        self.logger = logger
        self.eventBusHandler = eventBusHandler
        self.threadUtil = DIGraphShared.shared.threadUtil
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        self.eventListener = eventListener
    }

    public func embedMessage(message: Message, elementId: String) {}

    public func messageShown(message: Message) {
        logger.logWithModuleTag("Message shown: \(message.describeForLogs)", level: .debug)

        if let deliveryId = message.campaignDeliveryId {
            if shouldPostMessageShownMetric(forDeliveryId: deliveryId) {
                eventBusHandler.postEvent(TrackInAppMetricEvent(deliveryID: deliveryId, event: InAppMetric.opened.rawValue))
            } else {
                logger.logWithModuleTag("Skipping duplicate messageShown metric for deliveryId: \(deliveryId)", level: .debug)
            }
        }
        // To ensure the keyboard is dismissed on displaying an in-app message,
        // Update UI on main thread only.
        // Dismiss keyboard on showing the message to prevent gap between
        // displaying the in-app message and dismissing the keyboard.
        threadUtil.runMain {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        eventListener?.messageShown(message: InAppMessage(gistMessage: message))
    }

    public func messageDismissed(message: Message) {
        logger.logWithModuleTag("Message dismissed: \(message.describeForLogs)", level: .debug)

        eventListener?.messageDismissed(message: InAppMessage(gistMessage: message))
    }

    public func messageError(message: Message) {
        logger.logWithModuleTag("Message error: \(message.describeForLogs)", level: .debug)

        eventListener?.errorWithMessage(message: InAppMessage(gistMessage: message))
    }

    public func action(message: Message, currentRoute: String, action: String, name: String) {
        logger.logWithModuleTag("Message action: \(action), \(message.describeForLogs)", level: .debug)

        // a close action does not count as a clicked action.
        if action != "gist://close" {
            if let deliveryId = message.campaignDeliveryId {
                eventBusHandler.postEvent(TrackInAppMetricEvent(deliveryID: deliveryId, event: InAppMetric.clicked.rawValue, params: ["actionName": name, "actionValue": action]))
            }
        }

        eventListener?.messageActionTaken(
            message: InAppMessage(gistMessage: message),
            actionValue: action,
            actionName: name
        )
    }

    /// Returns true the first time a given `deliveryId` is observed (and records it),
    /// false on subsequent calls. Thread-safe via `seenMessageShownLock`.
    private func shouldPostMessageShownMetric(forDeliveryId deliveryId: String) -> Bool {
        seenMessageShownLock.lock()
        defer { seenMessageShownLock.unlock() }

        return seenMessageShownDeliveryIds.insert(deliveryId).inserted
    }
}

private extension Message {
    var campaignDeliveryId: String? {
        guard let deliveryId = gistProperties.campaignId else {
            return nil
        }

        return deliveryId
    }
}
