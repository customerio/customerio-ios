import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

/// Fluent builder for `LiveActivityConfig`.
///
/// ```swift
/// LiveActivityConfigBuilder()
///     .logLevel(.debug)
///     .register(OrderAttributes.self, identifier: "io.customer.liveactivities.order")
///     .appGroup("group.io.customer.example")
///     .build()
/// ```
public struct LiveActivityConfigBuilder {
    private var config: LiveActivityConfig

    public init() {
        self.config = LiveActivityConfig()
    }

    // MARK: - Fluent configuration

    /// Override the SDK-wide log level for the Live Activities module only.
    public func logLevel(_ level: CioLogLevel) -> Self {
        var copy = self
        copy.config.logLevel = level
        return copy
    }

    /// Register an `ActivityAttributes` type for SDK observation.
    ///
    /// The SDK monitors all live activities whose attributes type is `T`, forwarding
    /// push-to-start and per-instance push tokens to the Customer.io backend, and enables the
    /// local `start`/`update`/`end` API for this type. Call once per distinct type.
    ///
    /// - Parameters:
    ///   - type: The `ActivityAttributes` conformance to observe.
    ///   - identifier: A stable reverse-DNS identifier for this activity type,
    ///     e.g. `"io.customer.liveactivities.scoreboard"`. Sent as `notificationType` and matched
    ///     server-side to route pushes. Must be consistent between the app and the backend.
    #if os(iOS)
    @available(iOS 17.2, *)
    public func register<T: CIOActivityAttribute>(_ type: T.Type, identifier: String) -> Self {
        var copy = self
        copy.config.registrations.append(
            LiveActivityObservation.registration(for: T.self, identifier: identifier)
        )
        return copy
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
    /// Resolves the resource via `Bundle.main.url(forResource:withExtension:)` and calls
    /// `assertionFailure` (fatal in debug, no-op in release) if the resource is not found, so
    /// misconfigured asset keys surface immediately during development.
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
            assertionFailure(
                "[CustomerIO] Asset '\(bundleResource)' declared for key '\(key)' "
                    + "was not found in the app bundle. "
                    + "Ensure the file is included in the app target's Copy Bundle Resources phase."
            )
            return self
        }
        return registerAsset(key, at: url)
    }

    // MARK: - Build

    public func build() -> LiveActivityConfig {
        config
    }
}
