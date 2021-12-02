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
    func beforeNewProfileIdentified(oldIdentifier: String, newIdentifier: String) {
        deleteDeviceToken()
    }

    func profileIdentified(identifier: String) {
        guard let existingDeviceToken = globalDataStore.pushDeviceToken else {
            return
        }

        registerDeviceToken(existingDeviceToken)
    }
}
