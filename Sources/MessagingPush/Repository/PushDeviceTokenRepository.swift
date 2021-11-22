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
        let existingDeviceToken = globalDataStore.pushDeviceToken
        globalDataStore.pushDeviceToken = nil

        guard let existingDeviceToken = existingDeviceToken, let identifiedProfileId = profileStore.identifier else {
            return // ignore request, no token to delete
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
