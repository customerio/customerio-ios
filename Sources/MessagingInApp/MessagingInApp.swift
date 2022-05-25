import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance {
    func initialize(organizationId: String)
}

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
 */
public class MessagingInApp: MessagingInAppInstance {
    @Atomic public private(set) static var shared = MessagingInApp(customerIO: CustomerIO.shared)

    private var siteId: String!

    private var diGraphOverride: DICommon?
    private var diGraph: DICommon {
        diGraphOverride ?? DICommon.getInstance(siteId: siteId)
    }

    private var customerIOOverride: CustomerIOInstance?
    private var customerIO: CustomerIOInstance {
        customerIOOverride ?? CustomerIO.shared
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

    // for testing
    internal init(diGraph: DICommon, customerIO: CustomerIOInstance) {
        self.diGraphOverride = diGraph
        self.customerIOOverride = customerIO
        self.siteId = customerIO.siteId
    }

    private init(customerIO: CustomerIO) {
        if let siteId = customerIO.siteId {
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

        Gist.shared.setup(organizationId: organizationId)

        Gist.shared.delegate = self
    }
}

extension MessagingInApp: ProfileIdentifyHook {
    public func beforeIdentifiedProfileChange(oldIdentifier: String, newIdentifier: String) {}

    public func profileIdentified(identifier: String) {
        logger.debug("registering profile \(identifier) for in-app")

        Gist.shared.setUserToken(identifier)
    }

    public func beforeProfileStoppedBeingIdentified(oldIdentifier: String) {
        logger.debug("removing profile for in-app")

        Gist.shared.clearUserToken()
    }
}

extension MessagingInApp: GistDelegate {
    public func embedMessage(message: Message, elementId: String) {}

    // Aka: message opened
    public func messageShown(message: Message) {
        // the state of the SDK does not change if adding this queue task isn't successful so ignore result
        logger.debug("in-app message opened. \(message)")

        _ = queue.addTrackInAppDeliveryTask(deliveryId: message.messageId, event: .opened)
    }

    public func messageDismissed(message: Message) {
        logger.debug("in-app message dismissed. \(message)")
    }

    public func messageError(message: Message) {
        logger.error("error with in-app message. Message: \(message)")
    }

    public func action(message: Message, currentRoute: String, action: String) {
        logger.debug("in-app action made. \(action), \(message)")

        // a close action does not count as a clicked action.
        guard action != "gist://close" else {
            return
        }

        // the state of the SDK does not change if adding this queue task isn't successful so ignore result
        _ = queue.addTrackInAppDeliveryTask(deliveryId: message.messageId, event: .clicked)
    }
}
