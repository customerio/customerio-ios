import CioTracking
import Foundation

internal protocol PushDeviceTokenRepository: AutoMockable {
    func registerDeviceToken(_ deviceToken: String)
    func deleteDeviceToken()
}

// sourcery: InjectRegister = "PushDeviceTokenRepository"
internal class CioPushDeviceTokenRepository: PushDeviceTokenRepository {
    private let profileStore: ProfileStore
    private let backgroundQueue: Queue
    private var globalDataStore: GlobalDataStore

    internal init(diTracking: DITracking) {
        self.profileStore = diTracking.profileStore
        self.backgroundQueue = diTracking.queue
        self.globalDataStore = diTracking.globalDataStore
    }

    func registerDeviceToken(_ deviceToken: String) {
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

    func deleteDeviceToken() {
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
}

extension CioPushDeviceTokenRepository: ProfileIdentifyHook {
    // When a new profile is identified, delete token from previously identified profile for
    // privacy and messaging releveance reasons. We only want to send messages to the currently
    // identified profile.
    func beforeIdentifiedProfileChange(oldIdentifier: String, newIdentifier: String) {
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
