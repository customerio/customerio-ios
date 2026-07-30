import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation
import Testing

@testable import CioLiveActivities

struct LiveActivityHandleWidgetUrlTests {
    private func makeModule(_ bus: CapturingEventBusHandler) -> LiveActivitiesModuleImplementation {
        let sdk = FakeLiveActivitiesSDK(isUserIdentified: true, eventBusHandler: bus)
        return LiveActivitiesModuleImplementation(config: LiveActivityConfig(), sdk: sdk, tokenStorage: FakeTokenStore())
    }

    private func openedEvents(_ bus: CapturingEventBusHandler) -> [TrackMetricEvent] {
        bus.posted.compactMap { $0 as? TrackMetricEvent }.filter { $0.event == Metric.opened.rawValue }
    }

    @Test func cioUrl_withDeliveryAndDeepLink_reportsOpened_andReturnsRedirect() {
        let bus = CapturingEventBusHandler()
        let module = makeModule(bus)
        let url = CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deliveryId: "d1", deliveryToken: "tok", deepLink: "myapp://x")
        )!

        let redirect = module.handleWidgetUrl(url)

        #expect(redirect == URL(string: "myapp://x"))
        let opened = openedEvents(bus)
        #expect(opened.count == 1)
        #expect(opened.first?.deliveryID == "d1")
        #expect(opened.first?.deviceToken == "tok")
    }

    @Test func cioUrl_deliveryOnly_reportsOpened_andReturnsNilRedirect() {
        let bus = CapturingEventBusHandler()
        let module = makeModule(bus)
        let url = CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deliveryId: "d2", deliveryToken: nil, deepLink: nil)
        )!

        let redirect = module.handleWidgetUrl(url)

        #expect(redirect == nil)
        #expect(openedEvents(bus).first?.deliveryID == "d2")
    }

    @Test func cioUrl_deepLinkOnly_reportsNoOpened_andReturnsRedirect() {
        // A deep-link-only URL has nothing to attribute an open to, but is still navigable.
        let bus = CapturingEventBusHandler()
        let module = makeModule(bus)
        let url = CioLiveActivityWidgetUrl.trackingURL(
            for: CIOLiveActivityMetadata(deliveryId: nil, deliveryToken: nil, deepLink: "myapp://y")
        )!

        let redirect = module.handleWidgetUrl(url)

        #expect(redirect == URL(string: "myapp://y"))
        #expect(openedEvents(bus).isEmpty)
    }

    @Test func nonCioUrl_passesThroughUnchanged_andReportsNoOpened() {
        let bus = CapturingEventBusHandler()
        let module = makeModule(bus)
        let url = URL(string: "myapp://settings")!

        #expect(module.handleWidgetUrl(url) == url)
        #expect(openedEvents(bus).isEmpty)
    }
}
