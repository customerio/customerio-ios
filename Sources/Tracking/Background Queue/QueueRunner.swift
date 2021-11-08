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
public class CioQueueRunner: QueueRunner {
    private let jsonAdapter: JsonAdapter
    private let siteId: SiteId
    private let logger: Logger
    private let identifyRepository: IdentifyRepository

    init(siteId: SiteId, jsonAdapter: JsonAdapter, logger: Logger, identifyRepository: IdentifyRepository) {
        self.siteId = siteId
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.identifyRepository = identifyRepository
    }

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        let failureIfDontDecodeTaskData: Result<Void, CustomerIOError> = .failure(.http(.noRequestMade(nil)))

        switch task.type {
        case .identifyProfile:
            guard let taskData = getTaskData(task, type: IdentifyProfileQueueTaskData.self) else {
                return onComplete(failureIfDontDecodeTaskData)
            }

            identifyRepository.addOrUpdateCustomer(identifier: taskData.identifier,
                                                   requestBodyString: taskData.attributesJsonString,
                                                   onComplete: onComplete)
        case .trackEvent:
            guard let taskData = getTaskData(task, type: TrackEventQueueTaskData.self) else {
                return onComplete(failureIfDontDecodeTaskData)
            }

            identifyRepository.trackEvent(profileIdentifier: taskData.identifier,
                                          requestBodyString: taskData.attributesJsonString,
                                          onComplete: onComplete)
        }
    }

    /// (1) less code for `runTask` function to decode JSON and (2) one place to do error logging if decoding wrong.
    private func getTaskData<T: Decodable>(_ task: QueueTask, type: T.Type) -> T? {
        let taskData: T? = jsonAdapter.fromJson(task.data, decoder: nil)

        if taskData == nil {
            /// log as error because it's a developer error since SDK is who encoded the TaskData in the first place
            /// we should always be able to decode it without problem.
            logger.error("Failure decoding: \(task.data.string ?? "()") to \(type)")
        }

        return taskData
    }
}
