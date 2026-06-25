import CioInternalCommon
import Foundation

/// Live Activities module for the Customer.io SDK.
///
/// Call `initialize` after `CustomerIO.initialize(withConfig:)` and hold the returned
/// instance for the lifetime of your app:
/// ```swift
/// CustomerIO.initialize(withConfig: config)
/// let liveActivities = LiveActivitiesModule.initialize(
///     LiveActivityConfigBuilder()
///         .register(OrderAttributes.self, identifier: "io.customer.liveactivities.order")
///         .build()
/// )
/// ```
public final class LiveActivitiesModule {
    private let config: LiveActivityConfig
    private let sdk: CIOLiveActivitiesSDKProviding
    private let tokenStorage: LiveActivityTokenStorage

    // MARK: - Synchronized state readable from @Sendable closures

    /// The most recently identified user ID. Updated via ProfileIdentifiedEvent and
    /// AnonymousProfileIdentifiedEvent.
    private let _currentUserId = Synchronized<String?>(nil)

    /// The installation ID captured during initialization. Immutable after that point.
    private let _installationId = Synchronized<String?>(nil)

    /// The most recently registered APNs device token. Updated via RegisterDeviceTokenEvent.
    /// Used to detect a nil-to-real transition so stored push-to-start tokens can be resubmitted
    /// with a valid deviceId if they were originally sent before the token was available.
    private let _registeredDeviceToken = Synchronized<String?>(nil)

    private let _observedActivitiesContinuation = Synchronized<AsyncStream<LiveActivityInfo>.Continuation?>(nil)
    private let _observedActivitiesStream = Synchronized<AsyncStream<LiveActivityInfo>?>(nil)

    #if os(iOS)
    /// Running observation tasks keyed by activity type identifier.
    /// Cancelled and cleared on ResetEvent.
    private let _observationTasks = Synchronized<[String: Task<Void, Never>]>([:])
    #endif

    // MARK: - Public API

    /// Emits a `LiveActivityInfo` each time the SDK begins observing a new activity
    /// instance. Covers all creation paths: host-app-initiated, push-to-start, and
    /// launch replay.
    ///
    /// The stream buffers up to 10 events so subscribers that attach slightly after
    /// `initialize` do not miss activities observed during startup.
    ///
    /// The stream is finished on `ResetEvent`. The host app must re-subscribe after
    /// any subsequent `initialize` call.
    public var observedActivities: AsyncStream<LiveActivityInfo> {
        _observedActivitiesStream.wrappedValue ?? AsyncStream { _ in }
    }

    // MARK: - Public entry point

    /// Initialize the Live Activities module.
    ///
    /// Call this after `CustomerIO.initialize(withConfig:)`. Hold the returned instance
    /// for the lifetime of your app — it is not a singleton.
    ///
    /// - Parameter config: Module configuration built via `LiveActivityConfigBuilder`.
    /// - Returns: The initialized module instance.
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

    // MARK: - Internal inits (for testing)

    init(
        config: LiveActivityConfig,
        sdk: CIOLiveActivitiesSDKProviding,
        tokenStorage: LiveActivityTokenStorage
    ) {
        self.config = config
        self.sdk = sdk
        self.tokenStorage = tokenStorage
        makeNewObservedActivitiesStream()
    }

    // MARK: - Private

    private func makeNewObservedActivitiesStream() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LiveActivityInfo.self,
            bufferingPolicy: .bufferingNewest(10)
        )
        _observedActivitiesContinuation.wrappedValue = continuation
        _observedActivitiesStream.wrappedValue = stream
    }

    private func performInitialization() {
        sdk.logger.debug("LiveActivities module initialized.", "LiveActivities")

        _installationId.wrappedValue = sdk.installationId
        _registeredDeviceToken.wrappedValue = sdk.registeredDeviceToken

        syncAssets()
        registerEventBusObservers()

        #if os(iOS)
        for registration in config.registrations {
            startObserving(registration: registration)
        }
        #endif
    }

    /// Copy new or changed bundle assets into the AppGroup container.
    ///
    /// Skipped silently when no AppGroup identifier or no asset registrations are
    /// configured. Logs a warning on failure — asset sync failure does not prevent
    /// activity observation from starting.
    private func syncAssets() {
        guard
            let appGroupIdentifier = config.appGroupIdentifier,
            !config.assetRegistrations.isEmpty
        else { return }

        do {
            let writer = try AssetLibraryWriter(appGroupIdentifier: appGroupIdentifier)
            try writer.sync(registrations: config.assetRegistrations)
        } catch {
            sdk.logger.error("Live Activities asset sync failed: \(error)", "LiveActivities", nil)
        }
    }

    private func registerEventBusObservers() {
        sdk.eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [weak self] event in
            self?._currentUserId.wrappedValue = event.identifier
        }
        sdk.eventBusHandler.addObserver(AnonymousProfileIdentifiedEvent.self) { [weak self] event in
            self?._currentUserId.wrappedValue = event.identifier
        }
        sdk.eventBusHandler.addObserver(ResetEvent.self) { [weak self] _ in
            Task { [weak self] in await self?.handleReset() }
        }
        sdk.eventBusHandler.addObserver(RegisterDeviceTokenEvent.self) { [weak self] event in
            guard let self else { return }
            let previous = self._registeredDeviceToken.wrappedValue
            self._registeredDeviceToken.wrappedValue = event.token
            let wasAbsent = previous == nil || previous?.isEmpty == true
            guard wasAbsent, !event.token.isEmpty else { return }
            self.resubmitPushToStartTokens(deviceToken: event.token)
        }
    }

    #if os(iOS)
    private func startObserving(registration: ActivityTypeRegistration) {
        let identifier = registration.activityIdentifier
        let sdk = self.sdk
        let installationIdRef = _installationId
        let userIdRef = _currentUserId
        let continuationRef = _observedActivitiesContinuation
        let tokenStorage = self.tokenStorage

        let task = registration.startObserving(
            { token in
                let tokenHex = token.map { String(format: "%02x", $0) }.joined()
                let stored = tokenStorage.getPushToStartToken(activityType: identifier)
                guard stored != tokenHex else { return }
                sdk.track(name: "Live Notification Token", properties: [
                    "registrationType": "push_to_start",
                    "notificationType": identifier,
                    "platform": "ios",
                    "deviceId": sdk.registeredDeviceToken ?? "",
                    "pushToStartToken": tokenHex,
                    "installationId": installationIdRef.wrappedValue ?? ""
                ])
                tokenStorage.setPushToStartToken(activityType: identifier, tokenHex: tokenHex)
            },
            { activityId, token in
                let tokenHex = token.map { String(format: "%02x", $0) }.joined()
                sdk.track(name: "Live Notification Token", properties: [
                    "registrationType": "instance",
                    "notificationType": identifier,
                    "platform": "ios",
                    "instanceUUID": activityId,
                    "instanceToken": tokenHex,
                    "deviceId": sdk.registeredDeviceToken ?? "",
                    "installationId": installationIdRef.wrappedValue ?? ""
                ])
            },
            { activityId, contentStateData, staleDate in
                var properties: [String: Any] = [
                    "eventType": "start",
                    "notificationType": identifier,
                    "instanceUUID": activityId,
                    "deviceId": sdk.registeredDeviceToken ?? "",
                    "platform": "ios",
                    "installationId": installationIdRef.wrappedValue ?? ""
                ]
                if let staleDate {
                    properties["expiration"] = staleDate.timeIntervalSince1970
                }
                if let contentStateData,
                   let payload = try? JSONSerialization.jsonObject(with: contentStateData) as? [String: Any] {
                    properties["payload"] = payload
                }
                sdk.track(name: "Live Notification Event", properties: properties)
                let info = LiveActivityInfo(
                    activityId: activityId,
                    activityType: identifier,
                    installationId: installationIdRef.wrappedValue ?? "",
                    userId: userIdRef.wrappedValue ?? ""
                )
                continuationRef.wrappedValue?.yield(info)
            },
            { activityId, contentStateJSON in
                var properties: [String: Any] = [
                    "eventType": "update",
                    "notificationType": identifier,
                    "instanceUUID": activityId,
                    "deviceId": sdk.registeredDeviceToken ?? "",
                    "platform": "ios",
                    "installationId": installationIdRef.wrappedValue ?? ""
                ]
                if let payload = try? JSONSerialization.jsonObject(with: contentStateJSON) as? [String: Any] {
                    properties["payload"] = payload
                }
                sdk.track(name: "Live Notification Event", properties: properties)
            },
            { activityId, contentStateData in
                var properties: [String: Any] = [
                    "eventType": "end",
                    "notificationType": identifier,
                    "instanceUUID": activityId,
                    "deviceId": sdk.registeredDeviceToken ?? "",
                    "platform": "ios",
                    "installationId": installationIdRef.wrappedValue ?? ""
                ]
                if let contentStateData,
                   let payload = try? JSONSerialization.jsonObject(with: contentStateData) as? [String: Any] {
                    properties["payload"] = payload
                }
                sdk.track(name: "Live Notification Event", properties: properties)
            }
        )

        _observationTasks.mutating { $0[identifier] = task }
    }
    #endif

    #if os(iOS)
    private func resubmitPushToStartTokens(deviceToken: String) {
        for registration in config.registrations {
            let identifier = registration.activityIdentifier
            guard let tokenHex = tokenStorage.getPushToStartToken(activityType: identifier) else { continue }
            sdk.track(name: "Live Notification Token", properties: [
                "registrationType": "push_to_start",
                "notificationType": identifier,
                "platform": "ios",
                "deviceId": deviceToken,
                "pushToStartToken": tokenHex,
                "installationId": _installationId.wrappedValue ?? ""
            ])
        }
    }
    #endif

    private func handleReset() async {
        #if os(iOS)
        if #available(iOS 16.1, *) {
            for registration in config.registrations {
                await registration.endAllActivities()
            }
        }
        let tasks = _observationTasks.using { $0 }
        for (_, task) in tasks { task.cancel() }
        _observationTasks.wrappedValue = [:]
        #endif

        tokenStorage.clearAll()
        _observedActivitiesContinuation.wrappedValue?.finish()
        makeNewObservedActivitiesStream()
    }
}
