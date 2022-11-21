import Common
import Foundation

// Queue tasks for the Tracking module.
// sourcery: InjectRegister = "QueueRunnerHook"
internal class TrackingQueueRunner: ApiSyncQueueRunner, QueueRunnerHook {
    override init(siteId: SiteId, jsonAdapter: JsonAdapter, logger: Logger, httpClient: HttpClient) {
        super.init(
            siteId: siteId,
            jsonAdapter: jsonAdapter,
            logger: logger,
            httpClient: httpClient
        )
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) -> Bool {
        guard let queueTaskType = QueueTaskType(rawValue: task.type) else {
            return false
        }

        switch queueTaskType {
        case .identifyProfile: identify(task, onComplete: onComplete)
        case .trackEvent: track(task, onComplete: onComplete)
        case .registerPushToken: registerPushToken(task, onComplete: onComplete)
        case .deletePushToken: deletePushToken(task, onComplete: onComplete)
        case .trackPushMetric: trackPushMetric(task, onComplete: onComplete)
        }

        return true
    }
}

extension TrackingQueueRunner {
    private func identify(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: IdentifyProfileQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: taskData.identifier),
            headers: nil,
            body: taskData.attributesJsonString?.data
        )

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func track(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: TrackEventQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(
            endpoint: .trackCustomerEvent(identifier: taskData.identifier),
            headers: nil,
            body: taskData.attributesJsonString.data
        )

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func registerPushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: RegisterPushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(
            endpoint: .registerDevice(identifier: taskData.profileIdentifier),
            headers: nil,
            body: taskData.attributesJsonString?.data
        )

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func deletePushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: DeletePushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(
            endpoint: .deleteDevice(
                identifier: taskData.profileIdentifier,
                deviceToken: taskData.deviceToken
            ),
            headers: nil,
            body: nil
        )

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
