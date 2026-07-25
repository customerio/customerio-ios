import CioInternalCommon
import Foundation

/// What the OS accepted for a registration sync: the identifiers actually monitored and the radius
/// cap the OS clamps every region to. Both feed the initial-enter decision.
struct GeofenceOsRegistration {
    let registeredIds: Set<String>
    let maxMonitoringRadius: Double
}

/// OS registration + fetch plumbing, split out to keep the coordinator's core flow readable.
/// Methods are `internal` (not `private`) only because they live in a separate file from their
/// callers; they remain coordinator implementation detail.
extension GeofenceSyncCoordinatorImpl {
    /// Bridges the completion-based nearby fetch to async.
    func awaitApiFetch(latitude: Double, longitude: Double) async -> Result<GeofenceApiResponse, GeofenceApiError> {
        await withCheckedContinuation { continuation in
            apiService.fetchNearbyGeofences(latitude: latitude, longitude: longitude) { continuation.resume(returning: $0) }
        }
    }

    /// True when re-registering would be a no-op: same ids as recorded, all owned by this process
    /// and still held by the OS. Re-adding re-seeds each region's assumed state from the live fix,
    /// absorbing any crossing the OS hasn't delivered yet — once per trigger radius at driving
    /// speed. Any doubt falls through to the wholesale path, which re-establishes ownership, heals
    /// dropped regions, and tears down under the kill switch (a geofence-free area leaves the
    /// trigger owned with no business ids, so the ids alone would otherwise match).
    @MainActor
    func canSkipReregistration(
        nearestIds: Set<String>,
        previouslyRegisteredIds: Set<String>,
        registerMovementTrigger: Bool
    ) -> Bool {
        guard registerMovementTrigger, nearestIds == previouslyRegisteredIds else { return false }
        let expected = nearestIds.union([GeofenceConstants.movementTriggerIdentifier])
        return expected.isSubset(of: monitor.monitoredRegionIdentifiers)
            && expected.isSubset(of: monitor.osMonitoredRegionIdentifiers)
    }

    /// Moves only the trigger. Explicit stop-then-start, which both monitors serialize. Nothing is
    /// lost by re-seeding this one region: it is being re-centered precisely because the device
    /// left the old circle.
    @MainActor
    func recenterMovementTrigger(at location: LocationData, radius: Double) {
        monitor.stopMonitoring(identifier: GeofenceConstants.movementTriggerIdentifier)
        monitor.startMonitoring(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            center: location,
            radius: radius,
            transitionTypes: [.exit]
        )
    }

    /// Stops all monitored regions, then starts the new business set + movement trigger. Returns the
    /// OS-accepted identifiers (a region the monitor dropped for blocked permission / invalid
    /// coordinates is absent) plus the radius cap, so `emitInitialEnters` won't fire an unbalanced
    /// synthetic enter or one for a device outside the actually-monitored (clamped) circle.
    /// `@MainActor`-isolated so a same-actor caller (e.g. `applyCachedRegistration`)
    /// can register without yielding — see the protocol doc for why that matters.
    @MainActor
    @discardableResult
    func registerWithOsSync(
        businessRegions: [Geofence],
        movementTriggerLocation: LocationData,
        movementTriggerRadius: Double,
        registerMovementTrigger: Bool
    ) -> GeofenceOsRegistration {
        monitor.stopMonitoringAll()
        // Register the movement trigger FIRST so it isn't starved when business regions fill the
        // shared 20-region OS budget (e.g. a host app that also monitors regions): losing it freezes
        // the set, since exiting the trigger is what re-ranks toward now-closer geofences. Kept even
        // when the nearby set is empty (distance cap or an empty fetch) so the device keeps re-fetching
        // as it moves back toward geofences; skipped only when kill-switched (`maxBusinessGeofences == 0`).
        if registerMovementTrigger {
            monitor.startMonitoring(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                center: movementTriggerLocation,
                radius: movementTriggerRadius,
                transitionTypes: [.exit]
            )
        }
        for region in businessRegions {
            monitor.startMonitoring(
                identifier: region.id,
                center: LocationData(latitude: region.latitude, longitude: region.longitude),
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
        }
        return GeofenceOsRegistration(
            registeredIds: monitor.monitoredRegionIdentifiers,
            maxMonitoringRadius: monitor.maximumMonitoringRadius
        )
    }
}
