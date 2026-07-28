import Foundation

/// Shared helpers for background-delivery HTTP callers. Lifted into Common so the
/// host-scheme and Basic-auth rules stay in one place across modules (track POSTs in
/// `BackgroundDeliveryHttpClient`, geofence GETs in `GeofenceApiService`).
public enum BackgroundDeliveryHttp {
    /// `apiHost` is stored host-only in `BackgroundDeliveryContextStore` (e.g.
    /// `"cdp.customer.io/v1"`); prepend `https://` unless the caller already qualified it.
    public static func absoluteHost(_ host: String) -> String {
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return host
        }
        return "https://" + host
    }

    /// Base64-encodes `"\(cdpApiKey):"` for HTTP Basic auth.
    public static func basicAuthValue(cdpApiKey: String) -> String {
        let raw = "\(cdpApiKey):"
        return raw.data(using: .utf8)?.base64EncodedString() ?? raw
    }
}
