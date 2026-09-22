@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("PolygonWakeRadius")
struct PolygonWakeRadiusTests {
    private static let center = LocationData(latitude: 31.37, longitude: 74.17)

    private func config(localRefresh: Double = 1000) -> GeofenceConfig {
        GeofenceConfig(
            localRefreshTriggerRadius: localRefresh,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 19,
            maxMonitoringDistance: 50000
        )
    }

    /// ~400 m square around `center`; the venue at the middle sits ~200 m from the nearest edge.
    private func polygon(id: String, coveringRadius: Double = 500) -> Geofence {
        let ring = [
            LocationData(latitude: 31.3682, longitude: 74.1679),
            LocationData(latitude: 31.3682, longitude: 74.1721),
            LocationData(latitude: 31.3718, longitude: 74.1721),
            LocationData(latitude: 31.3718, longitude: 74.1679)
        ]
        return Geofence(
            id: id, latitude: Self.center.latitude, longitude: Self.center.longitude,
            radius: coveringRadius, name: id, transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 0), vertices: ring
        )
    }

    /// A ~4 km square around `center`, so its boundary is far from anything the tests probe.
    private func widePolygon(id: String) -> Geofence {
        let ring = [
            LocationData(latitude: 31.35, longitude: 74.15),
            LocationData(latitude: 31.35, longitude: 74.19),
            LocationData(latitude: 31.39, longitude: 74.19),
            LocationData(latitude: 31.39, longitude: 74.15)
        ]
        return Geofence(
            id: id, latitude: Self.center.latitude, longitude: Self.center.longitude,
            radius: 5000, name: id, transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 0), vertices: ring
        )
    }

    private func circle(id: String, radius: Double = 300) -> Geofence {
        Geofence(
            id: id, latitude: Self.center.latitude, longitude: Self.center.longitude,
            radius: radius, name: id, transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 0), vertices: nil
        )
    }

    /// A workspace with no polygons must behave exactly as it does today.
    @Test
    func radius_givenNoPolygons_expectConfiguredRefreshRadius() {
        let r = PolygonWakeRadius.radius(at: Self.center, registeredPolygons: [circle(id: "1")], config: config())
        #expect(r == 1000)
    }

    /// No boundary within the refresh radius, so there is nothing to tighten for.
    @Test
    func radius_givenNoBoundaryWithinRefreshRadius_expectConfiguredRefreshRadius() {
        let faraway = LocationData(latitude: 31.45, longitude: 74.17)
        let r = PolygonWakeRadius.radius(at: faraway, registeredPolygons: [polygon(id: "1")], config: config())
        #expect(r == 1000)
    }

    /// Outside the covering circle but near the ring. A covering-circle enter does not re-arm the
    /// trigger, so if the radius ignored polygons the device has not yet reached, the device would
    /// carry a wide trigger into the circle and across the boundary — no wake, no OS event, and an
    /// exit over an unchanged belief on the way out, making the whole visit silent.
    @Test
    func radius_givenDeviceOutsideCoveringCircleButNearBoundary_expectDistanceToBoundary() {
        // ~600 m north of centre: beyond the 500 m covering circle, ~400 m from the ring's north edge.
        let approaching = LocationData(latitude: 31.37539, longitude: 74.17)
        let r = PolygonWakeRadius.radius(at: approaching, registeredPolygons: [polygon(id: "1")], config: config())
        #expect(r > 360 && r < 440, "got \(r)")
    }

    @Test
    func radius_givenDeviceInsidePolygon_expectDistanceToNearestBoundary() {
        let r = PolygonWakeRadius.radius(at: Self.center, registeredPolygons: [polygon(id: "1")], config: config())
        // ~200 m to the nearest edge of the 400 m square.
        #expect(r > 190 && r < 210, "got \(r)")
    }

    /// The NEAREST boundary wins: a distant polygon must not let the device walk into a close one.
    @Test
    func radius_givenTwoPolygons_expectNearestBoundaryWins() {
        let near = LocationData(latitude: 31.3717, longitude: 74.17) // ~11 m inside the north edge
        // The wide polygon's boundary is ~2 km away; the narrow one's is ~11 m. Sizing by the
        // farthest instead of the nearest would return ~1000 m (capped) and let the device walk
        // straight through the near boundary unwoken.
        let wideOnly = PolygonWakeRadius.radius(at: near, registeredPolygons: [widePolygon(id: "far")], config: config())
        #expect(wideOnly == 1000, "control: wide polygon alone should cap at config, got \(wideOnly)")

        let both = PolygonWakeRadius.radius(
            at: near, registeredPolygons: [widePolygon(id: "far"), polygon(id: "near")], config: config()
        )
        #expect(both == GeofenceConstants.polygonWakeMinRadius, "got \(both)")
    }

    /// The floor is what stops the trigger shrinking into the range the OS promotes unreliably.
    @Test
    func radius_givenBoundaryNearerThanFloor_expectFloor() {
        let onEdge = LocationData(latitude: 31.37179, longitude: 74.17)
        let r = PolygonWakeRadius.radius(at: onEdge, registeredPolygons: [polygon(id: "1")], config: config())
        #expect(r == GeofenceConstants.polygonWakeMinRadius, "got \(r)")
    }

    /// Never larger than the configured refresh radius, even when the boundary is far off.
    @Test
    func radius_givenBoundaryBeyondRefreshRadius_expectCappedAtConfig() {
        let r = PolygonWakeRadius.radius(
            at: Self.center, registeredPolygons: [widePolygon(id: "1")], config: config(localRefresh: 150)
        )
        #expect(r == 150, "got \(r)")
    }

    /// A config below the floor cannot push the trigger into the range the OS drops.
    @Test
    func radius_givenConfigBelowFloor_expectFloorWins() {
        let r = PolygonWakeRadius.radius(
            at: Self.center, registeredPolygons: [polygon(id: "1")], config: config(localRefresh: 50)
        )
        #expect(r == GeofenceConstants.polygonWakeMinRadius, "got \(r)")
    }
}
