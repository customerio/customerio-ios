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

/// Direct-HTTP POST for background-delivery callers. Composes the `/track` URL from
/// `apiHost` in `BackgroundDeliveryContextStore` and authenticates with `cdpApiKey`.
/// Works in cold-wake state — no dependency on MessagingPush or any other module's
/// `HttpClient`.
public protocol BackgroundDeliveryHttpClient: AutoMockable, Sendable {
    /// Sends one CDP `/track` event.
    /// - Parameters:
    ///   - eventName: `track` event name (e.g. `"Geofence Entered"`).
    ///   - userId: Identified user id. Caller must validate non-empty before calling.
    ///   - properties: Event properties payload.
    ///   - completion: Called on URLSession's delegate queue with success or error.
    func sendTrackEvent(
        eventName: String,
        userId: String,
        properties: [String: Any],
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

    public convenience init(
        contextStore: BackgroundDeliveryContextStore,
        requestRunner: HttpRequestRunner,
        logger: Logger
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
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
        eventName: String,
        userId: String,
        properties: [String: Any],
        completion: @escaping (Result<Void, BackgroundDeliveryHttpError>) -> Void
    ) {
        guard let apiHost = contextStore.currentApiHost, !apiHost.isEmpty else {
            return completion(.failure(.missingApiHost))
        }
        guard let cdpApiKey = contextStore.currentCdpApiKey, !cdpApiKey.isEmpty else {
            return completion(.failure(.missingCdpApiKey))
        }

        let body: [String: Any] = [
            "event": eventName,
            "userId": userId,
            "properties": properties
        ]
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
