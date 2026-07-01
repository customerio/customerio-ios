import CioInternalCommon
import Foundation

class MessagingInAppImplementation: MessagingInAppInstance {
    @Atomic static var currentColorScheme: ColorScheme = .auto

    private let moduleConfig: MessagingInAppConfigOptions

    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let gist: GistProvider
    private let threadUtil: ThreadUtil
    private let eventBusHandler: EventBusHandler
    private let notificationInbox: NotificationInbox

    init(diGraph: DIGraphShared, moduleConfig: MessagingInAppConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.inAppMessageManager = diGraph.inAppMessageManager
        self.gist = diGraph.gistProvider
        self.threadUtil = diGraph.threadUtil
        self.eventBusHandler = diGraph.eventBusHandler
        self.notificationInbox = diGraph.notificationInbox

        Self.currentColorScheme = moduleConfig.colorScheme
        subscribeToInAppMessageState()
    }

    private func subscribeToInAppMessageState() {
        inAppMessageManager.dispatch(action: .initialize(
            siteId: moduleConfig.siteId,
            dataCenter: moduleConfig.region.rawValue,
            environment: GistEnvironment.production,
            colorScheme: moduleConfig.colorScheme
        )) {
            self.subscribeToEventBus()
        }
    }

    private func subscribeToEventBus() {
        // if identifier is already present, set the userToken again so in case if the customer was already identified and
        // module was added later on, we can notify gist about it.
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [weak self] event in
            guard let self else { return }
            self.logger.logWithModuleTag("registering profile \(event.identifier) for in-app", level: .debug)
            self.gist.setUserToken(event.identifier)
        }

        eventBusHandler.addObserver(AnonymousProfileIdentifiedEvent.self) { [weak self] event in
            guard let self else { return }
            self.logger.logWithModuleTag("registering anonymous profile \(event.identifier) for in-app", level: .debug)
            self.gist.setAnonymousId(event.identifier)
        }

        eventBusHandler.addObserver(ScreenViewedEvent.self) { [weak self] event in
            guard let self else { return }
            self.logger.logWithModuleTag("setting route for in-app to \(event.name)", level: .debug)
            self.gist.setCurrentRoute(event.name)
        }

        eventBusHandler.addObserver(ResetEvent.self) { [weak self] _ in
            guard let self else { return }
            self.logger.logWithModuleTag("removing profile for in-app", level: .debug)
            self.gist.resetState()
        }
    }

    var inbox: NotificationInbox {
        notificationInbox
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        gist.setEventListener(eventListener)
    }

    // Dismiss in-app message
    func dismissMessage() {
        gist.dismissMessage()
    }

    func setColorScheme(_ colorScheme: ColorScheme) {
        Self.currentColorScheme = colorScheme
        inAppMessageManager.dispatch(action: .setColorScheme(colorScheme: colorScheme))
    }
}
