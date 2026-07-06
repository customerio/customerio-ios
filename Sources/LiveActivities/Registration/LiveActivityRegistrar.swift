import CioInternalCommon
import Foundation

/// Decides *when* to register Live Activity push tokens with Customer.io.
///
/// Registration is a CDP track event, so the data pipeline owns delivery — this type only
/// decides timing. It holds the latest observed tokens and (re)sends them whenever the device
/// token or user changes, for each type whose `"<deviceToken>|<pushToStartToken>|<userId>"`
/// signature isn't already stored — the deviceToken is part of the signature so a device-token
/// rotation re-registers the token against the new device. Because a token captured while
/// anonymous or before a device token exists is held
/// pending (not sent, not stored), a registration skipped in that state re-fires automatically
/// once the user is identified / a token arrives — the same model as the Android registrar.
final class LiveActivityRegistrar: @unchecked Sendable {
    private struct PendingPushToStart {
        let attributesType: String
        let tokenHex: String
    }

    private struct PendingInstance {
        let notificationType: String
        let tokenHex: String
    }

    private let identity: LiveActivityIdentity
    private let store: LiveActivityTokenStorage
    private let reporter: LiveActivityReporter

    /// Latest observed push-to-start token per notificationType, awaiting a registrable state.
    private let pendingPushToStart = Synchronized<[String: PendingPushToStart]>([:])
    /// Latest observed instance token per instanceUUID, awaiting a registrable state.
    private let pendingInstance = Synchronized<[String: PendingInstance]>([:])
    /// Serializes `flushPending` so concurrent callers (the push-to-start task, per-activity
    /// observers, and identity/device-token events) can't each pass the dedup checks and
    /// double-send. Cheap: the body only enqueues CDP track events.
    private let flushLock = NSLock()

    init(identity: LiveActivityIdentity, store: LiveActivityTokenStorage, reporter: LiveActivityReporter) {
        self.identity = identity
        self.store = store
        self.reporter = reporter
    }

    // MARK: - Identity / device token changes (called by the module on event bus events)

    /// Device token or user changed — try to flush anything pending.
    func reevaluate() {
        flushPending()
    }

    /// Reset (logout): clear the dedup signatures so the next identified session re-registers, and
    /// drop instance state (reset ends all activities).
    ///
    /// The *persisted push-to-start token values* (`ptsvalue:` keys) are deliberately preserved:
    /// they're per-app and stay valid across logout, and ActivityKit does not re-emit an unchanged
    /// token to the restarted observer — so keeping the value lets the next login re-register it,
    /// even across a process restart (the in-memory `pendingPushToStart` alone would be lost then).
    func handleReset() {
        pendingInstance.wrappedValue = [:]
        for key in store.allRegistrationKeys() where !key.hasPrefix(Self.pushToStartValuePrefix) {
            store.clearRegistrationSignature(activityType: key)
        }
    }

    /// Seed `pendingPushToStart` from the persisted token values so a push-to-start token can be
    /// registered on a launch where ActivityKit does not re-yield it. Call once at init, before the
    /// event-bus observers are added (their replayed identify / device-token events trigger the
    /// flush that actually registers). Persisted values never clobber a fresher in-memory capture.
    func seedPendingPushToStartFromStore() {
        for key in store.allRegistrationKeys() where key.hasPrefix(Self.pushToStartValuePrefix) {
            let notificationType = String(key.dropFirst(Self.pushToStartValuePrefix.count))
            guard
                let raw = store.registrationSignature(activityType: key),
                let separator = raw.firstIndex(of: "|")
            else { continue }
            let attributesType = String(raw[..<separator])
            let tokenHex = String(raw[raw.index(after: separator)...])
            guard !tokenHex.isEmpty else { continue }
            pendingPushToStart.mutating { pending in
                if pending[notificationType] == nil {
                    pending[notificationType] = PendingPushToStart(attributesType: attributesType, tokenHex: tokenHex)
                }
            }
        }
        flushPending()
    }

    // MARK: - Observation callbacks

    func handlePushToStartToken(notificationType: String, attributesType: String, token: Data) {
        let tokenHex = token.hexString
        pendingPushToStart.mutating {
            $0[notificationType] = PendingPushToStart(attributesType: attributesType, tokenHex: tokenHex)
        }
        // Persist the token *value* (not just the dedup signature) so a future cold launch can
        // re-seed and register it even if ActivityKit doesn't re-yield the (unchanged) token.
        store.setRegistrationSignature(
            activityType: Self.pushToStartValueKey(notificationType),
            signature: "\(attributesType)|\(tokenHex)"
        )
        flushPending()
    }

    func handleInstanceToken(notificationType: String, instanceUUID: String, token: Data) {
        let tokenHex = token.hexString
        pendingInstance.mutating {
            $0[instanceUUID] = PendingInstance(notificationType: notificationType, tokenHex: tokenHex)
        }
        flushPending()
    }

    /// An activity ended — drop its per-instance state (in-memory + persisted) so the store
    /// doesn't grow unbounded and a reused id would re-register.
    func handleActivityEnded(instanceUUID: String) {
        pendingInstance.mutating { $0[instanceUUID] = nil }
        store.clearRegistrationSignature(activityType: Self.instanceStoreKey(instanceUUID))
    }

    /// Store key for a per-instance signature. Namespaced so it can't collide with a
    /// push-to-start key (an activity type identifier).
    private static func instanceStoreKey(_ instanceUUID: String) -> String {
        "instance:\(instanceUUID)"
    }

    /// Key prefix for a persisted push-to-start token value. Namespaced so it can't collide with a
    /// push-to-start dedup signature (bare activity type) or a per-instance signature.
    private static let pushToStartValuePrefix = "ptsvalue:"
    private static func pushToStartValueKey(_ notificationType: String) -> String {
        pushToStartValuePrefix + notificationType
    }

    // MARK: - Flush

    private func flushPending() {
        flushLock.lock()
        defer { flushLock.unlock() }

        guard
            let userId = identity.userId,
            let deviceToken = identity.deviceToken,
            !deviceToken.isEmpty
        else { return }

        for (notificationType, pending) in pendingPushToStart.wrappedValue {
            // Include the deviceToken so a device-token rotation (same push-to-start token + user)
            // re-registers against the new device rather than being skipped as unchanged.
            let signature = "\(deviceToken)|\(pending.tokenHex)|\(userId)"
            guard store.registrationSignature(activityType: notificationType) != signature else { continue }
            reporter.sendPushToStartToken(
                notificationType: notificationType,
                attributesType: pending.attributesType,
                pushToStartToken: pending.tokenHex
            )
            store.setRegistrationSignature(activityType: notificationType, signature: signature)
        }

        for (instanceUUID, pending) in pendingInstance.wrappedValue {
            // Dedup persists across launches (like push-to-start): keyed by instanceUUID with a
            // `deviceToken|token` value, so an unchanged instance token on relaunch is skipped,
            // while a rotated token or a new device re-registers. `flushPending` is serialized by
            // `flushLock`, so this check-then-set is atomic against concurrent callers.
            let storeKey = Self.instanceStoreKey(instanceUUID)
            let sendKey = "\(deviceToken)|\(pending.tokenHex)"
            guard store.registrationSignature(activityType: storeKey) != sendKey else { continue }
            reporter.sendInstanceToken(
                notificationType: pending.notificationType,
                instanceUUID: instanceUUID,
                instanceToken: pending.tokenHex
            )
            store.setRegistrationSignature(activityType: storeKey, signature: sendKey)
        }
    }
}
