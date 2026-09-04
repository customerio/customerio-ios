import CioInternalCommon
import CoreLocation
import Foundation

/// Baseline heal for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable (same convention as `+Registration`).
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Synthesizes crossings the OS never delivered: for each candidate (registered-unchanged by
    /// the sync that calls this), compares the stored dedup baseline against a fix resolved at
    /// drain time and delivers the transition when they unambiguously contradict
    /// (`BaselineHealDecision`).
    ///
    /// Runs as a pipeline operation ENQUEUED BEHIND the calling sync's own registration ops —
    /// baselines are read after those ops' rewrites have drained. The state-space model confirms
    /// this ordering (v5 run, 2026-08-08: removes ~21k lost-crossing orderings, adds only
    /// cooldown-absorbed duplicates; the read-at-sync variant races its own sync's queued
    /// rewrites). Delivery reuses `recordMonitorEvent`, so the dedup flip and transition-type
    /// filter are identical to the OS event path, and a later OS delivery of the same crossing
    /// dedups against the healed baseline.
    ///
    /// Each candidate's registered circle is CAPTURED here, synchronously with the calling sync's
    /// unchanged-diff, and re-verified when the operation drains: a later sync can stage a reshape
    /// (updating `registeredConditions` synchronously) while its storage rewrite is still queued
    /// behind this heal, and judging the old baseline against the new circle would synthesize a
    /// wrong transition. A candidate whose staged geometry or stored record no longer matches the
    /// capture is skipped — the reshape reseeds its baseline anyway.
    ///
    /// The write is additionally guarded on the baseline's age (`onlyIfBaselinePredates`): a
    /// genuine OS crossing recorded after the fix was taken — while the heal waited in the queue,
    /// or within the fix's own age — must win over a decision made from an older position, which
    /// would otherwise synthesize the reverse transition and dedup away the real one.
    func enqueueBaselineHeal(candidates: [String]) {
        // Captured before the enqueue: `registeredConditions` at this instant is what the calling
        // sync just diffed as unchanged.
        let expectedConditions = candidates.reduce(into: [String: RegisteredCondition]()) {
            $0[$1] = registeredConditions[$1]
        }
        guard !expectedConditions.isEmpty else { return }
        enqueueMonitorOperation { [weak self] _ in
            guard let self else { return }
            guard let fix = await self.resolveHealFix(), CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
            let records = await self.storage.getMonitorRegionRecords()
            for (identifier, condition) in expectedConditions.sorted(by: { $0.key < $1.key }) {
                guard self.ownedRegionIdentifiers.contains(identifier),
                      self.registeredConditions[identifier] == condition,
                      let record = records[identifier],
                      record.center == condition.center, record.radius == condition.radius
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
                guard case .deliver = await self.storage.recordMonitorEvent(
                    transition,
                    forIdentifier: identifier,
                    onlyIfBaselinePredates: fix.timestamp
                ) else { continue }
                self.logger.geofenceBaselineHealed(identifier: identifier, transition: transition)
                self.onTransition?(
                    identifier,
                    transition,
                    LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude),
                    fix.timestamp
                )
            }
        }
    }

    /// Freshest fix obtainable for the heal, resolved when the operation drains: reuses the
    /// movement resolver (one-shot request when the cache is stale, cached-fix fallback on
    /// timeout), so a sync whose originating fix never reaches this monitor — app-launch, manual,
    /// and foreground refreshes acquire theirs upstream and hand over coordinates only — still
    /// heals off a fix with a real timestamp and accuracy instead of silently skipping. Movement
    /// syncs pay nothing: the movement pass resolved through this same resolver moments earlier,
    /// so the cache is fresh. At most one request per sync, on the operation pipeline — never on
    /// the event path. Returns via `bestKnownFix()` so the freshest of the cache and the request
    /// wins; the decision's fix-age guard applies to the result.
    private func resolveHealFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix()) { [weak self] _ in
                continuation.resume(returning: self?.bestKnownFix())
            }
        }
    }
}
