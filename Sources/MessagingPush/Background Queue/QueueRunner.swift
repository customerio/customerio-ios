import CioTracking
import Foundation

// sourcery: InjectRegister = "QueueRunnerHook"
public class MessagingPushQueueRunner: ApiSyncQueueRunner, QueueRunnerHook {
    init(siteId: SiteId, diTracking: DITracking) {
        super.init(siteId: siteId, jsonAdapter: diTracking.jsonAdapter, logger: diTracking.logger,
                   httpClient: diTracking.httpClient)
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) -> Bool {
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
}
