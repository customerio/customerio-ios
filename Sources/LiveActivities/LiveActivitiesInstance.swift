import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit
#endif

// MARK: - LiveActivitiesInstance

/// The public Live Activities API surface, accessed via ``CustomerIO/liveActivities``.
///
/// Register the module with `SDKConfigBuilder.addModule(LiveActivitiesModule(config: ...))` before
/// `CustomerIO.initialize(withConfig:)`. Before initialization (or on iOS < 16.2) the accessor
/// returns a stub that logs an error and no-ops — it never throws or crashes because the module
/// wasn't ready yet.
///
/// **Example:**
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LiveActivitiesModule(config:
///         LiveActivityConfigBuilder()
///             .register(CIOSegmentsAttributes.self)
///             .register(CIOCountdownTimerAttributes.self)
///             .build()))
///     .build()
/// CustomerIO.initialize(withConfig: config)
///
/// let handle = try CustomerIO.liveActivities.start(CIOSegmentsAttributes(header: "…"), contentState: .init(…))
/// ```
public protocol LiveActivitiesInstance: AnyObject {
    #if os(iOS)
    /// Start a Live Activity locally. Pass your fully-built `attributes` and initial
    /// `contentState`; the SDK requests the activity, mints and tracks its correlation id
    /// internally, and reports a `start` event.
    ///
    /// Works with any `ActivityAttributes` type — conforming to `CIOActivityAttribute` is only
    /// required for push-to-start.
    ///
    /// - Returns: A handle whose `update`/`end` report the corresponding events, or `nil` when the
    ///   module isn't initialized or `Attributes` wasn't registered — both are logged, never thrown,
    ///   so an initialization-timing race can't surface an error to the host app.
    /// - Throws: rethrows ActivityKit's `Activity.request` error (e.g. the user disabled Live
    ///   Activities, or the device doesn't support them) — a genuine runtime condition to handle.
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: ActivityAttributes>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date?,
        relevanceScore: Double
    ) throws -> CIOLiveActivity<Attributes>?

    /// Start a Live Activity locally for a push-to-start-capable `CIOActivityAttribute` type. Same
    /// as the generic `start`, except the SDK mints the correlation id and injects it into
    /// `cioInstanceId` on your attributes before requesting the activity, matching the
    /// push-to-start contract.
    ///
    /// - Returns: A handle, or `nil` when the module isn't initialized or `Attributes` wasn't
    ///   registered (logged, never thrown).
    /// - Throws: rethrows ActivityKit's `Activity.request` error.
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: CIOActivityAttribute>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date?,
        relevanceScore: Double
    ) throws -> CIOLiveActivity<Attributes>?

    /// Wrap an activity your app created directly, so you can report `update`/`end` through the
    /// returned handle. Does not report a `start` event (use `start` for that).
    ///
    /// - Returns: A handle, or `nil` when the module isn't initialized (logged, never thrown) — so
    ///   the caller can end the just-created activity rather than leaking it.
    @available(iOS 16.2, *)
    @discardableResult
    func adopt<Attributes: ActivityAttributes>(_ activity: Activity<Attributes>) -> CIOLiveActivity<Attributes>?
    #endif

    /// Report an `opened` for a Customer.io Live Activity tracking URL (the one the `cioWidgetUrl(_:)`
    /// widget modifier builds), and return the customer's deep link to navigate to.
    ///
    /// Call this from your `UISceneDelegate.scene(_:openURLContexts:)` /
    /// `UIApplicationDelegate.application(_:open:options:)` for each opened URL:
    /// - If `url` is a Customer.io tracking URL, the SDK reports an `opened` for the **exact delivery**
    ///   the user tapped and returns its `redirect` deep link (`nil` if none) for you to route.
    /// - Otherwise `url` is returned unchanged, so your existing routing handles non-CIO URLs.
    @discardableResult
    func handleWidgetUrl(_ url: URL) -> URL?
}

#if os(iOS)
public extension LiveActivitiesInstance {
    /// Convenience `start` using the default `staleDate` (`nil`) and `relevanceScore` (`0`).
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: ActivityAttributes>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState
    ) throws -> CIOLiveActivity<Attributes>? {
        try start(attributes, contentState: contentState, staleDate: nil, relevanceScore: 0)
    }

    /// Convenience `start` (push-to-start overload) using the default `staleDate` and `relevanceScore`.
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: CIOActivityAttribute>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState
    ) throws -> CIOLiveActivity<Attributes>? {
        try start(attributes, contentState: contentState, staleDate: nil, relevanceScore: 0)
    }
}
#endif

// MARK: - UninitializedLiveActivities

/// Stub returned by ``CustomerIO/liveActivities`` before the module is initialized (or on iOS < 16.2).
/// Every call logs an error and no-ops — it never throws or crashes, so a call made before
/// `CustomerIO.initialize(withConfig:)` finishes can't surface an error to a production host app.
final class UninitializedLiveActivities: LiveActivitiesInstance {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    #if os(iOS)
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: ActivityAttributes>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date?,
        relevanceScore: Double
    ) throws -> CIOLiveActivity<Attributes>? {
        logger.moduleNotInitialized()
        return nil
    }

    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: CIOActivityAttribute>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date?,
        relevanceScore: Double
    ) throws -> CIOLiveActivity<Attributes>? {
        logger.moduleNotInitialized()
        return nil
    }

    @available(iOS 16.2, *)
    @discardableResult
    func adopt<Attributes: ActivityAttributes>(_ activity: Activity<Attributes>) -> CIOLiveActivity<Attributes>? {
        logger.moduleNotInitialized()
        return nil
    }
    #endif

    @discardableResult
    func handleWidgetUrl(_ url: URL) -> URL? {
        logger.moduleNotInitialized()
        return url
    }
}
