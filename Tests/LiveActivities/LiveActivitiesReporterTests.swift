import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Auth / device-token gating

struct LiveActivityReporterGateTests {
    @Test func reportStart_dropped_whenNoUserIdentified() {
        let cap = TrackCapture()
        cap.deviceToken = "dev-token"
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "t", payload: nil)
        #expect(cap.isEmpty)
    }

    @Test func reportStart_dropped_whenNoDeviceToken() {
        let cap = TrackCapture()
        cap.userId = "user-1"
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "t", payload: nil)
        #expect(cap.isEmpty)
    }

    @Test func reportStart_dropped_whenDeviceTokenEmpty() {
        let cap = TrackCapture()
        cap.userId = "user-1"
        cap.deviceToken = ""
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "t", payload: nil)
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

    @Test func reportStart_emitsLiveNotificationEvent_withoutInstallationId() {
        let cap = identifiedCapture()
        cap.makeReporter().reportStart(instanceUUID: "i1", notificationType: "type.a", payload: ["score": 1])
        #expect(cap.count == 1)
        #expect(cap.events[0].name == "Live Notification Event")
        #expect(cap.string(0, "eventType") == "start")
        #expect(cap.string(0, "instanceUUID") == "i1")
        #expect(cap.string(0, "notificationType") == "type.a")
        #expect(cap.string(0, "deviceId") == "dev-token")
        #expect(cap.string(0, "platform") == "ios")
        #expect(cap.events[0].properties["installationId"] == nil)
        #expect(cap.events[0].properties["payload"] != nil)
    }

    @Test func reportUpdate_and_reportEnd_setEventType() {
        let cap = identifiedCapture()
        let reporter = cap.makeReporter()
        reporter.reportUpdate(instanceUUID: "i1", notificationType: "type.a", payload: nil)
        reporter.reportEnd(instanceUUID: "i1", notificationType: "type.a")
        #expect(cap.string(0, "eventType") == "update")
        #expect(cap.string(1, "eventType") == "end")
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
        #expect(cap.string(0, "instanceUUID") == "i1")
        #expect(cap.string(0, "instanceToken") == "ddeeff")
    }
}
