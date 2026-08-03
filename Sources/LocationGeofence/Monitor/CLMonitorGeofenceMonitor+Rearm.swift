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
    func rearmConditions(_ identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        enqueueMonitorOperation { monitor in
            for identifier in identifiers {
                // A record without geometry can't be rebuilt; the next sync re-registers it.
                guard let record = records[identifier],
                      let center = record.center, let radius = record.radius
                else { continue }
                await monitor.remove(identifier)
                let condition = CLMonitor.CircularGeographicCondition(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    radius: radius
                )
                await monitor.add(condition, identifier: identifier, assuming: record.lastState == .enter ? .satisfied : .unsatisfied)
            }
        }
    }
}
