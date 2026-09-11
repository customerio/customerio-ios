@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// Covers the failure detail the SDK now keeps hold of.
///
/// Two things used to be discarded outright: the renderer's own `errorMessage` (the only
/// first-hand account of why a message would not render) and the `NSError` behind a failed
/// navigation. Both now reach the logs.
class InAppMessageErrorTests: UnitTest {
    // MARK: - renderer error payload

    /// Shape the renderer actually sends, e.g. `Unable to find "step-2" in payload.`
    private func errorEvent(errorMessage: String? = nil, target: String? = nil) -> EngineEventProperties {
        var parameters: [String: AnyObject] = [:]
        if let errorMessage = errorMessage {
            parameters["errorMessage"] = errorMessage as AnyObject
        }
        if let target = target {
            parameters["target"] = target as AnyObject
        }
        return ["parameters": parameters as AnyObject]
    }

    func test_getErrorProperties_givenMessageAndTarget_expectBoth() {
        let properties = errorEvent(errorMessage: "Unable to find \"step-2\" in payload.", target: "step-2")

        let detail = EngineEventHandler.getErrorProperties(properties: properties)

        XCTAssertEqual(detail, "Unable to find \"step-2\" in payload. (target: step-2)")
    }

    func test_getErrorProperties_givenMessageOnly_expectMessage() {
        let detail = EngineEventHandler.getErrorProperties(properties: errorEvent(errorMessage: "Boom"))

        XCTAssertEqual(detail, "Boom")
    }

    func test_getErrorProperties_givenTargetOnly_expectTargetDescribed() {
        let detail = EngineEventHandler.getErrorProperties(properties: errorEvent(target: "step-2"))

        XCTAssertEqual(detail, "Engine reported an error for target: step-2")
    }

    func test_getErrorProperties_givenNeither_expectNil() {
        XCTAssertNil(EngineEventHandler.getErrorProperties(properties: errorEvent()))
    }

    func test_getErrorProperties_givenNoParameters_expectNil() {
        XCTAssertNil(EngineEventHandler.getErrorProperties(properties: [:]))
    }

    // MARK: - navigation errors

    func test_init_givenNavigationError_expectReasonDetailAndCodeKept() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )

        let error = InAppMessageError(networkError: underlying)

        XCTAssertEqual(error.reason, .network)
        XCTAssertEqual(error.detail, "The Internet connection appears to be offline.")
        XCTAssertEqual(error.code, NSURLErrorNotConnectedToInternet)
    }

    // MARK: - log formatting

    func test_describeForLogs_givenCodeAndDetail_expectAllThree() {
        let error = InAppMessageError(reason: .network, detail: "offline", code: -1009)

        XCTAssertEqual(error.describeForLogs, "network (-1009): offline")
    }

    func test_describeForLogs_givenReasonOnly_expectReason() {
        XCTAssertEqual(InAppMessageError(reason: .timeout).describeForLogs, "timeout")
    }
}
