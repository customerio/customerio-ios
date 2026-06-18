import Foundation

/// Snaps the coordinates sent to `/geofences/nearby` (the `nearby` sync mode) to a ~1km grid
/// (rounding to 2 decimals; 0.01° ≈ 1.1km latitude) so the SDK never transmits the device's exact
/// position. Precise location stays on-device for proximity and movement-trigger logic.
///
/// Snapping is deterministic, not jittered: repeated syncs from the same area send the same value,
/// so averaging many requests can't recover the true position. The server fetch radius must cover
/// the re-sync displacement plus this cell, or a geofence near a cell boundary can be missed.
enum GeofenceCoordinateCoarsener {
    /// 2 decimal places ≈ a 1.1km grid in latitude (narrower east-west toward the poles).
    private static let gridScale = 100.0

    static func coarsen(_ coordinate: Double) -> Double {
        // Round-half-to-even matches the Android SDK's `HALF_EVEN`, keeping both platforms on the
        // same grid and avoiding the directional bias of always rounding up. Scaling by 100 and
        // dividing back yields the clean canonical double for the 2-decimal value (unlike
        // `NSDecimalNumber.doubleValue`, which can land one ULP off and re-leak precision).
        (coordinate * gridScale).rounded(.toNearestOrEven) / gridScale
    }
}
