import CioInternalCommon
import Foundation
import UIKit

/// A topology-exclusive coordinator for application, scene, and SwiftUI activation callbacks.
///
/// Create one coordinator for one host lifecycle owner. Each method invocation represents a new
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

    private let logger: Logger

    struct SceneConnectionActivation {
        let urls: [URL]
        let userActivities: [NSUserActivity]
        let shortcutItem: UIApplicationShortcutItem?
        let hasNotificationResponse: Bool
    }

    /// Creates a coordinator for one explicit host lifecycle surface.
    public convenience init(hostTopology: CioAppLifecycleHostTopology) {
        self.init(hostTopology: hostTopology, logger: DIGraphShared.shared.logger)
    }

    init(hostTopology: CioAppLifecycleHostTopology, logger: Logger) {
        self.hostTopology = hostTopology
        self.logger = logger
    }

    // MARK: - AppDelegate-only ingress

    /// Handles one URL received by an AppDelegate-only host.
    @discardableResult
    public func handleApplicationOpenURL(
        _ url: URL,
        route: (URL) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.appDelegateOnly, callback: "application open URL") else {
            return .rejectedHostTopology
        }
        return routeOnce { route(url) }
    }

    /// Handles one user activity received by an AppDelegate-only host.
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
    public func handleApplicationShortcut(
        _ shortcutItem: UIApplicationShortcutItem,
        route: (UIApplicationShortcutItem) -> Bool,
        completionHandler: (Bool) -> Void
    ) {
        let result: CioAppLifecycleHandlingResult
        if accepts(.appDelegateOnly, callback: "application shortcut") {
            result = routeOnce { route(shortcutItem) }
        } else {
            result = .rejectedHostTopology
        }
        completionHandler(result.wasHandled)
    }

    // MARK: - UIScene ingress

    /// Handles the activation reason attached to a newly connected UIKit scene.
    ///
    /// Exactly one URL, user activity, shortcut, or notification response is accepted. A cold scene
    /// connection represents one activation, so multiple candidates, including multiple URLs, are
    /// ambiguous and no routing closure is called. A notification response is reported as
    /// application-owned and is not processed here.
    @discardableResult
    public func handleSceneConnection(
        options connectionOptions: UIScene.ConnectionOptions,
        routeURL: (URL) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        handleSceneConnection(
            SceneConnectionActivation(
                urls: connectionOptions.urlContexts.map(\.url),
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
        route: (URL) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        handleSceneOpenURLs(urlContexts.map(\.url), route: route)
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
    public func handleSceneShortcut(
        _ shortcutItem: UIApplicationShortcutItem,
        route: (UIApplicationShortcutItem) -> Bool,
        completionHandler: (Bool) -> Void
    ) {
        let result: CioAppLifecycleHandlingResult
        if accepts(.uiScene, callback: "scene shortcut") {
            result = routeOnce { route(shortcutItem) }
        } else {
            result = .rejectedHostTopology
        }
        completionHandler(result.wasHandled)
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

    func handleSceneConnection(
        _ activation: SceneConnectionActivation,
        routeURL: (URL) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.uiScene, callback: "scene connection") else {
            return .rejectedHostTopology
        }

        let candidateCount = activation.urls.count
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
        if let url = activation.urls.first {
            return routeOnce { routeURL(url) }
        }
        if let userActivity = activation.userActivities.first {
            return routeOnce { continueUserActivity(userActivity) }
        }
        guard let shortcutItem = activation.shortcutItem else { return .noActivation }
        return routeOnce { performShortcut(shortcutItem) }
    }

    func handleSceneOpenURLs(
        _ urls: [URL],
        route: (URL) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        guard accepts(.uiScene, callback: "scene open URL") else {
            return .rejectedHostTopology
        }
        guard !urls.isEmpty else { return .noActivation }

        var handled = false
        // `route` has a required side effect for every URL, so keep the iteration explicit.
        // swiftlint:disable for_where
        for url in urls {
            if route(url) {
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
            logger.error(
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
        logger.error(
            "CIO: Ignoring \(callback) because it contains \(candidateCount) activation candidates."
        )
        return .rejectedAmbiguousInput
    }

    private func routeOnce(_ route: () -> Bool) -> CioAppLifecycleHandlingResult {
        route() ? .handled : .unhandled
    }
}
