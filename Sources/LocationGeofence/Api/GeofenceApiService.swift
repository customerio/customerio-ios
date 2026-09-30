import CioInternalCommon
import Foundation

enum GeofenceApiError: Error, Equatable {
    case missingApiHost
    case missingCdpApiKey
    case invalidRequest
    case http(statusCode: Int)
    case transport
    case decoding

    /// Stable token for `why=`; `String(describing:)` isn't stable.
    var diagnosticToken: String {
        switch self {
        case .missingApiHost: return "missing_api_host"
        case .missingCdpApiKey: return "missing_cdp_api_key"
        case .invalidRequest: return "invalid_request"
        case .http(let statusCode): return "http_\(statusCode)"
        case .transport: return "transport"
        case .decoding: return "decoding"
        }
    }
}

/// Fetches geofences + workspace config from the CDP API.
protocol GeofenceApiService: AutoMockable, Sendable {
    /// Carries no user identifier, only the workspace API key.
    func fetchNearbyGeofences(
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    )
}

// sourcery: InjectRegisterShared = "GeofenceApiService"
// sourcery: InjectCustomShared
/// `@unchecked Sendable`: all stored properties are `let`; mutable state lives in the injected,
/// thread-safe dependencies.
final class GeofenceApiServiceImpl: GeofenceApiService, @unchecked Sendable {
    /// Carries its own version: `apiHost` ends in `/v1`, shared with `/track`. Polygons are v2 only.
    static let nearestPath = "/v2/geofences/nearest"

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
        completion: @escaping (Result<GeofenceApiResponse, GeofenceApiError>) -> Void
    ) {
        let body: Data
        do {
            body = try JSONEncoder().encode(NearestRequest(latitude: latitude, longitude: longitude))
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

    /// Drops the host's trailing version segment, if any. Built from components, not spliced: a
    /// customer host's trailing slash, query or port must survive.
    static func composeUrl(apiHost: String, path: String) -> URL? {
        guard var components = URLComponents(string: BackgroundDeliveryHttp.absoluteHost(apiHost))
        else { return nil }
        // `percentEncodedPath`, not `path`, or an already-escaped segment is re-encoded.
        var segments = components.percentEncodedPath.split(separator: "/").map(String.init)
        if let last = segments.last, isVersionSegment(last) {
            segments.removeLast()
        }
        segments.append(contentsOf: path.split(separator: "/").map(String.init))
        components.percentEncodedPath = "/" + segments.joined(separator: "/")
        return components.url
    }

    private static func isVersionSegment(_ segment: String) -> Bool {
        segment.count >= 2 && segment.hasPrefix("v") && segment.dropFirst().allSatisfy(\.isNumber)
    }
}

/// `radius`/`limit` are optional server-side and deliberately omitted.
private struct NearestRequest: Encodable {
    let latitude: Double
    let longitude: Double
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
