import Foundation

/**
 Where queue tasks are executed asynchronously.

 To keep this class testable, try to keep it small. So, the class's job is to take a
 task type and generic `Data` for task data and call some other code to perform the
 actual work on executing the task.
 */
public protocol QueueRunner: AutoMockable {
    func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void)
}

// sourcery: InjectRegister = "QueueRunner"
public class CioQueueRunner: ApiSyncQueueRunner, QueueRunner {
    init(
        jsonAdapter: JsonAdapter,
        logger: Logger,
        httpClient: HttpClient,
        hooksManager: HooksManager,
        sdkConfig: SdkConfig
    ) {
        super.init(
            jsonAdapter: jsonAdapter,
            logger: logger,
            httpClient: httpClient,
            sdkConfig: sdkConfig
        )
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let queueTaskType = QueueTaskType(rawValue: task.type) else {
            logger.error("task \(task.type) not handled by any module")

            return onComplete(.failure(.noRequestMade(nil)))
        }

        switch queueTaskType {
        case .trackDeliveryMetric: trackDeliveryMetric(task, onComplete: onComplete)
        case .identifyProfile: identify(task, onComplete: onComplete)
        case .trackEvent: track(task, onComplete: onComplete)
        case .registerPushToken: registerPushToken(task, onComplete: onComplete)
        case .deletePushToken: deletePushToken(task, onComplete: onComplete)
        case .trackPushMetric: trackPushMetric(task, onComplete: onComplete)
        }
    }
}

private extension CioQueueRunner {
    private func trackDeliveryMetric(
        _ task: QueueTask,
        onComplete: @escaping (Result<Void, HttpRequestError>) -> Void
    ) {
        guard let taskData = getTaskData(task, type: TrackDeliveryEventRequestBody.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        guard let bodyData = jsonAdapter.toJson(taskData) else {
            return
        }

        performHttpRequest(endpoint: .trackDeliveryMetrics, requestBody: bodyData, onComplete: onComplete)
    }

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
