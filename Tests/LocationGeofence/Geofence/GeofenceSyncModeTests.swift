@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceSyncMode")
struct GeofenceSyncModeTests {
    private let config = GeofenceConfig.fallback

    @Test
    func active_isFetchAll() {
        // The shipped default sends no location. Flipping this is a deliberate SDK release.
        #expect(GeofenceSyncMode.active == .fetchAll)
    }

    @Test
    func fetchAll_neverRequiresRemoteFetchOnMovement() {
        // The full set is cached, so movement only re-ranks on-device — no distance ever forces a fetch.
        #expect(GeofenceSyncMode.fetchAll.movementRequiresRemoteFetch(distanceFromAnchor: 0, config: config) == false)
        #expect(GeofenceSyncMode.fetchAll.movementRequiresRemoteFetch(distanceFromAnchor: 1000000, config: config) == false)
    }

    @Test
    func nearby_requiresRemoteFetchBeyondTriggerRadius() {
        let radius = config.remoteFetchRefreshTriggerRadius
        #expect(GeofenceSyncMode.nearby.movementRequiresRemoteFetch(distanceFromAnchor: radius - 1, config: config) == false)
        #expect(GeofenceSyncMode.nearby.movementRequiresRemoteFetch(distanceFromAnchor: radius, config: config) == true)
    }
}
