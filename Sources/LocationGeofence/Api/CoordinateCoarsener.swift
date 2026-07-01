import Foundation

/// Reduces the precision of a coordinate before it leaves the device, so a location-bound
/// sync (`GeofenceSyncMode.fetchNearby`) sends an approximate position rather than an exact one.
///
/// Snaps to a uniform ground grid. Longitude degrees shrink toward the poles, so the longitude grid
/// is scaled by cos(latitude) to keep the spacing uniform in meters — a fixed-degree grid would
/// over-refine longitude at high latitudes. Coarse enough to avoid transmitting a precise position,
/// fine enough for the server to rank nearby geofences.
enum CoordinateCoarsener {
    /// Ground grid (meters) the coordinate is snapped to.
    static let gridMeters = 500.0

    /// Approximate meters per degree of latitude (near-constant), to convert the grid to degrees.
    private static let metersPerDegreeLatitude = 111320.0

    static func coarsen(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        let latGridDegrees = gridMeters / metersPerDegreeLatitude
        // Guard cos → 0 at the poles, where the longitude grid would otherwise span the globe.
        let cosLatitude = max(cos(latitude / 180 * .pi), 1e-6)
        let lngGridDegrees = gridMeters / (metersPerDegreeLatitude * cosLatitude)
        return (
            latitude: snapToGrid(latitude, gridDegrees: latGridDegrees),
            longitude: snapToGrid(longitude, gridDegrees: lngGridDegrees)
        )
    }

    /// Snaps to the grid, then trims binary-float noise (e.g. 37.775000000000006) so the coordinate
    /// stringifies cleanly into the request. 6 dp ≈ 0.1 m — far below the grid, so precision is unaffected.
    private static func snapToGrid(_ value: Double, gridDegrees: Double) -> Double {
        let snapped = (value / gridDegrees).rounded() * gridDegrees
        return (snapped * 1000000).rounded() / 1000000
    }
}
