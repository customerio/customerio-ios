import Foundation

/**
 Where queue tasks are executed asynchronously.

 To keep this class testable, try to keep it small. So, the class's job is to take a
 task type and generic `Data` for task data and call some other code to perform the
 actual work on executing the task.
 */
public protocol QueueRunner: AutoMockable {
    func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)
}

// sourcery: InjectRegister = "QueueRunner"
public class CioQueueRunner: ApiSyncQueueRunner, QueueRunner {
    // store hooks in memory so they don't get garbage collected in `runTask`.
    // a hook instance may need to call completion handler so hold strong reference so it can
    private let hooks: HooksManager

    init(siteId: SiteId, jsonAdapter: JsonAdapter, logger: Logger, httpClient: HttpClient, hooksManager: HooksManager) {
        self.hooks = hooksManager

        super.init(siteId: siteId, jsonAdapter: jsonAdapter, logger: logger, httpClient: httpClient)
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        let failureIfDontDecodeTaskData: Result<Void, CustomerIOError> = .failure(.http(.noRequestMade(nil)))

        if let queueTaskType = QueueTaskType(rawValue: task.type) {
            switch queueTaskType {
            case .identifyProfile:
                guard let taskData = getTaskData(task, type: IdentifyProfileQueueTaskData.self) else {
                    return onComplete(failureIfDontDecodeTaskData)
                }

                let httpParams = HttpRequestParams(endpoint: .identifyCustomer(identifier: taskData.identifier),
                                                   headers: nil, body: taskData.attributesJsonString?.data)

                performHttpRequest(params: httpParams, onComplete: onComplete)
            case .trackEvent:
                guard let taskData = getTaskData(task, type: TrackEventQueueTaskData.self) else {
                    return onComplete(failureIfDontDecodeTaskData)
                }

                let httpParams = HttpRequestParams(endpoint: .trackCustomerEvent(identifier: taskData.identifier),
                                                   headers: nil, body: taskData.attributesJsonString.data)

                performHttpRequest(params: httpParams, onComplete: onComplete)
            }
        } else {
            var hookHandled = false

            hooks.queueRunnerHooks.forEach { hook in
                if hook.runTask(task, onComplete: onComplete) {
                    hookHandled = true
                }
            }

            if !hookHandled {
                onComplete(.failure(.internalError(message: "Task \(task.type) not handled by anything including hooks")))
            }
        }
    }
}
