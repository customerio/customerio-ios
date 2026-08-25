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
    /// `records` comes from the caller (`adoptExistingRegions`), which has already seeded the
    /// geometry bookkeeping from it synchronously — noting it again at drain time would clobber
    /// a newer circle a sync staged while this operation was still queued.
    ///
    /// Each successful add is recorded in `knownConditionIdentifiers` and the mirror persisted, the
    /// same bookkeeping `startMonitoring` does. Without it the mirror under-reports a condition this
    /// re-add revived, and the next process seeds ownership from that mirror — so a cold-wake event
    /// for the revived condition would be dropped by the ownership gate.
    func rearmConditions(_ identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            var revived = false
            for identifier in identifiers {
                // A record without geometry can't be rebuilt; the next sync re-registers it.
                guard let record = records[identifier],
                      let center = record.center, let radius = record.radius
                else { continue }
                let readdStart = Date()
                await monitor.remove(identifier)
                let condition = CLMonitor.CircularGeographicCondition(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    radius: radius
                )
                await monitor.add(condition, identifier: identifier, assuming: record.lastState == .enter ? .satisfied : .unsatisfied)
                self.conditionReadds[identifier] = ConditionReadd(start: readdStart, added: Date(), center: center, radius: radius)
                // Recorded per identifier rather than in one pass at the end: an `.unmonitored` for
                // one of these can land between two iterations, and it must be able to take the
                // identifier back out.
                self.knownConditionIdentifiers.insert(identifier)
                revived = true
            }
            guard revived else { return }
            self.persistConditionMirror()
        }
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
    /// Unlike `rearmConditions`, ownership and records are read at DRAIN time, and a condition is
    /// skipped unless its record matches the staged registration: a mid-transition condition (e.g.
    /// adopt racing an in-flight reshape leaves the two temporarily disagreeing) will be settled by
    /// the queued ops, and re-arming it from either snapshot imposes geometry the other bookkeeping
    /// layer doesn't know about — the state-space model (v6) shows the sync layer then skips it as
    /// unchanged forever, so the OS never converges back to the desired set.
    func rearmOnForegroundIfStale() {
        guard Date().timeIntervalSince(lastRearmAt) >= GeofenceConstants.foregroundRearmInterval else { return }
        guard !ownedRegionIdentifiers.isEmpty else { return }
        // Stamped at enqueue so rapid foreground cycles can't queue a second rebuild behind this one.
        lastRearmAt = Date()
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
                await monitor.remove(identifier)
                let condition = CLMonitor.CircularGeographicCondition(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    radius: radius
                )
                await monitor.add(condition, identifier: identifier, assuming: record.lastState == .enter ? .satisfied : .unsatisfied)
                self.knownConditionIdentifiers.insert(identifier)
                rearmed += 1
            }
            guard rearmed > 0 else { return }
            self.persistConditionMirror()
            self.logger.geofenceForegroundRearm(count: rearmed)
        }
    }
}
