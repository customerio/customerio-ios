import CioTracking
import Foundation

internal class MessagingPushImplementation: MessagingPushInstance {
    private let profileStore: ProfileStore
    private let backgroundQueue: Queue
    private var globalDataStore: GlobalDataStore

    /// testing init
    internal init(
        profileStore: ProfileStore,
        backgroundQueue: Queue,
        globalDataStore: GlobalDataStore
    ) {
        self.profileStore = profileStore
        self.backgroundQueue = backgroundQueue
        self.globalDataStore = globalDataStore
    }

    init(siteId: String) {
        let diGraph = DITracking.getInstance(siteId: siteId)

        self.profileStore = diGraph.profileStore
        self.backgroundQueue = diGraph.queue
        self.globalDataStore = diGraph.globalDataStore
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        // no matter what, save the device token for use later. if a customer is identified later,
        // we can reference the token and register it to a new profile.
        globalDataStore.pushDeviceToken = deviceToken

        guard let identifier = profileStore.identifier else {
            return
        }

        _ = backgroundQueue.addTask(type: QueueTaskType.registerPushToken.rawValue,
                                    data: RegisterPushNotificationQueueTaskData(profileIdentifier: identifier,
                                                                                deviceToken: deviceToken,
                                                                                lastUsed: Date()))
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        guard let existingDeviceToken = globalDataStore.pushDeviceToken else {
            return // no device token to delete, ignore request
        }
        globalDataStore.pushDeviceToken = nil

        guard let identifiedProfileId = profileStore.identifier else {
            return // no profile to delete token from, ignore request
        }

        _ = backgroundQueue.addTask(type: QueueTaskType.deletePushToken.rawValue,
                                    data: DeletePushNotificationQueueTaskData(profileIdentifier: identifiedProfileId,
                                                                              deviceToken: existingDeviceToken))
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        _ = backgroundQueue.addTask(type: QueueTaskType.trackPushMetric.rawValue,
                                    data: MetricRequest(deliveryID: deliveryID, event: event, deviceToken: deviceToken,
                                                        timestamp: Date()))
    }
}

extension MessagingPushImplementation: ProfileIdentifyHook {
    // When a new profile is identified, delete token from previously identified profile for
    // privacy and messaging releveance reasons. We only want to send messages to the currently
    // identified profile.
    func beforeNewProfileIdentified(oldIdentifier: String, newIdentifier: String) {
        deleteDeviceToken()
    }

    // When a profile is identified, try to automatically register a device token to them if there is one assigned
    // to this device
    func profileIdentified(identifier: String) {
        guard let existingDeviceToken = globalDataStore.pushDeviceToken else {
            return
        }

        registerDeviceToken(existingDeviceToken)
    }
}
