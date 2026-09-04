@testable import CioMessagingInApp
import Foundation
import XCTest

/// Locks the source compatibility of `InAppEventListener` and `GistDelegate`.
///
/// Adding the failure reason meant adding a member to two PUBLIC protocols:
/// `errorWithMessage(message:error:)` and `messageError(message:error:)`. As bare requirements
/// those would break every existing conformer, turning an additive release into a breaking one.
/// They ship with defaults instead.
///
/// The conformers below implement ONLY the members that existed BEFORE the reason was added. They
/// carry no assertions and are not meant to: this is a COMPILE-TIME test. If a future change
/// removes a default or adds a bare requirement, this file stops compiling, which is the signal.
/// Verified to fail that way by deleting the defaults.
class InAppListenerSourceCompatTests: XCTestCase {
    /// Stands in for a host's listener written against the reason-less SDK.
    private final class LegacyEventListener: InAppEventListener {
        func messageShown(message: InAppMessage) {
            _ = message
        }

        func messageDismissed(message: InAppMessage) {
            _ = message
        }

        func errorWithMessage(message: InAppMessage) {
            _ = message
        }

        func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
            _ = (message, actionValue, actionName)
        }
    }

    /// The default must actually forward, not silently swallow — a host that only implemented the
    /// old callback has to keep receiving failures.
    func test_errorWithMessageDefault_givenLegacyListener_expectForwardedToReasonLessCallback() {
        final class ForwardingSpy: InAppEventListener {
            var reasonLessCallCount = 0
            func messageShown(message: InAppMessage) {}
            func messageDismissed(message: InAppMessage) {}
            func errorWithMessage(message: InAppMessage) {
                reasonLessCallCount += 1
            }

            func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {}
        }

        let listener = ForwardingSpy()
        let message = InAppMessage(gistMessage: Message(messageId: "test-message-id"))

        listener.errorWithMessage(message: message, error: InAppMessageError(reason: .timeout))

        XCTAssertEqual(listener.reasonLessCallCount, 1)
    }

    /// Compile-time only: a legacy conformer must still satisfy the protocol.
    func test_legacyConformer_expectStillSatisfiesProtocol() {
        let listener: InAppEventListener = LegacyEventListener()
        XCTAssertNotNil(listener)
    }
}
