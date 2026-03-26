import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

class MessagingPushImplementation: MessagingPushInstance {
    let pushLogger: PushNotificationLogger
    private let moduleConfig: MessagingPushConfigOptions
    private let logger: Logger
    private let jsonAdapter: JsonAdapter
    private let eventBusHandler: EventBusHandler

    private let nseCoordinatorsLock = NSLock()
    private var activeNSECoordinators: [NSEPushCoordinator] = []

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBusHandler = diGraph.eventBusHandler
        self.pushLogger = diGraph.pushNotificationLogger
    }

    func deleteDeviceToken() {
        eventBusHandler.postEvent(DeleteDeviceTokenEvent())
    }

    func registerDeviceToken(_ deviceToken: String) {
        eventBusHandler.postEvent(RegisterDeviceTokenEvent(token: deviceToken))
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        eventBusHandler.postEvent(TrackMetricEvent(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken))
    }

    #if canImport(UserNotifications)
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        let push = UNNotificationWrapper(notificationRequest: request)
        pushLogger.logReceivedPushMessage(notification: push)

        guard push.cioDelivery != nil else {
            pushLogger.logReceivedNonCioPushMessage()
            return false
        }

        pushLogger.logReceivedCioPushMessage()

        let autoTrackDelivery = moduleConfig.autoTrackPushEvents

        // Build a dedicated HttpClient + tracker + rich-push handler per notification so `cancel()` / `stopAll()`
        // only affect this coordinator (not concurrent NSE work). Resolve DI here so wrapper SDKs can override first.
        let (nseHttpClient, deliveryTracker) = DIGraphShared.shared.makeNSEScopedHttpClientAndDeliveryTracker()
        let coordinator = NSEPushCoordinator(
            deliveryTracker: RichPushNSEDeliveryTracking(
                tracker: deliveryTracker,
                pushLogger: pushLogger
            ),
            pushLogger: pushLogger,
            logger: logger,
            richPushHandler: NSEPushRichPushRequestHandler(httpClient: nseHttpClient),
            httpClient: nseHttpClient
        )
        addNSECoordinator(coordinator)
        Task { [weak self] in
            await coordinator.handle(
                request: request,
                withContentHandler: contentHandler,
                autoTrackDelivery: autoTrackDelivery
            )
            self?.removeNSECoordinator(coordinator)
        }
        return true
    }

    /**
     iOS telling the notification service to hurry up and stop modifying the push notifications.
     */
    func serviceExtensionTimeWillExpire() {
        logger.info("notification service time will expire. Stopping all notification requests early.")
        let coordinators = takeAllNSECoordinatorsForExpiry()
        for coordinator in coordinators {
            coordinator.cancel()
        }
    }

    private func addNSECoordinator(_ coordinator: NSEPushCoordinator) {
        nseCoordinatorsLock.lock()
        defer { nseCoordinatorsLock.unlock() }
        activeNSECoordinators.append(coordinator)
    }

    private func removeNSECoordinator(_ coordinator: NSEPushCoordinator) {
        nseCoordinatorsLock.lock()
        defer { nseCoordinatorsLock.unlock() }
        activeNSECoordinators.removeAll { ObjectIdentifier($0) == ObjectIdentifier(coordinator) }
    }

    /// Clears the list before `cancel()` so completed tasks do not call `removeNSECoordinator` for already-cancelled coordinators.
    private func takeAllNSECoordinatorsForExpiry() -> [NSEPushCoordinator] {
        nseCoordinatorsLock.lock()
        defer { nseCoordinatorsLock.unlock() }
        let copy = activeNSECoordinators
        activeNSECoordinators.removeAll()
        return copy
    }
    #endif
}
