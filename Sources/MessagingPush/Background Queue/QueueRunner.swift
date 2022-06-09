import Common
import Foundation

// Queue tasks for the MessagingPush module.
// sourcery: InjectRegister = "QueueRunnerHook"
public class MessagingPushQueueRunner: ApiSyncQueueRunner, QueueRunnerHook {
    override init(siteId: SiteId, jsonAdapter: JsonAdapter, logger: Logger, httpClient: HttpClient) {
        super.init(siteId: siteId, jsonAdapter: jsonAdapter, logger: logger,
                   httpClient: httpClient)
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) -> Bool {
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
    private func registerPushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: RegisterPushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(endpoint: .registerDevice(identifier: taskData.profileIdentifier),
                                           headers: nil, body: taskData.attributesJsonString?.data)

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func deletePushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: DeletePushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(endpoint: .deleteDevice(identifier: taskData.profileIdentifier,
                                                                   deviceToken: taskData.deviceToken),
                                           headers: nil,
                                           body: nil)

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func trackPushMetric(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
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
