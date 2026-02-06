@testable import CioLocation
import SharedTests
import Testing

@Suite("Location")
struct LocationConfigTests {
    @Test
    func init_givenTrackingEnabled_expectTrackingEnabled() {
        let config = LocationConfig(enableLocationTracking: true)
        #expect(config.enableLocationTracking == true)
    }

    @Test
    func init_givenTrackingDisabled_expectTrackingDisabled() {
        let config = LocationConfig(enableLocationTracking: false)
        #expect(config.enableLocationTracking == false)
    }
}
