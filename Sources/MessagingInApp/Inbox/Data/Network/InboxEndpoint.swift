import Foundation

/// Visual-inbox data-layer GET endpoints on the gist consumer host.
///
/// Kept separate from `QueueEndpoint` so the inbox fetch path can carry its own
/// per-attempt timeout without touching the existing queue client.
enum InboxEndpoint: GistNetworkRequest {
    /// `GET /api/v1/templates` — raw template registry `{ name: [versions] }`.
    case getTemplates
    /// `GET /api/v1/branding` — branding theme tokens + patterns.
    case getBranding

    var method: HTTPMethod {
        switch self {
        case .getTemplates, .getBranding:
            return .get
        }
    }

    var parameters: RequestParameters? {
        nil
    }

    /// Per-attempt 5s timeout for the inbox fetch path (the queue client keeps the default timeout).
    var timeoutInterval: TimeInterval? {
        InboxNetworkClientImpl.requestTimeout
    }

    var path: String {
        switch self {
        case .getTemplates:
            return "/api/v1/templates"
        case .getBranding:
            return "/api/v1/branding"
        }
    }
}
