import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation
import Testing

@testable import CioLiveActivities

#if os(iOS)
import ActivityKit

/// A plain `ActivityAttributes` type never passed to `register(...)`, used to exercise the
/// unregistered-type path without touching ActivityKit (the check happens before `Activity.request`).
@available(iOS 16.2, *)
private struct UnregisteredTestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}
}
#endif

/// Behavior of the module accessor's uninitialized stub and the "not registered" path — both must
/// degrade without throwing so an initialization-timing race can't surface an error to a host app.
struct LiveActivitiesModuleAccessorTests {
    @Test func uninitializedStub_handleWidgetUrl_returnsUrlUnchanged() {
        let stub = UninitializedLiveActivities(logger: NoopLogger())
        let url = URL(string: "myapp://settings")!
        // Not a Customer.io URL: handed back untouched so the host's existing routing is unaffected.
        #expect(stub.handleWidgetUrl(url) == url)
    }

    /// A Customer.io tracking URL must never be handed back to the host to navigate: it is an
    /// internal `cio-live-activity://` link. Parsing needs no module state, so even the stub can
    /// recover the customer's deep link.
    @Test func uninitializedStub_handleWidgetUrl_returnsRedirect_notTheTrackingUrl() throws {
        let stub = UninitializedLiveActivities(logger: NoopLogger())
        let deepLink = "myapp://order/42"
        let trackingUrl = try #require(CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deliveryId: "d-1", deliveryToken: "t-1", deepLink: deepLink)
        ))

        let routed = stub.handleWidgetUrl(trackingUrl)

        #expect(routed == URL(string: deepLink))
        #expect(routed != trackingUrl)
    }

    /// A tracked activity that carries no deep link has nowhere to route, so the host must be told
    /// "nothing to open" rather than being handed the tracking URL.
    @Test func uninitializedStub_handleWidgetUrl_withoutRedirect_returnsNil() throws {
        let stub = UninitializedLiveActivities(logger: NoopLogger())
        let trackingUrl = try #require(CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deliveryId: "d-1")
        ))

        #expect(stub.handleWidgetUrl(trackingUrl) == nil)
    }

    @Test func uninitializedStub_handleWidgetUrl_buffersOpenAndStillReturnsRedirect() throws {
        var buffered: [CIOLiveActivityMetadata] = []
        let stub = UninitializedLiveActivities(logger: NoopLogger()) { buffered.append($0) }
        let deepLink = "myapp://order/42"
        let trackingUrl = try #require(CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deliveryId: "d-1", deliveryToken: "t-1", deepLink: deepLink)
        ))

        let routed = stub.handleWidgetUrl(trackingUrl)

        #expect(routed == URL(string: deepLink))
        #expect(buffered.count == 1)
        #expect(buffered.first?.deliveryId == "d-1")
        #expect(buffered.first?.deliveryToken == "t-1")
    }

    @Test func uninitializedStub_handleWidgetUrl_nonCioUrl_doesNotBuffer() {
        var buffered: [CIOLiveActivityMetadata] = []
        let stub = UninitializedLiveActivities(logger: NoopLogger()) { buffered.append($0) }

        _ = stub.handleWidgetUrl(URL(string: "myapp://settings")!)

        #expect(buffered.isEmpty)
    }

    @Test func uninitializedStub_handleWidgetUrl_withoutDeliveryId_doesNotBuffer() throws {
        var buffered: [CIOLiveActivityMetadata] = []
        let stub = UninitializedLiveActivities(logger: NoopLogger()) { buffered.append($0) }
        let trackingUrl = try #require(CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deepLink: "myapp://order/42")
        ))

        _ = stub.handleWidgetUrl(trackingUrl)

        #expect(buffered.isEmpty)
    }

    #if os(iOS)
    @available(iOS 16.2, *)
    @Test func uninitializedStub_start_returnsNil_withoutThrowing() throws {
        let stub = UninitializedLiveActivities(logger: NoopLogger())
        let handle = try stub.start(UnregisteredTestAttributes(), contentState: .init())
        #expect(handle == nil)
    }

    @available(iOS 16.2, *)
    @Test func implementation_start_unregisteredType_returnsNil_withoutThrowing() throws {
        let sdk = FakeLiveActivitiesSDK(isUserIdentified: false)
        let module = LiveActivitiesModuleImplementation(
            config: LiveActivityConfig(), // no registrations
            sdk: sdk,
            tokenStorage: FakeTokenStore()
        )
        // Unregistered type: the SDK logs and returns nil *before* requesting an activity — no throw,
        // no ActivityKit call, so nothing is actually started.
        let handle = try module.start(UnregisteredTestAttributes(), contentState: .init())
        #expect(handle == nil)
    }
    #endif
}
