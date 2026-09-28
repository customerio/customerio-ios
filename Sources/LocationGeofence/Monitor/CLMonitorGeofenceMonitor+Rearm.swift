import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Re-adds every adopted condition instead of trusting the OS-side state. Per CLMonitor.h,
    /// CoreLocation silently stops monitoring a condition whose pending event no monitor was
    /// configured to receive (e.g. after a reboot, when the app is not relaunched), while the store
    /// still lists it. `assuming:` = stored baseline keeps the re-add silent unless something
    /// changed while unmonitored.
    ///
    /// Records are read at DRAIN, and a condition is skipped unless its record matches the staged
    /// geometry. A crossing accepted while this waited has moved the baseline, and a stale
    /// `assuming:` provokes a corrective; a reshape queued behind this would otherwise leave the OS
    /// and the bookkeeping disagreeing.
    ///
    /// Revived conditions go into `knownConditionIdentifiers` and the persisted mirror, or the next
    /// process would not own them and would drop their cold-wake events.
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
                // Stamped straight off the `add`: the contradiction gate's window starts here.
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

    /// Reports the OS's live condition set as `registration.applied`. Adopt and re-arm change what
    /// the OS holds without going through the sync coordinator, which emits it otherwise.
    ///
    /// Read from `monitor.identifiers`, not the requested set, which overstates the result when
    /// the loops above skip a condition.
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

    /// Re-arms every owned condition on foreground after `foregroundRearmInterval` with no rebuild.
    /// locationd's per-fence promotion record can wedge in a process suspended for days, reporting
    /// "outside" while the device is inside, and only a re-add recovers it. Cold launch already
    /// rebuilds via adopt; a long-suspended process never cold-launches.
    ///
    /// Same drain-time rules as `rearmConditions`. Re-arming a condition whose record and staged
    /// registration disagree imposes geometry one layer doesn't know about, and the sync layer
    /// would then skip it as unchanged forever.
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
                // Stamped straight off the `add`: the contradiction gate's window starts here.
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
