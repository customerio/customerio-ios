import Foundation

public extension DIGraphShared {
    /// Registers the shared ``PendingPushDeliveryStore`` for the host app or extension process.
    ///
    /// - Data Pipeline calls this with `appGroupId: nil` before creating ``DataPipelineImplementation`` when nothing is registered yet (inferred app group from `Bundle.main`).
    /// - MessagingPush calls this again with the push module's configured app group id (or `nil` to infer from the bundle).
    @discardableResult
    func registerPendingPushDeliveryStore(appGroupId: String?) -> PendingPushDeliveryStore {
        if let existing: PendingPushDeliveryStore = getOptional(PendingPushDeliveryStore.self) {
            let resolvedSuite = appGroupId ?? AppGroupIdentifier.identifier(forProcessBundleIdentifier: Bundle.main.bundleIdentifier)
            if existing.appGroupSuiteName == resolvedSuite {
                return existing
            }
        }

        let store = CioAppGroupPendingPushDeliveryStore(
            appGroupId: appGroupId,
            processBundleIdentifier: Bundle.main.bundleIdentifier,
            logger: logger
        )
        register(store, forType: PendingPushDeliveryStore.self)
        return store
    }

    /// Returns the previously registered ``PendingPushDeliveryStore``, or lazily creates one with inferred app group (`nil` app group id) if none was registered yet.
    var pendingPushDeliveryStore: PendingPushDeliveryStore {
        if let store: PendingPushDeliveryStore = getOptional(PendingPushDeliveryStore.self) {
            return store
        }
        return registerPendingPushDeliveryStore(appGroupId: nil)
    }
}
