import Common
import Foundation

// Queue tasks for the Tracking module.
// sourcery: InjectRegister = "QueueRunnerHook"
internal class TrackingQueueRunner: ApiSyncQueueRunner, QueueRunnerHook {
    override init(
        siteId: SiteId,
        jsonAdapter: JsonAdapter,
        logger: Logger,
        httpClient: HttpClient,
        sdkConfig: SdkConfig
    ) {
        super.init(
            siteId: siteId,
            jsonAdapter: jsonAdapter,
            logger: logger,
            httpClient: httpClient,
            sdkConfig: sdkConfig
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

        performHttpRequest(
            endpoint: .identifyCustomer(identifier: taskData.identifier),
            requestBody: taskData.attributesJsonString?.data,
            onComplete: onComplete
        )
    }

    private func track(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: TrackEventQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        performHttpRequest(
            endpoint: .trackCustomerEvent(identifier: taskData.identifier),
            requestBody: taskData.attributesJsonString.data,
            onComplete: onComplete
        )
    }

    private func registerPushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: RegisterPushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        performHttpRequest(
            endpoint: .registerDevice(identifier: taskData.profileIdentifier),
            requestBody: taskData.attributesJsonString?.data,
            onComplete: onComplete
        )
    }

    private func deletePushToken(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: DeletePushNotificationQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        performHttpRequest(endpoint: .deleteDevice(
            identifier: taskData.profileIdentifier,
            deviceToken: taskData.deviceToken
        ), requestBody: nil, onComplete: onComplete)
    }

    private func trackPushMetric(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: MetricRequest.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        guard let bodyData = jsonAdapter.toJson(taskData) else {
            return
        }

        performHttpRequest(endpoint: .pushMetrics, requestBody: bodyData, onComplete: onComplete)
    }
}
