import CioInternalCommon
import Foundation

class MessagingInAppImplementation: MessagingInAppInstance {
    private let moduleConfig: MessagingInAppConfigOptions

    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let gist: GistProvider
    private let threadUtil: ThreadUtil
    private let eventBusHandler: EventBusHandler

    init(diGraph: DIGraphShared, moduleConfig: MessagingInAppConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.inAppMessageManager = diGraph.inAppMessageManager
        self.gist = diGraph.gistProvider
        self.threadUtil = diGraph.threadUtil
        self.eventBusHandler = diGraph.eventBusHandler

        subscribeToInAppMessageState()
    }

    private func subscribeToInAppMessageState() {
        inAppMessageManager.dispatch(action: .initialize(
            siteId: moduleConfig.siteId,
            dataCenter: moduleConfig.region.rawValue,
            environment: GistEnvironment.production
        )) {
            self.subscribeToEventBus()
        }
    }

    private func subscribeToEventBus() {
        // if identifier is already present, set the userToken again so in case if the customer was already identified and
        // module was added later on, we can notify gist about it.
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { event in
            self.logger.logWithModuleTag("registering profile \(event.identifier) for in-app", level: .debug)

            self.gist.setUserToken(event.identifier)
        }

        eventBusHandler.addObserver(ScreenViewedEvent.self) { event in
            self.logger.logWithModuleTag("setting route for in-app to \(event.name)", level: .debug)

            self.gist.setCurrentRoute(event.name)
        }

        eventBusHandler.addObserver(ResetEvent.self) { _ in
            self.logger.logWithModuleTag("removing profile for in-app", level: .debug)

            self.gist.resetState()
        }
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        gist.setEventListener(eventListener)
    }

    // Dismiss in-app message
    func dismissMessage() {
        gist.dismissMessage()
    }
}
