import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Re-adds every adopted condition in place instead of trusting the OS-side monitoring state.
    /// Per CLMonitor.h, CoreLocation silently stops monitoring a condition whose pending event no
    /// monitor was configured to receive — after a reboot the app is not relaunched, so the first
    /// missed crossing kills monitoring while the persisted store still lists the condition. A
    /// fresh add re-arms it. Event-silent when nothing changed: `assuming:` seeds the stored
    /// baseline, so CLMonitor emits only transitions that happened while unmonitored — genuine
    /// catch-up, which the baseline comparison then delivers.
    ///
    /// Records are read when the operation DRAINS, not when it was staged, and a condition is
    /// skipped unless its record still matches the staged geometry — the same two rules as
    /// `rearmOnForegroundIfStale`. A crossing accepted while this waited in the queue has moved the
    /// baseline, and asserting the staged snapshot to the OS makes the daemon answer with a
    /// corrective the dedup then has to absorb: on the 2026-09-12 relaunch the trigger was re-added
    /// `satisfied` after its exit had been accepted, 30 ms earlier. A sync that reshaped a condition
    /// meanwhile has its own add queued behind this, and re-imposing the old circle here would leave
    /// the OS and the bookkeeping disagreeing — the case the geometry check skips.
    ///
    /// Each successful add is recorded in `knownConditionIdentifiers` and the mirror persisted, the
    /// same bookkeeping `startMonitoring` does. Without it the mirror under-reports a condition this
    /// re-add revived, and the next process seeds ownership from that mirror — so a cold-wake event
    /// for the revived condition would be dropped by the ownership gate.
    func rearmConditions(_ identifiers: Set<String>) {
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            let records = await self.storage.getMonitorRegionRecords()
            var revived = false
            for identifier in identifiers.sorted() {
                // A record without geometry can't be rebuilt; the next sync re-registers it.
                guard let record = records[identifier],
                      let center = record.center, let radius = record.radius,
                      self.registeredConditions[identifier] == RegisteredCondition(
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
                // Stamped straight off the `add`, before anything else runs. The contradiction
                // gate replays events against this instant, and a log dispatched between the two
                // pushes the anchor later than the OS actually accepted the circle.
                let addedAt = self.dateUtil.now
                self.conditionReadds[identifier] = ConditionReadd(start: readdStart, added: addedAt, center: center, radius: radius)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .readd)
                self.logger.geofenceConditionAdded(identifier: identifier)
                // Recorded per identifier rather than in one pass at the end: an `.unmonitored` for
                // one of these can land between two iterations, and it must be able to take the
                // identifier back out.
                self.knownConditionIdentifiers.insert(identifier)
                revived = true
            }
            guard revived else { return }
            self.persistConditionMirror()
            await self.reportRegisteredConditions(on: monitor)
        }
    }

    /// Reports the OS's live condition set as `registration.applied`, from inside the operation
    /// that changed it.
    ///
    /// Adopt and re-arm both alter which fences the OS is holding for us, and until now neither
    /// said so: `registration.applied` is emitted by the sync coordinator, and neither path goes
    /// through it. A relaunch that adopted twenty conditions, re-armed them and did nothing else
    /// therefore produced no output record at all — which is why replay could not catch the
    /// second-adopt defect, and why a reader could not answer "was this fence being watched" for
    /// the one session where the answer changed.
    ///
    /// Read from `monitor.identifiers`, not from the set we asked for. That is the contract the
    /// record already carries — "what the OS is holding, not what was asked for" — and it matters
    /// here more than at a sync: the loops above skip any condition whose record lost its geometry
    /// or whose staged circle no longer matches, so the requested set overstates the result.
    private func reportRegisteredConditions(on monitor: GeofenceConditionMonitoring) async {
        let held = Set(await monitor.identifiers)
        let movementTriggerId = GeofenceConstants.movementTriggerIdentifier
        logger.geofenceRegionsRegistered(
            identifiers: held.subtracting([movementTriggerId]).sorted(),
            movementTrigger: held.contains(movementTriggerId) ? movementTriggerId : nil
        )
    }

    /// Runs `rearmOnForegroundIfStale` when the app enters the foreground.
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

    /// Re-arms every owned condition when the app enters the foreground after
    /// `GeofenceConstants.foregroundRearmInterval` with no rebuild. locationd's per-fence promotion
    /// record can wedge while a process stays suspended for days — observed in field staying
    /// "outside" for hours while the daemon's own fixes placed the device inside — and only a
    /// rebuild recovers it: the re-add makes the OS re-evaluate from scratch and emit a corrective
    /// for any crossing its old record missed, while `assuming:` = stored baseline keeps it
    /// event-silent when nothing changed. Cold launch already rebuilds via adopt; a process that
    /// lives suspended for days never cold-launches.
    ///
    /// Ownership and records are read at DRAIN time, and a condition is skipped unless its record
    /// matches the staged registration — `rearmConditions` now applies the same rule: a mid-transition condition (e.g.
    /// adopt racing an in-flight reshape leaves the two temporarily disagreeing) will be settled by
    /// the queued ops, and re-arming it from either snapshot imposes geometry the other bookkeeping
    /// layer doesn't know about — the state-space model (v6) shows the sync layer then skips it as
    /// unchanged forever, so the OS never converges back to the desired set.
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
                      self.registeredConditions[identifier] == RegisteredCondition(
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
                // Stamped straight off the `add`, before anything else runs. The contradiction
                // gate replays events against this instant, and a log dispatched between the two
                // pushes the anchor later than the OS actually accepted the circle.
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
