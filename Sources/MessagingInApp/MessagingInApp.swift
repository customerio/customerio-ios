import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance: AutoMockable {
    func initialize(organizationId: String)
}

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
 */
public class MessagingInApp: MessagingInAppInstance {
    @Atomic public private(set) static var shared = MessagingInApp()

    private var siteId: String!

    private var diGraphOverride: DICommon?
    private var diGraph: DICommon {
        diGraphOverride ?? DICommon.getInstance(siteId: siteId)
    }

    private var moduleDiGraphOverride: DIMessagingInApp?
    private var moduleDiGraph: DIMessagingInApp {
        moduleDiGraphOverride ?? DIMessagingInApp.getInstance(siteId: siteId)
    }

    private var queue: Queue {
        diGraph.queue
    }

    private var jsonAdapter: JsonAdapter {
        diGraph.jsonAdapter
    }

    private var logger: Logger {
        diGraph.logger
    }

    private var inAppProvider: InAppProvider {
        moduleDiGraph.inAppProvider
    }

    // for testing
    internal init(diGraph: DICommon, moduleDiGraph: DIMessagingInApp, siteId: String) {
        self.diGraphOverride = diGraph
        self.moduleDiGraphOverride = moduleDiGraph
        self.siteId = siteId
    }

    private init() {
        if let siteId = CustomerIO.shared.siteId {
            self.siteId = siteId

            logger.info("MessagingInApp module setup with SDK")

            // Register module hooks now that the module is being initialized.
            let hooks = diGraph.hooksManager
            let moduleHookProvider = MessagingInAppModuleHookProvider(siteId: siteId)

            hooks.add(key: .messagingInApp, provider: moduleHookProvider)
        }
    }

    public func initialize(organizationId: String) {
        logger.debug("gist SDK being setup \(organizationId)")

        inAppProvider.initialize(organizationId: organizationId, delegate: self)
    }
}

extension MessagingInApp: ProfileIdentifyHook {
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

extension MessagingInApp: ScreenTrackingHook {
    public func screenViewed(name: String) {
        logger.debug("setting route for in-app to \(name)")

        inAppProvider.setRoute(name)
    }
}

extension MessagingInApp: GistDelegate {
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
