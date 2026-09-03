import Foundation

/// Why an in-app message failed to load or render.
///
/// The cases are deliberately coarse: each one maps to a different thing an integrator would do
/// about it — check connectivity, look at a slow renderer, report the message content to us, or
/// file an SDK bug. Finer detail belongs in ``InAppMessageError/detail``.
///
/// **Keep a `default:` branch when you switch on this.** More cases may be added in future
/// releases, and an exhaustive switch will stop compiling when that happens. The SDK is
/// distributed as source, so the compiler treats this enum as frozen at your build — use a plain
/// `default:` rather than `@unknown default:`.
public enum InAppMessageErrorReason: String {
    /// The renderer could not be reached: the navigation failed, for example on DNS, connectivity
    /// or TLS.
    case network
    /// The renderer was reached but never signalled that it had bootstrapped within the timeout.
    case timeout
    /// The renderer loaded and then reported that it could not render the message.
    case renderFailed
    /// The WebView's content process died, so the message can never finish.
    case webViewCrashed
    /// The SDK itself could not drive the render — a malformed URL, or configuration that would
    /// not encode or inject.
    case internalError
}

/// A single in-app message load/render failure, with as much context as the failing layer had.
public struct InAppMessageError: Error, Equatable {
    /// The coarse category. Branch on this.
    public let reason: InAppMessageErrorReason

    /// Human-readable detail from the layer that failed — a `WKWebView` error description, or the
    /// message the renderer itself reported. Free-form, unstable, and partly renderer-supplied, so
    /// treat it as **local diagnostics only**: write it to your logs, don't parse it, and don't
    /// forward it verbatim to analytics or crash reporting. Branch on ``reason`` instead.
    public let detail: String?

    /// The underlying platform error code where the failing layer had one — on iOS this is the
    /// `NSError` code behind a failed navigation, typically an `NSURLError`. `nil` when the failure
    /// carried no numeric code.
    ///
    /// Note this is not an HTTP status: an error response still completes navigation, so it does
    /// not reach the failure callbacks the SDK maps from.
    public let code: Int?

    public init(reason: InAppMessageErrorReason, detail: String? = nil, code: Int? = nil) {
        self.reason = reason
        self.detail = detail
        self.code = code
    }

    /// Compact form for logs: `network (-1009): The Internet connection appears to be offline.`
    var describeForLogs: String {
        var description = reason.rawValue
        if let code = code {
            description += " (\(code))"
        }
        if let detail = detail {
            description += ": \(detail)"
        }
        return description
    }
}

extension InAppMessageError {
    /// Builds a `.network` failure from a `WKWebView` navigation error, keeping the underlying
    /// description and `NSURLError` code that the SDK previously discarded.
    init(networkError: Error) {
        let nsError = networkError as NSError
        self.init(
            reason: .network,
            detail: nsError.localizedDescription,
            code: nsError.code
        )
    }
}
