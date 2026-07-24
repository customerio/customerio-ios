import CioLiveActivities_Attributes
import Foundation
import Testing

struct CioLiveActivityWidgetUrlTests {
    // MARK: - trackingURL emit decision

    @Test func trackingURL_nilMetadata_returnsNil() {
        #expect(CioLiveActivityWidgetUrl.trackingURL(for: nil) == nil)
    }

    @Test func trackingURL_tokenOnly_returnsNil() {
        // A delivery token alone can neither report an open (no deliveryId) nor navigate (no
        // deepLink), so it must not produce a tap URL that gets swallowed.
        let metadata = CIOLiveActivityMetadata(deliveryId: nil, deliveryToken: "tok", deepLink: nil)
        #expect(CioLiveActivityWidgetUrl.trackingURL(for: metadata) == nil)
    }

    @Test func trackingURL_emptyStrings_returnsNil() {
        let metadata = CIOLiveActivityMetadata(deliveryId: "", deliveryToken: "tok", deepLink: "")
        #expect(CioLiveActivityWidgetUrl.trackingURL(for: metadata) == nil)
    }

    // MARK: - trackingURL contents (via round-trip parse)

    @Test func trackingURL_deliveryIdOnly_carriesIdAndToken_noRedirect() {
        let metadata = CIOLiveActivityMetadata(deliveryId: "d1", deliveryToken: "tok", deepLink: nil)
        let parsed = CioLiveActivityWidgetUrl.trackingURL(for: metadata).flatMap(CioLiveActivityWidgetUrl.parse)
        #expect(parsed?.deliveryId == "d1")
        #expect(parsed?.deliveryToken == "tok")
        #expect(parsed?.redirect == nil)
    }

    @Test func trackingURL_deepLinkOnly_carriesRedirect_noIdOrToken() {
        // No deliveryId → a URL is still emitted for navigation, but the token isn't carried
        // (it's meaningless without a deliveryId to attribute the open to).
        let metadata = CIOLiveActivityMetadata(deliveryId: nil, deliveryToken: "tok", deepLink: "myapp://x")
        let parsed = CioLiveActivityWidgetUrl.trackingURL(for: metadata).flatMap(CioLiveActivityWidgetUrl.parse)
        #expect(parsed?.deliveryId == nil)
        #expect(parsed?.deliveryToken == nil)
        #expect(parsed?.redirect == URL(string: "myapp://x"))
    }

    @Test func trackingURL_allFields_roundTrip() {
        let metadata = CIOLiveActivityMetadata(deliveryId: "d1", deliveryToken: "tok", deepLink: "myapp://x")
        let parsed = CioLiveActivityWidgetUrl.trackingURL(for: metadata).flatMap(CioLiveActivityWidgetUrl.parse)
        #expect(parsed?.deliveryId == "d1")
        #expect(parsed?.deliveryToken == "tok")
        #expect(parsed?.redirect == URL(string: "myapp://x"))
    }

    // MARK: - parse rejects non-CIO URLs

    @Test func parse_nonCioUrl_returnsNil() {
        #expect(CioLiveActivityWidgetUrl.parse(URL(string: "https://example.com/open")!) == nil)
        #expect(CioLiveActivityWidgetUrl.parse(URL(string: "myapp://settings")!) == nil)
    }
}
