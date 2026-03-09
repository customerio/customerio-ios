@testable import CioLocation
import SharedTests
import Testing

@Suite("Location")
struct LocationConfigTests {
    @Test
    func init_givenOff_expectModeOff() {
        let config = LocationConfig(mode: .off)
        #expect(config.mode == .off)
    }

    @Test
    func init_givenManual_expectModeManual() {
        let config = LocationConfig(mode: .manual)
        #expect(config.mode == .manual)
    }

    @Test
    func init_givenOnAppStart_expectModeOnAppStart() {
        let config = LocationConfig(mode: .onAppStart)
        #expect(config.mode == .onAppStart)
    }
}
