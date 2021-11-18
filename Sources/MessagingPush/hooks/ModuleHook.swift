import CioTracking
import Foundation

/// We want to try and limit singletons so, we pass in a di graph from
/// the top level (MessagingPush class) classes and initialize new instances
/// when functions are called below.
class MessagingPushModuleHookProvider: ModuleHookProvider {
    private let diGraph: DIMessagingPush

    init(diGraph: DIMessagingPush) {
        self.diGraph = diGraph
    }

    var hook: ModuleHook? {
        diGraph.moduleHook
    }
}

// sourcery: InjectRegister = "ModuleHook"
class MessagingPushHook: ApiSyncQueueRunner, ModuleHook {
    private let globalDataStore: GlobalDataStore
    private let backgroundQueue: Queue

    init(siteId: SiteId, diTracking: DITracking) {
        self.globalDataStore = diTracking.globalDataStore
        self.backgroundQueue = diTracking.queue

        super.init(siteId: siteId, jsonAdapter: diTracking.jsonAdapter, logger: diTracking.logger,
                   httpClient: diTracking.httpClient)
    }

    func runQueueTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) -> Bool {
        let failureIfDontDecodeTaskData: Result<Void, CustomerIOError> = .failure(.http(.noRequestMade(nil)))

        if let queueTaskType = QueueTaskType(rawValue: task.type) {
            switch queueTaskType {
            case .registerPushToken:
                guard let taskData = getTaskData(task, type: RegisterPushNotificationQueueTaskData.self) else {
                    onComplete(failureIfDontDecodeTaskData)
                    return true
                }
                guard let body = jsonAdapter
                    .toJson(RegisterDeviceRequest(device: Device(token: taskData.deviceToken,
                                                                 lastUsed: taskData.lastUsed)),
                    encoder: nil)
                else {
                    onComplete(failureIfDontDecodeTaskData)
                    return true
                }

                let httpParams = HttpRequestParams(endpoint: .registerDevice(identifier: taskData.profileIdentifier),
                                                   headers: nil, body: body)

                performHttpRequest(params: httpParams, onComplete: onComplete)
            case .deletePushToken:
                guard let taskData = getTaskData(task, type: DeletePushNotificationQueueTaskData.self) else {
                    onComplete(failureIfDontDecodeTaskData)
                    return true
                }

                let httpParams =
                    HttpRequestParams(endpoint: .deleteDevice(identifier: taskData.profileIdentifier,
                                                              deviceToken: taskData.deviceToken),
                                      headers: nil, body: nil)

                performHttpRequest(params: httpParams, onComplete: onComplete)
            }

            return true
        }

        return false
    }

    func profileIdentified(identifier: String) {
        // automatically register push token to new profile if a device token exists
        if let existingPushDeviceToken = globalDataStore.pushDeviceToken {
            logger.verbose("Automatically adding device token to new profile \(identifier)")

            _ = backgroundQueue.addTask(type: QueueTaskType.registerPushToken.rawValue,
                                        data: RegisterPushNotificationQueueTaskData(profileIdentifier: identifier,
                                                                                    deviceToken: existingPushDeviceToken,
                                                                                    lastUsed: Date()))
        }
    }

    func beforeNewProfileIdentified(oldIdentifier: String, newIdentifier: String) {
        // automatically remove device token from old profile to avoid sending duplicate, irrelevant, or profile push to profile.
        if let existingPushDeviceToken = globalDataStore.pushDeviceToken {
            _ = backgroundQueue.addTask(type: QueueTaskType.deletePushToken.rawValue,
                                        data: DeletePushNotificationQueueTaskData(profileIdentifier: oldIdentifier,
                                                                                  deviceToken: existingPushDeviceToken))
        }
    }
}

internal enum QueueTaskType: String {
    case registerPushToken
    case deletePushToken
}
