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
    /// Returns the geofence set ranked around the device location. The request carries no user
    /// identifier (only the workspace API key), so the coordinate can't be attributed to a person.
    /// `radius` bounds the search in metres (the caller's server-fetch distance).
    func fetchNearbyGeofences(
        latitude: Double,
        longitude: Double,
        radius: Double,
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    )
}

// sourcery: InjectRegisterShared = "GeofenceApiService"
// sourcery: InjectCustomShared
/// `@unchecked Sendable`: all stored properties are `let` and the only mutable state lives
/// inside the injected stores/runner (already thread-safe). Lets callers invoke this from
/// a `Task` without an isolation hop.
final class GeofenceApiServiceImpl: GeofenceApiService, @unchecked Sendable {
    private static let nearestPath = "/geofences/nearest"

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

    func fetchNearbyGeofences(
        latitude: Double,
        longitude: Double,
        radius: Double,
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    ) {
        let body: Data
        do {
            body = try JSONEncoder().encode(NearestRequest(latitude: latitude, longitude: longitude, radius: radius))
        } catch {
            return completion(.failure(.invalidRequest))
        }
        post(path: Self.nearestPath, body: body, completion: completion)
    }

    private func post(
        path: String,
        body: Data,
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    ) {
        guard let apiHost = contextStore.currentApiHost, !apiHost.isEmpty else {
            return completion(.failure(.missingApiHost))
        }
        guard let cdpApiKey = contextStore.currentCdpApiKey, !cdpApiKey.isEmpty else {
            return completion(.failure(.missingCdpApiKey))
        }
        guard let url = Self.composeUrl(apiHost: apiHost, path: path) else {
            return completion(.failure(.invalidRequest))
        }

        let headers: HttpHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": "Basic \(BackgroundDeliveryHttp.basicAuthValue(cdpApiKey: cdpApiKey))"
        ]
        let params = HttpRequestParams(
            method: "POST",
            url: url,
            headers: headers,
            body: body
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

    /// Composes `https://{apiHost}{path}`. URLComponents normalizes the host + path.
    static func composeUrl(apiHost: String, path: String) -> URL? {
        URLComponents(string: BackgroundDeliveryHttp.absoluteHost(apiHost) + path)?.url
    }
}

/// Body of the nearby geofence fetch. `radius` bounds the search in metres; `limit` is optional
/// server-side and omitted.
private struct NearestRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let radius: Double
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
