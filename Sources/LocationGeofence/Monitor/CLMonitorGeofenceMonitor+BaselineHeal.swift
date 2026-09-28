import CioInternalCommon
import CoreLocation
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Synthesizes crossings the OS never delivered. Queued behind the calling sync's registration
    /// ops, so baselines are read after those rewrites.
    func enqueueBaselineHeal(candidates: [String]) {
        let expectedConditions = candidates.reduce(into: [String: RegisteredCondition]()) {
            $0[$1] = conditionLedger.condition(for: $1)
        }
        guard !expectedConditions.isEmpty else { return }
        enqueueMonitorOperation { [weak self] _ in
            guard let self else { return }
            guard let fix = await self.resolveHealFix(), CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
            let records = await self.storage.getMonitorRegionRecords()
            for (identifier, condition) in expectedConditions.sorted(by: { $0.key < $1.key }) {
                // A later sync may have reshaped the circle; the old baseline must not be judged
                // against it.
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
                    // Drain time, so a fix gone stale in the queue is rejected.
                    fixAge: self.dateUtil.now.timeIntervalSince(fix.timestamp),
                    lastState: record.lastState
                ) else { continue }
                // Fix time, not drain time: an OS crossing recorded after the fix must win.
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
                    true,
                    .circle(MonitoredCircle(
                        center: condition.center, radius: condition.radius,
                        maximumRadius: self.authManager.maximumRegionMonitoringDistance
                    ))
                )
            }
        }
    }

    /// Non-movement syncs pass bare coordinates with no timestamp or accuracy, so the heal resolves
    /// its own fix.
    private func resolveHealFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .baselineHeal) { [weak self] _, _ in
                continuation.resume(returning: self?.bestKnownFix())
            }
        }
    }
}
