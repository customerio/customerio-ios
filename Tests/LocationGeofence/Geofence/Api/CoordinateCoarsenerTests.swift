@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("CoordinateCoarsener")
struct CoordinateCoarsenerTests {
    @Test
    func coarsen_given500mGrid_expectSnappedAndTrimmedToGrid() {
        let coarse = CoordinateCoarsener.coarsen(latitude: 37.7749295, longitude: -122.4194155)
        // Snapped to the uniform ~500 m grid and trimmed of binary-float noise (clean 6 dp).
        #expect(coarse.latitude == 37.773985)
        #expect(coarse.longitude == -122.417457)
    }

    @Test
    func coarsen_givenHighLatitude_expectLongitudeGridWidensToStayUniform() {
        // At 60° (cos ≈ 0.5) a degree of longitude is ~half the ground distance, so the longitude
        // grid roughly doubles in degrees to hold the ~500 m floor — where fixed-degree rounding
        // would over-refine longitude instead.
        let coarse = CoordinateCoarsener.coarsen(latitude: 60.0, longitude: 10.123456)
        #expect(abs(coarse.longitude - 10.123456) < 0.0090) // ~the ~0.009° cell at this latitude
    }
}
