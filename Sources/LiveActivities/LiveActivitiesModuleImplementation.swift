import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit
#endif

/// Runtime implementation of the Live Activities module, returned by ``CustomerIO/liveActivities``
/// once the module has been registered and initialized.
///
/// Register the module via `SDKConfigBuilder.addModule(LiveActivitiesModule(config: ...))` before
/// `CustomerIO.initialize(withConfig:)`, then drive activities through ``CustomerIO/liveActivities``:
/// ```swift
/// let handle = try CustomerIO.liveActivities.start(OrderAttributes(...), contentState: .init(...))
/// await handle?.update(.init(...))
/// await handle?.end(.init(...))
/// ```
final class LiveActivitiesModuleImplementation: LiveActivitiesInstance {
    private let config: LiveActivityConfig
    private let sdk: CIOLiveActivitiesSDKProviding
    private let tokenStorage: LiveActivityTokenStorage

    private let identity = LiveActivityIdentity()
    private let localEndTracker: LiveActivityLocalEndTracker
    private let reporter: LiveActivityReporter
    private let registrar: LiveActivityRegistrar
    private let deliveryTracker: LiveActivityDeliveryTracker
    private let observer: LiveActivityObserver

    // MARK: - Init (created by LiveActivitiesModuleState; also used by tests)

    init(
        config: LiveActivityConfig,
        sdk: CIOLiveActivitiesSDKProviding,
        tokenStorage: LiveActivityTokenStorage,
        localEndTracker: LiveActivityLocalEndTracker = LiveActivityLocalEndTracker()
    ) {
        self.config = config
        self.sdk = sdk
        self.tokenStorage = tokenStorage
        self.localEndTracker = localEndTracker

        let identity = self.identity
        let reporter = LiveActivityReporter(
            track: { name, properties in sdk.track(name: name, properties: properties) },
            // Gate on the SDK's synchronous identified flag (backed by DataPipelineTracking),
            // not the async event-bus-fed identity cache, so a start() right after identify()
            // isn't dropped. Token registration still uses `identity` via the registrar.
            isUserIdentified: { sdk.isUserIdentified },
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
            onContentMetadata: { [deliveryTracker] _, _, metadata in
                // A backend push (start or update) carrying Customer.io delivery metadata: report a
                // `delivered` receipt (deduped by delivery id). Open attribution is carried in the
                // `cioWidgetUrl` tap URL (see `handleWidgetUrl`), so no per-instance cache is kept.
                deliveryTracker.reportDelivered(metadata: metadata)
            },
            onActivityEnded: { _ in
                // No per-instance state to evict: `handleWidgetUrl` attributes opens from the tapped
                // URL itself, not an observed-metadata cache.
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
    /// - Returns: A handle whose `update`/`end` report the corresponding events, or `nil` when
    ///   `Attributes` was not registered (logged, not thrown).
    /// - Throws: rethrows ActivityKit's `Activity.request` error.
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: ActivityAttributes>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date?,
        relevanceScore: Double
    ) throws -> CIOLiveActivity<Attributes>? {
        guard let notificationType = notificationType(forTypeName: String(describing: Attributes.self)) else {
            sdk.logger.liveActivityTypeNotRegistered(String(describing: Attributes.self))
            return nil
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

    /// Start a Live Activity locally for a `CIOActivityAttribute` type. Same as the generic
    /// `start`, except the SDK mints the correlation id and **injects it into `cioInstanceId`** on
    /// your attributes *before* requesting the activity — so the live activity itself, the reported
    /// `start` event, and later token registrations all carry the identical id, matching the
    /// push-to-start contract. Overload resolution prefers this over the generic `start` whenever
    /// `Attributes` conforms to `CIOActivityAttribute`.
    @available(iOS 16.2, *)
    @discardableResult
    func start<Attributes: CIOActivityAttribute>(
        _ attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date?,
        relevanceScore: Double
    ) throws -> CIOLiveActivity<Attributes>? {
        guard let notificationType = notificationType(forTypeName: String(describing: Attributes.self)) else {
            sdk.logger.liveActivityTypeNotRegistered(String(describing: Attributes.self))
            return nil
        }
        // Mint first and inject, so the activity carries the id (a plain ActivityAttributes type has
        // no field to hold it). Persist the Activity.id → id mapping so the observer and relaunch
        // recovery resolve the identical id even though the mint happened here.
        let id = ULID.generate()
        var attributes = attributes
        attributes.cioInstanceId = id
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: contentState, staleDate: staleDate, relevanceScore: relevanceScore),
            pushType: .token
        )
        _ = tokenStorage.resolveInstanceId(forActivityId: activity.id) { id }
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
    func adopt<Attributes: ActivityAttributes>(_ activity: Activity<Attributes>) -> CIOLiveActivity<Attributes>? {
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

    // MARK: - Open tracking

    /// Report an `opened` for a Customer.io Live Activity tracking URL (the one the `cioWidgetUrl(_:)`
    /// widget modifier builds), and return the customer's deep link to navigate to.
    ///
    /// Call this from your `UISceneDelegate.scene(_:openURLContexts:)` /
    /// `UIApplicationDelegate.application(_:open:options:)` for each opened URL:
    /// - If `url` is a Customer.io tracking URL, the SDK reports an `opened` for the **exact delivery**
    ///   the user tapped — the identity is carried in the URL, so it needs no observer lookup and works
    ///   even from a cold launch — and returns its `redirect` deep link (`nil` if none) for you to route.
    /// - Otherwise `url` is returned unchanged, so your existing routing handles non-CIO URLs.
    @discardableResult
    func handleWidgetUrl(_ url: URL) -> URL? {
        guard let parsed = CioLiveActivityWidgetUrl.parse(url) else { return url }
        if let deliveryId = parsed.deliveryId, !deliveryId.isEmpty {
            deliveryTracker.reportOpened(
                metadata: CIOLiveActivityMetadata(deliveryId: deliveryId, deliveryToken: parsed.deliveryToken)
            )
        }
        return parsed.redirect
    }

    // MARK: - Private

    private func notificationType(forTypeName name: String) -> String? {
        config.registrations.first { $0.attributesTypeName == name }?.activityIdentifier
    }

    // MARK: - Initialization (called by LiveActivitiesModuleState)

    /// One-time setup: seeds the persisted push-to-start token, registers event-bus observers, and
    /// starts ActivityKit observation. Invoked by `LiveActivitiesModuleState.performInitialization`.
    func performInitialization() {
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

    // Internal (not private) so the reset-suppression behavior can be driven directly in tests
    // without routing through the async event bus.
    func handleReset() async {
        // Reset is a logout: force-end every activity so one user's Live Activities never linger
        // into the next session. No `end` event is reported for these — the user is being
        // de-identified, so lifecycle events must not fire.
        //
        // Each activity is marked as an SDK-initiated (local) end just before it is force-ended, so
        // the `.dismissed` terminal its immediate dismissal produces is consumed by the observer and
        // not reported as a user swipe. Identity-based gating can't suppress this on its own: an
        // account switch — clearIdentify() then identify(B) — puts B into the synchronous identity
        // store before this async reset runs, so A's forced ends would otherwise be reported under B.
        identity.userId = nil
        // Do NOT clear existing local-end markers here: an activity the app ended via
        // CIOLiveActivity.end() just before logout is already gone from Activity.activities, so the
        // force-end loop below won't re-mark it. Dropping its marker would let its late `.dismissed`
        // terminal be misreported as a user swipe (under the next user). Markers are in-memory,
        // one-shot, and ULID-keyed, so keeping them is inert for any other activity.
        for registration in config.registrations {
            await registration.endAllActivities { [tokenStorage, localEndTracker] activityId, attributesInstanceId in
                let instanceId = tokenStorage.resolveInstanceId(forActivityId: activityId) {
                    if let attributesInstanceId, !attributesInstanceId.isEmpty { return attributesInstanceId }
                    return ULID.generate()
                }
                localEndTracker.markEnded(instanceId)
            }
        }
        registrar.handleReset()
        observer.restart()
    }
}
