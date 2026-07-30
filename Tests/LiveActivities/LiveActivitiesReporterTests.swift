import CioLiveActivities_Attributes
import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Auth / device-token gating

struct LiveActivityReporterGateTests {
    @Test func reportStart_dropped_whenNoUserIdentified() {
        let cap = TrackCapture()
        cap.deviceToken = "dev-token"
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "t", attributes: nil, contentState: nil)
        #expect(cap.isEmpty)
    }

    @Test func reportStart_dropped_whenNoDeviceToken() {
        let cap = TrackCapture()
        cap.userId = "user-1"
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "t", attributes: nil, contentState: nil)
        #expect(cap.isEmpty)
    }

    @Test func reportStart_dropped_whenDeviceTokenEmpty() {
        let cap = TrackCapture()
        cap.userId = "user-1"
        cap.deviceToken = ""
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "t", attributes: nil, contentState: nil)
        #expect(cap.isEmpty)
    }

    @Test func tokenEvent_dropped_whenAnonymous() {
        let cap = TrackCapture()
        cap.deviceToken = "dev-token"
        cap.makeReporter().sendPushToStartToken(notificationType: "t", attributesType: "A", pushToStartToken: "aabb")
        #expect(cap.isEmpty)
    }
}

// MARK: - Event shape

struct LiveActivityReporterShapeTests {
    private func identifiedCapture() -> TrackCapture {
        let cap = TrackCapture()
        cap.userId = "user-1"
        cap.deviceToken = "dev-token"
        return cap
    }

    @Test func reportStart_emitsAttributesAndContentState_withoutInstallationId() {
        let cap = identifiedCapture()
        cap.makeReporter().reportStart(
            instanceUUID: "i1",
            notificationType: "type.a",
            attributes: ["league": "premier"],
            contentState: ["home": 1, "away": 2]
        )
        #expect(cap.count == 1)
        #expect(cap.events[0].name == "Live Notification Event")
        #expect(cap.string(0, "eventType") == "start")
        #expect(cap.string(0, "cioInstanceId") == "i1")
        #expect(cap.string(0, "notificationType") == "type.a")
        #expect(cap.string(0, "deviceId") == "dev-token")
        #expect(cap.string(0, "platform") == "ios")
        #expect(cap.events[0].properties["installationId"] == nil)
        // No single `payload` property anymore — split into attributes + contentState.
        #expect(cap.events[0].properties["payload"] == nil)
        #expect(cap.events[0].properties["attributes"] != nil)
        #expect(cap.events[0].properties["contentState"] != nil)
        let attributes = cap.events[0].properties["attributes"] as? [String: Any]
        #expect(attributes?["league"] as? String == "premier")
        let contentState = cap.events[0].properties["contentState"] as? [String: Any]
        #expect(contentState?["home"] as? Int == 1)
        #expect(contentState?["away"] as? Int == 2)
    }

    @Test func reportEnd_withFinalContentState_sendsIt() {
        let cap = identifiedCapture()
        cap.makeReporter().reportEnd(instanceUUID: "i1", notificationType: "type.a", contentState: ["home": 5])
        #expect(cap.string(0, "eventType") == "end")
        #expect(cap.events[0].properties["contentState"] != nil)
    }

    @Test func reportEnd_withoutContentState_omitsIt() {
        let cap = identifiedCapture()
        cap.makeReporter().reportEnd(instanceUUID: "i1", notificationType: "type.a")
        #expect(cap.string(0, "eventType") == "end")
        #expect(cap.events[0].properties["contentState"] == nil)
        #expect(cap.events[0].properties["attributes"] == nil)
    }

    @Test func pushToStartToken_includesAttributesType_andNoInstallationId() {
        let cap = identifiedCapture()
        cap.makeReporter().sendPushToStartToken(notificationType: "type.a", attributesType: "MyAttributes", pushToStartToken: "aabbcc")
        #expect(cap.events[0].name == "Live Notification Token")
        #expect(cap.string(0, "registrationType") == "push_to_start")
        #expect(cap.string(0, "attributesType") == "MyAttributes")
        #expect(cap.string(0, "pushToStartToken") == "aabbcc")
        #expect(cap.events[0].properties["installationId"] == nil)
    }

    @Test func instanceToken_includesInstanceFields() {
        let cap = identifiedCapture()
        cap.makeReporter().sendInstanceToken(notificationType: "type.a", instanceUUID: "i1", instanceToken: "ddeeff")
        #expect(cap.string(0, "registrationType") == "instance")
        #expect(cap.string(0, "cioInstanceId") == "i1")
        #expect(cap.string(0, "instanceToken") == "ddeeff")
    }
}

// MARK: - Date wire format through the reporter (epoch seconds)

//
// Pure `EpochSecondsDate` Codable behavior is covered in `EpochSecondsDateTests`; these assert the
// reporter's own encoder/`encode(_:)` helper emit the same epoch-second wire format.

struct ReporterDateEncodingTests {
    /// The reporter's `payloadEncoder` must emit an epoch-second number for a date field, matching
    /// what ActivityKit decodes on a server push.
    @Test func payloadEncoder_encodesEpochSecondsNumber() throws {
        // 2021-01-01T00:00:00Z == 1_609_459_200 s
        let wrapper = EpochSecondsDate(Date(timeIntervalSince1970: 1609459200))
        let data = try LiveActivityReporter.payloadEncoder.encode(wrapper)
        #expect(String(decoding: data, as: UTF8.self) == "1609459200")
    }

    /// Encoding a content-state that contains an `EpochSecondsDate` through the reporter's
    /// `encode(_:)` helper must yield an epoch-second number under the field key.
    @Test func contentStateEncodesDateAsEpochSeconds() throws {
        struct State: Encodable {
            let endTime: EpochSecondsDate
        }
        let state = State(endTime: EpochSecondsDate(Date(timeIntervalSince1970: 1609459200)))
        let object = LiveActivityReporter.encode(state)
        #expect(object?["endTime"] as? Int64 == 1609459200 || object?["endTime"] as? Int == 1609459200)
    }
}
