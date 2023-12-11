import CioInternalCommon
import Combine
import Foundation

class MessagingInAppImplementation: MessagingInAppInstance {
    private let moduleConfig: MessagingInAppConfigOptions
    private let logger: CioInternalCommon.Logger
    private var inAppProvider: InAppProvider

    private var eventListener: InAppEventListener?
    private let threadUtil: ThreadUtil
    private let eventHandlingManager: EventHandlingManager
    private var subscriptions: Set<AnyCancellable> = []

    init(diGraph: DIGraphShared, moduleConfig: MessagingInAppConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.inAppProvider = diGraph.inAppProvider
        self.threadUtil = diGraph.threadUtil
        self.eventHandlingManager = EventHandlingManager(eventBus: diGraph.eventBus, eventStorage: diGraph.eventStorage)
        initialize()
    }

    private func initialize() {
        inAppProvider.initialize(siteId: moduleConfig.siteId, region: moduleConfig.region, delegate: self)

        eventHandlingManager.eventBus.onReceive(ProfileIdentifiedEvent.self) { event in
            self.logger.debug("registering profile \(event.identifier) for in-app")

            self.inAppProvider.setProfileIdentifier(event.identifier)
        }.store(in: &subscriptions)

        eventHandlingManager.eventBus.onReceive(ScreenViewedEvent.self) { event in
            self.logger.debug("setting route for in-app to \(event.name)")

            // Gist expects webview to be launched in main thread and changing route will trigger locally stored in-app messages for that route.
            self.threadUtil.runMain {
                self.inAppProvider.setRoute(event.name)
            }
        }.store(in: &subscriptions)

        eventHandlingManager.eventBus.onReceive(ResetEvent.self) { _ in
            self.logger.debug("removing profile for in-app")

            self.inAppProvider.clearIdentify()
        }.store(in: &subscriptions)

        // if identifier is already present, set the userToken again so in case if the customer was already identified and
        // module was added later on, we can notify gist about it.
        // FIXME: [CDP] Fetch from Journey
        // if let identifier = profileStore.identifier {
        //     inAppProvider.setProfileIdentifier(identifier)
        // }
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        self.eventListener = eventListener
    }

    // Dismiss in-app message
    func dismissMessage() {
        inAppProvider.dismissMessage()
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
            // FIXME: [CDP] Pass to Journey
            // _ = queue.addTrackInAppDeliveryTask(deliveryId: deliveryId, event: .opened)

//            eventHandlingManager.sendOrSaveEvent(event: TrackInAppMetricEvent(deliveryID: deliveryId, event: ""))
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
        if action != "gist://close" {
            if let deliveryId = getDeliveryId(from: message) {
                // the state of the SDK does not change if adding this queue task isn't successful so ignore result
                // FIXME: [CDP] Pass to Journey
                // _ = queue.addTrackInAppDeliveryTask(deliveryId: deliveryId, event: .clicked, metaData: ["action_name": name, "action_value": action])
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
