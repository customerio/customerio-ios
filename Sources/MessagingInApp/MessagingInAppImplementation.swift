import CioInternalCommon
import Foundation

class MessagingInAppImplementation: MessagingInAppInstance {
    private let moduleConfig: MessagingInAppConfigOptions

    private let logger: CioInternalCommon.Logger
    private var inAppProvider: InAppProvider

    private var eventListener: InAppEventListener?
    private let threadUtil: ThreadUtil
    var eventBusHandler: EventBusHandler

    init(diGraph: DIGraphShared, moduleConfig: MessagingInAppConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.inAppProvider = diGraph.inAppProvider
        self.threadUtil = diGraph.threadUtil
        self.eventBusHandler = diGraph.eventBusHandler
        initialize()
    }

    private func initialize() {
        inAppProvider.initialize(
            siteId: moduleConfig.siteId,
            region: moduleConfig.region,
            delegate: self,
            enableLogging: logger.logLevel == .debug
        )

        // if identifier is already present, set the userToken again so in case if the customer was already identified and
        // module was added later on, we can notify gist about it.
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { event in
            self.logger.debug("registering profile \(event.identifier) for in-app")

            self.inAppProvider.setProfileIdentifier(event.identifier)
        }

        eventBusHandler.addObserver(ScreenViewedEvent.self) { event in
            self.logger.debug("setting route for in-app to \(event.name)")

            // Gist expects webview to be launched in main thread and changing route will trigger locally stored in-app messages for that route.
            self.threadUtil.runMain {
                self.inAppProvider.setRoute(event.name)
            }
        }

        eventBusHandler.addObserver(ResetEvent.self) { _ in
            self.logger.debug("removing profile for in-app")

            // Gist may dismiss a modal if it's displayed. Run on main thread to call UI code.
            self.threadUtil.runMain {
                self.inAppProvider.clearIdentify()
            }
        }
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        self.eventListener = eventListener
    }

    // Sets a custom event bus handler for unit testing.
    // Do not use it in production.
    #if DEBUG
    func setEventBusHandler(_ eventBusHandler: EventBusHandler) {
        self.eventBusHandler = eventBusHandler
    }
    #endif

    // Dismiss in-app message
    func dismissMessage() {
        inAppProvider.dismissMessage()
    }
}

extension MessagingInAppImplementation: GistDelegate {
    // Aka: message opened
    public func messageShown(message: Message) {
        logger.debug("in-app message opened. \(message.describeForLogs)")

        eventListener?.messageShown(message: InAppMessage(gistMessage: message))

        if let deliveryId = message.deliveryId {
            eventBusHandler.postEvent(TrackInAppMetricEvent(deliveryID: deliveryId, event: InAppMetric.opened.rawValue))
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

        eventListener?.messageActionTaken(
            message: InAppMessage(gistMessage: message),
            actionValue: action,
            actionName: name
        )
    }
}
