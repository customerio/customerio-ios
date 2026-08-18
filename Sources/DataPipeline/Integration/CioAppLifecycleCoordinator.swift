import CioInternalCommon
import Foundation

#if canImport(UIKit)
import UIKit

/// Routes activation callbacks owned by an AppDelegate-only UIKit host.
///
/// Each method invocation represents a new activation occurrence, even when a later activation
/// carries an identical URL or activity. Notification response processing is intentionally not
/// part of this coordinator and remains owned by the global `UNUserNotificationCenter` delegate.
/// Framework and host adapters should invoke this coordinator only from their terminal routing
/// callback, after any required framework forwarding. Do not invoke it from both raw and forwarded
/// callback seats for the same activation.
///
/// All methods are main-actor isolated because UIKit lifecycle callbacks are delivered on the main
/// thread. Routing closures are invoked synchronously and are never retained.
@available(iOSApplicationExtension, unavailable)
@MainActor
public final class CioAppDelegateLifecycleCoordinator {
    /// Creates an AppDelegate-only lifecycle coordinator.
    public init() {}

    /// Handles one URL received by an AppDelegate-only host.
    @discardableResult
    public func handleOpenURL(
        _ url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any],
        route: (URL, [UIApplication.OpenURLOptionsKey: Any]) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        routeOnce { route(url, options) }
    }

    /// Handles one user activity delivered by iOS to an AppDelegate-only host.
    ///
    /// Invoke this method only from the OS-owned AppDelegate callback. If an SDK callback later
    /// supplies the same activity or URL as a routing fallback, route that value directly through
    /// the host's existing handler instead of re-entering the coordinator.
    @discardableResult
    public func handleUserActivity(
        _ userActivity: NSUserActivity,
        route: (NSUserActivity) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        routeOnce { route(userActivity) }
    }

    /// Handles one Home Screen quick action received by an AppDelegate-only host.
    ///
    /// The completion is invoked synchronously exactly once and is never retained.
    @discardableResult
    public func handleShortcut(
        _ shortcutItem: UIApplicationShortcutItem,
        route: (UIApplicationShortcutItem) -> Bool,
        completionHandler: (Bool) -> Void
    ) -> CioAppLifecycleHandlingResult {
        let result = routeOnce { route(shortcutItem) }
        completionHandler(result.wasHandled)
        return result
    }

    private func routeOnce(_ route: () -> Bool) -> CioAppLifecycleHandlingResult {
        route() ? .handled : .unhandled
    }
}

/// Routes activation callbacks owned by a UIKit scene host.
///
/// Create one coordinator for each scene lifecycle owner. Framework and host adapters should
/// invoke it only from their terminal routing callback, after any required framework forwarding.
/// A cold scene connection represents one activation and rejects ambiguous multi-item input. A
/// warm scene URL callback may coalesce independent activations and routes every URL once.
/// Do not invoke the coordinator from both raw and forwarded callback seats for one activation.
///
/// Notification responses remain application-owned and are not processed here. All methods are
/// main-actor isolated. Routing closures are invoked synchronously and are never retained.
@available(iOSApplicationExtension, unavailable)
@MainActor
public final class CioSceneLifecycleCoordinator {
    private let loggerProvider: () -> Logger

    struct SceneConnectionActivation<URLActivation> {
        let urlActivations: [URLActivation]
        let userActivities: [NSUserActivity]
        let shortcutItem: UIApplicationShortcutItem?
        let hasNotificationResponse: Bool
    }

    /// Creates a UIKit scene lifecycle coordinator.
    public init() {
        // This is a public host-integration entry point. Resolve the shared logger lazily so the
        // SDK can finish top-level module initialization before the first lifecycle callback.
        self.loggerProvider = { DIGraphShared.shared.logger }
    }

    init(logger: Logger) {
        self.loggerProvider = { logger }
    }

    /// Handles the activation reason attached to a newly connected UIKit scene.
    ///
    /// Exactly one URL, user activity, shortcut, or notification response is accepted. Multiple
    /// candidates are ambiguous and no routing closure is called. A notification response is
    /// reported as application-owned and is not processed here.
    @discardableResult
    public func handleConnection(
        options connectionOptions: UIScene.ConnectionOptions,
        routeURL: (UIOpenURLContext) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        handleConnection(
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
    /// in unspecified order; the aggregate result is handled when at least one route accepts it.
    @discardableResult
    public func handleOpenURLContexts(
        _ urlContexts: Set<UIOpenURLContext>,
        route: (UIOpenURLContext) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        handleOpenURLs(Array(urlContexts), route: route)
    }

    /// Handles one warm user-activity activation delivered to a UIKit scene.
    @discardableResult
    public func handleUserActivity(
        _ userActivity: NSUserActivity,
        route: (NSUserActivity) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        routeOnce { route(userActivity) }
    }

    /// Handles one Home Screen quick action delivered to a UIKit scene.
    ///
    /// The completion is invoked synchronously exactly once and is never retained.
    @discardableResult
    public func handleShortcut(
        _ shortcutItem: UIApplicationShortcutItem,
        route: (UIApplicationShortcutItem) -> Bool,
        completionHandler: (Bool) -> Void
    ) -> CioAppLifecycleHandlingResult {
        let result = routeOnce { route(shortcutItem) }
        completionHandler(result.wasHandled)
        return result
    }

    func handleConnection<URLActivation>(
        _ activation: SceneConnectionActivation<URLActivation>,
        routeURL: (URLActivation) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioAppLifecycleHandlingResult {
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

    func handleOpenURLs<URLActivation>(
        _ urlActivations: [URLActivation],
        route: (URLActivation) -> Bool
    ) -> CioAppLifecycleHandlingResult {
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

/// Routes URL activations owned by a SwiftUI app lifecycle.
///
/// A `UIApplicationDelegateAdaptor` may still own application-global initialization, token, and
/// notification callbacks, but it must not route the same UI activation through an AppDelegate
/// lifecycle coordinator. Each invocation represents a new activation occurrence.
@available(iOSApplicationExtension, unavailable)
@MainActor
public final class CioSwiftUILifecycleCoordinator {
    /// Creates a SwiftUI lifecycle coordinator.
    public init() {}

    /// Handles one URL delivered by a SwiftUI host's `onOpenURL` callback.
    @discardableResult
    public func handleOpenURL(
        _ url: URL,
        route: (URL) -> Bool
    ) -> CioAppLifecycleHandlingResult {
        route(url) ? .handled : .unhandled
    }
}
#endif
