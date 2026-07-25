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
    func rearmConditions(_ identifiers: Set<String>) {
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            let records = await self.storage.getMonitorRegionRecords()
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
                // This process now knows what the condition holds, so `setMonitoredRegions` can
                // leave it alone instead of re-adding it on the next sync.
                self.noteRegisteredCondition(
                    identifier: identifier,
                    center: center,
                    radius: radius,
                    transitionTypes: record.transitionTypes
                )
            }
        }
    }
}
