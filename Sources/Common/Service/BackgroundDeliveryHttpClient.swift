import Foundation

/// HTTP error surface for background-delivery POSTs. Distinct from `HttpRequestError` so
/// this path stays independent of MessagingPush — cold-wake delivery (geofence today,
/// potentially BGTask / Live Activities later) must work when no other module is initialized.
public enum BackgroundDeliveryHttpError: Error, Equatable {
    case missingApiHost
    case missingCdpApiKey
    case invalidRequest
    case http(statusCode: Int)
    case transport
}

/// One CDP `/track` request for a background-delivery caller. Bundles the request-body fields
/// into one value so the client signature stays stable as the payload grows.
public struct BackgroundTrackRequest {
    /// CDP `track` event name.
    public let eventName: String
    /// Identified user id. Caller must validate non-empty before sending.
    public let userId: String
    /// Custom event properties payload.
    public let properties: [String: Any]
    /// When the event occurred. Serialized into the reserved top-level `timestamp` field so the
    /// endpoint attributes the event to this instant rather than to when it was received; nil omits
    /// the field. The client owns the wire format, keeping it identical to the analytics channel.
    public let timestamp: Date?

    public init(eventName: String, userId: String, properties: [String: Any] = [:], timestamp: Date? = nil) {
        self.eventName = eventName
        self.userId = userId
        self.properties = properties
        self.timestamp = timestamp
    }
}

/// Direct-HTTP POST for background-delivery callers. Composes the `/track` URL from
/// `apiHost` in `BackgroundDeliveryContextStore` and authenticates with `cdpApiKey`.
/// Works in cold-wake state — no dependency on MessagingPush or any other module's
/// `HttpClient`.
public protocol BackgroundDeliveryHttpClient: AutoMockable, Sendable {
    /// Sends one CDP `/track` event.
    /// - Parameters:
    ///   - request: The event to deliver. See `BackgroundTrackRequest`.
    ///   - completion: Called on URLSession's delegate queue with success or error.
    func sendTrackEvent(
        _ request: BackgroundTrackRequest,
        completion: @escaping (Result<Void, BackgroundDeliveryHttpError>) -> Void
    )
}

// sourcery: InjectRegisterShared = "BackgroundDeliveryHttpClient"
// sourcery: InjectCustomShared
/// Implementation delegates the actual URL request execution to `HttpRequestRunner` so
/// tests can mock the network without touching `URLProtocol`.
public final class BackgroundDeliveryHttpClientImpl: BackgroundDeliveryHttpClient, @unchecked Sendable {
    private let contextStore: BackgroundDeliveryContextStore
    private let requestRunner: HttpRequestRunner
    private let session: URLSession
    private let logger: Logger

    /// - Parameters:
    ///   - requestTimeout: Per-request timeout. Defaults to 5s to fit a cold-wake background window
    ///     (e.g. region monitoring), where a slow send should fail fast and be retried by the caller
    ///     rather than be suspended mid-flight. Callers with a roomier window (e.g. a Notification
    ///     Service Extension) can pass a larger value.
    ///   - resourceTimeout: Whole-resource timeout, including waiting for connectivity. Defaults to 5s.
    public convenience init(
        contextStore: BackgroundDeliveryContextStore,
        requestRunner: HttpRequestRunner,
        logger: Logger,
        requestTimeout: TimeInterval = 5,
        resourceTimeout: TimeInterval = 5
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        self.init(
            contextStore: contextStore,
            requestRunner: requestRunner,
            session: URLSession(configuration: configuration),
            logger: logger
        )
    }

    /// Designated init for tests — allows injecting a stub session if the runner is real.
    init(
        contextStore: BackgroundDeliveryContextStore,
        requestRunner: HttpRequestRunner,
        session: URLSession,
        logger: Logger
    ) {
        self.contextStore = contextStore
        self.requestRunner = requestRunner
        self.session = session
        self.logger = logger
    }

    public func sendTrackEvent(
        _ request: BackgroundTrackRequest,
        completion: @escaping (Result<Void, BackgroundDeliveryHttpError>) -> Void
    ) {
        guard let apiHost = contextStore.currentApiHost, !apiHost.isEmpty else {
            return completion(.failure(.missingApiHost))
        }
        guard let cdpApiKey = contextStore.currentCdpApiKey, !cdpApiKey.isEmpty else {
            return completion(.failure(.missingCdpApiKey))
        }

        var body: [String: Any] = [
            "event": request.eventName,
            "userId": request.userId,
            "properties": request.properties
        ]
        // Reserved top-level field: a bare integer here is read as milliseconds, so send the ISO-8601 string.
        if let timestamp = request.timestamp {
            body["timestamp"] = timestamp.string(format: .iso8601WithMilliseconds)
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return completion(.failure(.invalidRequest))
        }
        guard let params = HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: BackgroundDeliveryHttp.absoluteHost(apiHost),
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Authorization": "Basic \(BackgroundDeliveryHttp.basicAuthValue(cdpApiKey: cdpApiKey))"
            ],
            body: bodyData
        ) else {
            return completion(.failure(.invalidRequest))
        }

        requestRunner.request(params: params, session: session) { _, response, error in
            if error != nil {
                return completion(.failure(.transport))
            }
            let statusCode = response?.statusCode ?? 0
            if (200 ..< 300).contains(statusCode) {
                completion(.success(()))
            } else {
                completion(.failure(.http(statusCode: statusCode)))
            }
        }
    }
}

// MARK: - DI

extension DIGraphShared {
    var customBackgroundDeliveryHttpClient: BackgroundDeliveryHttpClient {
        BackgroundDeliveryHttpClientImpl(
            contextStore: backgroundDeliveryContextStore,
            requestRunner: httpRequestRunner,
            logger: logger
        )
    }
}
