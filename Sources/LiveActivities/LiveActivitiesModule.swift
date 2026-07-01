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
///     OrderAttributes(activityInstanceId: id, ...)
/// }
/// await handle.update(.init(...))
/// await handle.end(.init(...))
/// ```
public final class LiveActivitiesModule {
    private let config: LiveActivityConfig
    private let sdk: CIOLiveActivitiesSDKProviding

    private let identity = LiveActivityIdentity()
    private let reporter: LiveActivityReporter
    private let registrar: LiveActivityRegistrar
    private let observer: LiveActivityObserver

    private let observedContinuation = Synchronized<AsyncStream<LiveActivityInfo>.Continuation?>(nil)
    private let observedStream = Synchronized<AsyncStream<LiveActivityInfo>?>(nil)

    // MARK: - Public API

    /// Emits a `LiveActivityInfo` each time the SDK begins observing a new activity instance
    /// (host-app-initiated, push-to-start, or launch replay).
    ///
    /// > Note: This is a single-consumer stream. Iterate it from exactly one place. It buffers up
    /// > to 10 events for subscribers that attach shortly after `initialize`, and is finished and
    /// > replaced on `ResetEvent` — re-subscribe after any subsequent reset.
    public var observedActivities: AsyncStream<LiveActivityInfo> {
        observedStream.wrappedValue ?? AsyncStream { _ in }
    }

    // MARK: - Entry point

    /// Initialize the Live Activities module. Call after `CustomerIO.initialize(withConfig:)`.
    /// Hold the returned instance for the app's lifetime — it is not a singleton.
    @discardableResult
    public static func initialize(_ config: LiveActivityConfig) -> LiveActivitiesModule {
        let sdk = CustomerIO.shared
        let module = LiveActivitiesModule(
            config: config,
            sdk: sdk,
            tokenStorage: StorageManagerActivityTokenStore(storage: sdk.storageManager)
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

        self.observer = LiveActivityObserver(
            registrations: config.registrations,
            registrar: registrar,
            onActivityAppeared: { [identity, observedContinuation] notificationType, activityInstanceId in
                let info = LiveActivityInfo(
                    activityId: activityInstanceId,
                    activityType: notificationType,
                    userId: identity.userId ?? ""
                )
                observedContinuation.wrappedValue?.yield(info)
            }
        )

        makeNewObservedActivitiesStream()
    }

    // MARK: - Local lifecycle API

    #if os(iOS)
    /// Start a Live Activity locally. The SDK mints the correlation id, passes it to your
    /// `attributes` builder, requests the activity, and reports a `start` event.
    ///
    /// - Returns: A handle whose `update`/`end` report the corresponding events.
    /// - Throws: `LiveActivityError.typeNotRegistered` if `Attributes` was not registered.
    @available(iOS 17.2, *)
    @discardableResult
    public func start<Attributes: CIOActivityAttribute>(
        contentState: Attributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Double = 0,
        attributes: (_ activityInstanceId: String) -> Attributes
    ) throws -> CIOLiveActivity<Attributes> {
        guard let notificationType = notificationType(forTypeName: String(describing: Attributes.self)) else {
            throw LiveActivityError.typeNotRegistered(String(describing: Attributes.self))
        }
        let id = UUID().uuidString.lowercased()
        let activity = try Activity.request(
            attributes: attributes(id),
            content: ActivityContent(state: contentState, staleDate: staleDate, relevanceScore: relevanceScore),
            pushType: .token
        )
        reporter.reportStart(
            instanceUUID: id,
            notificationType: notificationType,
            payload: LiveActivityReporter.payload(from: contentState)
        )
        return CIOLiveActivity(id: id, activity: activity, reporter: reporter, notificationType: notificationType)
    }

    /// Wrap an activity your app created directly, so you can report `update`/`end` through the
    /// returned handle. Does not report a `start` event (use `start` for that). Token capture for
    /// registered types happens automatically via observation regardless of `adopt`.
    @available(iOS 17.2, *)
    @discardableResult
    public func adopt<Attributes: CIOActivityAttribute>(_ activity: Activity<Attributes>) -> CIOLiveActivity<Attributes> {
        let notificationType = notificationType(forTypeName: String(describing: Attributes.self))
            ?? String(describing: Attributes.self)
        return CIOLiveActivity(
            id: activity.attributes.activityInstanceId,
            activity: activity,
            reporter: reporter,
            notificationType: notificationType
        )
    }
    #endif

    // MARK: - Private

    private func notificationType(forTypeName name: String) -> String? {
        config.registrations.first { $0.attributesTypeName == name }?.activityIdentifier
    }

    private func makeNewObservedActivitiesStream() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LiveActivityInfo.self,
            bufferingPolicy: .bufferingNewest(10)
        )
        observedContinuation.wrappedValue = continuation
        observedStream.wrappedValue = stream
    }

    private func performInitialization() {
        sdk.logger.debug("LiveActivities module initialized.", "LiveActivities")

        identity.deviceToken = sdk.registeredDeviceToken

        syncAssets()
        registerEventBusObservers()
        observer.start()
    }

    /// Copy new or changed bundle assets into the AppGroup container, off the init thread.
    ///
    /// Skipped silently when no AppGroup identifier or no asset registrations are configured.
    /// Failures are logged and do not prevent observation from starting.
    private func syncAssets() {
        guard
            let appGroupIdentifier = config.appGroupIdentifier,
            !config.assetRegistrations.isEmpty
        else { return }

        let registrations = config.assetRegistrations
        let logger = sdk.logger
        Task.detached(priority: .utility) {
            do {
                let writer = try AssetLibraryWriter(appGroupIdentifier: appGroupIdentifier)
                try writer.sync(registrations: registrations)
            } catch {
                logger.error("Live Activities asset sync failed: \(error)", "LiveActivities", nil)
            }
        }
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
        for registration in config.registrations {
            await registration.endAllActivities()
        }
        identity.userId = nil
        registrar.handleReset()
        observer.restart()
        observedContinuation.wrappedValue?.finish()
        makeNewObservedActivitiesStream()
    }
}
