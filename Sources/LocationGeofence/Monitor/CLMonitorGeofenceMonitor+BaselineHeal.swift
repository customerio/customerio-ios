import CioInternalCommon
import CoreLocation
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Synthesizes crossings the OS never delivered: for each registered-unchanged candidate,
    /// compares the stored baseline against a fix resolved at drain time (`BaselineHealDecision`).
    ///
    /// Enqueued behind the calling sync's own registration ops, so baselines are read after those
    /// rewrites drain. Delivery goes through `recordMonitorEvent`, so dedup and the transition-type
    /// filter match the OS event path, and a later OS copy of the same crossing dedups against it.
    ///
    /// Each candidate's circle is captured now and re-checked at drain: a later sync can stage a
    /// reshape while its storage rewrite is still queued behind this heal, and judging the old
    /// baseline against the new circle would synthesize a wrong transition.
    ///
    /// `onlyIfBaselinePredates` lets a genuine OS crossing recorded after the fix was taken win over
    /// this older decision. The OS path passes the same guard with its event date, because a heal
    /// advances neither `registeredAt` nor `lastEventDate` and an older OS event would otherwise
    /// reverse it. Both sides stamp OS/fix time, never drain time, so the result does not depend on
    /// how fast the queue drains.
    func enqueueBaselineHeal(candidates: [String]) {
        // The ledger at this instant is what the calling sync just diffed as unchanged.
        let expectedConditions = candidates.reduce(into: [String: RegisteredCondition]()) {
            $0[$1] = conditionLedger.condition(for: $1)
        }
        guard !expectedConditions.isEmpty else { return }
        enqueueMonitorOperation { [weak self] _ in
            guard let self else { return }
            guard let fix = await self.resolveHealFix(), CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
            let records = await self.storage.getMonitorRegionRecords()
            for (identifier, condition) in expectedConditions.sorted(by: { $0.key < $1.key }) {
                guard self.ownedRegionIdentifiers.contains(identifier),
                      self.conditionLedger.condition(for: identifier) == condition,
                      let record = records[identifier],
                      record.center == condition.center, record.radius == condition.radius
                else { continue }
                let center = CLLocation(latitude: condition.center.latitude, longitude: condition.center.longitude)
                guard let transition = BaselineHealDecision.synthesizedTransition(
                    distanceFromCenter: fix.distance(from: center),
                    radius: condition.radius,
                    horizontalAccuracy: fix.horizontalAccuracy,
                    // Age at drain time, so a delayed drain disqualifies a fix gone stale in the queue.
                    fixAge: self.dateUtil.now.timeIntervalSince(fix.timestamp),
                    lastState: record.lastState
                ) else { continue }
                // Stamped with the fix's time, not drain time, so the baseline records when the
                // evidence was taken. A refusal logs `baseline.refused`, not `os.callback.dropped`:
                // nothing arrived from the OS on this path.
                let outcome = await self.storage.recordMonitorEvent(
                    transition,
                    forIdentifier: identifier,
                    onlyIfBaselinePredates: fix.timestamp,
                    now: fix.timestamp
                )
                guard case .deliver = outcome else {
                    if let reason = outcome.diagnosticReason {
                        self.logger.geofenceBaselineRefused(identifier: identifier, transition: transition, reason: reason)
                    }
                    continue
                }
                self.logger.geofenceBaselineHealed(identifier: identifier, transition: transition)
                self.onTransition?(
                    identifier,
                    transition,
                    LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude),
                    fix.timestamp,
                    // A heal only synthesizes off a fix it just gated as fresh.
                    true,
                    // Judged against this condition, so the circle is known rather than looked up by date.
                    .circle(MonitoredCircle(
                        center: condition.center, radius: condition.radius,
                        maximumRadius: self.authManager.maximumRegionMonitoringDistance
                    ))
                )
            }
        }
    }

    /// Resolved at drain through the movement resolver, because non-movement syncs (launch, manual,
    /// foreground) hand this monitor coordinates only, with no timestamp or accuracy to judge.
    /// Movement syncs just resolved through the same resolver, so their cache is already fresh.
    /// Returns `bestKnownFix()` so the newer of cache and request wins; the decision's age guard
    /// applies to the result.
    private func resolveHealFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .baselineHeal) { [weak self] _, _ in
                continuation.resume(returning: self?.bestKnownFix())
            }
        }
    }
}
