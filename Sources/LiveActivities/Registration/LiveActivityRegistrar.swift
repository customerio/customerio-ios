import CioInternalCommon
import Foundation

/// Decides *when* to register Live Activity push tokens with Customer.io.
///
/// Registration is a CDP track event, so the data pipeline owns delivery — this type only
/// decides timing. It holds the latest observed tokens and (re)sends them whenever the device
/// token or user changes, for each type whose `"<token>|<userId>"` signature isn't already
/// stored. Because a token captured while anonymous or before a device token exists is held
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
    /// In-memory dedup of the last instance token sent per instanceUUID.
    private let sentInstance = Synchronized<[String: String]>([:])
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

    /// Reset (logout): clear the persisted signatures so the next identified session
    /// re-registers, and drop instance state (reset ends all activities).
    ///
    /// The pending *push-to-start* tokens are deliberately kept: they're per-app and stay valid
    /// across logout, and ActivityKit does not re-emit an unchanged token to the restarted
    /// observer — so if we dropped them here, the next login would have nothing to re-register.
    func handleReset() {
        pendingInstance.wrappedValue = [:]
        sentInstance.wrappedValue = [:]
        store.clearAll()
    }

    // MARK: - Observation callbacks

    func handlePushToStartToken(notificationType: String, attributesType: String, token: Data) {
        pendingPushToStart.mutating {
            $0[notificationType] = PendingPushToStart(attributesType: attributesType, tokenHex: token.hexString)
        }
        flushPending()
    }

    func handleInstanceToken(notificationType: String, instanceUUID: String, token: Data) {
        pendingInstance.mutating {
            $0[instanceUUID] = PendingInstance(notificationType: notificationType, tokenHex: token.hexString)
        }
        flushPending()
    }

    /// An activity ended — drop its per-instance state so the maps don't grow unbounded.
    func handleActivityEnded(instanceUUID: String) {
        pendingInstance.mutating { $0[instanceUUID] = nil }
        sentInstance.mutating { $0[instanceUUID] = nil }
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
            let signature = "\(pending.tokenHex)|\(userId)"
            guard store.registrationSignature(activityType: notificationType) != signature else { continue }
            reporter.sendPushToStartToken(
                notificationType: notificationType,
                attributesType: pending.attributesType,
                pushToStartToken: pending.tokenHex
            )
            store.setRegistrationSignature(activityType: notificationType, signature: signature)
        }

        for (instanceUUID, pending) in pendingInstance.wrappedValue {
            // Atomically claim the send: check-and-set in one locked step so concurrent
            // callers (rapid token updates / multiple observers) can't each pass the guard.
            let shouldSend = sentInstance.mutating { sent -> Bool in
                guard sent[instanceUUID] != pending.tokenHex else { return false }
                sent[instanceUUID] = pending.tokenHex
                return true
            }
            guard shouldSend else { continue }
            reporter.sendInstanceToken(
                notificationType: pending.notificationType,
                instanceUUID: instanceUUID,
                instanceToken: pending.tokenHex
            )
        }
    }
}
