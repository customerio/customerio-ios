import CioInternalCommon
import Foundation

#if canImport(UIKit)
import UIKit

/// A topology-exclusive coordinator for application, scene, and SwiftUI activation callbacks.
///
/// Create one coordinator for one host lifecycle owner. The topology guard is per coordinator,
/// not process-wide, so the host is responsible for wiring exactly one owner for each callback
/// surface. Each method invocation represents a new
/// activation occurrence, even when a later activation carries an identical URL or activity. This
/// deliberately avoids permanent payload or delivery-ID deduplication. Single-activation callbacks
/// call at most one host routing closure and reject ambiguous multi-item input. A warm scene URL
/// callback can contain multiple independent activation occurrences, so it routes every URL once.
///
/// Notification response processing is intentionally not part of this coordinator. Customer.io,
/// host, and third-party notification delegates continue to receive responses through the single
/// global `UNUserNotificationCenter` delegate proxy, which retains completion ownership.
///
/// Framework and host adapters should invoke this coordinator only from their terminal routing
/// callback, after any required framework forwarding. Do not invoke it from both raw and forwarded
/// callback seats for the same activation.
///
/// All methods are main-actor isolated because UIKit and SwiftUI lifecycle callbacks are delivered
/// on the main thread. Routing closures are invoked synchronously and are never retained.
@available(iOSApplicationExtension, unavailable)
@MainActor
public final class CioAppLifecycleCoordinator {
    /// The explicitly configured callback owner for this coordinator.
    public let hostTopology: CioAppLifecycleHostTopology

    private let loggerProvider: () -> Logger

    struct SceneConnectionActivation<URLActivation> {
        let urlActivations: [URLActivation]
        let userActivities: [NSUserActivity]
        let shortcutItem: UIApplicationShortcutItem?
        let hasNotificationResponse: Bool
    }

    /// Creates a coordinator for one explicit host lifecycle surface.
    public init(hostTopology: CioAppLifecycleHostTopology) {
        self.hostTopology = hostTopology
        // This is a public host-integration entry point. Resolve the shared logger lazily so the
        // SDK can finish top-level module initialization before the first lifecycle callback.
        self.loggerProvider = { DIGraphShared.shared.logger }
    }

    init(hostTopology: CioAppLifecycleHostTopology, logger: Logger) {
        self.hostTopology = hostTopology
        self.loggerProvider = { logger }
    }

    // MARK: - AppDelegate-only ingress

    /// Handles one URL received by an AppDelegate-only host.
    @discardableResult
    public func handleApplicationOpenURL(
        _ url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any],
        route: (URL, [UIApplication.OpenURLOptionsKey: Any]) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.appDelegateOnly, callback: "application open URL") else {
            return .rejectedHostTopology
        }
        return routeOnce { route(url, options) }
    }

    /// Handles one user activity delivered by iOS to an AppDelegate-only host.
    ///
    /// Invoke this method only from the OS-owned AppDelegate callback. If an SDK callback later
    /// supplies the same activity or URL as a routing fallback, route that value directly through
    /// the host's existing handler instead of re-entering the coordinator. Each OS callback is a
    /// new occurrence, so hosts must not add permanent payload deduplication.
    @discardableResult
    public func handleApplicationUserActivity(
        _ userActivity: NSUserActivity,
        route: (NSUserActivity) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.appDelegateOnly, callback: "application user activity") else {
            return .rejectedHostTopology
        }
        return routeOnce { route(userActivity) }
    }

    /// Handles one Home Screen quick action received by an AppDelegate-only host.
    ///
    /// The completion is invoked synchronously exactly once and is never retained.
    @discardableResult
    public func handleApplicationShortcut(
        _ shortcutItem: UIApplicationShortcutItem,
        route: (UIApplicationShortcutItem) -> Bool,
        completionHandler: (Bool) -> Void
    ) -> CioAppLifecycleHandlingResult {
        let result: CioAppLifecycleHandlingResult
        if accepts(.appDelegateOnly, callback: "application shortcut") {
            result = routeOnce { route(shortcutItem) }
        } else {
            result = .rejectedHostTopology
        }
        completionHandler(result.wasHandled)
        return result
    }

    // MARK: - UIScene ingress

    /// Handles the activation reason attached to a newly connected UIKit scene.
    ///
    /// Exactly one URL, user activity, shortcut, or notification response is accepted. A cold scene
    /// connection represents one activation, so multiple candidates, including multiple URLs, are
    /// ambiguous and no routing closure is called. Consequently, SDK open metrics associated with
    /// a discarded URL are not emitted. A notification response is reported as application-owned
    /// and is not processed here.
    @discardableResult
    public func handleSceneConnection(
        options connectionOptions: UIScene.ConnectionOptions,
        routeURL: (UIOpenURLContext) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        // Keep this UIKit wrapper deliberately thin. Tests exercise the generic core because
        // UIScene.ConnectionOptions cannot be constructed by host applications.
        handleSceneConnection(
            SceneConnectionActivation(
                urlActivations: Array(connectionOptions.urlContexts),
                userActivities: Array(connectionOptions.userActivities),
                shortcutItem: connectionOptions.shortcutItem,
                hasNotificationResponse: connectionOptions.notificationResponse != nil
            ),
            routeURL: routeURL,
            continueUserActivity: continueUserActivity,
            performShortcut: performShortcut
        )
    }

    /// Handles warm URL activations delivered to a UIKit scene.
    ///
    /// UIKit may coalesce multiple independent URL opens into one callback. Each URL is routed once
    /// in unspecified order; the aggregate result is handled when at least one route accepts its URL.
    @discardableResult
    public func handleSceneOpenURLContexts(
        _ urlContexts: Set<UIOpenURLContext>,
        route: (UIOpenURLContext) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        // Preserve every UIOpenURLContext for the host route; the generic core owns aggregation.
        handleSceneOpenURLs(Array(urlContexts), route: route)
    }

    /// Handles one warm user-activity activation delivered to a UIKit scene.
    @discardableResult
    public func handleSceneUserActivity(
        _ userActivity: NSUserActivity,
        route: (NSUserActivity) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.uiScene, callback: "scene user activity") else {
            return .rejectedHostTopology
        }
        return routeOnce { route(userActivity) }
    }

    /// Handles one Home Screen quick action delivered to a UIKit scene.
    ///
    /// The completion is invoked synchronously exactly once and is never retained.
    @discardableResult
    public func handleSceneShortcut(
        _ shortcutItem: UIApplicationShortcutItem,
        route: (UIApplicationShortcutItem) -> Bool,
        completionHandler: (Bool) -> Void
    ) -> CioAppLifecycleHandlingResult {
        let result: CioAppLifecycleHandlingResult
        if accepts(.uiScene, callback: "scene shortcut") {
            result = routeOnce { route(shortcutItem) }
        } else {
            result = .rejectedHostTopology
        }
        completionHandler(result.wasHandled)
        return result
    }

    // MARK: - SwiftUI ingress

    /// Handles one URL delivered by a SwiftUI host's `onOpenURL` callback.
    @discardableResult
    public func handleSwiftUIOpenURL(
        _ url: URL,
        route: (URL) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.swiftUILifecycle, callback: "SwiftUI open URL") else {
            return .rejectedHostTopology
        }
        return routeOnce { route(url) }
    }

    // MARK: - Testable core

    func handleSceneConnection<URLActivation>(
        _ activation: SceneConnectionActivation<URLActivation>,
        routeURL: (URLActivation) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.uiScene, callback: "scene connection") else {
            return .rejectedHostTopology
        }

        let candidateCount = activation.urlActivations.count
            + activation.userActivities.count
            + (activation.shortcutItem == nil ? 0 : 1)
            + (activation.hasNotificationResponse ? 1 : 0)
        guard candidateCount <= 1 else {
            return rejectAmbiguous(callback: "scene connection", candidateCount: candidateCount)
        }
        guard candidateCount == 1 else { return .noActivation }

        if activation.hasNotificationResponse {
            return .notificationOwnedByApplication
        }
        if let urlActivation = activation.urlActivations.first {
            return routeOnce { routeURL(urlActivation) }
        }
        if let userActivity = activation.userActivities.first {
            return routeOnce { continueUserActivity(userActivity) }
        }
        guard let shortcutItem = activation.shortcutItem else { return .noActivation }
        return routeOnce { performShortcut(shortcutItem) }
    }

    func handleSceneOpenURLs<URLActivation>(
        _ urlActivations: [URLActivation],
        route: (URLActivation) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.uiScene, callback: "scene open URL") else {
            return .rejectedHostTopology
        }
        guard !urlActivations.isEmpty else { return .noActivation }

        var handled = false
        // `route` has a required side effect for every URL, so keep the iteration explicit.
        // swiftlint:disable for_where
        for urlActivation in urlActivations {
            if route(urlActivation) {
                handled = true
            }
        }
        // swiftlint:enable for_where
        return handled ? .handled : .unhandled
    }

    private func accepts(
        _ expectedTopology: CioAppLifecycleHostTopology,
        callback: String
    ) -> Bool {
        guard hostTopology == expectedTopology else {
            loggerProvider().error(
                "CIO: Ignoring \(callback) because the coordinator owns \(hostTopology.rawValue), not \(expectedTopology.rawValue)."
            )
            return false
        }
        return true
    }

    private func rejectAmbiguous(
        callback: String,
        candidateCount: Int
    ) -> CioAppLifecycleHandlingResult {
        loggerProvider().error(
            "CIO: Ignoring \(callback) because it contains \(candidateCount) activation candidates."
        )
        return .rejectedAmbiguousInput
    }

    private func routeOnce(_ route: () -> Bool) -> CioAppLifecycleHandlingResult {
        route() ? .handled : .unhandled
    }
}
#endif
