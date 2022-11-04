import CioTracking
import Common
import Foundation
import Gist

internal class MessagingInAppImplementation: MessagingInAppInstance {
    private let logger: Logger
    private var queue: Queue
    private var jsonAdapter: JsonAdapter
    private var inAppProvider: InAppProvider

    init(siteId: SiteId, diGraph: DIGraph) {
        self.logger = diGraph.logger
        self.queue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.inAppProvider = diGraph.inAppProvider
    }

    func initialize(organizationId: String) {
        logger.debug("gist SDK being setup \(organizationId)")

        inAppProvider.initialize(organizationId: organizationId, delegate: self)
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
        // the state of the SDK does not change if adding this queue task isn't successful so ignore result
        logger.debug("in-app message opened. \(message.describeForLogs)")

        if let deliveryId = getDeliveryId(from: message) {
            // the state of the SDK does not change if adding this queue task isn't successful so ignore result
            _ = queue.addTrackInAppDeliveryTask(deliveryId: deliveryId, event: .opened)
        }
    }

    public func messageDismissed(message: Message) {
        logger.debug("in-app message dismissed. \(message.describeForLogs)")
    }

    public func messageError(message: Message) {
        logger.error("error with in-app message. \(message.describeForLogs)")
    }

    public func action(message: Message, currentRoute: String, action: String) {
        logger.debug("in-app action made. \(action), \(message.describeForLogs)")

        // a close action does not count as a clicked action.
        guard action != "gist://close" else {
            return
        }

        if let deliveryId = getDeliveryId(from: message) {
            // the state of the SDK does not change if adding this queue task isn't successful so ignore result
            _ = queue.addTrackInAppDeliveryTask(deliveryId: deliveryId, event: .clicked)
        }
    }

    private func getDeliveryId(from message: Message) -> String? {
        guard let deliveryId = message.gistProperties.campaignId else {
            logger
                .error("""
                in-app message opened but does not contain a delivery id.
                Not able to track event. \(message.describeForLogs)
                """)
            return nil
        }

        return deliveryId
    }
}
