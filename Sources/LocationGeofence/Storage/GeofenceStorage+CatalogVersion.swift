import Foundation

extension GeofenceStorage {
    /// True while the cache holds regions written before the catalog carried dwell: they read as
    /// dwell-disabled, which only the version tells apart from a server that disabled it. An empty
    /// or unreadable cache carries no dwell configuration, and an unreadable one already fails the
    /// freshness check.
    func cachedCatalogPredatesDwell() -> Bool {
        guard let state = loadFromDisk(), let regions = state.cachedGeofences, !regions.isEmpty else { return false }
        return (state.catalogVersion ?? 0) < GeofenceState.currentCatalogVersion
    }
}
