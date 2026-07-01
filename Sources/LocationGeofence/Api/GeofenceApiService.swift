import CioInternalCommon
import Foundation

/// Errors surfaced by `GeofenceApiService` callers.
enum GeofenceApiError: Error, Equatable {
    case missingApiHost
    case missingCdpApiKey
    case invalidRequest
    case http(statusCode: Int)
    case transport
    case decoding
}

/// Fetches geofences + workspace config from the CDP API.
protocol GeofenceApiService: AutoMockable, Sendable {
    /// Fetch-all: returns the full (capped) set with no location sent.
    func fetchAllGeofences(
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    )

    /// Fetch-nearby: returns the set ranked around the device. The coordinate is coarsened before
    /// it's sent (see `CoordinateCoarsener`) so an approximate, not exact, location leaves the device.
    func fetchNearbyGeofences(
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    )
}

// sourcery: InjectRegisterShared = "GeofenceApiService"
// sourcery: InjectCustomShared
/// `@unchecked Sendable`: all stored properties are `let` and the only mutable state lives
/// inside the injected stores/runner (already thread-safe). Lets callers invoke this from
/// a `Task` without an isolation hop.
final class GeofenceApiServiceImpl: GeofenceApiService, @unchecked Sendable {
    private static let endpointPath = "/geofences/nearby"

    private let contextStore: BackgroundDeliveryContextStore
    private let requestRunner: HttpRequestRunner
    private let session: URLSession
    private let logger: Logger

    init(
        contextStore: BackgroundDeliveryContextStore,
        requestRunner: HttpRequestRunner,
        session: URLSession = .shared,
        logger: Logger
    ) {
        self.contextStore = contextStore
        self.requestRunner = requestRunner
        self.session = session
        self.logger = logger
    }

    func fetchAllGeofences(
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    ) {
        request(queryItems: [], completion: completion)
    }

    func fetchNearbyGeofences(
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    ) {
        let coarse = CoordinateCoarsener.coarsen(latitude: latitude, longitude: longitude)
        request(queryItems: [
            URLQueryItem(name: "latitude", value: "\(coarse.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coarse.longitude)")
        ], completion: completion)
    }

    private func request(
        queryItems: [URLQueryItem],
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    ) {
        guard let apiHost = contextStore.currentApiHost, !apiHost.isEmpty else {
            return completion(.failure(.missingApiHost))
        }
        guard let cdpApiKey = contextStore.currentCdpApiKey, !cdpApiKey.isEmpty else {
            return completion(.failure(.missingCdpApiKey))
        }
        guard let url = Self.composeUrl(apiHost: apiHost, queryItems: queryItems) else {
            return completion(.failure(.invalidRequest))
        }

        let params = HttpRequestParams(
            method: "GET",
            url: url,
            headers: [
                "Accept": "application/json",
                "Authorization": "Basic \(BackgroundDeliveryHttp.basicAuthValue(cdpApiKey: cdpApiKey))"
            ],
            body: nil
        )

        requestRunner.request(params: params, session: session) { data, response, error in
            if error != nil {
                return completion(.failure(.transport))
            }
            let statusCode = response?.statusCode ?? 0
            guard (200 ..< 300).contains(statusCode) else {
                return completion(.failure(.http(statusCode: statusCode)))
            }
            guard let data else {
                return completion(.failure(.decoding))
            }
            do {
                let decoded = try JSONDecoder.snakeCase.decode(GeofenceApiResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(.decoding))
            }
        }
    }

    /// Composes `https://{apiHost}/geofences/nearby` with the given query items (empty for
    /// fetch-all). URLComponents handles percent-encoding for the query values.
    static func composeUrl(apiHost: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: BackgroundDeliveryHttp.absoluteHost(apiHost) + endpointPath)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }
}

private extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

// MARK: - DI

extension DIGraphShared {
    var customGeofenceApiService: GeofenceApiService {
        GeofenceApiServiceImpl(
            contextStore: backgroundDeliveryContextStore,
            requestRunner: httpRequestRunner,
            logger: logger
        )
    }
}
