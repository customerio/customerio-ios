@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("LocationProfileEnrichmentProvider")
struct LocationProfileEnrichmentProviderTests {
    private func makeProvider(storage: LastLocationStorageImpl, mode: LocationTrackingMode = .manual) -> LocationProfileEnrichmentProvider {
        LocationProfileEnrichmentProvider(storage: storage, config: LocationConfig(mode: mode))
    }

    @Test
    func getProfileEnrichmentAttributes_whenNoCachedLocation_returnsNil() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let provider = makeProvider(storage: storage)
        #expect(provider.getProfileEnrichmentAttributes() == nil)
    }

    @Test
    func getProfileEnrichmentAttributes_whenCachedLocationExists_returnsLatitudeAndLongitude() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        let provider = makeProvider(storage: storage)
        let attrs = provider.getProfileEnrichmentAttributes()
        #expect(attrs != nil)
        #expect(attrs?["location_latitude"] as? Double == 40.7128)
        #expect(attrs?["location_longitude"] as? Double == -74.0060)
    }

    @Test
    func getProfileEnrichmentAttributes_whenModeOff_returnsNilEvenWithCachedLocation() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        let provider = makeProvider(storage: storage, mode: .off)
        #expect(provider.getProfileEnrichmentAttributes() == nil)
    }

    @Test
    func resetContext_clearsCache_soGetProfileEnrichmentAttributesReturnsNil() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        let provider = makeProvider(storage: storage)
        #expect(provider.getProfileEnrichmentAttributes() != nil)
        provider.resetContext()
        #expect(provider.getProfileEnrichmentAttributes() == nil)
    }
}
