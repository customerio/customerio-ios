import CioTracking
import Common
import Foundation
import Gist

internal class MessagingInAppImplementation: MessagingInAppInstance {
    private let logger: Logger
    private var queue: Queue
    private var jsonAdapter: JsonAdapter
    private var inAppProvider: InAppProvider
    private var eventListener: InAppEventListener?

    private var identifier: String?

    init(diGraph: DIGraph) {
        self.logger = diGraph.logger
        self.queue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.inAppProvider = diGraph.inAppProvider
        self.identifier = diGraph.profileStore.identifier
    }

    func initialize(organizationId: String) {
        inAppProvider.initialize(organizationId: organizationId, delegate: self)

        if let identifier = identifier {
            inAppProvider.setProfileIdentifier(identifier)
        }
    }

    func initialize(organizationId: String, eventListener: InAppEventListener) {
        self.eventListener = eventListener
        initialize(organizationId: organizationId)
    }
}

extension MessagingInAppImplementation: ProfileIdentifyHook {
    public func beforeIdentifiedProfileChange(oldIdentifier: String, newIdentifier: String) {}

    public func profileIdentified(identifier: String) {
        logger.debug("registering profile \(identifier) for in-app")

        inAppProvider.setProfileIdentifier(identifier)
    }

    public func beforeProfileStoppedBeingIdentified(oldIdentifier: String) {
        logger.debug("removing profile for in-app")

        inAppProvider.clearIdentify()
    }
}

extension MessagingInAppImplementation: ScreenTrackingHook {
    public func screenViewed(name: String) {
        logger.debug("setting route for in-app to \(name)")

        inAppProvider.setRoute(name)
    }
}

extension MessagingInAppImplementation: GistDelegate {
    public func embedMessage(message: Message, elementId: String) {}

    // Aka: message opened
    public func messageShown(message: Message) {
        logger.debug("in-app message opened. \(message.describeForLogs)")

        eventListener?.messageShown(message: InAppMessage(gistMessage: message))

        if let deliveryId = getDeliveryId(from: message) {
            // the state of the SDK does not change if adding this queue task isn't successful so ignore result
            _ = queue.addTrackInAppDeliveryTask(deliveryId: deliveryId, event: .opened)
        }
    }

    public func messageDismissed(message: Message) {
        logger.debug("in-app message dismissed. \(message.describeForLogs)")

        eventListener?.messageDismissed(message: InAppMessage(gistMessage: message))
    }

    public func messageError(message: Message) {
        logger.error("error with in-app message. \(message.describeForLogs)")

        eventListener?.errorWithMessage(message: InAppMessage(gistMessage: message))
    }

    public func action(message: Message, currentRoute: String, action: String, name: String) {
        logger.debug("in-app action made. \(action), \(message.describeForLogs)")

        // a close action does not count as a clicked action.
        guard action != "gist://close" else {
            return
        }

        if let deliveryId = getDeliveryId(from: message) {
            // the state of the SDK does not change if adding this queue task isn't successful so ignore result
            _ = queue.addTrackInAppDeliveryTask(deliveryId: deliveryId, event: .clicked)
        }

        eventListener?.messageActionTaken(
            message: InAppMessage(gistMessage: message),
            action: action,
            name: name
        )
    }

    private func getDeliveryId(from message: Message) -> String? {
        guard let deliveryId = message.gistProperties.campaignId else {
            return nil
        }

        return deliveryId
    }
}
