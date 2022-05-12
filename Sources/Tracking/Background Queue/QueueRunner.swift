import Common
import Foundation

// Queue tasks for the Tracking module.
// sourcery: InjectRegister = "QueueRunnerHook"
internal class TrackingQueueRunner: ApiSyncQueueRunner, QueueRunnerHook {
    init(siteId: SiteId, diGraph: DICommon) {
        super.init(siteId: siteId, jsonAdapter: diGraph.jsonAdapter, logger: diGraph.logger,
                   httpClient: diGraph.httpClient)
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) -> Bool {
        guard let queueTaskType = QueueTaskType(rawValue: task.type) else {
            return false
        }

        switch queueTaskType {
        case .identifyProfile: identify(task, onComplete: onComplete)
        case .trackEvent: track(task, onComplete: onComplete)
        }

        return true
    }
}

extension TrackingQueueRunner {
    private func identify(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: IdentifyProfileQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(endpoint: .identifyCustomer(identifier: taskData.identifier),
                                           headers: nil, body: taskData.attributesJsonString?.data)

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }

    private func track(_ task: QueueTask, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        guard let taskData = getTaskData(task, type: TrackEventQueueTaskData.self) else {
            return onComplete(failureIfDontDecodeTaskData)
        }

        let httpParams = HttpRequestParams(endpoint: .trackCustomerEvent(identifier: taskData.identifier),
                                           headers: nil, body: taskData.attributesJsonString.data)

        performHttpRequest(params: httpParams, onComplete: onComplete)
    }
}

class TrackingModuleHookProvider: ModuleHookProvider {
    private let siteId: SiteId

    private var diGraphTracking: DITracking {
        DITracking.getInstance(siteId: siteId)
    }

    private var diGraph: DICommon {
        DICommon.getInstance(siteId: siteId)
    }

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        nil
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraphTracking.queueRunnerHook
    }

    var deviceAttributesHook: DeviceAttributesHook? {
        nil
    }
}
