import CioInternalCommon
import Foundation

#if canImport(UIKit)
import UIKit

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
    /// Exactly one URL, user activity, or shortcut is accepted. Multiple UI candidates are
    /// ambiguous and no routing closure is called. A notification response is independently
    /// application-owned, so its presence never suppresses one valid scene-owned UI activation.
    @discardableResult
    public func handleConnection(
        options connectionOptions: UIScene.ConnectionOptions,
        routeURL: (UIOpenURLContext) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioSceneLifecycleHandlingResult {
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
    ) -> CioSceneLifecycleHandlingResult {
        handleOpenURLs(Array(urlContexts), route: route)
    }

    func handleConnection<URLActivation>(
        _ activation: SceneConnectionActivation<URLActivation>,
        routeURL: (URLActivation) -> Bool,
        continueUserActivity: (NSUserActivity) -> Bool,
        performShortcut: (UIApplicationShortcutItem) -> Bool
    ) -> CioSceneLifecycleHandlingResult {
        let candidateCount = activation.urlActivations.count
            + activation.userActivities.count
            + (activation.shortcutItem == nil ? 0 : 1)
        guard candidateCount <= 1 else {
            return rejectAmbiguous(callback: "scene connection", candidateCount: candidateCount)
        }
        guard candidateCount == 1 else {
            return activation.hasNotificationResponse ? .notificationOwnedByApplication : .noActivation
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
    ) -> CioSceneLifecycleHandlingResult {
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
    ) -> CioSceneLifecycleHandlingResult {
        loggerProvider().error(
            "CIO: Ignoring \(callback) because it contains \(candidateCount) activation candidates."
        )
        return .rejectedAmbiguousInput
    }

    private func routeOnce(_ route: () -> Bool) -> CioSceneLifecycleHandlingResult {
        route() ? .handled : .unhandled
    }
}
#endif
