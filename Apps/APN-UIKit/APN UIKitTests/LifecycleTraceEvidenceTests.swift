import Foundation
import UIKit
import UserNotifications
import XCTest

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
