import CioInternalCommon
import Foundation

/// Holds the Live Activities module's runtime state and performs one-time initialization.
///
/// The `LiveActivitiesModule` value handed to `SDKConfigBuilder.addModule(_:)` is disposable; this
/// shared holder owns the live instance and backs the ``CustomerIO/liveActivities`` accessor. Before
/// initialization it returns an uninitialized stub, so the accessor is always safe to call.
final class LiveActivitiesModuleState {
    static let shared = LiveActivitiesModuleState()

    private var instance: LiveActivitiesInstance
    /// One-shot latch so only the first caller builds the implementation, guarded by `lock`.
    private var didInitialize = false
    private let lock = NSLock()

    private let pendingOpens = LiveActivityPendingOpens()

    private init() {
        self.instance = UninitializedLiveActivities(
            logger: DIGraphShared.shared.logger,
            bufferOpen: pendingOpens.append
        )
    }

    /// Performs one-time setup of the Live Activities module (push-to-start seed + observation).
    /// Called from `LiveActivitiesModule.initialize()` during `CustomerIO.initialize(withConfig:)`.
    ///
    /// **First call wins.** The latch is never reset, so a second `CustomerIO.initialize(withConfig:)`
    /// logs and keeps the original configuration rather than swapping it: the first config's type
    /// registrations and observers are already live, and replacing them mid-flight would orphan any
    /// activity started under them. Wrappers that initialize automatically and then again from
    /// JavaScript/Dart therefore keep the automatic configuration.
    func performInitialization(config: LiveActivityConfig) {
        lock.lock()
        if didInitialize {
            lock.unlock()
            DIGraphShared.shared.logger.reconfigurationNotSupported()
            return
        }
        didInitialize = true
        lock.unlock()

        // Build and start observation OUTSIDE the lock. `performInitialization()` registers event-bus
        // observers, synchronously replays the last identify/token events, and starts ActivityKit
        // observation — none of which should run while holding `lock`: doing so would needlessly
        // serialize `current` reads and risk a re-entrant deadlock (NSLock is non-reentrant) if any of
        // that work reads `CustomerIO.liveActivities`. Only the final assignment needs the lock.
        //
        // The trade-off this buys: for the duration of the work below, `current` still returns the
        // uninitialized stub, so a concurrent `CustomerIO.liveActivities` call from another thread
        // logs and no-ops instead of blocking until the implementation is ready. That is deliberate —
        // an initialization-time call that no-ops is preferable to one that deadlocks — and it is
        // invisible to the common case, where the SDK is initialized before any Live Activity call.
        let sdk = CustomerIO.shared
        let implementation = LiveActivitiesModuleImplementation(
            config: config,
            sdk: sdk,
            tokenStorage: KeyValueLiveActivityTokenStore(storage: sdk.sharedKeyValueStorage)
        )
        implementation.performInitialization()

        lock.lock()
        instance = implementation
        lock.unlock()

        for metadata in pendingOpens.drain() {
            implementation.reportBufferedOpen(metadata: metadata)
        }
    }

    /// The current Live Activities instance. Before initialization, returns a stub that logs an error when used.
    var current: LiveActivitiesInstance {
        lock.lock()
        defer { lock.unlock() }
        return instance
    }
}
