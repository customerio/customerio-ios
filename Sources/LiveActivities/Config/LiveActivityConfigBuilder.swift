import CioInternalCommon
import Foundation
#if os(iOS)
import ActivityKit
#endif

/// Fluent builder for `LiveActivityConfig`.
///
/// ```swift
/// LiveActivityConfigBuilder(baseURL: URL(string: "https://…")!)
///     .logLevel(.debug)
///     .appGroup("group.io.customer.example")
///     .build()
/// ```
public struct LiveActivityConfigBuilder {
    private var config: LiveActivityConfig

    /// Create a builder, optionally specifying the Live Activities API base URL.
    ///
    /// - Parameter baseURL: Base URL of the Live Activities API endpoint. Pass `nil`
    ///   (the default) to produce a module that compiles and runs but makes no network
    ///   requests. Update to a real URL before shipping.
    public init(baseURL: URL? = nil) {
        self.config = LiveActivityConfig(liveActivitiesBaseURL: baseURL)
    }

    // MARK: - Fluent configuration

    /// Set the base URL of the Live Activities API endpoint.
    ///
    /// - Note: This is a temporary field while backend endpoint paths are being finalised.
    public func baseURL(_ url: URL) -> Self {
        var copy = self
        copy.config.liveActivitiesBaseURL = url
        return copy
    }

    /// Override the SDK-wide log level for the Live Activities module only.
    public func logLevel(_ level: CioLogLevel) -> Self {
        var copy = self
        copy.config.logLevel = level
        return copy
    }

    /// Register an `ActivityAttributes` type for SDK observation.
    ///
    /// The SDK will monitor all live activities whose attributes type is `T`,
    /// reporting content state changes and push-to-start token rotations to the
    /// Customer.io backend. Call once per distinct `ActivityAttributes` type.
    ///
    /// - Parameters:
    ///   - type: The `ActivityAttributes` conformance to observe.
    ///   - identifier: A stable reverse-DNS identifier for this activity type,
    ///     e.g. `"io.customer.liveactivities.scoreboard"`. Used in API paths and
    ///     matched server-side to route pushes to the correct devices. Must be
    ///     consistent between the app and the Customer.io backend configuration.
    #if os(iOS)
    @available(iOS 17.2, *)
    public func register<T: CIOActivityAttribute>(_ type: T.Type, identifier: String) -> Self {
        var copy = self
        let registration = ActivityTypeRegistration(
            activityIdentifier: identifier,
            startObserving: { onPushToStartToken, onInstancePushToken, onActivityObserved, onStateUpdate, onEnd in
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await token in Activity<T>.pushToStartTokenUpdates {
                                await onPushToStartToken(token)
                            }
                        }
                        group.addTask {
                            await withTaskGroup(of: Void.self) { perActivityGroup in
                                for await activity in Activity<T>.activityUpdates {
                                    perActivityGroup.addTask {
                                        await Self.observeActivity(
                                            activity,
                                            onInstancePushToken: onInstancePushToken,
                                            onActivityObserved: onActivityObserved,
                                            onStateUpdate: onStateUpdate,
                                            onEnd: onEnd
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            },
            endAllActivities: {
                for activity in Activity<T>.activities {
                    await activity.end(dismissalPolicy: .immediate)
                }
            }
        )
        copy.config.registrations.append(registration)
        return copy
    }

    @available(iOS 17.2, *)
    private static func observeActivity<T: CIOActivityAttribute>(
        _ activity: Activity<T>,
        onInstancePushToken: @escaping (String, Data) async -> Void,
        onActivityObserved: @escaping (String) async -> Void,
        onStateUpdate: @escaping (String, Data) async -> Void,
        onEnd: @escaping (String) async -> Void
    ) async {
        let activityId = activity.attributes.activityInstanceId
        await onActivityObserved(activityId)
        // Instance push token — must be observed before state/lifecycle
        // so the backend has a valid token before any update arrives.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await token in activity.pushTokenUpdates {
                    await onInstancePushToken(activityId, token)
                }
            }
            group.addTask {
                let encoder = JSONEncoder()
                for await update in activity.contentUpdates {
                    if let data = try? encoder.encode(update.state) {
                        await onStateUpdate(activityId, data)
                    }
                }
            }
            group.addTask {
                for await state in activity.activityStateUpdates {
                    switch state {
                    case .ended, .dismissed, .stale:
                        await onEnd(activityId)
                    case .active, .pending:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
    }
    #endif

    /// Declare the AppGroup container identifier used to share pre-loaded image assets
    /// with the widget extension.
    ///
    /// The identifier must match the AppGroup declared in both the app target's and the
    /// widget extension target's entitlements.
    public func appGroup(_ identifier: String) -> Self {
        var copy = self
        copy.config.appGroupIdentifier = identifier
        return copy
    }

    /// Register a bundle asset for pre-loading into the AppGroup container.
    ///
    /// The asset is copied on first use and on any subsequent change (detected via
    /// SHA-256 hash). Assets are addressed by `key` in the widget extension.
    ///
    /// - Parameters:
    ///   - key: The string key used to retrieve this asset in the widget extension.
    ///   - url: The source URL of the asset file within the app bundle.
    public func registerAsset(_ key: String, at url: URL) -> Self {
        var copy = self
        copy.config.assetRegistrations.append(AssetRegistration(key: key, sourceURL: url))
        return copy
    }

    /// Register a named bundle resource for pre-loading into the AppGroup container.
    ///
    /// Resolves the resource via `Bundle.main.url(forResource:withExtension:)` and
    /// calls `fatalError` with a diagnostic message if the resource is not found, so
    /// misconfigured asset keys surface immediately at launch.
    ///
    /// - Parameters:
    ///   - key: The string key used to retrieve this asset in the widget extension.
    ///   - bundleResource: The resource name as passed to `Bundle.main.url(forResource:withExtension:)`.
    ///   - withExtension: The file extension, or `nil` to match any extension.
    public func registerAsset(
        _ key: String,
        bundleResource: String,
        withExtension ext: String? = nil
    ) -> Self {
        guard let url = Bundle.main.url(forResource: bundleResource, withExtension: ext) else {
            fatalError(
                "[CustomerIO] Asset '\(bundleResource)' declared for key '\(key)' "
                    + "was not found in the app bundle. "
                    + "Ensure the file is included in the app target's Copy Bundle Resources phase."
            )
        }
        return registerAsset(key, at: url)
    }

    // MARK: - Build

    public func build() -> LiveActivityConfig { config }
}
