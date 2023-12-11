import CioInternalCommon
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif
import Combine

class MessagingPushImplementation: MessagingPushInstance {
    let moduleConfig: MessagingPushConfigOptions
    let logger: Logger
    let jsonAdapter: JsonAdapter
    let eventBus: EventBus
    var subscriptions: Set<AnyCancellable> = []

    var eventStorage: EventStorage

    /// testing init
    init(
        moduleConfig: MessagingPushConfigOptions,
        logger: Logger,
        jsonAdapter: JsonAdapter,
        eventBus: EventBus,
        eventStorage: EventStorage
    ) {
        self.moduleConfig = moduleConfig
        self.logger = logger
        self.jsonAdapter = jsonAdapter
        self.eventBus = eventBus
        self.eventStorage = eventStorage
    }

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBus = diGraph.eventBus
        self.eventStorage = diGraph.eventStorage

        handleNewSubscriptionEvent()
    }

    private func handleNewSubscriptionEvent() {
        eventBus.onReceive(NewSubscriptionEvent.self) { [weak self] newSubEvent in
            guard let self = self else { return }
            switch newSubEvent.subscribedEventType {
            case String(describing: TrackMetricEvent.self):
                self.loadAndSendStoredEvents(ofType: TrackMetricEvent.self)
            // Add cases for other event types
            default:
                break
            }
        }.store(in: &subscriptions)
    }

    private func loadAndSendStoredEvents<E: EventRepresentable>(ofType eventType: E.Type) {
        do {
            let key = String(describing: eventType)
            let storedEvents: [E] = try eventStorage.loadAllEvents(ofType: eventType, withKey: key)
            storedEvents.forEach { eventBus.send($0) }
        } catch {
            // More robust error handling
            handleEventStorageError(error)
        }
    }

    private func handleEventStorageError(_ error: Error) {
        // Implement error handling logic
        print("Error loading stored events: \(error)")
    }

    func deleteDeviceToken() {
        // FIXME: [CDP] Pass to Journey
        // customerIO?.deleteDeviceToken()

        eventBus.send(DeleteDeviceTokenEvent())
    }

    func registerDeviceToken(_ deviceToken: String) {
        // FIXME: [CDP] Pass to Journey
        // customerIO?.registerDeviceToken(deviceToken)

        eventBus.send(RegisterDeviceTokenEvent(token: deviceToken))
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        // FIXME: [CDP] Pass to Journey
        // customerIO?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)

        eventBus.send(TrackMetricEvent(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken))
    }

    func sendOrSaveEvent(event: any EventRepresentable) {
        if eventBus.send(event) == false {
            let key = String(describing: event.self)
            do {
                try eventStorage.store(event: event, forKey: key)
            } catch {
                // Handle the error
                print(error)
            }
        }
    }

    #if canImport(UserNotifications)
    func trackMetric(
        notificationContent: UNNotificationContent,
        event: Metric
    ) {
        guard let deliveryID: String = notificationContent.userInfo["CIO-Delivery-ID"] as? String,
              let deviceToken: String = notificationContent.userInfo["CIO-Delivery-Token"] as? String
        else {
            return
        }

        trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
    #endif
}
