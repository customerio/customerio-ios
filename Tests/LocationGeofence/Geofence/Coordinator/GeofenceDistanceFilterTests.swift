@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceDistanceFilter")
struct GeofenceDistanceFilterTests {
    private let filter = GeofenceDistanceFilter()
    private let origin = LocationData(latitude: 0, longitude: 0)

    private func makeRegion(id: String, latitude: Double, longitude: Double) -> Geofence {
        Geofence(
            id: id,
            latitude: latitude,
            longitude: longitude,
            radius: 100,
            name: id,
            transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 0)
        )
    }

    @Test
    func nearest_givenEmpty_expectEmpty() {
        #expect(filter.nearest([], to: origin, limit: 5).isEmpty)
    }

    @Test
    func nearest_givenLimitZero_expectEmpty() {
        let regions = [makeRegion(id: "a", latitude: 0.1, longitude: 0.1)]
        #expect(filter.nearest(regions, to: origin, limit: 0).isEmpty)
    }

    @Test
    func nearest_givenLimitNegative_expectEmpty() {
        let regions = [makeRegion(id: "a", latitude: 0.1, longitude: 0.1)]
        #expect(filter.nearest(regions, to: origin, limit: -3).isEmpty)
    }

    @Test
    func nearest_givenFewerRegionsThanLimit_expectAllReturned() {
        let regions = [
            makeRegion(id: "a", latitude: 0.1, longitude: 0.1),
            makeRegion(id: "b", latitude: 0.2, longitude: 0.2)
        ]
        let result = filter.nearest(regions, to: origin, limit: 10)
        #expect(result.count == 2)
        #expect(Set(result.map(\.id)) == ["a", "b"])
    }

    @Test
    func nearest_givenMoreRegionsThanLimit_expectKClosestInDistanceOrder() {
        // c is closest, b mid, a farthest.
        let regions = [
            makeRegion(id: "a", latitude: 5.0, longitude: 0),
            makeRegion(id: "b", latitude: 2.0, longitude: 0),
            makeRegion(id: "c", latitude: 0.5, longitude: 0),
            makeRegion(id: "d", latitude: 10.0, longitude: 0)
        ]
        let result = filter.nearest(regions, to: origin, limit: 2)
        #expect(result.map(\.id) == ["c", "b"])
    }

    @Test
    func nearest_givenTiedDistances_expectStableOrderByIdAscending() {
        // Three regions at the same distance — tiebreaker is id ascending.
        let regions = [
            makeRegion(id: "z", latitude: 0.1, longitude: 0),
            makeRegion(id: "a", latitude: 0.1, longitude: 0),
            makeRegion(id: "m", latitude: 0.1, longitude: 0)
        ]
        let result = filter.nearest(regions, to: origin, limit: 3)
        #expect(result.map(\.id) == ["a", "m", "z"])
    }
}
