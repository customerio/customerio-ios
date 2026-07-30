import Foundation

/// The Customer.io Live Activity **tap-tracking URL** format, shared by the widget-side
/// ``SwiftUI/View/cioWidgetUrl(_:)`` modifier that builds it and the app-side handler that parses it.
///
/// A tap on a Live Activity is only observable if its `widgetURL` is set, and iOS delivers that URL
/// to the containing app on tap. Instead of relying on a customer deep link (which several activities
/// can share, making an `opened` ambiguous), Customer.io emits its **own** URL that carries the
/// delivery identity of the update currently on screen. Because the URL is derived from the same
/// `ContentState` that renders the activity, the reported open always matches what the user tapped —
/// with no app-side observer lookup and no dependency on a deep link. Any customer deep link rides
/// along as a `redirect` the app can navigate to after the open is reported.
public enum CioLiveActivityWidgetUrl {
    // Customer.io-owned scheme/host. A widget's `widgetURL` is an intra-app link delivered to the
    // containing app, so this scheme needs no `CFBundleURLTypes` registration.
    static let scheme = "cio-live-activity"
    static let host = "open"

    enum Key {
        static let deliveryId = "cio_delivery_id"
        static let deliveryToken = "cio_delivery_token"
        static let redirect = "cio_redirect"
    }

    /// Builds the tracking URL from a content-state's Customer.io metadata. Returns `nil` unless there
    /// is something to track (a `deliveryId`) or somewhere to redirect (a `deepLink`) — a
    /// `deliveryToken` alone is not sufficient: it can neither report an open nor navigate, so it
    /// never justifies a tap target on its own.
    public static func trackingURL(for metadata: CIOLiveActivityMetadata?) -> URL? {
        guard let metadata else { return nil }
        let deliveryId = metadata.deliveryId.flatMap { $0.isEmpty ? nil : $0 }
        let deepLink = metadata.deepLink.flatMap { $0.isEmpty ? nil : $0 }
        guard deliveryId != nil || deepLink != nil else { return nil }

        var items: [URLQueryItem] = []
        if let deliveryId {
            items.append(URLQueryItem(name: Key.deliveryId, value: deliveryId))
            // The token is the open's recipient — it only rides along with a deliveryId.
            if let token = metadata.deliveryToken, !token.isEmpty {
                items.append(URLQueryItem(name: Key.deliveryToken, value: token))
            }
        }
        if let deepLink {
            items.append(URLQueryItem(name: Key.redirect, value: deepLink))
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = items
        return components.url
    }

    /// Parsed contents of a Customer.io tracking widget URL.
    public struct Parsed {
        /// Delivery id of the update that was on screen when tapped; drives the `opened` metric.
        public let deliveryId: String?
        /// Delivery token of that update.
        public let deliveryToken: String?
        /// The customer's original deep link to navigate to after reporting, if any.
        public let redirect: URL?
    }

    /// Parses `url` if it is a Customer.io tracking URL; returns `nil` for any other URL.
    public static func parse(_ url: URL) -> Parsed? {
        guard url.scheme == scheme, url.host == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ key: String) -> String? {
            items.first { $0.name == key }?.value
        }
        return Parsed(
            deliveryId: value(Key.deliveryId),
            deliveryToken: value(Key.deliveryToken),
            redirect: value(Key.redirect).flatMap(URL.init(string:))
        )
    }
}

#if canImport(WidgetKit) && canImport(SwiftUI)
import SwiftUI
import WidgetKit

public extension View {
    /// Sets this Live Activity presentation's tap target to a Customer.io tracking URL built from the
    /// current content-state's `cioMetadata`, so a tap reports an `opened` for the exact update shown.
    ///
    /// Apply it to your Lock Screen view and Dynamic Island in place of Apple's `.widgetURL(_:)`
    /// (don't use both), passing `context.state.cioMetadata`. Forward the tapped URL to the SDK from
    /// your `UISceneDelegate`/`UIApplicationDelegate` open handler to report the open and recover the
    /// deep link. No custom URL scheme registration or entitlement is required.
    @available(iOS 16.1, *)
    func cioWidgetUrl(_ metadata: CIOLiveActivityMetadata?) -> some View {
        widgetURL(CioLiveActivityWidgetUrl.trackingURL(for: metadata))
    }
}

#if os(iOS)
@available(iOS 16.1, *)
public extension DynamicIsland {
    /// Dynamic Island counterpart of ``SwiftUI/View/cioWidgetUrl(_:)``. WidgetKit exposes `widgetURL`
    /// on `DynamicIsland` (not `View`), so the Dynamic Island needs its own overload; apply it the
    /// same way, passing `context.state.cioMetadata`.
    func cioWidgetUrl(_ metadata: CIOLiveActivityMetadata?) -> DynamicIsland {
        widgetURL(CioLiveActivityWidgetUrl.trackingURL(for: metadata))
    }
}
#endif
#endif
