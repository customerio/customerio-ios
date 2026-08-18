import Foundation
import UIKit
import UserNotifications
import XCTest

final class InMemoryLifecycleTraceSink: LifecycleTraceSink {
    private let lock = NSLock()
    private var storedLines: [String] = []
    private let lineWritesSucceed: Bool
    private let receiptWritesSucceed: Bool

    init(lineWritesSucceed: Bool = true, receiptWritesSucceed: Bool = true) {
        self.lineWritesSucceed = lineWritesSucceed
        self.receiptWritesSucceed = receiptWritesSucceed
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedLines
    }

    @discardableResult
    func write(line: String) -> Bool {
        guard lineWritesSucceed else { return false }
        lock.lock()
        storedLines.append(line)
        lock.unlock()
        return true
    }

    func writeReceipt(json: String) -> Bool {
        guard receiptWritesSucceed else { return false }
        return write(line: LifecycleTraceRecorder.receiptPrefix + json)
    }
}

final class LifecycleTraceEvidenceTests: XCTestCase {
    func testScenario_whenClassifyingColdStart_thenMatchesCanonicalScenarioBinding() {
        let cold: Set<LifecycleTraceScenario> = [
            .iconColdLaunch, .pushTapCold, .localNotificationTapCold, .customURLCold,
            .universalLinkCold, .quickActionCold, .liveActivityTapCold
        ]

        for scenario in cold {
            XCTAssertTrue(scenario.isColdStart, scenario.rawValue)
        }
        for scenario in [
            LifecycleTraceScenario.pushForeground, .pushTapWarm, .localNotificationForeground,
            .localNotificationTapWarm, .customURLWarm, .universalLinkWarm, .quickActionWarm,
            .liveActivityTapWarm, .tokenRegistration, .registrationFailure,
            .backgroundFetch, .appBackgroundForeground, .notificationSettings, .unitFixture
        ] {
            XCTAssertFalse(scenario.isColdStart, scenario.rawValue)
        }
    }

    func testObserveURL_whenCredentialsArePresent_thenOnlySafeFactsAndOpaqueInputsRemain() throws {
        let url = try XCTUnwrap(URL(
            string: "customerio-test://settings/private?site_id=SECRET&cdp_api_key=HIDDEN#fragment"
        ))
        let observation = LifecycleTraceEvidence.observe(url: url)

        XCTAssertEqual(observation.flags[.hasURL], true)
        XCTAssertEqual(observation.enums[.urlScheme], "custom")
        XCTAssertEqual(observation.enums[.urlClass], "custom-scheme")
        XCTAssertEqual(observation.counts[.urlPathComponents], 1)
        XCTAssertEqual(observation.counts[.urlQueryItems], 2)
        XCTAssertEqual(observation.correlations[.url], .string(url.absoluteString))
        assertSafePayload(observation, excluding: ["SECRET", "HIDDEN", "settings", "site_id", "fragment"])
    }

    func testObserveURL_whenLiveActivityURL_thenClassifiesWithoutEmittingPayloadValues() throws {
        let url = try XCTUnwrap(URL(
            string: "cio-live-activity://open?cio_delivery_id=SECRET-ID&cio_delivery_token=SECRET-TOKEN&cio_redirect=customerio-test://private"
        ))
        let observation = LifecycleTraceEvidence.observe(url: url)

        XCTAssertEqual(observation.enums[.urlClass], "cio-live-activity")
        XCTAssertEqual(observation.flags[.hasDeliveryID], true)
        XCTAssertEqual(observation.flags[.hasDeliveryToken], true)
        XCTAssertEqual(observation.flags[.hasRedirect], true)
        XCTAssertEqual(observation.correlations[.delivery], .string("SECRET-ID"))
        assertSafePayload(observation, excluding: ["SECRET", "private", "cio_redirect"])
    }

    func testLiveActivityRoute_whenShapeIsNotProductionParserShape_thenDoesNotClaimCustomerIORoute() throws {
        let valid = try XCTUnwrap(URL(string: "cio-live-activity://open?cio_delivery_id=value"))
        XCTAssertTrue(LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(valid))

        for value in [
            "cio-live-activity://other?cio_delivery_id=value",
            "cio-live-activity://open",
            "customerio-test://open?cio_delivery_id=value"
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertFalse(LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(url), value)
        }
    }

    func testLiveActivityRoute_whenRedirectCannotBeParsed_thenRefusesRuntimeTrace() throws {
        let valid = try XCTUnwrap(URL(
            string: "cio-live-activity://open?cio_delivery_id=value&cio_redirect=customerio-test://dashboard"
        ))
        let malformed = try XCTUnwrap(URL(
            string: "cio-live-activity://open?cio_delivery_id=value&cio_redirect=http://%5B"
        ))

        XCTAssertTrue(LifecycleTraceEvidence.isTraceableURLRoute(valid))
        XCTAssertFalse(LifecycleTraceEvidence.isTraceableURLRoute(malformed))
        let meaningless = try XCTUnwrap(URL(string: "cio-live-activity://open?foo=bar"))
        XCTAssertFalse(LifecycleTraceEvidence.isTraceableURLRoute(meaningless))
    }

    func testWidgetRoutingResult_whenSDKTransformsURL_thenMatchesCanonicalRouteOutcome() throws {
        let original = try XCTUnwrap(URL(string: "cio-live-activity://open?cio_delivery_id=value"))
        let redirect = try XCTUnwrap(URL(string: "customerio-test://dashboard"))

        XCTAssertEqual(LifecycleTraceEvidence.widgetRoutingResult(original: original, destination: nil), .handled)
        XCTAssertEqual(LifecycleTraceEvidence.widgetRoutingResult(original: original, destination: original), .unhandled)
        XCTAssertEqual(LifecycleTraceEvidence.widgetRoutingResult(original: original, destination: redirect), .redirect)
    }

    func testObserveLaunchOptions_whenPayloadExists_thenRecordsOnlyPresenceAndCount() {
        let observation = LifecycleTraceEvidence.observe(launchOptions: [
            .remoteNotification: ["CIO-Delivery-ID": "SECRET"],
            .url: "customerio-test://private"
        ])

        XCTAssertEqual(observation.flags[.hasLaunchOptions], true)
        XCTAssertEqual(observation.counts[.launchOptionKeys], 2)
        assertSafePayload(observation, excluding: ["SECRET", "private"])
    }

    func testObserveDeviceToken_whenPresent_thenUsesByteCountAndInMemoryRequestIdentity() {
        let token = Data((0 ..< 32).map(UInt8.init))
        let observation = LifecycleTraceEvidence.observe(deviceToken: token)

        XCTAssertEqual(observation.flags[.hasDeviceToken], true)
        XCTAssertEqual(observation.counts[.deviceTokenBytes], 32)
        XCTAssertEqual(observation.correlations[.request], .data(token))
        XCTAssertTrue(observation.enums.isEmpty)
    }

    func testObserveFCMToken_whenPresent_thenDoesNotDeriveDigestOrAlias() {
        let observation = LifecycleTraceEvidence.observe(fcmToken: "SECRET-FCM-TOKEN")

        XCTAssertEqual(observation.flags[.hasFCMToken], true)
        XCTAssertEqual(observation.counts[.fcmTokenCharacters], 16)
        XCTAssertTrue(observation.correlations.isEmpty)
        assertSafePayload(observation, excluding: ["SECRET", "TOKEN"])
    }

    func testObserveNotificationRequest_whenCustomerIOPayload_thenPreservesSafeClassification() {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "CIO-Delivery-ID": "SECRET-DELIVERY",
            "CIO-Delivery-Token": "SECRET-TOKEN",
            "aps": ["alert": "private body"]
        ]
        let request = UNNotificationRequest(identifier: "SECRET-REQUEST", content: content, trigger: nil)
        let observation = LifecycleTraceEvidence.observe(
            notificationRequest: request,
            delegatePeer: .customerIOMessagingPush
        )

        XCTAssertEqual(observation.flags[.hasNotification], true)
        XCTAssertEqual(observation.flags[.hasAPS], true)
        XCTAssertEqual(observation.enums[.notificationClass], "customerio")
        XCTAssertEqual(observation.enums[.notificationOrigin], "unknown")
        XCTAssertEqual(observation.enums[.delegatePeer], "customerio-messaging-push")
        XCTAssertEqual(observation.counts[.notificationUserInfoKeys], 3)
        XCTAssertEqual(observation.correlations[.request], .string("SECRET-REQUEST"))
        XCTAssertEqual(observation.correlations[.delivery], .string("SECRET-DELIVERY"))
        assertSafePayload(observation, excluding: ["SECRET", "private body"])
    }

    func testObserveNotificationRequest_whenDeliveryTokenIsNotString_thenMatchesSDKNonCustomerIOClassification() {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "CIO-Delivery-ID": "delivery",
            "CIO-Delivery-Token": 42
        ]
        let request = UNNotificationRequest(identifier: "request", content: content, trigger: nil)

        let observation = LifecycleTraceEvidence.observe(notificationRequest: request)

        XCTAssertEqual(observation.flags[.hasDeliveryID], true)
        XCTAssertEqual(observation.flags[.hasDeliveryToken], false)
        XCTAssertEqual(observation.enums[.notificationClass], "non-customerio")
    }

    func testObservePresentationOptions_whenVisible_thenUsesExactFlagsAndCount() {
        var options: UNNotificationPresentationOptions = [.alert, .badge, .sound]
        if #available(iOS 14.0, *) {
            options = [.banner, .list, .badge, .sound]
        }
        let observation = LifecycleTraceEvidence.observe(presentationOptions: options)

        XCTAssertEqual(observation.flags[.presentationBadge], true)
        XCTAssertEqual(observation.flags[.presentationSound], true)
        XCTAssertEqual(observation.enums[.presentationClass], "visible")
        if #available(iOS 14.0, *) {
            XCTAssertEqual(observation.flags[.presentationAlert], false)
            XCTAssertEqual(observation.flags[.presentationBanner], true)
            XCTAssertEqual(observation.flags[.presentationList], true)
            XCTAssertEqual(observation.counts[.presentationOptions], 4)
        } else {
            XCTAssertEqual(observation.flags[.presentationBanner], false)
            XCTAssertEqual(observation.flags[.presentationList], false)
            XCTAssertEqual(observation.counts[.presentationOptions], 3)
        }
    }

    func testCanonicalEnums_whenComparedWithContract_thenClosedVocabularyHasExpectedCriticalSeats() {
        XCTAssertEqual(LifecycleTraceCallback.allCases.count, 118)
        XCTAssertEqual(LifecycleTraceCallback.applicationDidDiscardSceneSessions.rawValue, "application.did-discard-scene-sessions")
        XCTAssertEqual(LifecycleTraceCallback.swiftUIOnOpenURL.rawValue, "swiftui.on-open-url")
        XCTAssertEqual(LifecycleTraceCallback.hostRouteURL.rawValue, "host.route-url")
        XCTAssertEqual(LifecycleTraceCallback.customerIORouteDeepLink.rawValue, "customerio.route-deep-link")
        XCTAssertEqual(LifecycleTraceCallback.fixtureCompletionObserved.rawValue, "fixture.completion-observed")
        XCTAssertEqual(LifecycleTraceEvidenceLevel.allCasesForTesting, ["diagnostic", "L2", "L3"])
    }

    func testContext_whenIdentityIsNotCanonicalLowercaseUUIDv4_thenFailsClosed() {
        XCTAssertNil(LifecycleTraceContext(
            manifestID: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            runID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            streamID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            processID: 1,
            processInstanceID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            integration: .nativeIOS,
            runtime: .swift,
            provider: .apn,
            scenario: .tokenRegistration,
            evidenceLevel: .l2
        ))
    }

    private func assertSafePayload(_ observation: LifecycleTraceObservation, excluding fragments: [String]) {
        let safePayload = String(describing: observation.flags)
            + String(describing: observation.counts)
            + String(describing: observation.enums)
        for fragment in fragments {
            XCTAssertFalse(safePayload.contains(fragment), "safe payload leaked \(fragment)")
        }
    }
}

private extension LifecycleTraceEvidenceLevel {
    static var allCasesForTesting: [String] {
        [
            LifecycleTraceEvidenceLevel.diagnostic.rawValue,
            LifecycleTraceEvidenceLevel.l2.rawValue,
            LifecycleTraceEvidenceLevel.l3.rawValue
        ]
    }
}

final class LifecycleTraceCaptureGuardrailTests: XCTestCase {
    func testRecord_whenSecondSceneParticipates_thenCaptureFailsClosed() throws {
        let (recorder, sink) = try makeRecorder()
        XCTAssertTrue(recorder.record(
            callback: .sceneDidBecomeActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange,
            observations: LifecycleTraceObservation(correlations: [.scene: .string("scene-A")])
        ))
        XCTAssertFalse(recorder.record(
            callback: .sceneWillResignActive,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange,
            observations: LifecycleTraceObservation(correlations: [.scene: .string("scene-B")])
        ))
        XCTAssertNil(close(recorder))
        XCTAssertFalse(sink.lines.contains { $0.hasPrefix(LifecycleTraceRecorder.receiptPrefix) })
    }

    func testRecord_whenMultipleURLContextsArrive_thenCaptureFailsClosed() throws {
        let (recorder, sink) = try makeRecorder()
        XCTAssertFalse(recorder.record(
            callback: .sceneOpenURLContexts,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .entry,
            observations: LifecycleTraceObservation(counts: [.urlContexts: 2])
        ))
        XCTAssertNil(close(recorder))
        XCTAssertFalse(sink.lines.contains { $0.hasPrefix(LifecycleTraceRecorder.receiptPrefix) })
    }

    func testAppDelegateOnlyTerminal_whenApplicationBecomesActive_thenCloses() throws {
        let (recorder, _) = try makeRecorder(topology: .appDelegateOnly)
        XCTAssertTrue(recorder.record(
            callback: .applicationDidBecomeActive,
            owner: .applicationDelegate,
            kind: .osCallback,
            phase: .stateChange
        ))
        let expectation = expectation(description: "app delegate terminal receipt")
        XCTAssertTrue(recorder.endScenario(after: .activeApplication) { receipt in
            XCTAssertNotNil(receipt)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 3)
    }

    func testHarnessEndCleanup_whenTerminalIsRejected_thenRetainsCleanupUntilAcceptedEnd() throws {
        let (recorder, _) = try makeRecorder()
        var cleanupCalls = 0
        LifecycleTraceHarness.registerEndCleanup {
            cleanupCalls += 1
        }

        var rejectedCompletionCalled = false
        XCTAssertFalse(recorder.endScenario(after: .tokenRegistration) { _ in
            rejectedCompletionCalled = true
            LifecycleTraceHarness.handleEndCompletion()
        })
        XCTAssertFalse(rejectedCompletionCalled)
        XCTAssertEqual(cleanupCalls, 0)

        let expectation = expectation(description: "accepted end cleanup")
        XCTAssertTrue(recorder.endScenario(after: .activeScene) { _ in
            LifecycleTraceHarness.handleEndCompletion()
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 3)
        XCTAssertEqual(cleanupCalls, 1)
    }

    func testHarnessEndCleanup_whenAcceptedReceiptPublicationFails_thenStillRunsCleanup() throws {
        let (recorder, sink) = try makeRecorder(receiptWritesSucceed: false)
        var cleanupCalls = 0
        LifecycleTraceHarness.registerEndCleanup {
            cleanupCalls += 1
        }

        let expectation = expectation(description: "failed receipt publication cleanup")
        XCTAssertTrue(recorder.endScenario(after: .activeScene) { receipt in
            XCTAssertNil(receipt)
            LifecycleTraceHarness.handleEndCompletion()
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(cleanupCalls, 1)
        XCTAssertFalse(sink.lines.contains { $0.hasPrefix(LifecycleTraceRecorder.receiptPrefix) })
    }

    func testRecorder_whenLinePublicationFails_thenFailsClosedWithoutReceipt() throws {
        let (recorder, sink) = try makeRecorder(lineWritesSucceed: false)

        XCTAssertNil(close(recorder))
        XCTAssertTrue(sink.lines.isEmpty)
    }

    private func makeRecorder(
        topology: LifecycleTraceHostTopology = .uiScene,
        lineWritesSucceed: Bool = true,
        receiptWritesSucceed: Bool = true
    ) throws -> (LifecycleTraceRecorder, InMemoryLifecycleTraceSink) {
        let context = try XCTUnwrap(LifecycleTraceContext(
            manifestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            runID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            streamID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            processID: 42,
            processInstanceID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            integration: .nativeIOS,
            runtime: .swift,
            provider: .apn,
            scenario: .iconColdLaunch,
            evidenceLevel: .diagnostic,
            hostTopology: topology,
            activationOccurrenceIdentity: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        ))
        let sink = InMemoryLifecycleTraceSink(
            lineWritesSucceed: lineWritesSucceed,
            receiptWritesSucceed: receiptWritesSucceed
        )
        let recorder = LifecycleTraceRecorder(context: context, sink: sink)
        XCTAssertTrue(recorder.startScenario())
        return (recorder, sink)
    }

    private func close(_ recorder: LifecycleTraceRecorder) -> LifecycleTraceStreamReceipt? {
        let expectation = expectation(description: "post-drain receipt")
        var result: LifecycleTraceStreamReceipt?
        recorder.endScenarioAndDrain { receipt in
            result = receipt
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
        return result
    }
}
