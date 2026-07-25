import CioInternalCommon
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
        // No opened metric is reported (module isn't initialized), but routing still proceeds.
        #expect(stub.handleWidgetUrl(url) == url)
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
