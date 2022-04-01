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
    private let hooks: HooksManager
    // store currently running queue hook in memory so it doesn't get garbage collected.
    // hook instance needs to call completion handler so hold strong reference
    private var currentlyRunningHook: QueueRunnerHook?

    init(siteId: SiteId, jsonAdapter: JsonAdapter, logger: Logger, httpClient: HttpClient, hooksManager: HooksManager) {
        self.hooks = hooksManager

        super.init(siteId: siteId, jsonAdapter: jsonAdapter, logger: logger, httpClient: httpClient)
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        var hookHandled = false

        hooks.queueRunnerHooks.forEach { hook in
            if hook.runTask(task, onComplete: { result in
                self.currentlyRunningHook = nil
                onComplete(result)
            }) {
                self.currentlyRunningHook = hook
                hookHandled = true
            }
        }

        if !hookHandled {
            let errorMessage = "task \(task.type) not handled by any module"
            onComplete(.failure(.internalError(message: errorMessage)))
        }
    }
}
