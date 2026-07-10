import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit
#endif

/// Errors thrown by the Live Activities public API.
public enum LiveActivityError: Error {
    /// `start` was called for an attributes type that was not passed to
    /// `LiveActivityConfigBuilder.register(_:identifier:)`.
    case typeNotRegistered(String)
}

/// Live Activities module for the Customer.io SDK.
///
/// Call `initialize` after `CustomerIO.initialize(withConfig:)` and hold the returned instance
/// for the lifetime of your app:
/// ```swift
/// CustomerIO.initialize(withConfig: config)
/// let liveActivities = LiveActivitiesModule.initialize(
///     LiveActivityConfigBuilder()
///         .register(OrderAttributes.self, identifier: "io.customer.liveactivities.order")
///         .build()
/// )
/// // Start an activity locally — the SDK mints its id and reports a `start` event:
/// let handle = try liveActivities.start(contentState: .init(...)) { id in
///     OrderAttributes(cioInstanceId: id, ...)
/// }
/// await handle.update(.init(...))
/// await handle.end(.init(...))
/// ```
public final class LiveActivitiesModule {
    private let config: LiveActivityConfig
    private let sdk: CIOLiveActivitiesSDKProviding
    private let tokenStorage: LiveActivityTokenStorage

    private let identity = LiveActivityIdentity()
    private let localEndTracker = LiveActivityLocalEndTracker()
    private let reporter: LiveActivityReporter
    private let registrar: LiveActivityRegistrar
    private let deliveryTracker: LiveActivityDeliveryTracker
    private let observer: LiveActivityObserver

    /// Latest delivery metadata observed per activity instance, used to attribute an `opened`
    /// metric and resolve the deep link when the app is opened from a tapped activity.
    private let latestMetadata = Synchronized<[String: CIOLiveActivityMetadata]>([:])

    // MARK: - Entry point

    /// Initialize the Live Activities module. Call after `CustomerIO.initialize(withConfig:)`.
    /// Hold the returned instance for the app's lifetime — it is not a singleton.
    @discardableResult
    public static func initialize(_ config: LiveActivityConfig) -> LiveActivitiesModule {
        let sdk = CustomerIO.shared
        let module = LiveActivitiesModule(
            config: config,
            sdk: sdk,
            tokenStorage: KeyValueLiveActivityTokenStore(storage: sdk.sharedKeyValueStorage)
        )
        module.performInitialization()
        return module
    }

    // MARK: - Init (also used by tests)

    init(
        config: LiveActivityConfig,
        sdk: CIOLiveActivitiesSDKProviding,
        tokenStorage: LiveActivityTokenStorage
    ) {
        self.config = config
        self.sdk = sdk
        self.tokenStorage = tokenStorage

        let identity = self.identity
        let reporter = LiveActivityReporter(
            track: { name, properties in sdk.track(name: name, properties: properties) },
            currentUserId: { identity.userId },
            deviceToken: { identity.deviceToken },
            logger: sdk.logger
        )
        let registrar = LiveActivityRegistrar(identity: identity, store: tokenStorage, reporter: reporter)
        self.reporter = reporter
        self.registrar = registrar

        let deliveryTracker = LiveActivityDeliveryTracker(
            postMetric: { [sdk] deliveryId, event, deliveryToken in
                sdk.eventBusHandler.postEvent(
                    TrackMetricEvent(deliveryID: deliveryId, event: event, deviceToken: deliveryToken)
                )
            },
            store: tokenStorage,
            logger: sdk.logger
        )
        self.deliveryTracker = deliveryTracker

        self.observer = LiveActivityObserver(
            registrations: config.registrations,
            registrar: registrar,
            localEndTracker: localEndTracker,
            store: tokenStorage,
            onUserDismissed: { [reporter] notificationType, cioInstanceId in
                // A user swipe-away — report `end` (matches Android's dismiss-intent behavior).
                reporter.reportEnd(instanceUUID: cioInstanceId, notificationType: notificationType)
            },
            onContentMetadata: { [deliveryTracker, latestMetadata] _, cioInstanceId, metadata in
                // A backend push (start or update) carrying Customer.io delivery metadata: report a
                // `delivered` receipt (deduped by delivery id) and remember the tap destination.
                latestMetadata.mutating { $0[cioInstanceId] = metadata }
                deliveryTracker.reportDelivered(metadata: metadata)
            },
            onActivityEnded: { [latestMetadata] cioInstanceId in
                // Drop the tap destination once the activity terminates, so a later open of the same
                // URL can't be misattributed to this (ended) delivery.
                latestMetadata.mutating { $0[cioInstanceId] = nil }
            }
        )
    }

    // MARK: - Local lifecycle API

    #if os(iOS)
    /// Start a Live Activity locally. Pass your fully-built `attributes` and initial
    /// `contentState`; the SDK requests the activity, mints and tracks its correlation id
    /// internally, and reports a `start` event. You never supply or see the id at the call site.
    ///
    /// Works with any `ActivityAttributes` type — conforming to `CIOActivityAttribute` is only
    /// required for push-to-start.
    ///
    /// - Returns: A handle whose `update`/`end` report the corresponding events.
    /// - Throws: `LiveActivityError.typeNotRegistered` if `Attributes` was not registered.
    @available(iOS 16.2, *)
    @discardableResult
    public func start<Attributes: ActivityAttributes>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Double = 0
    ) throws -> CIOLiveActivity<Attributes> {
        guard let notificationType = notificationType(forTypeName: String(describing: Attributes.self)) else {
            throw LiveActivityError.typeNotRegistered(String(describing: Attributes.self))
        }
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: contentState, staleDate: staleDate, relevanceScore: relevanceScore),
            pushType: .token
        )
        // Mint (and persist) the correlation id keyed by the system Activity.id, atomically so the
        // registration observer picking up this same activity resolves to the identical id.
        let id = tokenStorage.resolveInstanceId(forActivityId: activity.id) { ULID.generate() }
        reporter.reportStart(
            instanceUUID: id,
            notificationType: notificationType,
            attributes: LiveActivityReporter.encode(attributes),
            contentState: LiveActivityReporter.encode(contentState)
        )
        return CIOLiveActivity(
            id: id,
            activity: activity,
            reporter: reporter,
            notificationType: notificationType,
            logger: sdk.logger,
            markLocalEnd: { [localEndTracker] in localEndTracker.markEnded($0) }
        )
    }

    /// Wrap an activity your app created directly, so you can report `update`/`end` through the
    /// returned handle. Does not report a `start` event (use `start` for that). Token capture for
    /// registered types happens automatically via observation regardless of `adopt`. Works with any
    /// `ActivityAttributes` type.
    @available(iOS 16.2, *)
    @discardableResult
    public func adopt<Attributes: ActivityAttributes>(_ activity: Activity<Attributes>) -> CIOLiveActivity<Attributes> {
        let notificationType = notificationType(forTypeName: String(describing: Attributes.self))
            ?? String(describing: Attributes.self)
        let id = tokenStorage.resolveInstanceId(forActivityId: activity.id) { ULID.generate() }
        return CIOLiveActivity(
            id: id,
            activity: activity,
            reporter: reporter,
            notificationType: notificationType,
            logger: sdk.logger,
            markLocalEnd: { [localEndTracker] in localEndTracker.markEnded($0) }
        )
    }
    #endif

    // MARK: - Deep link / open tracking

    /// Report an `opened` metric when the app is opened from a tapped Live Activity. Call this from
    /// your `UIApplicationDelegate.application(_:open:options:)` /
    /// `UISceneDelegate.scene(_:openURLContexts:)` — the same place you already route your app's
    /// deep links — mirroring how push taps are forwarded to the SDK.
    ///
    /// If the URL matches a Customer.io-tracked activity's deep link, the SDK reports an `opened`
    /// metric (the same metric normal push uses) and returns `true`. Returns `false` for unrelated
    /// URLs. Navigation stays with your existing URL routing: because a Live Activity tap arrives
    /// through the normal `openURL` path (not a push-tap callback), the SDK does not re-open the URL
    /// — that would re-enter `openURL` and loop.
    @discardableResult
    public func handleDeepLinkOpen(_ url: URL) -> Bool {
        let target = url.absoluteString
        let matched: CIOLiveActivityMetadata? = latestMetadata.mutating { map in
            guard let key = map.first(where: { $0.value.deepLink == target })?.key else { return nil }
            // Attribute the open exactly once: remove the entry so a repeated open of the same URL
            // isn't reported again against an activity we've already credited.
            return map.removeValue(forKey: key)
        }
        guard let metadata = matched else { return false }
        deliveryTracker.reportOpened(metadata: metadata)
        return true
    }

    // MARK: - Private

    private func notificationType(forTypeName name: String) -> String? {
        config.registrations.first { $0.attributesTypeName == name }?.activityIdentifier
    }

    private func performInitialization() {
        // Apply the optional module log-level override. The SDK exposes a single shared logger, so
        // this raises/lowers the level used by Live Activities logging (and the shared logger with it);
        // when `nil` the existing SDK-wide level is left untouched.
        if let logLevel = config.logLevel {
            sdk.logger.setLogLevel(logLevel)
        }

        sdk.logger.debug("LiveActivities module initialized.", "LiveActivities")

        identity.deviceToken = sdk.registeredDeviceToken

        // Seed any persisted push-to-start token before adding observers: the event-bus replays the
        // last identify / device-token events to the new observers, and that replay flushes the
        // seeded token — so registration no longer depends on ActivityKit re-yielding the token.
        registrar.seedPendingPushToStartFromStore()

        registerEventBusObservers()
        observer.start()
    }

    private func registerEventBusObservers() {
        sdk.eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [identity, registrar] event in
            identity.userId = event.identifier
            registrar.reevaluate()
        }
        sdk.eventBusHandler.addObserver(AnonymousProfileIdentifiedEvent.self) { [identity] _ in
            // An anonymous profile is not an identified user — Live Activities stay gated off.
            identity.userId = nil
        }
        sdk.eventBusHandler.addObserver(RegisterDeviceTokenEvent.self) { [identity, registrar] event in
            identity.deviceToken = event.token
            registrar.reevaluate()
        }
        sdk.eventBusHandler.addObserver(DeleteDeviceTokenEvent.self) { [identity] _ in
            identity.deviceToken = nil
        }
        sdk.eventBusHandler.addObserver(ResetEvent.self) { [weak self] _ in
            Task { [weak self] in await self?.handleReset() }
        }
    }

    private func handleReset() async {
        // NOTE: force-ending all activities on reset is under review (plan decision #2) —
        // it may remove activities the user still wants and emits no `end` event.
        //
        // Clear the identified user *before* force-ending: reset is a logout, so no lifecycle
        // event should fire, and gating the reporter off first ensures the terminal states these
        // ends produce can't be misreported as user dismissals (the reporter drops when anonymous).
        identity.userId = nil
        localEndTracker.clearAll()
        latestMetadata.wrappedValue = [:]
        for registration in config.registrations {
            await registration.endAllActivities()
        }
        registrar.handleReset()
        observer.restart()
    }
}
