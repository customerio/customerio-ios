import CoreLocation
import Foundation

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
}
