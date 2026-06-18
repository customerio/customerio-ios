@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceCoordinateCoarsener")
struct GeofenceCoordinateCoarsenerTests {
    @Test
    func coarsen_snapsToTwoDecimalGrid() {
        #expect(GeofenceCoordinateCoarsener.coarsen(37.7749) == 37.77)
        #expect(GeofenceCoordinateCoarsener.coarsen(-122.4194) == -122.42)
        // Already on the grid — unchanged.
        #expect(GeofenceCoordinateCoarsener.coarsen(10.0) == 10.0)
    }

    @Test
    func coarsen_mapsNearbyPointsToTheSameCell() {
        // Two precise points inside the same ~1km cell produce an identical coarse value, so
        // repeated syncs send the same coordinate and can't be averaged back to the true point.
        #expect(GeofenceCoordinateCoarsener.coarsen(37.7701) == GeofenceCoordinateCoarsener.coarsen(37.7749))
    }

    @Test
    func coarsen_roundsHalfToEven() {
        // Banker's rounding (parity with Android's HALF_EVEN): 0.125 → 0.12, not 0.13.
        #expect(GeofenceCoordinateCoarsener.coarsen(0.125) == 0.12)
    }
}
