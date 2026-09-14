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

    /// A stable machine token. `String(describing:)` would change with the case name, the
    /// associated value, or a future `CustomStringConvertible`, and these end up in `why=`.
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
    /// Returns the geofence set ranked around the device location. The request carries no user
    /// identifier (only the workspace API key), so the coordinate can't be attributed to a person.
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
    /// Carries its own version. `apiHost` ends in `/v1` (region-derived, e.g.
    /// `cdp.customer.io/v1`) and is shared with `/track`, which is still v1 — so the version here
    /// cannot come from the host. Polygon regions are only returned by v2.
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

    /// Composes `{apiHost}{path}`, dropping a trailing version segment off the host because `path`
    /// supplies its own. Handles `/v1`, another version, or no version at all — a self-hosted or
    /// overridden host may legitimately carry none.
    ///
    /// Rebuilt from parsed components rather than spliced onto the host string: `apiHost` is
    /// customer-supplied, and a trailing slash on it concatenates into a `//` the server does not
    /// route. Splitting also drops empty segments, and confining the edit to the path leaves a
    /// query or port on the host intact instead of appending into it.
    static func composeUrl(apiHost: String, path: String) -> URL? {
        guard var components = URLComponents(string: BackgroundDeliveryHttp.absoluteHost(apiHost))
        else { return nil }
        // `percentEncodedPath`, not `path`: reading and writing the decoded form would re-encode
        // an already-escaped segment on an overridden host.
        var segments = components.percentEncodedPath.split(separator: "/").map(String.init)
        if let last = segments.last, isVersionSegment(last) {
            segments.removeLast()
        }
        segments.append(contentsOf: path.split(separator: "/").map(String.init))
        components.percentEncodedPath = "/" + segments.joined(separator: "/")
        return components.url
    }

    /// `v` followed by digits and nothing else, so a path segment that merely starts with `v`
    /// (`/v`, `/venues`) is left alone.
    private static func isVersionSegment(_ segment: String) -> Bool {
        segment.count >= 2 && segment.hasPrefix("v") && segment.dropFirst().allSatisfy(\.isNumber)
    }
}

/// Body of the nearby geofence fetch. `radius`/`limit` are optional server-side and omitted.
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
