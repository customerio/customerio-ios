import CioTracking
import Foundation

// Queue tasks for the MessagingPush module.
// sourcery: InjectRegister = "QueueRunnerHook"
public class MessagingPushQueueRunner: ApiSyncQueueRunner, QueueRunnerHook {
    init(siteId: SiteId, diTracking: DITracking) {
        super.init(siteId: siteId, jsonAdapter: diTracking.jsonAdapter, logger: diTracking.logger,
                   httpClient: diTracking.httpClient)
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) -> Bool {
        guard let queueTaskType = QueueTaskType(rawValue: task.type) else {
            return false
        }

        switch queueTaskType {
        case .registerPushToken: registerPushToken(task, onComplete: onComplete)
        case .deletePushToken: deletePushToken(task, onComplete: onComplete)
        case .trackPushMetric: trackPushMetric(task, onComplete: onComplete)
        }

        return true
    }
}

private extension MessagingPushQueueRunner {
    private func registerPushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let taskData = getTaskData(task, type: RegisterPushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let requestBody =
            RegisterDeviceRequest(device: Device(token: taskData.deviceToken, lastUsed: taskData.lastUsed))

        guard let body = jsonAdapter.toJson(requestBody, encoder: nil) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(endpoint: .registerDevice(identifier: taskData.profileIdentifier),
                                           headers: nil, body: body)

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func deletePushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let taskData = getTaskData(task, type: DeletePushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(endpoint: .deleteDevice(identifier: taskData.profileIdentifier,
                                                                   deviceToken: taskData.deviceToken),
                                           headers: nil,
                                           body: nil)

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func trackPushMetric(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let taskData = getTaskData(task, type: MetricRequest.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        guard let bodyData = jsonAdapter.toJson(taskData) else {
            return
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .pushMetrics, headers: nil, body: bodyData)

        performHttpRequest(params: httpRequestParameters, onComplete: onComplete)
    }
}
