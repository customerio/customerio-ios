import CioInternalCommon
import CoreLocation
import Foundation

/// Baseline heal for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable (same convention as `+Registration`).
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Synthesizes crossings the OS never delivered: for each candidate (registered-unchanged by
    /// the sync that calls this), compares the stored dedup baseline against the sync's fix and
    /// delivers the transition when they unambiguously contradict (`BaselineHealDecision`).
    ///
    /// Runs as a pipeline operation ENQUEUED BEHIND the calling sync's own registration ops —
    /// baselines are read after those ops' rewrites have drained, with the fix captured at sync
    /// time. The state-space model confirms this ordering (v5 run, 2026-08-08: removes ~21k
    /// lost-crossing orderings, adds only cooldown-absorbed duplicates; the read-at-sync variant
    /// races its own sync's queued rewrites). Delivery reuses `recordMonitorEvent`, so the dedup
    /// flip and transition-type filter are identical to the OS event path, and a later OS
    /// delivery of the same crossing dedups against the healed baseline.
    func enqueueBaselineHeal(candidates: [String], fix: CLLocation?) {
        guard let fix, CLLocationCoordinate2DIsValid(fix.coordinate), !candidates.isEmpty else { return }
        enqueueMonitorOperation { [weak self] _ in
            guard let self else { return }
            let records = await self.storage.getMonitorRegionRecords()
            for identifier in candidates.sorted() {
                guard self.ownedRegionIdentifiers.contains(identifier),
                      let condition = self.registeredConditions[identifier],
                      let record = records[identifier]
                else { continue }
                let center = CLLocation(latitude: condition.center.latitude, longitude: condition.center.longitude)
                guard let transition = BaselineHealDecision.synthesizedTransition(
                    distanceFromCenter: fix.distance(from: center),
                    radius: condition.radius,
                    horizontalAccuracy: fix.horizontalAccuracy,
                    // Age at drain time, so a delayed drain disqualifies the fix instead of
                    // trusting a snapshot that has gone stale in the queue.
                    fixAge: -fix.timestamp.timeIntervalSinceNow,
                    lastState: record.lastState
                ) else { continue }
                guard case .deliver = await self.storage.recordMonitorEvent(transition, forIdentifier: identifier) else { continue }
                self.logger.geofenceBaselineHealed(identifier: identifier, transition: transition)
                self.onTransition?(
                    identifier,
                    transition,
                    LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
                )
            }
        }
    }
}
