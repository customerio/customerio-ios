@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("LocationProfileEnrichmentProvider")
struct LocationProfileEnrichmentProviderTests {
    @Test
    func getProfileEnrichmentAttributes_whenNoCachedLocation_returnsNil() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let provider = LocationProfileEnrichmentProvider(storage: storage)
        #expect(provider.getProfileEnrichmentAttributes() == nil)
    }

    @Test
    func getProfileEnrichmentAttributes_whenCachedLocationExists_returnsLatitudeAndLongitude() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        let provider = LocationProfileEnrichmentProvider(storage: storage)
        let attrs = provider.getProfileEnrichmentAttributes()
        #expect(attrs != nil)
        #expect(attrs?["location_latitude"] as? Double == 40.7128)
        #expect(attrs?["location_longitude"] as? Double == -74.0060)
    }

    @Test
    func resetContext_clearsCache_soGetProfileEnrichmentAttributesReturnsNil() {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        let provider = LocationProfileEnrichmentProvider(storage: storage)
        #expect(provider.getProfileEnrichmentAttributes() != nil)
        provider.resetContext()
        #expect(provider.getProfileEnrichmentAttributes() == nil)
    }
}
