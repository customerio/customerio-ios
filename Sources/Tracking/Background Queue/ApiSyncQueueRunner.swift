import Foundation

// base class for queue runner subclasses that perform networking
open class ApiSyncQueueRunner {
    public let jsonAdapter: JsonAdapter
    public let siteId: SiteId
    public let logger: Logger
    private let httpClient: HttpClient

    public let failureIfDontDecodeTaskData: Result<Void, CustomerIOError> = .failure(.http(.noRequestMade(nil)))

    public init(siteId: SiteId, jsonAdapter: JsonAdapter, logger: Logger, httpClient: HttpClient) {
        self.siteId = siteId
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.httpClient = httpClient
    }

    /// (1) less code for `runTask` function to decode JSON and (2) one place to do error logging if decoding wrong.
    public func getTaskData<T: Decodable>(_ task: QueueTask, type: T.Type) -> T? {
        let taskData: T? = jsonAdapter.fromJson(task.data, decoder: nil)

        if taskData == nil {
            /// log as error because it's a developer error since SDK is who encoded the TaskData in the first place
            /// we should always be able to decode it without problem.
            logger.error("Failure decoding: \(task.data.string ?? "()") to \(type)")
        }

        return taskData
    }

    public func performHttpRequest(
        params: HttpRequestParams,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        httpClient.request(params) { result in
            switch result {
            case .success: onComplete(.success(()))
            case .failure(let httpError): onComplete(.failure(.http(httpError)))
            }
        }
    }
}
