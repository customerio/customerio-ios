@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceDistanceFilter")
struct GeofenceDistanceFilterTests {
    private let filter = GeofenceDistanceFilter()
    private let origin = LocationData(latitude: 0, longitude: 0)

    private func makeRegion(id: String, latitude: Double, longitude: Double, radius: Double = 100) -> Geofence {
        Geofence(
            id: id,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            name: id,
            transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 0)
        )
    }

    @Test
    func nearest_givenEmpty_expectEmpty() {
        #expect(filter.nearest([], to: origin, limit: 5, maxDistance: GeofenceConstants.noMonitoringDistanceCap).isEmpty)
    }

    @Test
    func nearest_givenLimitZero_expectEmpty() {
        let regions = [makeRegion(id: "a", latitude: 0.1, longitude: 0.1)]
        #expect(filter.nearest(regions, to: origin, limit: 0, maxDistance: GeofenceConstants.noMonitoringDistanceCap).isEmpty)
    }

    @Test
    func nearest_givenLimitNegative_expectEmpty() {
        let regions = [makeRegion(id: "a", latitude: 0.1, longitude: 0.1)]
        #expect(filter.nearest(regions, to: origin, limit: -3, maxDistance: GeofenceConstants.noMonitoringDistanceCap).isEmpty)
    }

    @Test
    func nearest_givenFewerRegionsThanLimit_expectAllReturned() {
        let regions = [
            makeRegion(id: "a", latitude: 0.1, longitude: 0.1),
            makeRegion(id: "b", latitude: 0.2, longitude: 0.2)
        ]
        let result = filter.nearest(regions, to: origin, limit: 10, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
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
        let result = filter.nearest(regions, to: origin, limit: 2, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
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
        let result = filter.nearest(regions, to: origin, limit: 3, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
        #expect(result.map(\.id) == ["a", "m", "z"])
    }

    @Test
    func nearest_givenMaxDistance_expectExcludesRegionsBeyondCap() {
        let regions = [
            makeRegion(id: "near", latitude: 0.01, longitude: 0), // ~1.1 km
            makeRegion(id: "far", latitude: 1.0, longitude: 0) // ~111 km
        ]
        let result = filter.nearest(regions, to: origin, limit: 5, maxDistance: 5000) // 5 km cap
        #expect(result.map(\.id) == ["near"])
    }

    @Test
    func nearest_givenNoMaxDistance_expectAllIncluded() {
        let regions = [
            makeRegion(id: "near", latitude: 0.01, longitude: 0),
            makeRegion(id: "far", latitude: 1.0, longitude: 0)
        ]
        // The no-cap sentinel includes every region regardless of distance.
        let result = filter.nearest(regions, to: origin, limit: 5, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
        #expect(result.map(\.id) == ["near", "far"])
    }

    // MARK: - Ranking by boundary rather than center

    @Test
    func nearest_givenDeviceInsideLargeRegion_expectItRanksFirst() {
        // Device sits inside `big` (center ~2.2 km away, radius 5 km) and outside `small`
        // (center 1 km away). Ranking on center distance would put `small` first.
        let regions = [
            makeRegion(id: "small", latitude: 0.009, longitude: 0, radius: 100),
            makeRegion(id: "big", latitude: 0.02, longitude: 0, radius: 5000)
        ]
        let result = filter.nearest(regions, to: origin, limit: 2, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
        #expect(result.map(\.id) == ["big", "small"])
    }

    @Test
    func nearest_givenLimitFilledByNearerCenters_expectContainingRegionStillMonitored() {
        // Regression: a region the device occupies must never be evicted by regions with nearer
        // centers. Evicting it stops monitoring and its exit can then never be reported.
        var regions = (0 ..< 19).map {
            makeRegion(id: "decoy\(String(format: "%02d", $0))", latitude: 0.001, longitude: 0, radius: 50)
        }
        regions.append(makeRegion(id: "containing", latitude: 0.018, longitude: 0, radius: 2000))
        let result = filter.nearest(regions, to: origin, limit: 19, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
        #expect(result.count == 19)
        #expect(result.first?.id == "containing")
    }

    @Test
    func nearest_givenContainingRegionCenterBeyondMaxDistance_expectStillIncluded() {
        // The distance cap is also boundary-based: a region whose center is outside the cap but
        // whose area contains the device must survive filtering.
        let regions = [makeRegion(id: "containing", latitude: 0.05, longitude: 0, radius: 8000)]
        let result = filter.nearest(regions, to: origin, limit: 5, maxDistance: 1000)
        #expect(result.map(\.id) == ["containing"])
    }

    @Test
    func nearest_givenRegionsFullyOutside_expectOrderedByBoundaryDistance() {
        // `wide` has the farther center but the nearer boundary, so it ranks first.
        let regions = [
            makeRegion(id: "tight", latitude: 0.02, longitude: 0, radius: 100), // edge ~2.1 km
            makeRegion(id: "wide", latitude: 0.03, longitude: 0, radius: 2000) // edge ~1.3 km
        ]
        let result = filter.nearest(regions, to: origin, limit: 2, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
        #expect(result.map(\.id) == ["wide", "tight"])
    }

    @Test
    func nearest_givenMultipleContainingRegions_expectAllRankAheadOfOutsideOnes() {
        // Every containing region has boundary distance 0, so they tie and break by id, but all
        // must precede any region the device is outside of.
        let regions = [
            makeRegion(id: "outside", latitude: 0.005, longitude: 0, radius: 100),
            makeRegion(id: "inside-b", latitude: 0.01, longitude: 0, radius: 3000),
            makeRegion(id: "inside-a", latitude: 0.02, longitude: 0, radius: 5000)
        ]
        let result = filter.nearest(regions, to: origin, limit: 3, maxDistance: GeofenceConstants.noMonitoringDistanceCap)
        #expect(result.map(\.id) == ["inside-a", "inside-b", "outside"])
    }
}
