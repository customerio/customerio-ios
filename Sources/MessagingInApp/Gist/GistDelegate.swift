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
class GistDelegateImpl: GistDelegate {
    private let logger: Logger
    private let eventBusHandler: EventBusHandler

    private var eventListener: InAppEventListener?

    init(logger: Logger, eventBusHandler: EventBusHandler) {
        self.logger = logger
        self.eventBusHandler = eventBusHandler
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        self.eventListener = eventListener
    }

    public func embedMessage(message: Message, elementId: String) {}

    public func messageShown(message: Message) {
        logger.debug("[InApp] Message shown: \(message.describeForLogs)")

        if let deliveryId = getDeliveryId(from: message) {
            eventBusHandler.postEvent(TrackInAppMetricEvent(deliveryID: deliveryId, event: InAppMetric.opened.rawValue))
        }

        eventListener?.messageShown(message: InAppMessage(gistMessage: message))
    }

    public func messageDismissed(message: Message) {
        logger.debug("[InApp] Message dismissed: \(message.describeForLogs)")

        eventListener?.messageDismissed(message: InAppMessage(gistMessage: message))
    }

    public func messageError(message: Message) {
        logger.debug("[InApp] Message error: \(message.describeForLogs)")

        eventListener?.errorWithMessage(message: InAppMessage(gistMessage: message))
    }

    public func action(message: Message, currentRoute: String, action: String, name: String) {
        logger.debug("[InApp] Message action: \(action), \(message.describeForLogs)")

        // a close action does not count as a clicked action.
        if action != "gist://close" {
            if let deliveryId = getDeliveryId(from: message) {
                eventBusHandler.postEvent(TrackInAppMetricEvent(deliveryID: deliveryId, event: InAppMetric.clicked.rawValue, params: ["actionName": name, "actionValue": action]))
            }
        }

        eventListener?.messageActionTaken(
            message: InAppMessage(gistMessage: message),
            actionValue: action,
            actionName: name
        )
    }

    private func getDeliveryId(from message: Message) -> String? {
        guard let deliveryId = message.gistProperties.campaignId else {
            return nil
        }

        return deliveryId
    }
}
