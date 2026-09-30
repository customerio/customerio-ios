import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// CoreLocation can silently stop monitoring a condition it still lists, so re-add rather than
    /// trust it. Records are read at DRAIN; skip any whose record doesn't match the staged geometry.
    func rearmConditions(_ identifiers: Set<String>) {
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            let records = await self.storage.getMonitorRegionRecords()
            var revived = false
            for identifier in identifiers.sorted() {
                // A record without geometry can't be rebuilt; the next sync re-registers it.
                guard let record = records[identifier],
                      let center = record.center, let radius = record.radius,
                      self.conditionLedger.condition(for: identifier) == RegisteredCondition(
                          center: center,
                          radius: radius,
                          transitionTypes: record.transitionTypes
                      )
                else { continue }
                let readdStart = self.dateUtil.now
                await monitor.remove(identifier)
                await monitor.add(
                    center: center,
                    radius: radius,
                    identifier: identifier,
                    assuming: record.lastState == .enter ? .satisfied : .unsatisfied
                )
                // Straight off the `add`: the contradiction gate's window starts here.
                let addedAt = self.dateUtil.now
                self.conditionReadds[identifier] = ConditionReadd(start: readdStart, added: addedAt, center: center, radius: radius)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .readd)
                self.logger.geofenceConditionAdded(identifier: identifier)
                // Per identifier, not at the end: an `.unmonitored` landing between iterations must
                // be able to take it back out.
                self.knownConditionIdentifiers.insert(identifier)
                revived = true
            }
            guard revived else { return }
            self.persistConditionMirror()
            await self.reportRegisteredConditions(on: monitor)
        }
    }

    /// The OS's live set, not the requested one, which overstates when a condition was skipped.
    private func reportRegisteredConditions(on monitor: GeofenceConditionMonitoring) async {
        let held = Set(await monitor.identifiers)
        let movementTriggerId = GeofenceConstants.movementTriggerIdentifier
        logger.geofenceRegionsRegistered(
            identifiers: held.subtracting([movementTriggerId]).sorted(),
            movementTrigger: held.contains(movementTriggerId) ? movementTriggerId : nil
        )
    }

    func registerForegroundRearm() {
        #if canImport(UIKit)
        foregroundObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rearmOnForegroundIfStale()
            }
        }
        #endif
    }

    /// A fence's OS state can wedge in a process suspended for days, and only a re-add recovers it.
    /// Same drain-time match as `rearmConditions`, or the sync layer skips a mismatch as unchanged
    /// forever.
    func rearmOnForegroundIfStale() {
        guard dateUtil.now.timeIntervalSince(lastRearmAt) >= GeofenceConstants.foregroundRearmInterval else { return }
        guard !ownedRegionIdentifiers.isEmpty else { return }
        // Stamped at enqueue so rapid foreground cycles can't queue a second rebuild behind this one.
        lastRearmAt = dateUtil.now
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            let records = await self.storage.getMonitorRegionRecords()
            var rearmed = 0
            for identifier in self.ownedRegionIdentifiers.sorted() {
                guard let record = records[identifier],
                      let center = record.center, let radius = record.radius,
                      self.conditionLedger.condition(for: identifier) == RegisteredCondition(
                          center: center,
                          radius: radius,
                          transitionTypes: record.transitionTypes
                      )
                else { continue }
                let readdStart = self.dateUtil.now
                await monitor.remove(identifier)
                await monitor.add(
                    center: center,
                    radius: radius,
                    identifier: identifier,
                    assuming: record.lastState == .enter ? .satisfied : .unsatisfied
                )
                // Straight off the `add`: the contradiction gate's window starts here.
                let addedAt = self.dateUtil.now
                self.conditionReadds[identifier] = ConditionReadd(start: readdStart, added: addedAt, center: center, radius: radius)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .readd)
                self.logger.geofenceConditionAdded(identifier: identifier)
                self.knownConditionIdentifiers.insert(identifier)
                rearmed += 1
            }
            guard rearmed > 0 else { return }
            self.persistConditionMirror()
            self.logger.geofenceForegroundRearm(count: rearmed)
            await self.reportRegisteredConditions(on: monitor)
        }
    }
}
