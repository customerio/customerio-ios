@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceRegionRequest.matchesRegistered")
struct GeofenceRegionRequestTests {
    private static let uncapped = Double.greatestFiniteMagnitude

    private func makeRequest(
        latitude: Double = 10,
        longitude: Double = 20,
        radius: Double = 100,
        transitionTypes: Set<GeofenceTransition> = [.enter, .exit]
    ) -> GeofenceRegionRequest {
        GeofenceRegionRequest(
            identifier: "region",
            center: LocationData(latitude: latitude, longitude: longitude),
            radius: radius,
            transitionTypes: transitionTypes
        )
    }

    @Test
    func matchesRegistered_givenIdenticalCircle_expectMatch() {
        let request = makeRequest()
        #expect(request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 100,
            transitionTypes: [.enter, .exit],
            clampedTo: Self.uncapped
        ))
    }

    @Test
    func matchesRegistered_givenCoordinateDriftWithinTolerance_expectMatch() {
        let request = makeRequest()
        #expect(request.matchesRegistered(
            center: LocationData(latitude: 10 + 5e-8, longitude: 20 - 5e-8),
            radius: 100,
            transitionTypes: [.enter, .exit],
            clampedTo: Self.uncapped
        ))
    }

    @Test
    func matchesRegistered_givenMovedCenter_expectNoMatch() {
        let request = makeRequest()
        #expect(!request.matchesRegistered(
            center: LocationData(latitude: 10.001, longitude: 20),
            radius: 100,
            transitionTypes: [.enter, .exit],
            clampedTo: Self.uncapped
        ))
    }

    @Test
    func matchesRegistered_givenRadiusDriftWithinTolerance_expectMatch() {
        let request = makeRequest()
        #expect(request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 100.2,
            transitionTypes: [.enter, .exit],
            clampedTo: Self.uncapped
        ))
    }

    @Test
    func matchesRegistered_givenResizedRadius_expectNoMatch() {
        let request = makeRequest(radius: 100)
        #expect(!request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 250,
            transitionTypes: [.enter, .exit],
            clampedTo: Self.uncapped
        ))
    }

    @Test
    func matchesRegistered_givenRadiusAboveCapAndRegisteredAtCap_expectMatch() {
        // The OS clamps the radius at registration.
        let request = makeRequest(radius: 5000)
        #expect(request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 1000,
            transitionTypes: [.enter, .exit],
            clampedTo: 1000
        ))
    }

    @Test
    func matchesRegistered_givenRadiusAboveCapButRegisteredBelowCap_expectNoMatch() {
        let request = makeRequest(radius: 5000)
        #expect(!request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 400,
            transitionTypes: [.enter, .exit],
            clampedTo: 1000
        ))
    }

    @Test
    func matchesRegistered_givenRadiusBelowCap_expectCapIgnored() {
        let request = makeRequest(radius: 100)
        #expect(request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 100,
            transitionTypes: [.enter, .exit],
            clampedTo: 1000
        ))
    }

    @Test
    func matchesRegistered_givenNarrowedTransitionTypes_expectNoMatch() {
        let request = makeRequest(transitionTypes: [.enter, .exit])
        #expect(!request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 100,
            transitionTypes: [.enter],
            clampedTo: Self.uncapped
        ))
    }

    @Test
    func matchesRegistered_givenDifferentSingleTransitionType_expectNoMatch() {
        let request = makeRequest(transitionTypes: [.exit])
        #expect(!request.matchesRegistered(
            center: LocationData(latitude: 10, longitude: 20),
            radius: 100,
            transitionTypes: [.enter],
            clampedTo: Self.uncapped
        ))
    }
}
