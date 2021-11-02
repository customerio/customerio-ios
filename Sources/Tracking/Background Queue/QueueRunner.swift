import Foundation

public protocol QueueRunner: AutoMockable {
    func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, Error>) -> Void)
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

    public func runTask(_ task: QueueTask, onComplete: @escaping (Result<Void, Error>) -> Void) {
        switch task.type {
        case .identifyProfile:
            guard let taskData: String = jsonAdapter.fromJson(task.data, decoder: nil) else {
                logger
                    .error("Not able to convert: \(task.data.string ?? "?string?") to JSON object needed")
                return onComplete(.success(()))
            }

            identifyRepository
                .addOrUpdateCustomer(identifier: taskData, body: taskData, jsonEncoder: nil) { result in
                    switch result {
                    case .success:
                        return onComplete(Result.success(()))
                    case .failure(let error):
                        return onComplete(Result.failure(error))
                    }
                }
        }
    }
}
