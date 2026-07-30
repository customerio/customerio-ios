@testable import CioMessagingInApp
import Foundation
import XCTest

/// Locks the source compatibility of the public inbox protocols.
///
/// Adding the Visual Notification Inbox introduced new members on two PUBLIC protocols:
/// `NotificationInbox` gained `setInboxEventListener` / `notifyMessageActionTaken` /
/// `notifyMessageShown`, and `MessagingInAppInstance` gained `setInboxEventListener`. Those are
/// SDK-internal plumbing, but the protocols are public — so as bare requirements they would break
/// every existing external conformer and test double, turning an additive release into a breaking
/// one. They ship with defaults instead.
///
/// The conformers below implement ONLY the members that existed BEFORE the inbox feature. They carry
/// no assertions and are not meant to: this file is a COMPILE-TIME test. If a future change removes
/// a default or adds a bare requirement to either protocol, this file stops compiling, which is the
/// signal. Verified to fail that way by deleting the defaults.
class InboxProtocolSourceCompatibilityTests: XCTestCase {
    /// Stands in for a host's own `NotificationInbox` conformer written against the pre-inbox SDK.
    private final class LegacyInboxConformer: NotificationInbox {
        func getMessages(topic: String?) async -> [InboxMessage] {
            []
        }

        func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?) {
            _ = (listener, topic)
        }

        func removeChangeListener(_ listener: NotificationInboxChangeListener) {
            _ = listener
        }

        func markMessageOpened(message: InboxMessage) {
            _ = message
        }

        func markMessageUnopened(message: InboxMessage) {
            _ = message
        }

        func markMessageDeleted(message: InboxMessage) {
            _ = message
        }

        func trackMessageClicked(message: InboxMessage, actionName: String?) {
            _ = (message, actionName)
        }

        func messages(topic: String?) -> AsyncStream<[InboxMessage]> {
            AsyncStream { $0.finish() }
        }
    }

    /// Stands in for a host's own `MessagingInAppInstance` conformer written against the pre-inbox SDK.
    /// `inbox` predates the inbox UI work, so it is a real requirement rather than a defaulted one.
    private final class LegacyInAppConformer: MessagingInAppInstance {
        var inbox: NotificationInbox { LegacyInboxConformer() }
        func setEventListener(_ eventListener: InAppEventListener?) {
            _ = eventListener
        }

        func dismissMessage() {}
        func setColorScheme(_ colorScheme: ColorScheme) {
            _ = colorScheme
        }
    }

    /// Both conformers compile, and the defaulted members are reachable on them.
    func test_legacyConformers_whenInboxMembersNotImplemented_expectDefaultsUsed() {
        let inbox = LegacyInboxConformer()
        let message = InboxMessage(
            queueId: "q-1",
            deliveryId: "d-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        // Defaulted plumbing: no listener support, so an action is never reported as handled.
        XCTAssertFalse(
            inbox.notifyMessageActionTaken(message: message, actionValue: "v", actionName: "a"),
            "the default must not intercept, so the SDK's own navigation still runs"
        )

        // Remaining defaults are no-ops; calling them proves they resolve on a bare conformer.
        inbox.setInboxEventListener(nil)
        inbox.notifyMessageShown(message: message)
        LegacyInAppConformer().setInboxEventListener(nil)
    }
}
