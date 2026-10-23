import CioInternalCommon
import Foundation

/// Which OS edges were registered only for visit bookkeeping, kept apart from the cache so an OS
/// callback for a fence the cache no longer holds can still be told from a configured one. Each
/// method runs its load → modify → save inside the actor with no `await` between steps.
extension GeofenceStorage {
    /// Records each circle's bookkeeping-only edges. Called BEFORE the fences are registered: the
    /// refresh registers with the OS ahead of caching, so a callback for a newly added fence can
    /// arrive before the cache holds it.
    ///
    /// - Parameter pruningToCache: keep only entries for `geofences` and for what the cache holds
    ///   now. Called ahead of the cache write, so a fence dropped by the PREVIOUS refresh is still
    ///   covered through this one — the window for callbacks queued when it was unregistered — and
    ///   is forgotten after it. False when registering from the cache itself: entries only added.
    func recordRegistrationIntent(for geofences: [Geofence], pruningToCache: Bool) {
        var state = loadFromDisk() ?? GeofenceState()
        let recorded = state.unconfiguredOsTransitions ?? [:]
        var intents = recorded
        if pruningToCache {
            let kept = Set(geofences.map(\.id)).union((state.cachedGeofences ?? []).map(\.id))
            intents = intents.filter { kept.contains($0.key) }
        }
        // Reversed so the first occurrence of a duplicated id decides, like every cache lookup.
        for geofence in geofences.reversed() {
            let unconfigured = geofence.unconfiguredOsTransitions
            intents[geofence.id] = unconfigured.isEmpty ? nil : unconfigured
        }
        guard intents != recorded else { return }
        state.unconfiguredOsTransitions = intents.isEmpty ? nil : intents
        saveToDisk(state)
    }

    /// The cached fence an OS callback is for, or — when the cache no longer holds it — the edges
    /// it was registered for only as bookkeeping. One read, so the answer is one consistent state.
    func transitionTarget(id: String) -> GeofenceTransitionTarget {
        let state = loadFromDisk()
        if let geofence = state?.cachedGeofences?.first(where: { $0.id == id }) {
            return .cached(geofence)
        }
        return .uncached(unconfigured: state?.unconfiguredOsTransitions?[id] ?? [])
    }
}

/// What the store knows about the fence an OS callback names.
enum GeofenceTransitionTarget: Equatable, Sendable {
    case cached(Geofence)
    /// `unconfigured`: edges registered only for visit bookkeeping; empty when none are known.
    case uncached(unconfigured: Set<GeofenceTransition>)
}
