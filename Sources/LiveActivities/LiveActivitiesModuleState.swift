import CioInternalCommon
import Foundation

/// Holds the Live Activities module's runtime state and performs one-time initialization.
///
/// The `LiveActivitiesModule` value handed to `SDKConfigBuilder.addModule(_:)` is disposable; this
/// shared holder owns the live instance and backs the ``CustomerIO/liveActivities`` accessor. Before
/// initialization it returns an uninitialized stub, so the accessor is always safe to call.
final class LiveActivitiesModuleState {
    static let shared = LiveActivitiesModuleState()

    private var instance: LiveActivitiesInstance = UninitializedLiveActivities(logger: DIGraphShared.shared.logger)
    /// One-shot latch so only the first caller builds the implementation, guarded by `lock`.
    private var didInitialize = false
    private let lock = NSLock()

    private init() {}

    /// Performs one-time setup of the Live Activities module (push-to-start seed + observation).
    /// Called from `LiveActivitiesModule.initialize()` during `CustomerIO.initialize(withConfig:)`.
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
    }

    /// The current Live Activities instance. Before initialization, returns a stub that logs an error when used.
    var current: LiveActivitiesInstance {
        lock.lock()
        defer { lock.unlock() }
        return instance
    }
}
